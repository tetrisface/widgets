-- luacheck: globals ECO_CONS_TEST IsInBuildRange pcall
-- luacheck: no self

function widget:GetInfo()
  return {
    desc = 'Some snippets copied from gui_build_costs.lua by Milan Satala',
    author = 'tetrisface',
    version = '',
    date = 'feb, 2016',
    name = 'eco cons',
    license = '',
    layer = -99990,
    enabled = true
  }
end

-- todo make idle builders repair adjacent buildings (testing)
-- todo make idle builders guard adjacent active builders (limit distance to building)
-- todo make (eco?) builders rearrange queue for max build power assistance
-- todo make builders push back unnecessary eco types

local NewSetList = VFS.Include('common/SetList.lua').NewSetList
VFS.Include('LuaUI/Widgets/helpers.lua')

local GetFeatureHealth = Spring.GetFeatureHealth
local GetFeatureResources = Spring.GetFeatureResources
local GetFeatureResurrect = Spring.GetFeatureResurrect
local GetFeaturesInCylinder = Spring.GetFeaturesInCylinder
local GetTeamResources = Spring.GetTeamResources
local GetTeamUnits = Spring.GetTeamUnits
local GetUnitCommands = Spring.GetUnitCommands
local GetUnitDefID = Spring.GetUnitDefID
local GetUnitHealth = Spring.GetUnitHealth
local GetUnitIsBuilding = Spring.GetUnitIsBuilding
local GetUnitBasePosition = Spring.GetUnitBasePosition
local GetUnitBuildeeRadius = Spring.GetUnitBuildeeRadius
local GetUnitRadius = Spring.GetUnitRadius
local GetUnitResources = Spring.GetUnitResources
local GetUnitsInCylinder = Spring.GetUnitsInCylinder
local GiveOrderToUnit = Spring.GiveOrderToUnit
local MRandom = math.random
local UnitDefs = UnitDefs
local tidalStrength = Game.tidal
local windMax = Game.windMax
local windMin = Game.windMin

local responsivenessSpeed = 1
local waitGameFramesDefault = 30
local frameStaggeringModuloMultiplier = 1
local responsivenessPresets = {1, 1.5, 2, 3, 4}
local protectedResurrectDefNames = {armcom = true, legcom = true, corcom = true}

-- resource thresholds
local STALL_LEVEL = 0.01           -- resource fraction below this == stalling
local LEAK_LEVEL = 0.99            -- resource fraction above this == leaking
local METAL_LEVEL_HIGH = 0.8       -- metal level deemed comfortably high
local METAL_LEVEL_LOW = 0.15       -- metal level above this still allows power building
local METAL_LEVEL_FULL = 0.96      -- metal level at which the conversion floor may be raised
local POWER_NEED_AFFORDABLE_FLOOR = 0.75 -- minimum buildpower priority when eco can afford it
local STALL_RUNWAY_SECONDS = 2     -- storage empties within this at the current pull == already stalling
local POWER_RUNWAY_SECONDS = 10    -- no extra build power if a resource empties within this at the current drain
local TREND_DEADBAND = 0.001       -- |mean(income - expense)| below this fraction of storage per second counts as flat

-- energy conversion (mmLevel is the storage fraction converters may not eat below;
-- the game converts at most 2 * (1 - mmLevel) * energyStorage per second, whatever the converter count)
local MM_LEVEL_BIAS = 0.12         -- margin above mmLevel before energy counts as surplus
local MM_LEVEL_MIN = 0.12          -- top bar UI floor for the conversion level
local MM_LEVEL_MAX = 0.75          -- MM_LEVEL_MAX + MM_LEVEL_BIAS must stay below LEAK_LEVEL
local MM_LEVEL_STEP = 0.02         -- conversion level change per resource sample
local MM_SATURATION = 0.95         -- mmUse / mmCapacity at or above this == converters saturated

-- scanning / timing
local CANDIDATE_SCAN_PADDING = 250 -- buildDistance + this == idle-candidate scan radius
local EARLY_GAME_REPAIR_FRAMES = 60 * 30 -- ~1 minute; below this, queued REPAIR is honored
local REGULARIZATION_WINDOW = 5    -- samples in the income/expense trend window
local RESOURCE_SAMPLE_INTERVAL = 30 -- frames between resource samples; matches engine TEAM_SLOWUPDATE_RATE
local FORWARDED_CLEANUP_INTERVAL = 100 -- frames between forwardedFromTargetIds purges
local BUILDER_RESCAN_INTERVAL = 300    -- frames between full builder roster rescans
local BATCH_ORDER_INTERVAL = 4         -- frames between BatchOrder() calls
local REMOVE_RESEND_FRAMES = 15        -- a REMOVE needs a few frames to reach its unit; resend only if the command outlives this
local MIN_ASSIGN_SECONDS = 1           -- a target its current builders finish sooner gets nobody else: the order would land on a finished unit

-- placement (see "Placement" below)
local PLACE_NEED = 0.9                 -- a need at or above this with nothing to assist may place a building
local PLACE_COOLDOWN_FRAMES = 300      -- per eco type, from when a round was last under way: lets what was finished show in the need
local PLACE_ANCHOR_TRIES = 40          -- outermost anchors tried for an open adjacent spot
local PLACE_BATCH_MAX = 6              -- buildings placed per round at most
local PLACE_QUEUE_SCAN_DEPTH = 200     -- orders read per builder when collecting what is already queued
local PLACE_AFFORD_SECONDS = 20        -- a round costs no more metal than is stored plus this much income
local PLACE_MAX_INTERRUPTION = 3       -- who may place: 1 only builders with nothing to do, 2 also guarding ones, 3 also ones on their own build queue
local PLACE_POWER_UTILIZATION = 0.75   -- build power is only placed while at least this share of the existing one is building
-- Spring.TestBuildOrder never returns the documented 3 (open): the engine folds it into 2
-- (reclaimable) for backward compatibility, and a feature in the way comes back as a second value.
local BUILD_SPOT_OPEN = 2

local function applyResponsivenessSpeed(speed)
  responsivenessSpeed = speed
  frameStaggeringModuloMultiplier = 1 / speed
  waitGameFramesDefault = math.max(2, math.floor(30 / speed))
end

local myTeamId = Spring.GetMyTeamID()
local busyCommands = {
  [CMD.GUARD] = true,
  [CMD.MOVE] = true,
  [CMD.RECLAIM] = true
}
local upgradableFromDefIds
local upgradableToDefIds
local ecoBuildDefIds
local ecoBuildingTypeDefIds
-- static per-unitDef eco scores, filled once in Initialize
local defBuildPowerScore = {}
-- Placement (see the section below); one table, since the file is near Lua's 200-local limit.
local Placement = {
  familyDefIds = {},          -- family -> {unitDefID...}: a building in every faction's and the scavengers' version
  familyEcoType = {},         -- family -> 'energy' | 'mMM' | 'power'
  placeableByBuilderDef = {}, -- builder unitDefID -> family -> the unitDefID it builds for that family
  lastFrame = {},             -- eco type -> frame a round of it was last placed or still under way
  pending = {},               -- eco type -> {builderId, unitDefID} of the round its builder still has to work off
  enabled = true,             -- cleared for the rest of the game when placement faults
  utilization = 0,            -- share of the roster's build power that is building something, from Builders()
  -- advisor seam: an outside widget may judge a due round before it is placed (see placeOrAwaitAdvice)
  openRounds = {},            -- eco type -> frame its round became due
  advice = {},                -- eco type -> {frame, family, place} from the advisor
  advisorMode = nil,          -- 'act': a due round waits ADVICE_WAIT_FRAMES for advice
  ADVICE_WAIT_FRAMES = 90,
  ADVICE_MAX_AGE_FRAMES = 150
}
local defEnergyScore = {}
local defMetalMMScore = {}

local regularizedResourceDerivativesMetal
local regularizedResourceDerivativesEnergy
local forwardedFromTargetIds
local builders
local builderUnitIds
local metalMakers
local reclaimTargets
local reclaimTargetsPrev

local possibleMetalMakersMetalProduction = 0
local possibleMetalMakersUpkeep = 0
local releasedMetal = 0
local regularizationCounter = 0
local energyLevel = 0.5
local isEnergyLeaking = true
local isEnergyStalling = false
local isMetalLeaking = true
local isMetalStalling = false
local metalLevel = 0.5
local conversionSnapshot
local positiveMMLevel = true
local regularizedNegativeMetal = false
local regularizedNegativeEnergy = false
local regularizedPositiveEnergy = true
local regularizedPositiveMetal = true
local needPower = true
local needEnergy = true
local needMM = true
local powerNeed = 0.5
local energyNeed = 0.5
local mMMNeed = 0.5
local totalBuildSpeed = 0

local gameFrameModulo
local buildersJitterModulo

local anyBuildWillMStall = false
local anyBuildWillEStall = false
local assignedTargetBuildSpeed = {}
local isUnitLogActive = false
local selectedUnits = {}

-- per-frame caches (cleared at start of Builders())
local cachedResourceStatus = {}
local cachedUnitsUpkeep = nil
local cachedMetalMakersUpkeep = nil
local cachedTargetWillStall = {}
local purgedThisFrame = {}
local InvalidatePurgedUnitCommands

local logNoop = function()
end
log = logNoop

-- Observer seam: an evaluator (eco_cons_eval.lua) installs a sink via WG.eco_cons to see every order given.
local decisionSink
local function emitDecision(kind, builderId, targetId)
  if decisionSink then
    decisionSink(kind, builderId, targetId)
  end
end

-- ============================================================
-- Decision predicates (queue shape & reclaim eligibility)
-- ============================================================

-- True if the builder has its own build order (negative cmd id) in slot 1 or 2.
-- Slot 2 is checked as a safety against weird padding commands leading the queue.
local function hasOwnBuildOrder(commandQueue)
  return commandQueue
    and ((commandQueue[1] and commandQueue[1].id < 0)
      or (commandQueue[2] and commandQueue[2].id < 0))
end

-- True if slot 1 is GUARD / MOVE / RECLAIM (busy with a manual/explicit action).
local function isManualOrBusy(commandQueue)
  return commandQueue and commandQueue[1] and busyCommands[commandQueue[1].id]
end

-- True if slot 1 is REPAIR within the early-game window (queued repairs are honored early).
local function isEarlyRepair(commandQueue, gameFrame)
  return commandQueue and commandQueue[1]
    and commandQueue[1].id == CMD.REPAIR
    and gameFrame < EARLY_GAME_REPAIR_FRAMES
end

-- True if both slots are build orders — the multi-item build queue case
-- where BuildQueueSkipAssisted may fast-forward.
local function hasMultiSlotBuildQueue(commandQueue)
  if not commandQueue or not commandQueue[1] then return false end
  local firstId = commandQueue[1].id
  return firstId < 0 and commandQueue[2] and commandQueue[2].id and commandQueue[2].id < 0
end

-- Compound guard for the eco-driven opportunistic reclaim path inside Builders().
-- Returns false if the builder is leaking, busy, already reclaiming, in early repair,
-- or has its own build queue (don't divert builders from their own work).
local function shouldOpportunisticallyReclaim(commandQueue, gameFrame)
  if isMetalLeaking or isEnergyLeaking then return false end
  if isManualOrBusy(commandQueue) then return false end
  if isEarlyRepair(commandQueue, gameFrame) then return false end
  if hasOwnBuildOrder(commandQueue) then return false end
  return true
end

-- ============================================================
-- Utility accessors
-- ============================================================
local function IsUnitSelectedLog(unitId)
  if isUnitLogActive then
    return selectedUnits[unitId] == true
  end
  return false
end

local function UnitIdDef(unitId)
  return UnitDefs[GetUnitDefID(unitId)]
end

local function MetalMakingEfficiencyDef(unitDef)
  return unitDef and unitDef.customParams and unitDef.customParams.energyconv_efficiency and
    tonumber(unitDef.customParams.energyconv_efficiency) or
    0
end

-- builders is keyed by unit id; builderUnitIds (SetList) only provides iteration
-- order. SetList:Remove is a swap-remove, so index-mirroring the two would desync.
local function RemoveBuilder(unitID)
  if unitID == nil then return end
  builders[unitID] = nil
  builderUnitIds:Remove(unitID)
end

local function AddBuilder(unitID, unitDefID)
  if unitID == nil then return end

  local existingBuilder = builders[unitID]
  if existingBuilder then
    if builderUnitIds.hash[unitID] == nil then
      builderUnitIds:Add(unitID)
    end
    return existingBuilder
  end

  local unitDef = UnitDefs[unitDefID]
  if not (unitDef and unitDef.isBuilder and unitDef.canAssist and not unitDef.isFactory) then
    return
  end

  if builderUnitIds.hash[unitID] == nil then
    builderUnitIds:Add(unitID)
  end
  local builder = {
    id = unitID,
    def = unitDef,
    defID = unitDefID,
    targetId = nil,
    lastOrder = 0
  }
  builders[unitID] = builder
  return builder
end

local function BuilderById(id)
  if id == nil then return end
  local builder = builders[id]
  if not builder then
    RemoveBuilder(id)
    return
  end
  return builder
end

local function RescanBuilders()
  local myUnits = GetTeamUnits(myTeamId)
  for i = 1, #myUnits do
    local unitID = myUnits[i]
    AddBuilder(unitID, GetUnitDefID(unitID))
  end
end

local function RefreshSelectedUnits()
  selectedUnits = {}
  local selectedUnitsList = Spring.GetSelectedUnits()
  for i = 1, #selectedUnitsList do
    selectedUnits[selectedUnitsList[i]] = true
  end
end

local function SetUnitLogActive(active)
  isUnitLogActive = active == true
  log = isUnitLogActive and Spring.Echo or logNoop
  Spring.Echo('eco cons unit logging: ' .. (isUnitLogActive and 'enabled' or 'disabled'))
end

local function AddObjectSpotlight(...)
  local spotlight = WG['ObjectSpotlight']
  if spotlight and spotlight.addSpotlight then
    spotlight.addSpotlight(...)
  end
end

local function SetBuilderLastOrder(builderId)
  local builder = BuilderById(builderId)
  if builder then
    builder.lastOrder = Spring.GetGameFrame()
  end
end

local function AllowBuilderOrder(builderId, currentGameFrame, waitGameFrames)
  currentGameFrame = currentGameFrame or Spring.GetGameFrame()
  waitGameFrames = waitGameFrames or waitGameFramesDefault
  local builder = BuilderById(builderId)
  if not builder then
    return
  end
  return builder.lastOrder < currentGameFrame - waitGameFrames
end

local function EnergyMakeDef(unitDef)
  if not unitDef then
    return 0
  end

  local totalEOut = unitDef.energyMake or 0

  totalEOut = totalEOut + -1 * (unitDef.energyUpkeep or 0)

  if unitDef.tidalGenerator and unitDef.tidalGenerator > 0 and tidalStrength > 0 then
    local mult = 1 -- DEFAULT
    if unitDef.customParams then
      mult = unitDef.customParams.energymultiplier or mult
    end
    totalEOut = totalEOut + (tidalStrength * mult)
  end

  if unitDef.windGenerator and unitDef.windGenerator > 0 then
    local mult = 1 -- DEFAULT
    if unitDef.customParams then
      mult = unitDef.customParams.energymultiplier or mult
    end

    local unitWindMin = math.min(windMin, unitDef.windGenerator)
    local unitWindMax = math.min(windMax, unitDef.windGenerator)
    totalEOut = totalEOut + (((unitWindMin + unitWindMax) / 2) * mult)
  end
  return totalEOut
end

local function Interpolate(value, inMin, inMax, outMin, outMax)
  return outMin +
    ((((value < inMin) and inMin or ((value > inMax) and inMax or value)) - inMin) / (inMax - inMin)) *
      (outMax - outMin)
end

local function Clamp01(value)
  if not value or value < 0 then
    return 0
  end
  if value > 1 then
    return 1
  end
  return value
end

local function SafeDivide(numerator, denominator, fallback)
  if denominator and denominator ~= 0 then
    return numerator / denominator
  end
  return fallback or 0
end

local function UnitCost(unitDef)
  local cost = unitDef and (unitDef.cost or unitDef.metalCost) or 1
  return cost > 0 and cost or 1
end

local function BuildPowerScore(unitDef)
  if unitDef and unitDef.buildOptions and #unitDef.buildOptions > 0 then
    return 1.01
  end
  return Interpolate((unitDef and unitDef.buildSpeed) or 0, 0, 1000, 0, 1)
end

local function EnergyScore(unitDef)
  return Clamp01(SafeDivide(EnergyMakeDef(unitDef), UnitCost(unitDef), 0) * 3)
end

local function MetalAndMMScore(unitDef)
  local cost = UnitCost(unitDef)
  local extractScore = SafeDivide((unitDef and unitDef.extractsMetal) or 0, cost, 0) * 50
  local metalMakeScore = SafeDivide((unitDef and (unitDef.metalMake or unitDef.makesMetal)) or 0, cost, 0) * 50
  local metalMakerEfficiencyScore = MetalMakingEfficiencyDef(unitDef) * 50

  return Clamp01(math.max(extractScore, metalMakeScore, metalMakerEfficiencyScore))
end

-- armfus, corfus and legfus_scav are one family: the same building in another faction's or the
-- scavengers' version. Anchors are matched by family; the builder places its own version.
function Placement.familyKey(unitName)
  local name = unitName:gsub('_scav$', '')
  name = name:gsub('^arm', '')
  name = name:gsub('^cor', '')
  name = name:gsub('^leg', '')
  return name
end

function Placement.isScavVersion(unitName)
  return unitName:sub(-5) == '_scav'
end

-- Anything immobile, which includes nano turrets (the engine does not flag those as buildings).
-- Extractors and geothermal need a spot, so they are never placed.
function Placement.isPlaceable(unitDef)
  return not unitDef.canMove and (unitDef.extractsMetal or 0) == 0 and not (unitDef.customParams or {}).geothermal
end

function widget:Initialize()
  if Spring.GetSpectatingState() or Spring.IsReplay() then
    widgetHandler:RemoveWidget()
    return
  end

  myTeamId = Spring.GetMyTeamID()
  forwardedFromTargetIds = NewSetList()
  builders = {}
  builderUnitIds = NewSetList()
  ecoBuildDefIds = {}
  ecoBuildingTypeDefIds = {
    energy = {map = {}, list = {}},
    power = {map = {}, list = {}},
    mMM = {map = {}, list = {}}
  }
  metalMakers = {}
  possibleMetalMakersUpkeep = 0
  possibleMetalMakersMetalProduction = 0
  reclaimTargets = NewSetList()
  reclaimTargetsPrev = NewSetList()
  regularizedResourceDerivativesEnergy = {}
  regularizedResourceDerivativesMetal = {}
  regularizationCounter = 0
  assignedTargetBuildSpeed = {}
  upgradableFromDefIds = {}
  upgradableToDefIds = {}
  defBuildPowerScore = {}
  defEnergyScore = {}
  defMetalMMScore = {}
  Placement.familyDefIds = {}
  Placement.familyEcoType = {}
  Placement.placeableByBuilderDef = {}
  Placement.lastFrame = {}
  Placement.pending = {}
  Placement.enabled = true
  Placement.utilization = 0
  Placement.openRounds = {}
  Placement.advice = {}
  Placement.advisorMode = nil

  local myUnits = GetTeamUnits(myTeamId)
  for _, unitID in ipairs(myUnits) do
    local unitDefID = GetUnitDefID(unitID)
    widget:UnitFinished(unitID, unitDefID, myTeamId)
  end

  for unitDefID, unitDef in pairs(UnitDefs) do
    defBuildPowerScore[unitDefID] = BuildPowerScore(unitDef)
    defEnergyScore[unitDefID] = EnergyScore(unitDef)
    defMetalMMScore[unitDefID] = MetalAndMMScore(unitDef)

    if (unitDef.extractsMetal > 0 or (unitDef.customParams or {}).geothermal) then
      if (unitDef.customParams or {}).techlevel == '1' then
        upgradableFromDefIds[unitDefID] = true
      elseif (unitDef.customParams or {}).techlevel == '2' then
        upgradableToDefIds[unitDefID] = true
      end
    end

    if
      not unitDef.isFactory and
        (unitDef.isBuilder or (unitDef.buildSpeed and unitDef.buildSpeed > 0) or
          (unitDef.extractsMetal and unitDef.extractsMetal > 0) or
          MetalMakingEfficiencyDef(unitDef) > 0 or
          (unitDef.metalMake and unitDef.metalMake > 0) or
          (EnergyMakeDef(unitDef) > 0))
     then
      ecoBuildDefIds[unitDefID] = true

      local ecoType = 'mMM'
      if unitDef.isBuilder or (unitDef.buildSpeed and unitDef.buildSpeed > 0) then
        ecoType = 'power'
      elseif EnergyMakeDef(unitDef) > 0 then
        ecoType = 'energy'
      end
      ecoBuildingTypeDefIds[ecoType].map[unitDefID] = true
      table.insert(ecoBuildingTypeDefIds[ecoType].list, unitDefID)

      if Placement.isPlaceable(unitDef) then
        local family = Placement.familyKey(unitDef.name)
        Placement.familyDefIds[family] = Placement.familyDefIds[family] or {}
        table.insert(Placement.familyDefIds[family], unitDefID)
        Placement.familyEcoType[family] = ecoType
      end
    end
  end

  for unitDefID, unitDef in pairs(UnitDefs) do
    if unitDef.isBuilder and unitDef.canMove and unitDef.buildOptions then
      local byFamily = {}
      for _, optionDefID in ipairs(unitDef.buildOptions) do
        local option = UnitDefs[optionDefID]
        local family = option and Placement.familyKey(option.name)
        if family and Placement.familyEcoType[family] then
          local current = byFamily[family]
          if not current or (Placement.isScavVersion(option.name) and not Placement.isScavVersion(UnitDefs[current].name)) then
            byFamily[family] = optionDefID
          end
        end
      end
      Placement.placeableByBuilderDef[unitDefID] = byFamily
    end
  end

  WG['eco_cons'] = {
    getResponsivenessSpeed = function() return responsivenessSpeed end,
    setResponsivenessSpeed = function(value)
      applyResponsivenessSpeed(math.max(0.25, math.min(4, value)))
    end,
    setDecisionSink = function(sink) decisionSink = sink end,
    getAdvisorContext = function() return Placement.advisorContext(Spring.GetGameFrame()) end,
    setAdvisorMode = function(mode) Placement.advisorMode = mode end,
    setAdvice = function(ecoType, advice) Placement.advice[ecoType] = advice end,
    ecoTypeOf = function(unitDefID)
      for name, group in pairs(ecoBuildingTypeDefIds) do
        if group.map[unitDefID] then return name end
      end
    end,
    getDecisionState = function()
      return {
        powerNeed = powerNeed,
        energyNeed = energyNeed,
        mMMNeed = mMMNeed,
        isMetalStalling = isMetalStalling,
        isEnergyStalling = isEnergyStalling,
        isMetalLeaking = isMetalLeaking,
        isEnergyLeaking = isEnergyLeaking,
        anyBuildWillMStall = anyBuildWillMStall,
        anyBuildWillEStall = anyBuildWillEStall
      }
    end,
  }
end

-- ============================================================
-- Metal maker registry & unit lifecycle
-- ============================================================
local function RegisterMetalMaker(unitID, unitDef)
  if metalMakers[unitID] then
    return
  end
  local upkeep = unitDef.energyUpkeep or 0
  local makesMetal = unitDef.makesMetal or 0
  -- store the registered amounts so Unregister subtracts exactly what was added,
  -- even when the unit def can no longer be resolved
  metalMakers[unitID] = {upkeep = upkeep, makesMetal = makesMetal}
  cachedMetalMakersUpkeep = nil
  possibleMetalMakersUpkeep = possibleMetalMakersUpkeep + upkeep
  possibleMetalMakersMetalProduction = possibleMetalMakersMetalProduction + makesMetal
end

local function UnregisterMetalMaker(unitID)
  local registered = unitID and metalMakers[unitID]
  if not registered then
    return
  end
  metalMakers[unitID] = nil
  cachedMetalMakersUpkeep = nil
  possibleMetalMakersUpkeep = possibleMetalMakersUpkeep - registered.upkeep
  possibleMetalMakersMetalProduction = possibleMetalMakersMetalProduction - registered.makesMetal
end

local function isMetalMaker(unitDef)
  local customParams = unitDef.customParams or {}
  if
    unitDef.isBuilding and
      ((unitDef.onOffable and (unitDef.makesMetal or 0) > 0 and (unitDef.energyUpkeep or 0) > 0) or
        customParams.energyconv_capacity)
   then
    return true
  else
    return false
  end
end

function widget:UnitFinished(unitID, unitDefID, unitTeam)
  if unitTeam == myTeamId then
    local unitDef = UnitDefs[unitDefID]
    if not unitDef then
      return
    end
    AddBuilder(unitID, unitDefID)
    if isMetalMaker(unitDef) then
      RegisterMetalMaker(unitID, unitDef)
    end
  end
end

function widget:UnitDestroyed(unitID, _unitDefID, unitTeam)
  if unitTeam == myTeamId then
    RemoveBuilder(unitID)
    UnregisterMetalMaker(unitID)
  end
end

function widget:UnitGiven(unitID, unitDefID, unitTeam, oldTeam)
  widget:UnitFinished(unitID, unitDefID, unitTeam)
  widget:UnitDestroyed(unitID, nil, oldTeam)
end

function widget:UnitTaken(unitID, unitDefID, unitTeam, oldTeam)
  widget:UnitFinished(unitID, unitDefID, unitTeam)
  widget:UnitDestroyed(unitID, nil, oldTeam)
end

-- ============================================================
-- Math & sorting helpers
-- ============================================================
local function getBuildTimeLeft(targetId, targetDef)
  local _, _, _, _, build = GetUnitHealth(targetId)
  local currentBuildSpeed = assignedTargetBuildSpeed[targetId] or 0

  if not targetDef then
    targetDef = UnitDefs[GetUnitDefID(targetId)]
  end

  local buildLeft = (1 - build) * targetDef.buildTime

  local time = buildLeft / currentBuildSpeed

  return time
end

local function SortHealthAsc(a, b)
  return (a.health + ((a.maxHealth or 0) / 30)) < (b.health - ((b.maxHealth or 0) / 30))
end

local function FeatureSortByHealth(features)
  local feature
  for i = 1, #features do
    feature = features[i]
    feature.health, feature.maxHealth = GetFeatureHealth(feature.id)
  end
  table.sort(features, SortHealthAsc)
  return features
end

-- ============================================================
-- Order primitives & queue purging
-- ============================================================
local function reclaim(builderId, unitId)
  GiveOrderToUnit(builderId, CMD.INSERT, {0, CMD.RECLAIM, CMD.OPT_SHIFT, unitId}, {'alt'})
  InvalidatePurgedUnitCommands(builderId)
  emitDecision('reclaim', builderId, unitId)
end

local function reclaimByEcoType(builderId, features, needMetalNow, needEnergyNow)
  if needMetalNow and (needEnergyNow or needEnergy) and features['metalenergy'] and #features['metalenergy'] > 0 then
    features['metalenergy'] = FeatureSortByHealth(features['metalenergy'])
    reclaim(builderId, Game.maxUnits + features['metalenergy'][1].id)
  elseif needMetalNow and features['metal'] and #features['metal'] > 0 then
    features['metal'] = FeatureSortByHealth(features['metal'])
    reclaim(builderId, Game.maxUnits + features['metal'][1].id)
  elseif (needEnergyNow or needEnergy) and features['energy'] and #features['energy'] > 0 then
    features['energy'] = FeatureSortByHealth(features['energy'])
    reclaim(builderId, Game.maxUnits + features['energy'][1].id)
  end
end

local function isBeingReclaimed(targetId)
  return reclaimTargetsPrev.hash[targetId] ~= nil or reclaimTargets.hash[targetId] ~= nil
end

local function purgeRepairs(builderId, cmdQueue)
  if not cmdQueue then
    return {}
  end

  local removeCommands = {}
  local purgedQueue = {}
  -- BAR's ImmobileBuilder widget keeps nano turrets on a FIGHT order and answers an idle turret
  -- with an unshifted one, which also wipes whatever was ordered in between. Theirs stays.
  local builder = builders[builderId]
  local isImmobile = builder and not builder.def.canMove
  local gameFrame = Spring.GetGameFrame()
  local previousRemoveSentFrames = builder and builder.removeSentFrames or {}
  local removeSentFrames = {}
  for i = 1, #cmdQueue do
    local cmd = cmdQueue[i]
    local targetId = cmd.params[1]
    local shouldRemove = false
    local purgeKind = 'purge_repair'

    if cmd.id == CMD.REPAIR then -- 40
      local health, maxHealth, _, _, targetBuild = GetUnitHealth(targetId)
      if
        (targetBuild ~= nil and health ~= nil and targetBuild >= 1 and health >= maxHealth) or
          isBeingReclaimed(targetId)
       then
        shouldRemove = true
        if not targetBuild then
          reclaimTargets:Remove(targetId)
          reclaimTargetsPrev:Remove(targetId)
        end
      elseif isImmobile and health ~= nil and #cmd.params == 1 and not IsInBuildRange(builderId, targetId) then
        -- e.g. a damaged unit that walked off: the engine keeps the order and the turret waits on it forever
        shouldRemove = true
        purgeKind = 'purge_unreachable'
      end
    elseif cmd.id == CMD.RECLAIM then -- 90
      if #cmd.params == 1 then
        reclaimTargets:Add(targetId)
      end
    elseif cmd.id < 0 or (cmd.id == CMD.FIGHT and not isImmobile) then
      purgeKind = cmd.id < 0 and 'purge_build' or 'purge_fight'
      local buildQueueUnits = GetUnitsInCylinder(cmd.params[1], cmd.params[3], 5, myTeamId)
      if buildQueueUnits and #buildQueueUnits > 0 then
        local buildingUnitId = buildQueueUnits[1]
        local cylinderTargetDefId = GetUnitDefID(buildingUnitId)

        -- dont purge upgrades and when covered by con
        if
          UnitDefs[cylinderTargetDefId].isBuilding and not upgradableFromDefIds[cylinderTargetDefId] and
            not upgradableToDefIds[-cmd.id]
         then
          local health, maxHealth, _, _, targetBuild = GetUnitHealth(buildingUnitId)
          if targetBuild ~= nil and health ~= nil and targetBuild >= 1 and health >= maxHealth then
            shouldRemove = true
          elseif isBeingReclaimed(buildingUnitId) then
            shouldRemove = true
            reclaimTargets:Remove(buildingUnitId)
            reclaimTargetsPrev:Remove(buildingUnitId)
          end
        end
      end
    end

    if shouldRemove then
      local sentFrame = previousRemoveSentFrames[cmd.tag]
      local isOnItsWay = sentFrame and gameFrame - sentFrame < REMOVE_RESEND_FRAMES
      removeSentFrames[cmd.tag] = isOnItsWay and sentFrame or gameFrame
      if not isOnItsWay then
        removeCommands[#removeCommands + 1] = {CMD.REMOVE, {cmd.tag}, {'ctrl'}}
        emitDecision(purgeKind, builderId)
      end
    else
      purgedQueue[#purgedQueue + 1] = cmd
    end
  end

  if builder then
    builder.removeSentFrames = removeSentFrames
  end
  if #removeCommands > 0 then
    Spring.GiveOrderArrayToUnit(builderId, removeCommands)
  end
  purgedThisFrame[builderId] = purgedQueue
  return purgedQueue
end

InvalidatePurgedUnitCommands = function(builderId)
  purgedThisFrame[builderId] = nil
end

local function repair(builderId, targetId, shift)
  -- log('repairing', builderId, targetId, alt, Spring.GetGameFrame())
  if shift then
    GiveOrderToUnit(builderId, CMD.INSERT, {0, CMD.REPAIR, CMD.OPT_CTRL, targetId}, {'shift'})
  else
    GiveOrderToUnit(builderId, CMD.INSERT, {0, CMD.REPAIR, CMD.OPT_CTRL, targetId}, {'alt'})
  end
  InvalidatePurgedUnitCommands(builderId)
  SetBuilderLastOrder(builderId)
end

-- ============================================================
-- Resource state & needs
-- ============================================================
local function getMetalMakersUpkeep()
  if cachedMetalMakersUpkeep ~= nil then
    return cachedMetalMakersUpkeep
  end
  local totalUpKeep = 0
  for unitID in pairs(metalMakers) do
    local _, _, _, energy = GetUnitResources(unitID)
    totalUpKeep = totalUpKeep + energy
  end
  cachedMetalMakersUpkeep = totalUpKeep
  return totalUpKeep
end

local function readResourceSnapshot(resourceType)
  local current, storage, expenseWanted, income, expenseActual, shareSlider, sent, received =
    GetTeamResources(myTeamId, resourceType)

  current = current or 0
  storage = storage or 0
  income = income or 0
  expenseActual = expenseActual or 0

  local localDelta = income - expenseActual
  local level = SafeDivide(current, storage, 0)
  local runwaySeconds = localDelta < 0 and current / -localDelta or math.huge

  return {
    current = current,
    storage = storage,
    expenseWanted = expenseWanted or 0,
    income = income,
    expenseActual = expenseActual,
    shareSlider = shareSlider or 0,
    sent = sent or 0,
    received = received or 0,
    supply = income + (received or 0), -- own income plus what allies hand over: all that expense may draw on
    localDelta = localDelta,
    level = level,
    runwaySeconds = runwaySeconds,
    isOverflowing = level > LEAK_LEVEL,
    isLocallyPositive = localDelta > 0,
    isLocallyNegative = localDelta < 0
  }
end

local function ResourceDrainPressure(resourceSnapshot)
  if resourceSnapshot.current <= 0 then
    return 0
  end
  return Interpolate(
    (resourceSnapshot.expenseActual - resourceSnapshot.income) / resourceSnapshot.current,
    0, 10, 1, 0
  )
end

-- Converter state as published by game_energy_conversion.lua (BAR converter defs carry
-- no energyUpkeep, so unit-def upkeep sums cannot tell whether converters are saturated).
local function readConversionSnapshot()
  local level = Spring.GetTeamRulesParam(myTeamId, 'mmLevel')
  local use = Spring.GetTeamRulesParam(myTeamId, 'mmUse') or 0
  local capacity = Spring.GetTeamRulesParam(myTeamId, 'mmCapacity') or 0
  return {
    available = level ~= nil,
    level = level or 0,
    use = use,
    capacity = capacity,
    saturated = use >= capacity * MM_SATURATION, -- true with zero converters: nothing throttles the surplus
    floor = math.min((level or 0) + MM_LEVEL_BIAS, LEAK_LEVEL)
  }
end

local function recomputePowerNeed(metalSnapshot, energySnapshot)
  -- at or past break-even, more build power (assisted or placed) only turns the surplus into a stall
  local shortfall = Placement.buildPowerShortfall()
  if
    not needPower or isMetalStalling or isEnergyStalling or
      metalSnapshot.runwaySeconds < POWER_RUNWAY_SECONDS or
      energySnapshot.runwaySeconds < POWER_RUNWAY_SECONDS or
      (shortfall and shortfall <= 0)
   then
    powerNeed = 0
    return
  end

  local metalPressure = regularizedNegativeMetal and ResourceDrainPressure(metalSnapshot) or metalSnapshot.level
  local energyPressure = regularizedNegativeEnergy and ResourceDrainPressure(energySnapshot) or energySnapshot.level

  if positiveMMLevel and not needMM and not regularizedNegativeEnergy then
    energyPressure = metalSnapshot.level
  end

  powerNeed = math.max(POWER_NEED_AFFORDABLE_FLOOR, Clamp01(metalPressure * energyPressure))
end

local function recomputeEnergyAndMMNeed(metalSnapshot, energySnapshot, conversion)
  energyNeed = 0
  mMMNeed = 0

  if isEnergyStalling then
    energyNeed = 1
    return
  end

  local metalOverflowing = isMetalLeaking or metalSnapshot.isOverflowing
  local energyAboveMMLevel = energySnapshot.level > conversion.floor
  local energyInvestmentBlocked =
    energySnapshot.isOverflowing or isEnergyLeaking or
    (energyAboveMMLevel and energySnapshot.isLocallyNegative)

  if energyInvestmentBlocked then
    if
      not metalOverflowing and energyAboveMMLevel and conversion.saturated and
        not anyBuildWillEStall
     then
      mMMNeed = Interpolate(energySnapshot.level, conversion.floor, 1, 0.75, 1)
    end
    return
  end

  if anyBuildWillEStall or regularizedNegativeEnergy then
    energyNeed = Interpolate(energySnapshot.level, 0, conversion.floor, 1, 0.75)
    return
  end

  if positiveMMLevel then
    energyNeed = Interpolate(
      1 - (energySnapshot.level - conversion.floor) - (conversion.saturated and 0.5 or 0),
      0, 1, 0, 0.5
    )

    if energySnapshot.isLocallyPositive and energySnapshot.income > math.max(energySnapshot.expenseActual, energySnapshot.expenseWanted) then
      log('mm pos e', energySnapshot.level, conversion.floor)
      if
        energySnapshot.expenseWanted > energySnapshot.expenseActual and
          metalSnapshot.expenseWanted > metalSnapshot.expenseActual and
          energySnapshot.expenseActual > 0 and
          metalSnapshot.expenseActual > 0
       then
        local eRatio = energySnapshot.expenseWanted / energySnapshot.expenseActual
        local mRatio = metalSnapshot.expenseWanted / metalSnapshot.expenseActual
        local ratioTotal = eRatio + mRatio
        if ratioTotal > 0 then
          energyNeed = eRatio / ratioTotal
          mMMNeed = mRatio / ratioTotal
          log(string.format('ratios e %0.2f m %0.2f need e %0.2f m %0.2f', eRatio, mRatio, energyNeed, mMMNeed))
        end
      else
        mMMNeed = Interpolate(energySnapshot.level, conversion.floor, 1, 0.75, 1)
      end
    else
      mMMNeed = Interpolate(energySnapshot.level, conversion.floor, 1, 0.5, 1)
    end
  elseif regularizedPositiveEnergy then
    energyNeed = Interpolate(energySnapshot.level, 0, conversion.floor, 1, 0.75)
  else
    energyNeed = anyBuildWillMStall and Interpolate(energySnapshot.level, 0, conversion.floor, 1, 0.75) or 0.5
  end

  -- clamp: don't build more of a resource type that is already overflowing
  if isEnergyLeaking or energySnapshot.isOverflowing then
    energyNeed = 0
  end
  if metalOverflowing then
    mMMNeed = 0
  end
end

-- Sign of the windowed mean: 1 rising, -1 falling, 0 flat (within the dead band).
local function TrendSign(samples, deadband)
  local count = #samples
  if count == 0 then
    return 0
  end
  local sum = 0
  for i = 1, count do
    sum = sum + samples[i]
  end
  local mean = sum / count
  if mean > deadband then
    return 1
  end
  if mean < -deadband then
    return -1
  end
  return 0
end

local function UpdateResourceNeeds()
  local metalSnapshot = readResourceSnapshot('metal')
  local energySnapshot = readResourceSnapshot('energy')
  conversionSnapshot = readConversionSnapshot()

  regularizationCounter = (regularizationCounter % REGULARIZATION_WINDOW) + 1
  regularizedResourceDerivativesMetal[regularizationCounter] = metalSnapshot.localDelta
  regularizedResourceDerivativesEnergy[regularizationCounter] = energySnapshot.localDelta
  local metalTrend = TrendSign(regularizedResourceDerivativesMetal, TREND_DEADBAND * metalSnapshot.storage)
  local energyTrend = TrendSign(regularizedResourceDerivativesEnergy, TREND_DEADBAND * energySnapshot.storage)
  regularizedPositiveMetal = metalTrend > 0
  regularizedPositiveEnergy = energyTrend > 0
  regularizedNegativeMetal = metalTrend < 0
  regularizedNegativeEnergy = energyTrend < 0

  metalLevel = metalSnapshot.level
  energyLevel = energySnapshot.level

  positiveMMLevel = conversionSnapshot.saturated and energyLevel > conversionSnapshot.floor

  isMetalStalling = metalLevel < STALL_LEVEL and not regularizedPositiveMetal
  isEnergyStalling = energyLevel < STALL_LEVEL and not regularizedPositiveEnergy
  isMetalLeaking = metalSnapshot.isOverflowing and regularizedPositiveMetal
  isEnergyLeaking = energySnapshot.isOverflowing and regularizedPositiveEnergy

  needPower =
    (metalLevel > METAL_LEVEL_HIGH or (regularizedPositiveMetal and metalLevel > METAL_LEVEL_LOW)) and
    (positiveMMLevel or not regularizedNegativeEnergy)
  needEnergy =
    isEnergyStalling or
    not (energySnapshot.isOverflowing or isEnergyLeaking or (energyLevel > conversionSnapshot.floor and energySnapshot.isLocallyNegative))
  needMM =
    positiveMMLevel and not metalSnapshot.isOverflowing and
    (not regularizedNegativeEnergy or isEnergyLeaking or isMetalStalling)

  recomputePowerNeed(metalSnapshot, energySnapshot)
  recomputeEnergyAndMMNeed(metalSnapshot, energySnapshot, conversionSnapshot)
end

local function PopulateResourceStatus()
  if cachedResourceStatus.metal and cachedResourceStatus.energy then
    return
  end

  local resourceData = {}
  for _, resourceType in ipairs({'metal', 'energy'}) do
    local current, storage, pullExpWanted, income, _, _, _, received = GetTeamResources(myTeamId, resourceType)
    if income then
      resourceData[resourceType] = {
        total = received or 0,
        current = current or 0,
        storage = storage or 0,
        pullExpWanted = pullExpWanted or 0,
        income = income,
        expense = 0
      }
    end
  end

  local units = GetTeamUnits(myTeamId)
  for i = 1, #units do
    local metalMake, metalUse, energyMake, energyUse = GetUnitResources(units[i])
    local metal = resourceData.metal
    if metal then
      metalMake = metalMake or 0
      metalUse = metalUse or 0
      metal.total = metal.total + metalMake - metalUse
      metal.expense = metal.expense + metalUse
    end

    local energy = resourceData.energy
    if energy then
      energyMake = energyMake or 0
      energyUse = energyUse or 0
      energy.total = energy.total + energyMake - energyUse
      energy.expense = energy.expense + energyUse
    end
  end

  for resourceType, data in pairs(resourceData) do
    local drainRate = data.pullExpWanted - data.income
    local alreadyInStall = drainRate > 0 and data.current < drainRate * STALL_RUNWAY_SECONDS
    cachedResourceStatus[resourceType] = {
      data.total,
      data.current,
      data.storage,
      data.expense,
      alreadyInStall
    }
  end
end

local function GetResourceStatus(resourceType)
  if not cachedResourceStatus[resourceType] then
    PopulateResourceStatus()
  end

  if cachedResourceStatus[resourceType] then
    local c = cachedResourceStatus[resourceType]
    return c[1], c[2], c[3], c[4], c[5]
  end
end

-- ============================================================
-- Stall prediction
-- ============================================================
local function buildingWillStallType(type, consumption, secondsLeft, releasedExpenditures)
  local currentChange, lvl, _, _, alreadyInStall = GetResourceStatus(type)

  local changeWhenBuilding = currentChange - consumption + releasedExpenditures

  -- log('buildingWillStallType', type, 'currentChange', currentChange, 'consumption', consumption, 'changeWhenBuilding', changeWhenBuilding, 'releasedExpenditures', releasedExpenditures)

  if type == 'metal' then
    changeWhenBuilding = changeWhenBuilding - releasedMetal
  end

  releasedMetal = 0
  if type == 'energy' and possibleMetalMakersUpkeep > 0 then
    local metalMakersUpkeep = getMetalMakersUpkeep()
    if changeWhenBuilding < 0 then
      changeWhenBuilding = changeWhenBuilding + metalMakersUpkeep

      local releasedEnergy
      if changeWhenBuilding > 0 then
        releasedEnergy = changeWhenBuilding
        changeWhenBuilding = 0
      else
        releasedEnergy = metalMakersUpkeep
      end
      releasedMetal = possibleMetalMakersMetalProduction * releasedEnergy / possibleMetalMakersUpkeep
    end
  end

  local after = lvl + secondsLeft * changeWhenBuilding

  -- log('buildingWillStallType', type, 'secondsLeft', secondsLeft, 'consumption', consumption, 'changeWhenBuilding', changeWhenBuilding, 'after', after, 'alreadyInStall', alreadyInStall)

  return (alreadyInStall or after < 0) and consumption > 1

  -- return not (consumption < 1 or (not alreadyInStall and after > 0)
  -- if consumption < 1 or (not alreadyInStall and after > 0) then
  --   return changeWhenBuilding > 0
  -- else
  --   return true
  -- end
end

local function getUnitsUpkeep()
  if cachedUnitsUpkeep then
    return cachedUnitsUpkeep[1], cachedUnitsUpkeep[2]
  end

  local metal = 0
  local energy = 0

  local i = 1
  while i <= builderUnitIds.count do
    local unitID = builderUnitIds.list[i]
    local builder = builders[unitID]
    if builder then
      local metalMake, metalUse, energyMake, energyUse = GetUnitResources(unitID)
      metal = metal + (metalUse or 0) - (metalMake or 0) + (builder.def.metalMake or 0)
      energy = energy + (energyUse or 0) - (energyMake or 0) + (builder.def.energyMake or 0)
      i = i + 1
    else
      RemoveBuilder(unitID)
    end
  end

  cachedUnitsUpkeep = {metal, energy}
  return metal, energy
end

local function IsTimeToMoveOn(secondsLeft, builderId, builderDef, targetTotalBuildSpeed)
  if not targetTotalBuildSpeed then
    return false
  end
  local plannerBuildSpeed = BuilderById(builderId).def.buildSpeed
  local plannerBuildShare = plannerBuildSpeed / targetTotalBuildSpeed
  local slowness = (45 / builderDef.speed)
  local moduloBonus = ((gameFrameModulo * buildersJitterModulo) / 30) / 2
  if
    ((plannerBuildShare < 0.75 and secondsLeft < (1.2 * slowness + moduloBonus)) or
      (plannerBuildShare < 0.5 and secondsLeft < (3.4 * slowness + moduloBonus)) or
      (plannerBuildShare < 0.15 and secondsLeft < (8 * slowness + moduloBonus)) or
      (plannerBuildShare < 0.05 and secondsLeft < (12 * slowness + moduloBonus)))
   then
    return true
  else
    return false
  end
end

local function TargetWillStall(targetId, targetDef, targetTotalBuildSpeed, secondsLeft)
  if cachedTargetWillStall[targetId] then
    local c = cachedTargetWillStall[targetId]
    return c[1], c[2], c[3]
  end

  if not targetDef then
    targetDef = UnitIdDef(targetId)
  end
  if not targetTotalBuildSpeed then
    targetTotalBuildSpeed = assignedTargetBuildSpeed[targetId]
  end
  if not secondsLeft then
    secondsLeft = getBuildTimeLeft(targetId, targetDef)
  end
  local speed = targetDef.buildTime / targetTotalBuildSpeed
  local metal = targetDef.metalCost / speed
  local energy = targetDef.energyCost / speed

  local mDrain, eDrain = getUnitsUpkeep()

  -- log('targetWillStall', 'secondsLeft', secondsLeft, 'totalBuildSpeed', totalBuildSpeed, 'speed', speed, 'metal', metal, 'energy', energy, 'mDrain', mDrain, 'eDrain', eDrain)
  local eStall = buildingWillStallType('energy', energy, secondsLeft, eDrain)
  local mStall = buildingWillStallType('metal', metal, secondsLeft, mDrain)

  cachedTargetWillStall[targetId] = {mStall or eStall, mStall, eStall}
  return mStall or eStall, mStall, eStall
end

-- ============================================================
-- Build prioritization & feature scanning
-- ============================================================
local function scoreEcoCandidate(candidate)
  if not candidate or not candidate.defId then
    return 0
  end

  return
    powerNeed * (defBuildPowerScore[candidate.defId] or 0) +
    energyNeed * (defEnergyScore[candidate.defId] or 0) +
    mMMNeed * (defMetalMMScore[candidate.defId] or 0)
end

local function ScoreEcoCandidates(candidates)
  for i = 1, #candidates do
    candidates[i].score = scoreEcoCandidate(candidates[i])
  end
end

local function BuildQueueSkipAssisted(builder, targetId, cmdQueueTag, _cmdQueueTagg)
  local targetDef = UnitDefs[GetUnitDefID(targetId)]
  local targetTotalBuildSpeed = assignedTargetBuildSpeed[targetId]
  local secondsLeft = getBuildTimeLeft(targetId, targetDef)
  -- log('ff', Spring.GetGameFrame())
  -- table.echo(
  --   {
  --     leave = forwardedFromTargetIds.hash[targetId] == nil,
  --     id = forwardedFromTargetIds.hash[targetId],
  --     time = IsTimeToMoveOn(secondsLeft, builder.id, builder.def, totalBuildSpeed),
  --     nostall = not TargetWillStall(targetId, targetDef, totalBuildSpeed, secondsLeft),
  --   }
  -- )
  -- target has previously been abandoned
  -- local gf = Spring.GetGameFrame()
  if IsUnitSelectedLog(builder.id) then
    log(
      builder.id,
      'ff from ' ..
        (forwardedFromTargetIds.hash[targetId] == nil and '1' or '0') ..
          ' time ' ..
            (IsTimeToMoveOn(secondsLeft, builder.id, builder.def, targetTotalBuildSpeed) and '1' or '0') ..
              ' eco ' ..
                (not TargetWillStall(targetId, targetDef, targetTotalBuildSpeed, secondsLeft) and '1' or '0') ..
                  ' dbg ' .. targetTotalBuildSpeed .. ' ' .. secondsLeft .. ' ' .. tostring(Spring.GetGameFrame())
    )
  end
  if
    forwardedFromTargetIds.hash[targetId] == nil and
      IsTimeToMoveOn(secondsLeft, builder.id, builder.def, targetTotalBuildSpeed) and
      not TargetWillStall(targetId, targetDef, targetTotalBuildSpeed, secondsLeft)
   then
    if IsUnitSelectedLog(builder.id) then
      log(
        builder.id,
        'moving on',
        forwardedFromTargetIds.hash[targetId] == nil,
        IsTimeToMoveOn(secondsLeft, builder.id, builder.def, targetTotalBuildSpeed),
        not TargetWillStall(targetId, targetDef, targetTotalBuildSpeed, secondsLeft)
      )
    end

    -- moveOnFromBuilding(builder.id, targetId, cmdQueueTag, cmdQueueTagg)
    GiveOrderToUnit(builder.id, CMD.REMOVE, {cmdQueueTag}, {'ctrl'}) -- was 0 instead of 'ctrl' for a while
    InvalidatePurgedUnitCommands(builder.id)
    emitDecision('skip_assisted', builder.id, targetId)
    if targetId then
      forwardedFromTargetIds:Add(targetId)
    end
  end
end

local function getReclaimableFeatures(x, z, radius)
  local wrecksInRange = GetFeaturesInCylinder(x, z, radius)
  local nWrecksInRange = #wrecksInRange

  local features = {
    ['metalenergy'] = {},
    ['metal'] = {},
    ['energy'] = {},
    ['all'] = {}
  }

  if nWrecksInRange == 0 then
    return features, 0
  end

  local nME = 0
  local nM = 0
  local nE = 0
  local nAll = 0
  for i = 1, nWrecksInRange do
    local featureId = wrecksInRange[i]

    local featureRessurrect = GetFeatureResurrect(featureId)
    if not protectedResurrectDefNames[featureRessurrect] then
      local metal, _, energy = GetFeatureResources(featureId)

      nAll = nAll + 1
      features['all'][nAll] = {id = featureId}
      if metal > 0 and energy > 0 then
        nME = nME + 1
        features['metalenergy'][nME] = {id = featureId}
      elseif metal > 0 then
        nM = nM + 1
        features['metal'][nM] = {id = featureId}
      elseif energy > 0 then
        nE = nE + 1
        features['energy'][nE] = {id = featureId}
      end
    end
  end
  return features, nAll
end

local function GetSingleReclaimFeatureId(command)
  if not command or command.id ~= CMD.RECLAIM then return end
  local params = command.params
  if not params or #params ~= 1 then return end

  local encodedTargetID = tonumber(params[1])
  if not encodedTargetID or encodedTargetID <= Game.maxUnits then return end
  return encodedTargetID - Game.maxUnits
end

local function SortBuildEcoPrio(a, b)
  if a == nil or b == nil then
    return false
  end
  if a.defId == b.defId and a.build ~= b.build then
    return a.build > b.build
  end

  local scoreA = a.score or 0
  local scoreB = b.score or 0
  if scoreA ~= scoreB then
    return scoreA > scoreB
  end

  if a.build ~= b.build then
    return a.build > b.build
  end
  -- if a and b then
  -- log('SortBuildEcoPrio p', math.floor(0.5 + powerNeed * 100), 'e', math.floor(0.5 + energyNeed * 100), 'm', math.floor(0.5 + mMMNeed * 100), scoreA, scoreB, a.def.translatedHumanName, b.def.translatedHumanName, a.build, b.build)
  -- end
  return (a.id or 0) < (b.id or 0)
end

-- ============================================================
-- Per-builder dispatch (idle / repair / reclaim decisions)
-- ============================================================
local function GetPurgedUnitCommands(builderId, queueSize)
  local cached = purgedThisFrame[builderId]
  if cached then
    return cached, #cached
  end
  if queueSize == nil then
    queueSize = 100
  end
  local commandQueue = GetUnitCommands(builderId, queueSize)
  if commandQueue == nil then
    widget:UnitDestroyed(builderId, nil, myTeamId)
    return nil, 0
  end

  commandQueue = purgeRepairs(builderId, commandQueue)
  return commandQueue, #commandQueue
end

local function scanNearbyBuildables(builder)
  local builderId = builder.id
  local builderDef = builder.def
  local builderPosX, _, builderPosZ = GetUnitBasePosition(builderId)
  local candidateIds = GetUnitsInCylinder(builderPosX, builderPosZ, builderDef.buildDistance + CANDIDATE_SCAN_PADDING, myTeamId)
  local damaged = {}
  local unfinished = {}
  local guardBuilders = {}
  local nDamaged = 0
  local nUnfinished = 0

  for j = 1, #candidateIds do
    local candidateId = candidateIds[j]
    if candidateId ~= builderId then
      local candidateHealth, candidateMaxHealth, _, _, candidateBuild = GetUnitHealth(candidateId)
      if
        candidateHealth ~= nil and candidateMaxHealth ~= nil and
          (candidateHealth < candidateMaxHealth or candidateBuild < 1)
       then
        local candidateDefId = GetUnitDefID(candidateId)
        if IsInBuildRange(builderId, candidateId) then
          local candidate = {
            id = candidateId,
            defId = candidateDefId,
            def = UnitDefs[candidateDefId],
            health = candidateHealth,
            maxHealth = candidateMaxHealth,
            build = candidateBuild,
            healthRatio = candidateHealth / candidateMaxHealth
          }
          if candidateBuild < 1 then
            nUnfinished = nUnfinished + 1
            unfinished[nUnfinished] = candidate
          elseif candidateHealth < candidateMaxHealth then
            nDamaged = nDamaged + 1
            damaged[nDamaged] = candidate
          else
            local candidateQueue = GetUnitCommands(candidateId, 3)
            if candidateQueue and #candidateQueue > 0 and candidateQueue[1].id < 0 then
              table.insert(guardBuilders, candidateId)
            end
          end
        end
      end
    end
  end

  return damaged, nDamaged, unfinished, nUnfinished, guardBuilders, builderPosX, builderPosZ
end

local function tryReclaimOrGuard(builder, builderPosX, builderPosZ, isBuildingEco, guardBuilders)
  local builderId = builder.id
  local builderDef = builder.def
  local features = {}
  local nFeaturesAll = 0
  local _needMetal = metalLevel < 0.9
  local _needEnergy = needEnergy or energyLevel < 0.9
  local cmdQueue, nCmdQueue = GetPurgedUnitCommands(builderId)

  if
    not isMetalLeaking and not isEnergyLeaking and builderDef and
      (#builderDef.buildOptions == 0 or nCmdQueue == 0 or not isBuildingEco)
   then
    features, nFeaturesAll = getReclaimableFeatures(builderPosX, builderPosZ, builderDef.buildDistance)
    if features then
      if _needMetal and _needEnergy then
        reclaimByEcoType(builderId, features, true, true)
      elseif _needMetal then
        reclaimByEcoType(builderId, features, true, false)
      elseif _needEnergy then
        reclaimByEcoType(builderId, features, false, true)
      end
    end
  elseif
    cmdQueue and nCmdQueue > 0 and cmdQueue[1].id == CMD.RECLAIM and
      (metalLevel > 0.97 or energyLevel > 0.97 or isMetalLeaking or isEnergyLeaking)
   then
    local featureId = GetSingleReclaimFeatureId(cmdQueue[1])
    if featureId then
      local metal, _, energy = GetFeatureResources(featureId)
      if metal and metal > 0 and (metalLevel > 0.97 or isMetalLeaking) then
        GiveOrderToUnit(builderId, CMD.REMOVE, {nil}, {'ctrl'})
        InvalidatePurgedUnitCommands(builderId)
        emitDecision('reclaim_cancel', builderId)
      elseif energy and energy > 0 and (energyLevel > 0.97 or isEnergyLeaking) then
        GiveOrderToUnit(builderId, CMD.REMOVE, {nil}, {'ctrl'})
        InvalidatePurgedUnitCommands(builderId)
        emitDecision('reclaim_cancel', builderId)
      end
    end
  else
    local reclaiming = false
    if MRandom() < (builderDef.translatedHumanName == 'Base Builder' and 0.6 or 0.16) then
      features, nFeaturesAll = getReclaimableFeatures(builderPosX, builderPosZ, builderDef.buildDistance)
      if nFeaturesAll > 0 then
        local featuresAll = FeatureSortByHealth(features.all)
        for i = 1, nFeaturesAll do
          local feature = featuresAll[i]
          if feature and feature.health and feature.health < 81 then
            GiveOrderToUnit(
              builderId, CMD.INSERT,
              {0, CMD.RECLAIM, CMD.OPT_SHIFT, Game.maxUnits + feature.id},
              {'alt'}
            )
            InvalidatePurgedUnitCommands(builderId)
            emitDecision('clear_wreck', builderId)
            reclaiming = true
            break
          elseif feature and feature.health and feature.health >= 81 then
            break
          end
        end
      end
    end

    if not reclaiming and #guardBuilders > 0 then
      log('guarding', builderDef.translatedHumanName, '->', guardBuilders[1])
      GiveOrderToUnit(builderId, CMD.INSERT, {0, CMD.GUARD, CMD.OPT_SHIFT, guardBuilders[1]}, {'alt'})
      InvalidatePurgedUnitCommands(builderId)
      emitDecision('guard', builderId, guardBuilders[1])
    end
  end

  return features, nFeaturesAll
end

local function shouldTryReclaimOrGuard(multiSlotBuildQueue, isRepairingDamaged, targetHealthRatio, nDamaged, nUnfinished, builderDef)
  if multiSlotBuildQueue then return false end

  -- if currently repairing damaged, only override when this builder's resource need is severe
  -- and the damaged-pool is small enough that we don't need to keep helping
  if isRepairingDamaged then
    local resourceNeedSevere =
      energyNeed > (1 - targetHealthRatio) or mMMNeed > (1 - targetHealthRatio) or
      energyLevel < targetHealthRatio or metalLevel < targetHealthRatio
    if not (resourceNeedSevere and nDamaged < 5) then return false end
  end

  -- only act when there's nothing more useful to do (no unfinished targets, or stalls override)
  return nUnfinished == 0 or isEnergyStalling or isMetalStalling or
    (nUnfinished > 0 and (anyBuildWillEStall or anyBuildWillMStall) and
      (builderDef.buildSpeed < 0.2 * totalBuildSpeed or (metalLevel < 0.05 and energyLevel < 0.05)))
end

local function tryRepairMostDamaged(builder, targetId, damaged, nDamaged, multiSlotBuildQueue, gameFrame)
  local targetHealthRatio = 1
  local isRepairingDamaged = false
  if nDamaged == 0 or not targetId then
    return isRepairingDamaged, targetHealthRatio
  end

  table.sort(damaged, SortHealthAsc)
  local damagedTarget = damaged[1]
  local damagedTargetId = damagedTarget.id
  local targetHealth, targetMaxHealth = GetUnitHealth(targetId)
  targetHealthRatio = targetHealth / targetMaxHealth

  if
    targetId ~= damagedTargetId and
      (not targetHealthRatio or targetHealthRatio == 0 or damagedTarget.healthRatio * 0.95 < targetHealthRatio) and
      not isBeingReclaimed(damagedTargetId) and
      AllowBuilderOrder(builder.id, gameFrame) and
      not multiSlotBuildQueue
   then
    repair(builder.id, damagedTargetId, false)
    emitDecision('repair_damaged', builder.id, damagedTargetId)
    isRepairingDamaged = true
  end
  return isRepairingDamaged, targetHealthRatio
end

local function dispatchIdleActions(builder, targetId, cmdQueue, nCmdQueue, gameFrame, multiSlotBuildQueue)
  local builderId = builder.id

  local isBuildingEco =
    nCmdQueue == 0 or
    (cmdQueue[1] and
      (((cmdQueue[1].id == CMD.REPAIR) and (ecoBuildDefIds[GetUnitDefID(cmdQueue[1].params[1])])) or
        ((ecoBuildDefIds[-cmdQueue[1].id]) and GetUnitIsBuilding(builderId) ~= nil)))

  -- dont disturb buildqueuers, ecoers and pass through candidate fetching
  if hasOwnBuildOrder(cmdQueue) and not isBuildingEco and not multiSlotBuildQueue then
    return {}, 0, nil, 0
  end

  local builderDef = builder.def
  local features = {}
  local nFeaturesAll = 0
  local candidatesDamaged, nCandidatesDamaged, candidatesUnfinished, nCandidatesUnfinished, candidatesGuardBuilders, builderPosX, builderPosZ =
    scanNearbyBuildables(builder)

  local isRepairingDamaged, targetHealthRatio =
    tryRepairMostDamaged(builder, targetId, candidatesDamaged, nCandidatesDamaged, multiSlotBuildQueue, gameFrame)

  if nCandidatesUnfinished > 0 and (not isRepairingDamaged or multiSlotBuildQueue) then
    ScoreEcoCandidates(candidatesUnfinished)
    table.sort(candidatesUnfinished, SortBuildEcoPrio)
  end

  if shouldTryReclaimOrGuard(multiSlotBuildQueue, isRepairingDamaged, targetHealthRatio, nCandidatesDamaged, nCandidatesUnfinished, builderDef) then
    features, nFeaturesAll = tryReclaimOrGuard(builder, builderPosX, builderPosZ, isBuildingEco, candidatesGuardBuilders)
  end

  return candidatesUnfinished, nCandidatesUnfinished, features, nFeaturesAll
end

local function SortBuildBuildSpeed(a, b)
  return (a.buildSpeed * a.build) > (b.buildSpeed * b.build)
end

-- ============================================================
-- Batch eco assignment
-- ============================================================
local function getCandidateAlternatives(ecoBuildingList)
  local candidateAlternatives = {}
  local candidateAlternativeUnitIds = Spring.GetTeamUnitsByDefs(myTeamId, ecoBuildingList)

  for i = 1, #candidateAlternativeUnitIds do
    local unitId = candidateAlternativeUnitIds[i]
    local build = select(5, GetUnitHealth(unitId))
    if build and build < 1 and getBuildTimeLeft(unitId, UnitDefs[GetUnitDefID(unitId)]) >= MIN_ASSIGN_SECONDS then
      local x, _, z = GetUnitBasePosition(unitId)
      table.insert(
        candidateAlternatives,
        {
          id = unitId,
          build = build,
          buildSpeed = 0,
          builderIds = {},
          alreadyBuilding = {},
          x = x,
          z = z,
          radius = GetUnitBuildeeRadius(unitId) or 0
        }
      )
    end
  end

  return candidateAlternatives
end

-- The engine (CBuilderCAI::IsInBuildRange) accepts a target whose 2D center distance is within
-- buildDistance + the target's buildee radius. A nano turret ordered beyond that keeps the order at
-- its queue front and stands still until others finish the target, so it gets exactly the engine's
-- reach; a mobile builder walks the last elmos and keeps a wider one.
local function IsWithinBuildRange(builderSnapshot, candidate)
  if not builderSnapshot.x or not builderSnapshot.z or not candidate.x or not candidate.z then
    return false
  end

  local builderDef = builderSnapshot.builder.def
  local centerRange = builderDef.buildDistance + candidate.radius
  if builderDef.canMove then
    centerRange = centerRange + builderSnapshot.radius - 12
  end
  local deltaX = builderSnapshot.x - candidate.x
  local deltaZ = builderSnapshot.z - candidate.z
  return deltaX * deltaX + deltaZ * deltaZ < centerRange * centerRange
end

local function BuildBatchBuilderSnapshots(gameFrame)
  local snapshots = {}
  local i = 1
  while i <= builderUnitIds.count do
    local builderID = builderUnitIds.list[i]
    local builder = builders[builderID]
    if not builder then
      RemoveBuilder(builderID)
    else
      local commandQueue = GetUnitCommands(builderID, 3)
      local firstCommand = commandQueue and commandQueue[1]
      local busy = firstCommand and (busyCommands[firstCommand.id] or firstCommand.id < 0) or false
      local snapshot = {
        builder = builder,
        busy = busy,
        targetDefID = builder.targetId and GetUnitDefID(builder.targetId)
      }

      if
        not busy and builder.targetId ~= builderID and not selectedUnits[builderID] and
          AllowBuilderOrder(builderID, gameFrame)
       then
        local x, _, z = GetUnitBasePosition(builderID)
        snapshot.x = x
        snapshot.z = z
        snapshot.radius = GetUnitRadius(builderID) or 0
        snapshot.isCandidate = snapshot.x ~= nil and snapshot.z ~= nil
      end

      snapshots[#snapshots + 1] = snapshot
      i = i + 1
    end
  end
  return snapshots
end

local function NormalizedPositiveNeeds()
  local needs = {
    {'power', powerNeed},
    {'energy', energyNeed},
    {'mMM', mMMNeed}
  }
  local positiveNeeds = {}

  for _, need in ipairs(needs) do
    local needName = need[1]
    local needValue = need[2]
    if needValue and needValue > 0 then
      local ecoBuildingList = ecoBuildingTypeDefIds[needName].list
      local candidateAlternatives = getCandidateAlternatives(ecoBuildingList)
      if #candidateAlternatives > 0 then
        table.insert(positiveNeeds, {
          name = needName,
          value = needValue,
          candidateAlternatives = candidateAlternatives
        })
      end
    end
  end

  if #positiveNeeds == 0 then
    return positiveNeeds
  end

  table.sort(
    positiveNeeds,
    function(a, b)
      if a.value == b.value then
        return a.name < b.name
      end
      return a.value > b.value
    end
  )

  -- Scale down only when the needs claim more than every builder. Normalizing up would hand a
  -- small residual need (e.g. energy 0.19 at 99% storage) all builders whenever the dominant
  -- need has nothing to assist.
  local sum = 0
  for _, need in ipairs(positiveNeeds) do
    sum = sum + need.value
  end
  local scale = math.max(1, sum)
  for _, need in ipairs(positiveNeeds) do
    need.value = need.value / scale
  end

  return positiveNeeds
end

local function BatchOrder(gameFrame)
  local needs = NormalizedPositiveNeeds()
  if #needs == 0 then
    return
  end

  local assignedBuilders = {}
  local builderSnapshots = BuildBatchBuilderSnapshots(gameFrame)
  for _, need in ipairs(needs) do
    local needName = need.name
    local needValue = need.value
    -- Get the ecoBuildingDefIds[type].map for the current need type
    local ecoBuildingMap = ecoBuildingTypeDefIds[needName].map

    -- Get candidates for alternative builds (units to assist or start new builds)
    local candidateAlternatives = need.candidateAlternatives

    -- Filter builders not selected and not throttled
    local candidateBuilderCount = 0
    local correctTypeBuilders = 0
    local incorrectTypeBuilders = 0
    for i = 1, #builderSnapshots do
      local snapshot = builderSnapshots[i]
      local builder = snapshot.builder
      if not assignedBuilders[builder.id] and not snapshot.busy then
        if builder.targetId ~= builder.id then
          if snapshot.targetDefID then
            if ecoBuildingMap[snapshot.targetDefID] then
              correctTypeBuilders = correctTypeBuilders + 1
            else
              incorrectTypeBuilders = incorrectTypeBuilders + 1
            end
          end

          if snapshot.isCandidate then
            candidateBuilderCount = candidateBuilderCount + 1
            for j = 1, #candidateAlternatives do
              local candidate = candidateAlternatives[j]
              if IsWithinBuildRange(snapshot, candidate) then
                candidate.buildSpeed = candidate.buildSpeed + builder.def.buildSpeed
                if builder.targetId == candidate.id then
                  candidate.alreadyBuilding[builder.id] = true
                end
                table.insert(candidate.builderIds, builder.id)
              end
            end
          end
        end
      end
    end

    -- Sort by build power * construction progress
    table.sort(candidateAlternatives, SortBuildBuildSpeed)

    -- Assign a subset of builders to assist or start new builds
    local targets = {}
    local nTotalBuilders = math.max(correctTypeBuilders + incorrectTypeBuilders, candidateBuilderCount)
    if nTotalBuilders > 0 then
      local assignedForNeed = 0
      local fulfilledNeed = 0
      -- log(needName, 'total', nTotalBuilders, 'correct', correctTypeBuilders, 'incorrect', incorrectTypeBuilders)
      for _, candidateAlternative in ipairs(candidateAlternatives) do
        for _, builderId in ipairs(candidateAlternative.builderIds) do
          if not assignedBuilders[builderId] then
            if fulfilledNeed < needValue then
              if targets[candidateAlternative.id] == nil then
                targets[candidateAlternative.id] = {}
              end

              assignedBuilders[builderId] = true
              assignedForNeed = assignedForNeed + 1
              fulfilledNeed = assignedForNeed / nTotalBuilders

              if not candidateAlternative.alreadyBuilding[builderId] then
                table.insert(targets[candidateAlternative.id], builderId)
                AddObjectSpotlight(
                  'unit',
                  'me',
                  builderId,
                  {0, 1, 0, 1},
                  {duration = 25, radius = 2, heightCoefficient = 5}
                )
                local assignedBuilder = builders[builderId]
                if assignedBuilder then
                  assignedBuilder.targetId = candidateAlternative.id
                end
                SetBuilderLastOrder(builderId)
              end
            else
              break
            end
          end
        end
        if fulfilledNeed >= needValue then
          break
        end
      end

      -- If there are builders to assign, issue a batch order
      if assignedForNeed > 0 then
        for targetId, _builders in pairs(targets) do
          if #_builders > 0 then
            -- log(string.format('p %0i e %i m %i', powerNeed * 100, energyNeed * 100, mMMNeed * 100))
            if isUnitLogActive then
              log(
                needName ..
                  string.format(
                    ' batch %.2f builders %s/%s %s target ',
                    needValue,
                    #_builders,
                    nTotalBuilders,
                    table.tostring(_builders)
                  ) ..
                    targetId,
                UnitDefs[GetUnitDefID(targetId)].translatedHumanName,
                gameFrame
              )
            end

            Spring.GiveOrderToUnitArray(_builders, CMD.INSERT, {0, CMD.REPAIR, CMD.OPT_CTRL, targetId}, {'alt'})
            for _, builderId in ipairs(_builders) do
              emitDecision('assign_' .. needName, builderId, targetId)
            end
          end
        end
      end
    end
  end
end

-- ============================================================
-- Placement: when a need has nothing to assist, extend the player's own cluster of that type
-- with one more building, directly adjacent to an existing one, in the builder's own version.
-- ============================================================
function Placement.halfExtents(unitDef, facing)
  local rotated = facing % 2 == 1
  local halfX = (rotated and unitDef.zsize or unitDef.xsize) * 4
  local halfZ = (rotated and unitDef.xsize or unitDef.zsize) * 4
  return halfX, halfZ
end

-- The four positions whose footprint touches the anchor's.
function Placement.adjacentPositions(anchorX, anchorZ, anchorHalfX, anchorHalfZ, halfX, halfZ)
  return {
    {anchorX + anchorHalfX + halfX, anchorZ},
    {anchorX - anchorHalfX - halfX, anchorZ},
    {anchorX, anchorZ + anchorHalfZ + halfZ},
    {anchorX, anchorZ - anchorHalfZ - halfZ}
  }
end

-- What one building of the type gives per second: energy made, energy a converter can use up, build power.
function Placement.perBuilding(ecoType, unitDef)
  if ecoType == 'energy' then
    return EnergyMakeDef(unitDef)
  end
  if ecoType == 'mMM' then
    return tonumber((unitDef.customParams or {}).energyconv_capacity) or 0
  end
  return unitDef.buildSpeed or 0
end

-- What a round of the type should cover, in the unit of perBuilding; 0 where that cannot be told.
function Placement.shortfall(ecoType)
  local energy = readResourceSnapshot('energy')
  if ecoType == 'energy' then
    return math.max(energy.expenseWanted, energy.expenseActual) - energy.supply
  end
  if ecoType == 'mMM' then
    return energy.supply - energy.expenseActual
  end
  return Placement.buildPowerShortfall() or 0
end

-- Build power the resources can feed on top of what the team has; nil while nothing is under
-- construction, since then nothing tells what a build point costs. One build point of the current
-- targets costs a known amount of metal and energy, so each resource's surplus says how many more
-- build points per second it could feed, and the tighter one rules. Storage is no supply: build
-- power that lives off it stalls once that is empty. Negative while the resources are the bottleneck.
function Placement.buildPowerShortfall()
  local busy, metalDrain, energyDrain = 0, 0, 0
  for targetId, buildSpeed in pairs(assignedTargetBuildSpeed) do
    local def = UnitIdDef(targetId)
    if def then
      busy = busy + buildSpeed
      metalDrain = metalDrain + buildSpeed * def.metalCost / def.buildTime
      energyDrain = energyDrain + buildSpeed * def.energyCost / def.buildTime
    end
  end
  if busy <= 0 then
    return nil
  end
  local metal, energy = readResourceSnapshot('metal'), readResourceSnapshot('energy')
  local feedable = busy * math.min(
    SafeDivide(metal.supply - metal.expenseActual, metalDrain, math.huge),
    SafeDivide(energy.supply - energy.expenseActual, energyDrain, math.huge)
  )
  return feedable - (totalBuildSpeed - busy)
end

-- Every family of the type the team owns, as {family, unit, owned, investment, cost, perBuilding},
-- described by the version it owns the most of.
function Placement.ownedFamilies(ecoType)
  local families = {}
  for family, familyType in pairs(Placement.familyEcoType) do
    if familyType == ecoType then
      local owned, investment, mostOwned, mostOwnedDefID = 0, 0, 0, nil
      for _, unitDefID in ipairs(Placement.familyDefIds[family]) do
        local count = Spring.GetTeamUnitDefCount(myTeamId, unitDefID) or 0
        owned = owned + count
        investment = investment + count * UnitCost(UnitDefs[unitDefID])
        if count > mostOwned then
          mostOwned, mostOwnedDefID = count, unitDefID
        end
      end
      if owned > 0 then
        local unitDef = UnitDefs[mostOwnedDefID]
        families[#families + 1] = {
          family = family,
          unit = unitDef.name,
          owned = owned,
          investment = investment,
          cost = UnitCost(unitDef),
          perBuilding = Placement.perBuilding(ecoType, unitDef)
        }
      end
    end
  end
  return families
end

-- The family the player has put the most resources into (units x cost). Counting units alone
-- would keep extending whatever was spammed early, long after the player moved up a tier.
function Placement.mostInvested(families)
  local best
  for _, family in ipairs(families) do
    if not best or family.investment > best.investment then
      best = family
    end
  end
  return best and best.family
end

function Placement.dominantFamily(ecoType)
  return Placement.mostInvested(Placement.ownedFamilies(ecoType))
end

-- Every standing building of the family as a footprint {x, z, halfX, halfZ, facing}.
function Placement.standingAnchors(family)
  local anchors = {}
  local unitIds = Spring.GetTeamUnitsByDefs(myTeamId, Placement.familyDefIds[family])
  for i = 1, #unitIds do
    local unitId = unitIds[i]
    local x, _, z = GetUnitBasePosition(unitId)
    if x then
      local facing = Spring.GetUnitBuildFacing(unitId) or 0
      local halfX, halfZ = Placement.halfExtents(UnitDefs[GetUnitDefID(unitId)], facing)
      anchors[#anchors + 1] = {x = x, z = z, halfX = halfX, halfZ = halfZ, facing = facing}
    end
  end
  return anchors
end

-- Build orders still waiting in the mobile builders' queues, as footprints that also carry their
-- unitDefID. The engine's build test knows nothing of these: to it a queued spot is open ground.
function Placement.queuedFootprints()
  local footprints = {}
  for i = 1, builderUnitIds.count do
    local builderId = builderUnitIds.list[i]
    local builder = builders[builderId]
    if builder and builder.def.canMove and #builder.def.buildOptions > 0 then
      local queue = GetUnitCommands(builderId, PLACE_QUEUE_SCAN_DEPTH) or {}
      for j = 1, #queue do
        local command = queue[j]
        local unitDef = command.id < 0 and UnitDefs[-command.id]
        if unitDef and command.params[3] then
          local facing = command.params[4] or 0
          local halfX, halfZ = Placement.halfExtents(unitDef, facing)
          footprints[#footprints + 1] = {
            x = command.params[1],
            z = command.params[3],
            halfX = halfX,
            halfZ = halfZ,
            facing = facing,
            unitDefID = -command.id
          }
        end
      end
    end
  end
  return footprints
end

-- The cluster to extend: the standing buildings plus the queued ones of the same family, so that
-- a round goes to the edge of what the player has planned, not into it.
function Placement.withQueuedAnchors(anchors, family, queued)
  local isFamilyDef = {}
  for _, unitDefID in ipairs(Placement.familyDefIds[family]) do
    isFamilyDef[unitDefID] = true
  end
  local cluster = {}
  for i = 1, #anchors do
    cluster[i] = anchors[i]
  end
  for _, footprint in ipairs(queued) do
    if isFamilyDef[footprint.unitDefID] then
      cluster[#cluster + 1] = footprint
    end
  end
  return cluster
end

-- The unitDefID this mobile builder places for the family, and how much of an interruption that
-- is to it: 1 nothing of its own to do, 2 guarding, 3 on its own build queue. The order is
-- inserted ahead of its queue, so it goes back to either afterwards. Never a builder that is
-- selected, moving or reclaiming, and never one that would leave a frame only it works on: an
-- abandoned frame starts to decay.
function Placement.placementDefFor(builderId, builder, family, gameFrame)
  local byFamily = builder.def.canMove and Placement.placeableByBuilderDef[builder.defID]
  local unitDefID = byFamily and byFamily[family]
  if not unitDefID or selectedUnits[builderId] or not AllowBuilderOrder(builderId, gameFrame) then
    return
  end
  -- no queue: the builder died since the last roster rescan
  local queue = GetUnitCommands(builderId, 2)
  local first = queue and queue[1]
  if not queue or (first and (first.id == CMD.MOVE or first.id == CMD.RECLAIM)) then
    return
  end
  local interruption = 1
  if hasOwnBuildOrder(queue) then
    local othersBuildSpeed = (assignedTargetBuildSpeed[builder.targetId] or 0) - builder.def.buildSpeed
    if builder.targetId and othersBuildSpeed <= 0 then
      return
    end
    interruption = 3
  elseif first and first.id == CMD.GUARD then
    interruption = 2
  end
  if interruption > PLACE_MAX_INTERRUPTION then
    return
  end
  return unitDefID, interruption
end

-- The builder it interrupts least, and among those the one nearest an anchor.
function Placement.leastBusyBuilder(family, anchors, gameFrame)
  local bestId, bestDefID, bestInterruption, bestDistanceSq
  for i = 1, builderUnitIds.count do
    local builderId = builderUnitIds.list[i]
    local builder = builders[builderId]
    local unitDefID, interruption, x, _, z
    if builder then
      unitDefID, interruption = Placement.placementDefFor(builderId, builder, family, gameFrame)
    end
    if unitDefID then
      x, _, z = GetUnitBasePosition(builderId)
    end
    if x then
      for _, anchor in ipairs(anchors) do
        local deltaX, deltaZ = anchor.x - x, anchor.z - z
        local distanceSq = deltaX * deltaX + deltaZ * deltaZ
        if
          not bestId or interruption < bestInterruption or
            (interruption == bestInterruption and distanceSq < bestDistanceSq)
         then
          bestId, bestDefID, bestInterruption, bestDistanceSq = builderId, unitDefID, interruption, distanceSq
        end
      end
    end
  end
  return bestId, bestDefID
end

-- How many to place in one round: enough to cover the shortfall the need stands for, one where
-- that cannot be told, at most PLACE_BATCH_MAX and no more than can be paid for soon. A single
-- wind turbine does nothing for a stall; three fusions at once would start a metal stall instead.
-- Build power rounds down and may be none: one turret over break-even is a stall.
function Placement.batchSize(ecoType, unitDef)
  local perBuilding, shortfall = Placement.perBuilding(ecoType, unitDef), Placement.shortfall(ecoType)
  local isPower = ecoType == 'power'
  if perBuilding <= 0 or shortfall <= 0 then
    return isPower and 0 or 1
  end
  local metal = readResourceSnapshot('metal')
  local affordable = math.floor((metal.current + metal.income * PLACE_AFFORD_SECONDS) / UnitCost(unitDef))
  if isPower then
    return math.min(PLACE_BATCH_MAX, affordable, math.floor(shortfall / perBuilding))
  end
  return math.max(1, math.min(PLACE_BATCH_MAX, affordable, math.ceil(shortfall / perBuilding)))
end

-- Up to `count` open spots as {x, y, z, facing, halfX, halfZ}, each touching an anchor or a spot
-- chosen before it, none overlapping another or a queued building. Anchors are footprints and are
-- tried outermost first: inside a packed cluster every side is taken, the open sides are at its edge.
function Placement.openAdjacentSpots(unitDefID, anchors, count, queued)
  local centerX, centerZ = 0, 0
  for i = 1, #anchors do
    centerX = centerX + anchors[i].x / #anchors
    centerZ = centerZ + anchors[i].z / #anchors
  end
  local outermostFirst = {}
  for i = 1, #anchors do
    local anchor = anchors[i]
    local deltaX, deltaZ = anchor.x - centerX, anchor.z - centerZ
    outermostFirst[i] = {anchor = anchor, distanceSq = deltaX * deltaX + deltaZ * deltaZ}
  end
  table.sort(outermostFirst, function(a, b) return a.distanceSq > b.distanceSq end)

  local unitDef = UnitDefs[unitDefID]
  local spots = {}
  local function overlapsAny(footprints, x, z, halfX, halfZ)
    for _, footprint in ipairs(footprints) do
      if math.abs(x - footprint.x) < halfX + footprint.halfX and math.abs(z - footprint.z) < halfZ + footprint.halfZ then
        return true
      end
    end
    return false
  end
  local function takeOpenSpotsAround(aroundX, aroundZ, aroundHalfX, aroundHalfZ, facing)
    local halfX, halfZ = Placement.halfExtents(unitDef, facing)
    for _, position in ipairs(Placement.adjacentPositions(aroundX, aroundZ, aroundHalfX, aroundHalfZ, halfX, halfZ)) do
      local x, z = position[1], position[2]
      if #spots < count and not overlapsAny(spots, x, z, halfX, halfZ) then
        local y = Spring.GetGroundHeight(x, z)
        local status, blockingFeatureID = Spring.TestBuildOrder(unitDefID, x, y, z, facing)
        if status == BUILD_SPOT_OPEN and not blockingFeatureID then
          if overlapsAny(queued, x, z, halfX, halfZ) then
            emitDecision('avoided_queued_spot')
          else
            spots[#spots + 1] = {x = x, y = y, z = z, facing = facing, halfX = halfX, halfZ = halfZ}
          end
        end
      end
    end
  end

  for i = 1, math.min(#outermostFirst, PLACE_ANCHOR_TRIES) do
    if #spots >= count then break end
    local anchor = outermostFirst[i].anchor
    takeOpenSpotsAround(anchor.x, anchor.z, anchor.halfX, anchor.halfZ, anchor.facing)
  end
  -- still short: grow outward from the spots chosen so far
  local grownFrom = 1
  while #spots < count and grownFrom <= #spots do
    local spot = spots[grownFrom]
    takeOpenSpotsAround(spot.x, spot.z, spot.halfX, spot.halfZ, spot.facing)
    grownFrom = grownFrom + 1
  end
  return spots
end

function Placement.PlaceOne(ecoType, gameFrame, advisedFamily)
  local isAdvised = Placement.familyEcoType[advisedFamily] == ecoType
  local family = isAdvised and advisedFamily or Placement.dominantFamily(ecoType)
  if not family then return emitDecision('noplace_family') end
  if isAdvised then emitDecision('advised_family') end
  local anchors = Placement.standingAnchors(family)
  if #anchors == 0 then return emitDecision('noplace_anchor') end
  local builderId, unitDefID = Placement.leastBusyBuilder(family, anchors, gameFrame)
  if not builderId then return emitDecision('noplace_builder') end
  local unitDef = UnitDefs[unitDefID]
  local wanted = Placement.batchSize(ecoType, unitDef)
  if wanted == 0 then
    Placement.lastFrame[ecoType] = gameFrame
    return emitDecision('noplace_batch')
  end
  -- read the queues only now that a builder is found: it is the costly part of a round
  local queued = Placement.queuedFootprints()
  local spots = Placement.openAdjacentSpots(unitDefID, Placement.withQueuedAnchors(anchors, family, queued), wanted, queued)
  if #spots == 0 then return emitDecision('noplace_spot') end
  if #spots < wanted then emitDecision('short_of_spots') end

  for position, spot in ipairs(spots) do
    GiveOrderToUnit(builderId, CMD.INSERT, {position - 1, -unitDefID, 0, spot.x, spot.y, spot.z, spot.facing}, {'alt'})
    emitDecision('place_' .. ecoType .. ':' .. unitDef.name, builderId)
  end
  InvalidatePurgedUnitCommands(builderId)
  SetBuilderLastOrder(builderId)
  Placement.lastFrame[ecoType] = gameFrame
  Placement.pending[ecoType] = {builderId = builderId, unitDefID = unitDefID}
  AddObjectSpotlight('unit', 'me', builderId, {0, 0.5, 1, 1}, {duration = 25, radius = 2, heightCoefficient = 5})
end

-- True while a round of the type is still being worked off: its builder holds one of the build
-- orders (it may still be walking there), or any building of the type is unfinished. This looks at
-- every unfinished one; the assist candidates leave out those about to finish.
function Placement.isUnderWay(ecoType)
  local pending = Placement.pending[ecoType]
  if pending then
    local queue = GetUnitCommands(pending.builderId, 20) or {}
    for i = 1, #queue do
      if queue[i].id == -pending.unitDefID then
        return true
      end
    end
    Placement.pending[ecoType] = nil
  end
  local unitIds = Spring.GetTeamUnitsByDefs(myTeamId, ecoBuildingTypeDefIds[ecoType].list)
  for i = 1, #unitIds do
    local build = select(5, GetUnitHealth(unitIds[i]))
    if build and build < 1 then
      return true
    end
  end
  return false
end

-- One round per type at a time, and the next only once nothing of the type has been under way
-- for the cooldown: a building that just finished gets to show in the need before more is added.
-- The power need only says metal is piling up. More build power is the answer to that only while
-- the builders already there are busy; with most of them idle, what is missing is something to build.
function Placement.PlaceForNeeds(gameFrame)
  local needs = {{'energy', energyNeed}, {'mMM', mMMNeed}, {'power', powerNeed}}
  for _, need in ipairs(needs) do
    local ecoType, value = need[1], need[2]
    local isDue = false
    if value >= PLACE_NEED and (ecoType ~= 'power' or Placement.utilization >= PLACE_POWER_UTILIZATION) then
      if Placement.isUnderWay(ecoType) then
        Placement.lastFrame[ecoType] = gameFrame
      else
        isDue = gameFrame - (Placement.lastFrame[ecoType] or -PLACE_COOLDOWN_FRAMES) >= PLACE_COOLDOWN_FRAMES
      end
    end
    if isDue then
      -- stays set through the tick after placing, so an advisor that only watches still sees the round
      Placement.openRounds[ecoType] = Placement.openRounds[ecoType] or gameFrame
      Placement.placeOrAwaitAdvice(ecoType, gameFrame)
    else
      Placement.openRounds[ecoType] = nil
    end
  end
end

-- With an advisor acting, a due round waits a moment for its advice. Without one, or when the
-- advice does not come in time, the round goes ahead on the heuristics: the advisor can change
-- which family is extended or call the round off, never stall placement.
function Placement.placeOrAwaitAdvice(ecoType, gameFrame)
  local advice = Placement.advice[ecoType]
  if advice and gameFrame - advice.frame > Placement.ADVICE_MAX_AGE_FRAMES then
    advice = nil
  end
  local waitedFrames = gameFrame - Placement.openRounds[ecoType]
  if Placement.advisorMode == 'act' and not advice and waitedFrames < Placement.ADVICE_WAIT_FRAMES then
    return emitDecision('await_advice')
  end
  Placement.advice[ecoType] = nil
  if advice and advice.place == false then
    Placement.lastFrame[ecoType] = gameFrame
    return emitDecision('advised_against')
  end
  Placement.PlaceOne(ecoType, gameFrame, advice and advice.family)
end

-- What an advisor needs to judge the due rounds: plain numbers and names, no engine handles.
function Placement.advisorContext(gameFrame)
  local rounds = {}
  for ecoType, openFrame in pairs(Placement.openRounds) do
    local families = Placement.ownedFamilies(ecoType)
    rounds[#rounds + 1] = {
      ecoType = ecoType,
      openFrame = openFrame,
      shortfall = Placement.shortfall(ecoType),
      heuristicFamily = Placement.mostInvested(families),
      families = families
    }
  end
  return {
    frame = gameFrame,
    metal = readResourceSnapshot('metal'),
    energy = readResourceSnapshot('energy'),
    conversion = conversionSnapshot or readConversionSnapshot(),
    buildSpeed = totalBuildSpeed,
    utilization = Placement.utilization,
    rounds = rounds
  }
end

-- Placement is the one part that acts on the map. A fault in it switches placement off for the
-- rest of the game instead of taking the widget, and with it all assisting, down.
function Placement.run(gameFrame)
  if not Placement.enabled then return end
  local ok, fault = pcall(Placement.PlaceForNeeds, gameFrame)
  if not ok then
    Placement.enabled = false
    Spring.Echo('eco cons: placement disabled after error: ' .. tostring(fault))
  end
end

-- ============================================================
-- Main per-frame loop
-- ============================================================
local function beginFrame()
  totalBuildSpeed = 0
  anyBuildWillMStall = false
  anyBuildWillEStall = false
  assignedTargetBuildSpeed = {}
  cachedResourceStatus = {}
  cachedUnitsUpkeep = nil
  cachedMetalMakersUpkeep = nil
  cachedTargetWillStall = {}
  purgedThisFrame = {}
end

local function endFrame()
  reclaimTargetsPrev = reclaimTargets
  reclaimTargets = NewSetList()
end

local function processBuilder(builder, gameFrame)
  local builderId = builder.id
  local builderDef = builder.def
  local commandQueue, nCommandQueue = GetPurgedUnitCommands(builderId)

  -- dont wait if has queued stuff and leaking
  if
    commandQueue and nCommandQueue > 0 and (isMetalLeaking or isEnergyLeaking) and
      commandQueue[1].id == CMD.WAIT
   then
    GiveOrderToUnit(builderId, CMD.REMOVE, {nil}, {'ctrl'})
    InvalidatePurgedUnitCommands(builderId)
    emitDecision('unwait', builderId)
    commandQueue, nCommandQueue = GetPurgedUnitCommands(builderId)
  end

  if not commandQueue then return end

  local builderPosX, _, builderPosZ
  local features = nil
  local nFeaturesAll = 0
  local targetId = builder.targetId

  local multiSlotBuildQueue = hasMultiSlotBuildQueue(commandQueue)
  local isManualActionCommand = isManualOrBusy(commandQueue)

  local candidatesUnfinished = {}
  local nCandidatesUnfinished = 0
  if (targetId and not isManualActionCommand) or nCommandQueue == 0 then
    candidatesUnfinished, nCandidatesUnfinished, features, nFeaturesAll =
      dispatchIdleActions(builder, targetId, commandQueue, nCommandQueue, gameFrame, multiSlotBuildQueue)
  end

  -- queue fast forward / skip ahead
  if targetId and multiSlotBuildQueue then
    BuildQueueSkipAssisted(builder, targetId, commandQueue[1].tag, commandQueue[2].tag)
  end

  if shouldOpportunisticallyReclaim(commandQueue, gameFrame) and not multiSlotBuildQueue then
    if not features then
      builderPosX, _, builderPosZ = GetUnitBasePosition(builderId, true)
      features, nFeaturesAll = getReclaimableFeatures(builderPosX, builderPosZ, builderDef.buildDistance)
    end
    if nFeaturesAll > 0 then
      if isMetalStalling and isEnergyStalling then
        reclaimByEcoType(builderId, features, true, true)
      elseif isMetalStalling and not isEnergyLeaking then
        reclaimByEcoType(builderId, features, true, false)
      else
        reclaimByEcoType(builderId, features, false, true)
      end
    end
  end

  -- easy finish neighbour
  if AllowBuilderOrder(builderId, gameFrame, 2) then
    targetId = GetUnitIsBuilding(builderId)
    if targetId then
      local targetDefId = GetUnitDefID(targetId)
      local _, _, _, _, targetBuild = GetUnitHealth(targetId)
      for j = 1, nCandidatesUnfinished do
        local candidate = candidatesUnfinished[j]
        local candidateId = candidate.id
        -- same type and not actually same building
        if
          candidate.defId == targetDefId and candidateId ~= targetId and candidate.build and
            candidate.build < 1 and
            candidate.build > targetBuild and
            AllowBuilderOrder(builderId, gameFrame)
         then
          log(
            'ef repair',
            candidate.id,
            candidate.def.translatedHumanName,
            candidate.build,
            'instead of',
            candidatesUnfinished[j + 1] and
              candidatesUnfinished[j + 1].def.translatedHumanName .. ' ' .. candidatesUnfinished[j + 1].build,
            not multiSlotBuildQueue
          )
          repair(builderId, candidateId, false)
          emitDecision('finish_neighbour', builderId, candidateId)
          AddObjectSpotlight(
            'unit',
            'me',
            builderId,
            {1, 1, 0, 1},
            {duration = 25, radius = 2, heightCoefficient = 5}
          )
          break
        end
      end
    end
  end
end

local function Builders(gameFrame)
  beginFrame()
  local busyBuildSpeed = 0
  local i = 1
  while i <= builderUnitIds.count do
    local builderID = builderUnitIds.list[i]
    local builder = builders[builderID]
    if builder then
      builder.targetId = GetUnitIsBuilding(builder.id)
      if builder.targetId then
        assignedTargetBuildSpeed[builder.targetId] =
          (assignedTargetBuildSpeed[builder.targetId] or 0) + builder.def.buildSpeed
        busyBuildSpeed = busyBuildSpeed + builder.def.buildSpeed
      end
      i = i + 1
    else
      RemoveBuilder(builderID)
    end
  end

  i = 1
  while i <= builderUnitIds.count do
    local builderID = builderUnitIds.list[i]
    local builder = builders[builderID]
    if builder then
      if builder.targetId then
        local _, mStall, eStall = TargetWillStall(builder.targetId)
        anyBuildWillMStall = anyBuildWillMStall or mStall
        anyBuildWillEStall = anyBuildWillEStall or eStall
      end
      totalBuildSpeed = totalBuildSpeed + builder.def.buildSpeed
      i = i + 1
    else
      RemoveBuilder(builderID)
    end
  end
  Placement.utilization = totalBuildSpeed > 0 and busyBuildSpeed / totalBuildSpeed or 0

  RefreshSelectedUnits()

  if gameFrame % BATCH_ORDER_INTERVAL == 0 then
    BatchOrder(gameFrame)
  end

  i = 1
  while i <= builderUnitIds.count do
    local builderID = builderUnitIds.list[i]
    local builder = builders[builderID]
    if not builder then
      RemoveBuilder(builderID)
    else
      if i % buildersJitterModulo == 0 then
        -- Debug mode deliberately opts selected builders into processing so
        -- per-selected-unit diagnostics can observe the real decision path.
        if (not selectedUnits[builderID] or isUnitLogActive) and AllowBuilderOrder(builder.id, gameFrame) then
          processBuilder(builder, gameFrame)
        end
      end
      i = i + 1
    end
  end
  endFrame()
end

-- ============================================================
-- Frame stagger / responsiveness
-- ============================================================
local function GameFrameModulo()
  local nBuilderUnitIds = builderUnitIds.count
  return math.max(
    1,
    math.floor(
      0.5 +
        ((nBuilderUnitIds > 200 and Interpolate(nBuilderUnitIds, 201, 300, 40, 90) or
          nBuilderUnitIds > 100 and Interpolate(nBuilderUnitIds, 101, 200, 21, 40) or
          nBuilderUnitIds > 50 and Interpolate(nBuilderUnitIds, 51, 100, 11, 20) or
          nBuilderUnitIds > 15 and Interpolate(nBuilderUnitIds, 15, 50, 2, 15) or
          1) *
          frameStaggeringModuloMultiplier)
    )
  )
end

local function BuildersJitterModulo()
  local nBuilderUnitIds = builderUnitIds.count
  local modulo =
    (nBuilderUnitIds > 200 and Interpolate(nBuilderUnitIds, 200, 350, 5, 8) or
    nBuilderUnitIds > 100 and Interpolate(nBuilderUnitIds, 100, 200, 3, 5) or
    nBuilderUnitIds > 30 and Interpolate(nBuilderUnitIds, 30, 100, 2, 3) or
    -- nBuilderUnitIds > 10 and Interpolate(nBuilderUnitIds, 10, 30, 1, 3) or
    1)
  modulo = math.floor(0.5 + (modulo * frameStaggeringModuloMultiplier))
  return modulo > 1 and math.random(modulo - 1, modulo + 1) or 1
end

-- ============================================================
-- Widget callbacks
-- ============================================================
-- Conversion level to request, or nil to leave it alone. Raises the floor while metal is
-- full so converters keep energy in storage; lowers it while energy overflows and the
-- floor (not converter capacity) is what throttles conversion. Without converters the level
-- throttles nothing, so a manual setting is left alone.
local function NudgeMetalMakerLevel(conversion, currentMetalLevel, energyLeaking)
  if conversion.capacity <= 0 then return end
  local level = conversion.level
  if currentMetalLevel >= METAL_LEVEL_FULL and not energyLeaking then
    if level >= MM_LEVEL_MAX then return end
    return math.min(MM_LEVEL_MAX, level + MM_LEVEL_STEP)
  end
  if energyLeaking and currentMetalLevel < METAL_LEVEL_FULL and not conversion.saturated then
    if level <= MM_LEVEL_MIN then return end
    return math.max(MM_LEVEL_MIN, level - MM_LEVEL_STEP)
  end
end

local function LevelPercent(level)
  return math.floor(level * 100 + 0.5)
end

local function SendNudgedMetalMakerLevel()
  if not conversionSnapshot or not conversionSnapshot.available then return false end

  local target = NudgeMetalMakerLevel(conversionSnapshot, metalLevel, isEnergyLeaking)
  if not target then return false end

  local percent = LevelPercent(target)
  if percent == LevelPercent(conversionSnapshot.level) then return false end

  Spring.SendLuaRulesMsg(string.format(string.char(137) .. '%i', percent))
  emitDecision(target > conversionSnapshot.level and 'mm_up' or 'mm_down')
  return true
end

function widget:GameFrame(gameFrame)
  if gameFrame % RESOURCE_SAMPLE_INTERVAL == 0 then
    UpdateResourceNeeds()
    SendNudgedMetalMakerLevel()
    Placement.run(gameFrame)
  end

  gameFrameModulo = GameFrameModulo()

  if gameFrame % gameFrameModulo == 0 then
    buildersJitterModulo = BuildersJitterModulo()

    -- log(
    --   'gameframe mod %s (%.1fs) builders mod %s (%s/%s) - - - p %.0f e %.0f m %.0f',
    --     gameFrameModulo,
    --     gameFrameModulo / 30,
    --     buildersJitterModulo,
    --     math.floor(builderUnitIds.count / buildersJitterModulo),
    --     builderUnitIds.count,
    --     powerNeed * 100, energyNeed * 100, mMMNeed * 100
    --   )
    -- )

    Builders(gameFrame)
  end

  if gameFrame % FORWARDED_CLEANUP_INTERVAL == 0 then
    for i = 1, forwardedFromTargetIds.count do
      local abandonedTargetId = forwardedFromTargetIds.list[i]
      if abandonedTargetId then
        local _, _, _, _, build = GetUnitHealth(abandonedTargetId)
        if build == nil or build == 1 then
          forwardedFromTargetIds:Remove(abandonedTargetId)
        end
      else
        forwardedFromTargetIds:Remove(nil)
      end
    end
  end

  if gameFrame % BUILDER_RESCAN_INTERVAL == 0 then
    RescanBuilders()
  end
end

function widget:KeyPress(key, mods, _isRepeat)
  if key == KEYSYMS.L and mods['ctrl'] then
    SetUnitLogActive(not isUnitLogActive)
    return true
  end
  if key == KEYSYMS.T and mods['ctrl'] and mods['shift'] then
    local currentIndex = 1
    for i, preset in ipairs(responsivenessPresets) do
      if preset == responsivenessSpeed then
        currentIndex = i
        break
      end
    end
    local nextIndex = (currentIndex % #responsivenessPresets) + 1
    applyResponsivenessSpeed(responsivenessPresets[nextIndex])
    Spring.Echo('eco cons responsiveness: ' .. responsivenessSpeed .. 'x')
    return true
  end
end

function widget:Shutdown()
  WG['eco_cons'] = nil
end

function widget:GetConfigData()
  return { responsivenessSpeed = responsivenessSpeed }
end

function widget:SetConfigData(data)
  if data.responsivenessSpeed then
    applyResponsivenessSpeed(data.responsivenessSpeed)
  end
end

-- ============================================================
-- Spectator / replay rehooks
-- ============================================================
local function specInit()
  if Spring.GetSpectatingState() or Spring.IsReplay() then
    widget:Initialize()
  end
end

function widget:PlayerRemoved()
  specInit()
end

function widget:PlayerAdded()
  specInit()
end

function widget:PlayerChanged()
  specInit()
end

function widget:TeamChanged()
  specInit()
end

function widget:TeamDied()
  specInit()
end

-- function widget:KeyPress(key, mods, isRepeat)
--   if (key == 114 and mods['ctrl']) then
--     Spring.SendCommands("disablewidget cons")
--     Spring.SendCommands("enablewidget cons")
--     return false
--   end

--   if key == 113 and mods['alt'] and mods['ctrl'] then -- 'q'
--     table.echo({
--       -- needPower = (metalLevel > 0.8 or (regularizedPositiveMetal and metalLevel > 0.15)) and (positiveMMLevel or not regularizedNegativeEnergy)
--       -- needEnergy = (not (regularizedPositiveEnergy and isEnergyLeaking and positiveMMLevel)) or isEnergyStalling
--       -- needMM = positiveMMLevel and (not regularizedNegativeEnergy or isEnergyLeaking or isMetalStalling)
--       -- needPower = (needPower and 'true' or 'false') .. ' metalLevel ' .. tostring((metalLevel > 0.8) or (regularizedPositiveMetal and metalLevel > 0.15)) .. ' positiveMMLevel ' .. positiveMMLevel .. ' not regularizedNegativeEnergy ' .. tostring(not regularizedNegativeEnergy),
--       -- needEnergy = (needEnergy and 'true' or 'false') .. ' not (regularizedPositiveEnergy ' .. tostring(not regularizedPositiveEnergy) .. ' and isEnergyLeaking ' .. tostring(not isEnergyLeaking) .. ' and positiveMMLevel ' .. tostring(not positiveMMLevel) .. ') or isEnergyStalling ' .. (isEnergyStalling and 'true' or 'false'),
--       -- needMM = (needMM and 'true' or 'false') .. 'positiveMMLevel ' .. positiveMMLevel .. ' '
--       Interpolate(8, 0, 10, 1, 0)
--     })
--     return true
--   end
-- end

if ECO_CONS_TEST then
  return {
    addBuilder = AddBuilder,
    removeBuilder = RemoveBuilder,
    builderById = BuilderById,
    rescanBuilders = RescanBuilders,
    getBuilderRegistrySnapshot = function()
      local snapshot = {count = builderUnitIds.count, list = {}, records = {}}
      for i = 1, builderUnitIds.count do
        local unitID = builderUnitIds.list[i]
        snapshot.list[i] = unitID
        local builder = builders[unitID]
        if builder then
          snapshot.records[unitID] = {id = builder.id, defID = builder.defID, lastOrder = builder.lastOrder}
        end
      end
      return snapshot
    end,
    dropBuilderRecordForTest = function(unitID) builders[unitID] = nil end,
    getMetalMakerTotals = function()
      return possibleMetalMakersUpkeep, possibleMetalMakersMetalProduction
    end,
    setResponsivenessSpeed = applyResponsivenessSpeed,
    gameFrameModulo = GameFrameModulo,
    refreshSelectedUnits = RefreshSelectedUnits,
    isSelected = function(unitID) return selectedUnits[unitID] == true end,
    setUnitLogActive = SetUnitLogActive,
    isUnitSelectedLog = IsUnitSelectedLog,
    addObjectSpotlight = AddObjectSpotlight,
    getSingleReclaimFeatureId = GetSingleReclaimFeatureId,
    isWithinBuildRange = IsWithinBuildRange,
    buildBatchBuilderSnapshots = BuildBatchBuilderSnapshots,
    getCandidateAlternatives = getCandidateAlternatives,
    normalizedPositiveNeeds = NormalizedPositiveNeeds,
    setAssignedTargetBuildSpeed = function(speeds) assignedTargetBuildSpeed = speeds end,
    setTotalBuildSpeed = function(speed) totalBuildSpeed = speed end,
    buildPowerShortfall = Placement.buildPowerShortfall,
    familyKey = Placement.familyKey,
    adjacentPositions = Placement.adjacentPositions,
    placeForNeeds = Placement.PlaceForNeeds,
    batchSize = Placement.batchSize,
    runPlacement = Placement.run,
    setBuildPowerUtilization = function(utilization) Placement.utilization = utilization end,
    scanNearbyBuildables = scanNearbyBuildables,
    beginFrame = beginFrame,
    getPurgedUnitCommands = GetPurgedUnitCommands,
    invalidatePurgedUnitCommands = InvalidatePurgedUnitCommands,
    getResourceStatus = GetResourceStatus,
    getUnitsUpkeep = getUnitsUpkeep,
    scoreEcoCandidate = scoreEcoCandidate,
    scoreEcoCandidates = ScoreEcoCandidates,
    setNeeds = function(nextPowerNeed, nextEnergyNeed, nextMMNeed)
      powerNeed = nextPowerNeed
      energyNeed = nextEnergyNeed
      mMMNeed = nextMMNeed
    end,
    updateResourceNeeds = UpdateResourceNeeds,
    nudgeMetalMakerLevel = NudgeMetalMakerLevel,
    sendNudgedMetalMakerLevel = SendNudgedMetalMakerLevel,
    readConversionSnapshot = readConversionSnapshot,
    trendSign = TrendSign,
    getNeeds = function() return powerNeed, energyNeed, mMMNeed end,
    getTrend = function()
      return regularizedPositiveMetal, regularizedNegativeMetal, regularizedPositiveEnergy, regularizedNegativeEnergy
    end,
    hasMultiSlotBuildQueue = hasMultiSlotBuildQueue
  }
end
