-- luacheck: globals ECO_CONS_TEST IsInBuildRange
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
local MM_LEVEL_BIAS = 0.12         -- bias added to mmLevel rules param
local POWER_NEED_AFFORDABLE_FLOOR = 0.75 -- minimum buildpower priority when eco can afford it

-- scanning / timing
local CANDIDATE_SCAN_PADDING = 250 -- buildDistance + this == idle-candidate scan radius
local EARLY_GAME_REPAIR_FRAMES = 60 * 30 -- ~1 minute; below this, queued REPAIR is honored
local REGULARIZATION_WINDOW = 5    -- frames in income/expense derivative smoother
local FORWARDED_CLEANUP_INTERVAL = 100 -- frames between forwardedFromTargetIds purges
local BUILDER_RESCAN_INTERVAL = 300    -- frames between full builder roster rescans
local BATCH_ORDER_INTERVAL = 4         -- frames between BatchOrder() calls

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
local regularizationCounter = 1
local energyLevel = 0.5
local isEnergyLeaking = true
local isEnergyStalling = false
local isMetalLeaking = true
local isMetalStalling = false
local metalLevel = 0.5
local metalMakersLevel = 0.5
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
  regularizedResourceDerivativesEnergy = {true}
  regularizedResourceDerivativesMetal = {true}
  assignedTargetBuildSpeed = {}
  upgradableFromDefIds = {}
  upgradableToDefIds = {}
  defBuildPowerScore = {}
  defEnergyScore = {}
  defMetalMMScore = {}

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

      if unitDef.isBuilder or (unitDef.buildSpeed and unitDef.buildSpeed > 0) then
        ecoBuildingTypeDefIds['power'].map[unitDefID] = true
        table.insert(ecoBuildingTypeDefIds['power'].list, unitDefID)
      elseif EnergyMakeDef(unitDef) > 0 then
        ecoBuildingTypeDefIds['energy'].map[unitDefID] = true
        table.insert(ecoBuildingTypeDefIds['energy'].list, unitDefID)
      elseif
        unitDef.extractsMetal or MetalMakingEfficiencyDef(unitDef) > 0 or (unitDef.metalMake and unitDef.metalMake > 0)
       then
        -- log('adding mMM', unitDef.translatedHumanName, MetalMakingEfficiencyDef(unitDef))
        ecoBuildingTypeDefIds['mMM'].map[unitDefID] = true
        table.insert(ecoBuildingTypeDefIds['mMM'].list, unitDefID)
      end
    end
  end

  WG['eco_cons'] = {
    getResponsivenessSpeed = function() return responsivenessSpeed end,
    setResponsivenessSpeed = function(value)
      applyResponsivenessSpeed(math.max(0.25, math.min(4, value)))
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
  for i = 1, #cmdQueue do
    local cmd = cmdQueue[i]
    local targetId = cmd.params[1]
    local shouldRemove = false

    if cmd.id == CMD.REPAIR then -- 40
      local health, maxHealth, _, _, targetBuild = GetUnitHealth(targetId)
      if
        (targetBuild ~= nil and health ~= nil and targetBuild >= 1 and health >= maxHealth) or
          isBeingReclaimed(targetId)
       then
        table.insert(removeCommands, {CMD.REMOVE, {cmd.tag}, {'ctrl'}})
        shouldRemove = true
        if not targetBuild then
          reclaimTargets:Remove(targetId)
          reclaimTargetsPrev:Remove(targetId)
        end
      end
    elseif cmd.id == CMD.RECLAIM then -- 90
      if #cmd.params == 1 then
        reclaimTargets:Add(targetId)
      end
    elseif cmd.id < 0 or cmd.id == CMD.FIGHT then
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
            table.insert(removeCommands, {CMD.REMOVE, {cmd.tag}, {'ctrl'}})
            shouldRemove = true
          elseif isBeingReclaimed(buildingUnitId) then
            table.insert(removeCommands, {CMD.REMOVE, {cmd.tag}, {'ctrl'}})
            shouldRemove = true
            reclaimTargets:Remove(buildingUnitId)
            reclaimTargetsPrev:Remove(buildingUnitId)
          end
        end
      end
    end

    if not shouldRemove then
      purgedQueue[#purgedQueue + 1] = cmd
    end
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

  return {
    current = current,
    storage = storage,
    expenseWanted = expenseWanted or 0,
    income = income,
    expenseActual = expenseActual,
    shareSlider = shareSlider or 0,
    sent = sent or 0,
    received = received or 0,
    localDelta = localDelta,
    level = level,
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

local function areMetalMakersSaturated()
  return getMetalMakersUpkeep() >= possibleMetalMakersUpkeep
end

local function recomputePowerNeed(metalSnapshot, energySnapshot)
  if not needPower or anyBuildWillMStall or anyBuildWillEStall or isMetalStalling or isEnergyStalling then
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

local function recomputeEnergyAndMMNeed(metalSnapshot, energySnapshot)
  energyNeed = 0
  mMMNeed = 0

  if isEnergyStalling then
    energyNeed = 1
    return
  end

  local metalOverflowing = isMetalLeaking or metalSnapshot.isOverflowing
  local energyAboveMMLevel = energySnapshot.level > metalMakersLevel
  local energyInvestmentBlocked =
    energySnapshot.isOverflowing or isEnergyLeaking or
    (energyAboveMMLevel and energySnapshot.isLocallyNegative)

  if energyInvestmentBlocked then
    if
      not metalOverflowing and energyAboveMMLevel and areMetalMakersSaturated() and
        not anyBuildWillEStall
     then
      mMMNeed = Interpolate(energySnapshot.level, metalMakersLevel, 1, 0.75, 1)
    end
    return
  end

  if anyBuildWillEStall or regularizedNegativeEnergy then
    energyNeed = Interpolate(energySnapshot.level, 0, metalMakersLevel, 1, 0.75)
    return
  end

  if positiveMMLevel then
    energyNeed = Interpolate(
      1 - (energySnapshot.level - metalMakersLevel) - (areMetalMakersSaturated() and 0.5 or 0),
      0, 1, 0, 0.5
    )

    if energySnapshot.isLocallyPositive and energySnapshot.income > math.max(energySnapshot.expenseActual, energySnapshot.expenseWanted) then
      log('mm pos e', energySnapshot.level, metalMakersLevel)
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
        mMMNeed = Interpolate(energySnapshot.level, metalMakersLevel, 1, 0.75, 1)
      end
    else
      mMMNeed = Interpolate(energySnapshot.level, metalMakersLevel, 1, 0.5, 1)
    end
  elseif regularizedPositiveEnergy then
    energyNeed = Interpolate(energySnapshot.level, 0, metalMakersLevel, 1, 0.75)
  else
    energyNeed = anyBuildWillMStall and Interpolate(energySnapshot.level, 0, metalMakersLevel, 1, 0.75) or 0.5
  end

  -- clamp: don't build more of a resource type that is already overflowing
  if isEnergyLeaking or energySnapshot.isOverflowing then
    energyNeed = 0
  end
  if metalOverflowing then
    mMMNeed = 0
  end
end

local function UpdateResourceNeeds()
  local metalSnapshot = readResourceSnapshot('metal')
  local energySnapshot = readResourceSnapshot('energy')

  regularizationCounter = (regularizationCounter % REGULARIZATION_WINDOW) + 1
  regularizedResourceDerivativesMetal[regularizationCounter] = metalSnapshot.isLocallyPositive
  regularizedResourceDerivativesEnergy[regularizationCounter] = energySnapshot.isLocallyPositive
  regularizedPositiveMetal = table.full_of(regularizedResourceDerivativesMetal, true)
  regularizedPositiveEnergy = table.full_of(regularizedResourceDerivativesEnergy, true)
  regularizedNegativeMetal = table.full_of(regularizedResourceDerivativesMetal, false)
  regularizedNegativeEnergy = table.full_of(regularizedResourceDerivativesEnergy, false)

  metalLevel = metalSnapshot.level
  energyLevel = energySnapshot.level

  metalMakersLevel = (Spring.GetTeamRulesParam(myTeamId, 'mmLevel') or 0) + MM_LEVEL_BIAS
  positiveMMLevel = areMetalMakersSaturated() and energyLevel > metalMakersLevel

  isMetalStalling = metalLevel < STALL_LEVEL and not regularizedPositiveMetal
  isEnergyStalling = energyLevel < STALL_LEVEL and not regularizedPositiveEnergy
  isMetalLeaking = metalSnapshot.isOverflowing and regularizedPositiveMetal
  isEnergyLeaking = energySnapshot.isOverflowing and regularizedPositiveEnergy

  needPower =
    (metalLevel > METAL_LEVEL_HIGH or (regularizedPositiveMetal and metalLevel > METAL_LEVEL_LOW)) and
    (positiveMMLevel or not regularizedNegativeEnergy)
  needEnergy =
    isEnergyStalling or
    not (energySnapshot.isOverflowing or isEnergyLeaking or (energyLevel > metalMakersLevel and energySnapshot.isLocallyNegative))
  needMM =
    positiveMMLevel and not metalSnapshot.isOverflowing and
    (not regularizedNegativeEnergy or isEnergyLeaking or isMetalStalling)

  recomputePowerNeed(metalSnapshot, energySnapshot)
  recomputeEnergyAndMMNeed(metalSnapshot, energySnapshot)
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
    local alreadyInStall = data.pullExpWanted > data.current or data.expense > data.current
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
      elseif energy and energy > 0 and (energyLevel > 0.97 or isEnergyLeaking) then
        GiveOrderToUnit(builderId, CMD.REMOVE, {nil}, {'ctrl'})
        InvalidatePurgedUnitCommands(builderId)
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
    if build and build < 1 then
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
          radius = GetUnitRadius(unitId) or 0
        }
      )
    end
  end

  return candidateAlternatives
end

local function IsWithinBuildRange(builderSnapshot, candidate)
  if not builderSnapshot.x or not builderSnapshot.z or not candidate.x or not candidate.z then
    return false
  end

  local surfaceRange = builderSnapshot.builder.def.buildDistance - 12
  if surfaceRange <= 0 then return false end

  local centerRange = surfaceRange + builderSnapshot.radius + candidate.radius
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

  -- normalize need values so that they sum to 1
  local sum = 0
  for _, need in ipairs(positiveNeeds) do
    sum = sum + need.value
  end
  if sum <= 0 then
    return {}
  end
  for _, need in ipairs(positiveNeeds) do
    need.value = need.value / sum
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
          end
        end
      end
    end
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
  local i = 1
  while i <= builderUnitIds.count do
    local builderID = builderUnitIds.list[i]
    local builder = builders[builderID]
    if builder then
      builder.targetId = GetUnitIsBuilding(builder.id)
      if builder.targetId then
        assignedTargetBuildSpeed[builder.targetId] =
          (assignedTargetBuildSpeed[builder.targetId] or 0) + builder.def.buildSpeed
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

  UpdateResourceNeeds()

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
local function SendMetalMakerLevelIfNeeded(currentMetalLevel)
  if not currentMetalLevel or currentMetalLevel <= 0.96 then return false end

  local currentMMLevel = Spring.GetTeamRulesParam(myTeamId, 'mmLevel')
  if not currentMMLevel then return false end

  Spring.SendLuaRulesMsg(
    string.format(string.char(137) .. '%i', math.min(88, math.floor(currentMMLevel * 100 + 2)))
  )
  return true
end

function widget:GameFrame(gameFrame)
  gameFrameModulo = GameFrameModulo()

  if gameFrame % gameFrameModulo == 0 then
    SendMetalMakerLevelIfNeeded(metalLevel)

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
    sendMetalMakerLevelIfNeeded = SendMetalMakerLevelIfNeeded,
    hasMultiSlotBuildQueue = hasMultiSlotBuildQueue
  }
end
