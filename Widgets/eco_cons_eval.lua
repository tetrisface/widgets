-- luacheck: globals ECO_CONS_EVAL_TEST loadstring next
-- luacheck: no self

function widget:GetInfo()
  return {
    name = 'eco cons eval',
    desc = 'Logs eco cons decisions next to their resource outcomes to infolog as [eco_eval] lines, and reloads eco cons and itself when their files change',
    author = 'tetrisface',
    date = '2026-10-01',
    license = 'Public Domain',
    layer = 0,
    enabled = true
  }
end

local Echo = Spring.Echo
local GetGameFrame = Spring.GetGameFrame
local GetMyTeamID = Spring.GetMyTeamID
local GetTeamResources = Spring.GetTeamResources
local GetTeamRulesParam = Spring.GetTeamRulesParam
local GetTeamUnits = Spring.GetTeamUnits
local GetUnitCommands = Spring.GetUnitCommands
local GetUnitCurrentCommand = Spring.GetUnitCurrentCommand
local GetUnitBuildeeRadius = Spring.GetUnitBuildeeRadius
local GetUnitDefID = Spring.GetUnitDefID
local GetUnitHealth = Spring.GetUnitHealth
local GetUnitIsBuilding = Spring.GetUnitIsBuilding
local GetUnitPosition = Spring.GetUnitPosition

local SAMPLE_FRAMES = 30   -- 1 s, so per-second rates sum to amounts
local LINE_SECONDS = 10    -- timeline line cadence
local SUMMARY_SECONDS = 300 -- cumulative summary cadence, so a game that never ends cleanly still reports
local STALL_LEVEL = 0.05
local STALL_RUNWAY_SECONDS = 3 -- storage that empties within this at the current net drain counts as stalling
local UNMET_FACTOR = 1.05  -- pull above expense by this factor == demand going unmet
local LEAK_LEVEL = 0.99
local QUEUE_SCAN_DEPTH = 20 -- commands read per builder when counting queued builds
local ORDER_SETTLE_FRAMES = 20 -- an order gets this long to reach its unit before its outcome is judged
local RELOAD_POLL_SECONDS = 2

-- Dev loop: a widget whose file changed on disk is reloaded, so an edit takes effect in the running game.
local WATCHED = {
  {name = 'eco cons', file = 'LuaUI/Widgets/eco_cons.lua'},
  {name = 'eco cons eval', file = 'LuaUI/Widgets/eco_cons_eval.lua'}
}

-- decision kinds that send a builder to work on a unit
local DIRECTING = {assign_power = true, assign_energy = true, assign_mMM = true, finish_neighbour = true, repair_damaged = true}

local ACTIVITIES = {
  'idle', 'idle_nano', 'travel', 'stuck', 'area', 'power', 'energy', 'mMM', 'other', 'repair', 'reclaim', 'guard', 'patrol', 'move', 'wait', 'misc'
}
local CONDITIONS = {'all', 'mStall', 'eStall', 'mLeak', 'eLeak'}
local ECO_CONS_FLAGS = {
  {'isMetalStalling', 'mStall'}, {'isEnergyStalling', 'eStall'},
  {'isMetalLeaking', 'mLeak'}, {'isEnergyLeaking', 'eLeak'},
  {'anyBuildWillMStall', 'willMStall'}, {'anyBuildWillEStall', 'willEStall'}
}

--------------------------------------------------------------------------------
-- Pure core. No Spring calls.
--------------------------------------------------------------------------------

-- target is {build = 0..1, ecoType = 'power'|'energy'|'mMM'|nil} while the engine reports a build/repair target.
-- isArea: the command covers an area rather than one unit, so holding it means nothing there needs work.
-- immobile separates nano turrets from mobile builders: an idle one was not sent anywhere, and one holding
-- an order without working on it cannot walk there, so it is stuck until that target is finished by others.
local function classifyActivity(target, commandId, immobile, isArea)
  if target then
    if target.build >= 1 then return 'repair' end
    return target.ecoType or 'other'
  end
  if not commandId then return immobile and 'idle_nano' or 'idle' end
  if commandId == CMD.REPAIR and isArea then return 'area' end
  if commandId < 0 or commandId == CMD.REPAIR then return immobile and 'stuck' or 'travel' end
  if commandId == CMD.RECLAIM then return 'reclaim' end
  if commandId == CMD.GUARD then return 'guard' end
  if commandId == CMD.FIGHT or commandId == CMD.PATROL then return 'patrol' end
  if commandId == CMD.MOVE then return 'move' end
  if commandId == CMD.WAIT then return 'wait' end
  return 'misc'
end

-- One poll of a watched file. A changed source must read the same twice, so a file caught mid-write is
-- not loaded, and it must compile, so a syntax error leaves the running widget in place.
-- Returns 'reload', or 'broken' plus the compile error, or nil.
local function pollWatch(watch, source, compile)
  if source == nil or source == watch.loaded or source == watch.rejected then
    watch.pending = nil
    return
  end
  if source ~= watch.pending then
    watch.pending = source
    return
  end
  watch.pending = nil
  local chunk, compileError = compile(source)
  if not chunk then
    watch.rejected = source
    return 'broken', compileError
  end
  watch.loaded = source
  return 'reload'
end

-- What became of an order eco cons gave a builder a moment ago.
-- The engine keeps an unreachable order at the front of a nano turret's queue, blocking the turret.
local function orderOutcome(isBuildingTarget, targetNeedsWork, holdsOrder, canReach)
  if isBuildingTarget then return 'ord_took' end
  if not targetNeedsWork then return 'ord_moot' end
  if not holdsOrder then return 'ord_lost' end
  return canReach and 'ord_walking' or 'ord_stuck'
end

-- Why a nano turret holds a repair order without working on it.
local function stuckCause(targetExists, targetNeedsWork, isInRange)
  if not targetExists then return 'gone' end
  if not targetNeedsWork then return 'done' end
  return isInRange and 'near' or 'far'
end

-- Ground truth, independent of eco cons' own trend-smoothed flags.
-- excess is what the engine reports as lost to full storage; overflow also counts what is shared away.
local function resourceOutcome(current, storage, pull, income, expense, excess)
  local level = storage > 0 and current / storage or 0
  -- Pull alone proves nothing: builds starved of the other resource leave their pull on this one unspent.
  local starved = level < STALL_LEVEL and pull > expense * UNMET_FACTOR
  local stalling = starved or (expense > income and current < (expense - income) * STALL_RUNWAY_SECONDS)
  local leaking = level >= LEAK_LEVEL and income > expense
  return {
    level = level,
    income = income,
    expense = expense,
    stalling = stalling,
    leaking = leaking,
    unmet = stalling and math.max(0, pull - expense) or 0,
    overflow = leaking and income - expense or 0,
    excess = excess or 0
  }
end

local function activeConditions(metal, energy)
  return {all = true, mStall = metal.stalling, eStall = energy.stalling, mLeak = metal.leaking, eLeak = energy.leaking}
end

local function addCounts(into, counts)
  for key, value in pairs(counts) do
    into[key] = (into[key] or 0) + value
  end
end

local function newStats()
  local buckets = {}
  for _, name in ipairs(CONDITIONS) do
    buckets[name] = {seconds = 0, needSeconds = 0, needs = {}, shares = {}, decisions = {}, directed = {}}
  end
  return {
    buckets = buckets,
    metal = {income = 0, unmet = 0, overflow = 0, excess = 0},
    energy = {income = 0, unmet = 0, overflow = 0, excess = 0},
    retargets = 0
  }
end

-- sample: metal/energy (resourceOutcome), shares (activity -> build power fraction), decisions (kind -> count),
-- directed (the part of shares working on a target eco cons chose), builders (count), retargets,
-- state (eco cons getDecisionState(), nil while eco cons is off)
local function accumulate(stats, sample)
  local state = sample.state
  for name, active in pairs(activeConditions(sample.metal, sample.energy)) do
    if active then
      local bucket = stats.buckets[name]
      bucket.seconds = bucket.seconds + 1
      addCounts(bucket.directed, sample.directed)
      addCounts(bucket.shares, sample.shares)
      addCounts(bucket.decisions, sample.decisions)
      if state then
        bucket.needSeconds = bucket.needSeconds + 1
        addCounts(bucket.needs, {power = state.powerNeed, energy = state.energyNeed, mMM = state.mMMNeed})
      end
    end
  end
  for _, resource in ipairs({'metal', 'energy'}) do
    local total, outcome = stats[resource], sample[resource]
    total.income = total.income + outcome.income
    total.unmet = total.unmet + outcome.unmet
    total.overflow = total.overflow + outcome.overflow
    total.excess = total.excess + outcome.excess
  end
  stats.retargets = stats.retargets + sample.retargets
end

local function percent(fraction)
  return string.format('%d%%', math.floor(fraction * 100 + 0.5))
end

local function clock(seconds)
  return string.format('%d:%02d', math.floor(seconds / 60), math.floor(seconds % 60))
end

local function formatShares(shares, divisor)
  local parts = {}
  for _, activity in ipairs(ACTIVITIES) do
    local share = (shares[activity] or 0) / divisor
    if share >= 0.005 then
      parts[#parts + 1] = activity .. ' ' .. percent(share)
    end
  end
  return table.concat(parts, ' ')
end

local function formatCounts(counts, divisor, numberFormat)
  local kinds = {}
  for kind in pairs(counts) do
    kinds[#kinds + 1] = kind
  end
  table.sort(kinds)
  for i = 1, #kinds do
    kinds[i] = string.format('%s=' .. numberFormat, kinds[i], counts[kinds[i]] / divisor)
  end
  return table.concat(kinds, ' ')
end

local function formatNeeds(needs, divisor)
  if divisor == 0 then return 'need -' end
  return string.format('need p%.2f e%.2f m%.2f', needs.power / divisor, needs.energy / divisor, needs.mMM / divisor)
end

local function formatFlags(names, isActive)
  local active = {}
  for _, name in ipairs(names) do
    if isActive(name) then active[#active + 1] = name end
  end
  return '[' .. table.concat(active, ',') .. ']'
end

local function formatEcoConsView(state)
  if not state then return 'eco_cons off' end
  local names, labels = {}, {}
  for _, flag in ipairs(ECO_CONS_FLAGS) do
    names[#names + 1] = flag[2]
    labels[flag[2]] = flag[1]
  end
  return string.format(
    'ec p%.2f e%.2f m%.2f %s',
    state.powerNeed, state.energyNeed, state.mMMNeed,
    formatFlags(names, function(name) return state[labels[name]] end)
  )
end

local function formatResource(label, outcome)
  return string.format('%s %s +%.0f -%.0f', label, percent(outcome.level), outcome.income, outcome.expense)
end

-- conversion: {level, use, capacity} from the energy conversion rules params
-- queued: build orders in builders' own queues by eco type, i.e. what eco cons could pull forward
local function timelineLine(seconds, sample, conversion, decisions, queued)
  local conditions = activeConditions(sample.metal, sample.energy)
  return string.format(
    '%s %s %s mm %s %.0f/%.0f %s | %s | bp %.0f x%d | %s | ec %s | q %s | %s',
    clock(seconds), formatResource('M', sample.metal), formatResource('E', sample.energy),
    percent(conversion.level), conversion.use, conversion.capacity,
    formatFlags({'mStall', 'eStall', 'mLeak', 'eLeak'}, function(name) return conditions[name] end),
    formatEcoConsView(sample.state),
    sample.buildSpeed, sample.builders, formatShares(sample.shares, 1), formatShares(sample.directed, 1),
    formatCounts(queued, 1, '%g'), formatCounts(decisions, 1, '%g')
  )
end

local function summaryLines(stats, ecoConsSeen)
  local all = stats.buckets.all.seconds
  local lines = {
    string.format(
      'summary %s eco_cons=%s retargets/min=%.1f',
      clock(all), ecoConsSeen and 'on' or 'off', stats.retargets * 60 / math.max(all, 1)
    )
  }
  for _, resource in ipairs({'metal', 'energy'}) do
    local total = stats[resource]
    lines[#lines + 1] = string.format(
      '  %s income %.0f overflow %.0f (%s) excess %.0f unmet %.0f',
      resource, total.income, total.overflow, percent(total.overflow / math.max(total.income, 1)), total.excess, total.unmet
    )
  end
  for _, name in ipairs(CONDITIONS) do
    local bucket = stats.buckets[name]
    if bucket.seconds > 0 then
      lines[#lines + 1] = string.format(
        '  %s %ds (%s) %s | ec %s | all %s | /min %s',
        name, bucket.seconds, percent(bucket.seconds / all),
        formatNeeds(bucket.needs, bucket.needSeconds),
        formatShares(bucket.directed, bucket.seconds),
        formatShares(bucket.shares, bucket.seconds),
        formatCounts(bucket.decisions, bucket.seconds / 60, '%.1f')
      )
    end
  end
  return lines
end

--------------------------------------------------------------------------------
-- Spring glue
--------------------------------------------------------------------------------

local myTeamID
local builderSpeedByDefID = {}
local buildDistanceByDefID = {}
local immobileDefIDs = {}
local stats = newStats()
local pendingDecisions = {}
local lineDecisions = {}
local lastTargets = {}
local ecoConsTargets = {} -- builderID -> the unit eco cons last sent it to
local pendingOrders = {} -- builderID -> {targetID, frame}: orders whose outcome is not judged yet
local sinkOwner -- the WG.eco_cons table holding our sink
local summaryPrinted = false
local secondsSinceReloadPoll = 0

local function log(line)
  Echo('[eco_eval] ' .. line)
end

local function count(kind)
  pendingDecisions[kind] = (pendingDecisions[kind] or 0) + 1
end

local function buildProgress(unitID)
  return select(5, GetUnitHealth(unitID))
end

local function needsWork(unitID)
  local health, maxHealth, _, _, build = GetUnitHealth(unitID)
  return health ~= nil and (build < 1 or health < maxHealth)
end

-- Same rule as the engine's CBuilderCAI::IsInBuildRange.
local function inBuildRange(builderID, targetID)
  local builderX, _, builderZ = GetUnitPosition(builderID)
  local targetX, _, targetZ = GetUnitPosition(targetID)
  local range = (buildDistanceByDefID[GetUnitDefID(builderID)] or 0) + GetUnitBuildeeRadius(targetID)
  return (builderX - targetX) ^ 2 + (builderZ - targetZ) ^ 2 <= range ^ 2
end

local function settleOrder(builderID, order)
  pendingOrders[builderID] = nil
  local builderDefID = GetUnitDefID(builderID)
  if not builderDefID then return end
  local targetID = order.targetID
  local commandID, _, _, commandTargetID = GetUnitCurrentCommand(builderID)
  local targetNeedsWork = needsWork(targetID)
  local outcome = orderOutcome(
    GetUnitIsBuilding(builderID) == targetID,
    targetNeedsWork,
    commandID == CMD.REPAIR and commandTargetID == targetID,
    not immobileDefIDs[builderDefID] or (targetNeedsWork and inBuildRange(builderID, targetID))
  )
  count(outcome)
end

local function settleOrders(frame)
  for builderID, order in pairs(pendingOrders) do
    if frame - order.frame >= ORDER_SETTLE_FRAMES then
      settleOrder(builderID, order)
    end
  end
end

local function onDecision(kind, builderID, targetID)
  count(kind)
  if not (builderID and targetID) then return end
  ecoConsTargets[builderID] = targetID
  if not DIRECTING[kind] then return end

  local frame = GetGameFrame()
  local previous = pendingOrders[builderID]
  if previous and frame - previous.frame >= ORDER_SETTLE_FRAMES then
    settleOrder(builderID, previous)
  elseif previous then
    count('ord_redone') -- replaced before it could be judged
  end
  pendingOrders[builderID] = {targetID = targetID, frame = frame}
end

-- WG.eco_cons is a new table each time eco cons initializes; follow it.
local function ecoConsApi()
  local api = WG.eco_cons
  if api and api ~= sinkOwner then
    api.setDecisionSink(onDecision)
    sinkOwner = api
  end
  return api
end

local function noEcoType() end

local function readResource(resource)
  local current, storage, pull, income, expense, _, _, _, excess = GetTeamResources(myTeamID, resource)
  return resourceOutcome(current or 0, storage or 0, pull or 0, income or 0, expense or 0, excess)
end

local function readConversion()
  return {
    level = GetTeamRulesParam(myTeamID, 'mmLevel') or 0,
    use = GetTeamRulesParam(myTeamID, 'mmUse') or 0,
    capacity = GetTeamRulesParam(myTeamID, 'mmCapacity') or 0
  }
end

-- A retarget is a builder leaving a target that is still unfinished: churn, or a deliberate skip.
local function sampleBuilders(ecoTypeOf)
  local speeds, directedSpeeds, totalSpeed, builders, retargets, targets = {}, {}, 0, 0, 0, {}
  local units = GetTeamUnits(myTeamID)
  for i = 1, #units do
    local unitID = units[i]
    local unitDefID = GetUnitDefID(unitID)
    local speed = builderSpeedByDefID[unitDefID]
    if speed and (buildProgress(unitID) or 0) >= 1 then
      local targetID = GetUnitIsBuilding(unitID)
      local target = targetID and {build = buildProgress(targetID) or 1, ecoType = ecoTypeOf(GetUnitDefID(targetID))}
      local commandID, _, _, _, _, _, fourthParam = GetUnitCurrentCommand(unitID)
      local activity = classifyActivity(target, commandID, immobileDefIDs[unitDefID], fourthParam ~= nil)
      speeds[activity] = (speeds[activity] or 0) + speed
      totalSpeed = totalSpeed + speed
      builders = builders + 1
      if targetID and ecoConsTargets[unitID] == targetID then
        directedSpeeds[activity] = (directedSpeeds[activity] or 0) + speed
      end

      local lastTarget = lastTargets[unitID]
      if lastTarget and lastTarget ~= targetID and (buildProgress(lastTarget) or 1) < 1 then
        retargets = retargets + 1
      end
      targets[unitID] = targetID
    end
  end
  lastTargets = targets

  local shares, directed = {}, {}
  for activity, speed in pairs(speeds) do
    shares[activity] = speed / totalSpeed
  end
  for activity, speed in pairs(directedSpeeds) do
    directed[activity] = speed / totalSpeed
  end
  return shares, directed, totalSpeed, builders, retargets
end

-- Stuck nano turrets by cause, '_ec' marking orders eco cons gave; 'build' is a held build order.
local function stuckCauses()
  local causes = {}
  local units = GetTeamUnits(myTeamID)
  for i = 1, #units do
    local unitID = units[i]
    if immobileDefIDs[GetUnitDefID(unitID)] and not GetUnitIsBuilding(unitID) and (buildProgress(unitID) or 0) >= 1 then
      local commandID, _, _, targetID, secondParam = GetUnitCurrentCommand(unitID)
      local cause
      if commandID and commandID < 0 then
        cause = 'build'
      elseif commandID == CMD.REPAIR and targetID and not secondParam then
        local targetExists = GetUnitDefID(targetID) ~= nil
        local targetNeedsWork = targetExists and needsWork(targetID)
        cause = stuckCause(targetExists, targetNeedsWork, targetNeedsWork and inBuildRange(unitID, targetID))
        if ecoConsTargets[unitID] == targetID then
          cause = cause .. '_ec'
        end
      end
      if cause then
        causes[cause] = (causes[cause] or 0) + 1
      end
    end
  end
  return causes
end

local function queuedBuilds(ecoTypeOf)
  local counts = {}
  local units = GetTeamUnits(myTeamID)
  for i = 1, #units do
    local unitID = units[i]
    if builderSpeedByDefID[GetUnitDefID(unitID)] then
      local commands = GetUnitCommands(unitID, QUEUE_SCAN_DEPTH) or {}
      for j = 1, #commands do
        local commandID = commands[j].id
        if commandID < 0 then
          local ecoType = ecoTypeOf(-commandID) or 'other'
          counts[ecoType] = (counts[ecoType] or 0) + 1
        end
      end
    end
  end
  return counts
end

local function takeSample(ecoTypeOf, api)
  local shares, directed, buildSpeed, builders, retargets = sampleBuilders(ecoTypeOf)
  local sample = {
    metal = readResource('metal'),
    energy = readResource('energy'),
    shares = shares,
    buildSpeed = buildSpeed,
    builders = builders,
    directed = directed,
    retargets = retargets,
    decisions = pendingDecisions,
    state = api and api.getDecisionState()
  }
  pendingDecisions = {}
  return sample
end

local function logSummary()
  for _, line in ipairs(summaryLines(stats, sinkOwner ~= nil)) do
    log(line)
  end
end

local function printFinalSummary()
  if summaryPrinted or stats.buckets.all.seconds == 0 then return end
  summaryPrinted = true
  logSummary()
end

function widget:Initialize()
  if Spring.GetSpectatingState() or Spring.IsReplay() then
    widgetHandler:RemoveWidget()
    return
  end
  myTeamID = GetMyTeamID()
  for unitDefID, unitDef in pairs(UnitDefs) do
    -- same roster rule as eco cons AddBuilder
    if unitDef.isBuilder and unitDef.canAssist and not unitDef.isFactory and unitDef.buildSpeed > 0 then
      builderSpeedByDefID[unitDefID] = unitDef.buildSpeed
      buildDistanceByDefID[unitDefID] = unitDef.buildDistance
      immobileDefIDs[unitDefID] = not unitDef.canMove
    end
  end
  for _, watch in ipairs(WATCHED) do
    watch.loaded = VFS.LoadFile(watch.file, VFS.RAW)
  end
end

function widget:Update(deltaSeconds)
  secondsSinceReloadPoll = secondsSinceReloadPoll + deltaSeconds
  if secondsSinceReloadPoll < RELOAD_POLL_SECONDS then return end
  secondsSinceReloadPoll = 0
  for _, watch in ipairs(WATCHED) do
    local action, compileError = pollWatch(watch, VFS.LoadFile(watch.file, VFS.RAW), loadstring)
    if action == 'reload' then
      log('reloading ' .. watch.name)
      Spring.SendCommands('luaui disablewidget ' .. watch.name, 'luaui enablewidget ' .. watch.name)
    elseif action == 'broken' then
      log('not reloading ' .. watch.name .. ': ' .. tostring(compileError))
    end
  end
end

function widget:GameFrame(frame)
  if frame % SAMPLE_FRAMES ~= 0 then return end
  local api = ecoConsApi()
  local ecoTypeOf = api and api.ecoTypeOf or noEcoType
  settleOrders(frame)
  local sample = takeSample(ecoTypeOf, api)
  accumulate(stats, sample)
  addCounts(lineDecisions, sample.decisions)
  local seconds = stats.buckets.all.seconds
  if seconds % LINE_SECONDS == 0 then
    log(timelineLine(frame / 30, sample, readConversion(), lineDecisions, queuedBuilds(ecoTypeOf)))
    local causes = stuckCauses()
    if next(causes) then
      log('stuck turrets ' .. formatCounts(causes, 1, '%g'))
    end
    lineDecisions = {}
  end
  if seconds % SUMMARY_SECONDS == 0 then
    logSummary()
  end
end

function widget:GameOver()
  printFinalSummary()
end

-- Resigning or an idle takeover ends the evaluated game; eco cons removes itself the same way.
function widget:PlayerChanged()
  if Spring.GetSpectatingState() then
    widgetHandler:RemoveWidget()
  end
end

function widget:Shutdown()
  printFinalSummary()
  if sinkOwner then
    sinkOwner.setDecisionSink(nil)
  end
end

if ECO_CONS_EVAL_TEST then
  return {
    classifyActivity = classifyActivity,
    orderOutcome = orderOutcome,
    stuckCause = stuckCause,
    pollWatch = pollWatch,
    resourceOutcome = resourceOutcome,
    newStats = newStats,
    accumulate = accumulate,
    timelineLine = timelineLine,
    summaryLines = summaryLines
  }
end
