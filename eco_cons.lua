function widget:GetInfo()
  return {
    desc = 'Some inspiration from gui_build_costs.lua by Milan Satala and also some from ecostats.lua by Jools, iirc',
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
VFS.Include('luaui/Widgets/.noload/misc/helpers.lua')

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
local GetUnitPosition = Spring.GetUnitPosition
local GetUnitResources = Spring.GetUnitResources
local GetUnitSeparation = Spring.GetUnitSeparation
local GetUnitsInCylinder = Spring.GetUnitsInCylinder
local GetUnitStates = Spring.GetUnitStates
local GiveOrderToUnit = Spring.GiveOrderToUnit
local MRandom = math.random
local UnitDefs = UnitDefs
local tidalStrength = Game.tidal
local windMax = Game.windMax
local windMin = Game.windMin

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
local anyBuildWillStall = false
local assignedTargetBuildSpeed = {}
local isUnitLogActive = false
local selectedUnits = {}
-- local mapPosUnitCache = LRUCacheTable:new(100)

-- WG["ObjectSpotlight"].addSpotlight = function() end
log = function() end

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

local function BuilderById(id)
  local builder = builders[builderUnitIds.hash[id]]
  if not builder then
    widget:UnitDestroyed(id)
    return
  end
  return builder
end

local function SetBuilderLastOrder(builderId)
  BuilderById(builderId).lastOrder = Spring.GetGameFrame()
end

local function AllowBuilderOrder(builderId, currentGameFrame, waitGameFrames)
  currentGameFrame = currentGameFrame or Spring.GetGameFrame()
  waitGameFrames = waitGameFrames or 15
  local builder = BuilderById(builderId)
  if not builder then
    return
  end
  return builder.lastOrder < currentGameFrame - waitGameFrames
end

local function EnergyMakeDef(_unitDef)
  if not _unitDef then
    return 0
  end

  local totalEOut = _unitDef.energyMake or 0

  totalEOut = totalEOut + -1 * (_unitDef and _unitDef.energyUpkeep or 0)

  if _unitDef.tidalGenerator and _unitDef.tidalGenerator > 0 and tidalStrength > 0 then
    local mult = 1 -- DEFAULT
    if _unitDef.customParams then
      mult = _unitDef.customParams.energymultiplier or mult
    end
    totalEOut = totalEOut + (tidalStrength * mult)
  end

  if _unitDef.windGenerator and _unitDef.windGenerator > 0 then
    local mult = 1 -- DEFAULT
    if _unitDef.customParams then
      mult = _unitDef.customParams.energymultiplier or mult
    end

    local unitWindMin = math.min(windMin, _unitDef.windGenerator)
    local unitWindMax = math.min(windMax, _unitDef.windGenerator)
    totalEOut = totalEOut + (((unitWindMin + unitWindMax) / 2) * mult)
  end
  return totalEOut
end

function widget:Initialize()
  if Spring.GetSpectatingState() or Spring.IsReplay() then
    widgetHandler:RemoveWidget()
  end

  myTeamId = Spring.GetMyTeamID()
  forwardedFromTargetIds = NewSetList()
  builders = {}
  builderUnitIds = NewSetList()
  ecoBuildDefIds = {}
  ecoBuildingTypeDefIds = {
    energy = { map = {}, list = {} },
    power = { map = {}, list = {} },
    mMM = { map = {}, list = {} }
  }
  metalMakers = {}
  reclaimTargets = NewSetList()
  reclaimTargetsPrev = NewSetList()
  regularizedResourceDerivativesEnergy = { true }
  regularizedResourceDerivativesMetal = { true }
  assignedTargetBuildSpeed = {}
  upgradableFromDefIds = {}
  upgradableToDefIds = {}

  local myUnits = GetTeamUnits(myTeamId)
  for _, unitID in ipairs(myUnits) do
    local unitDefID = GetUnitDefID(unitID)
    widget:UnitFinished(unitID, unitDefID, myTeamId)
  end

  for unitDefID, unitDef in pairs(UnitDefs) do
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
end

local function RegisterMetalMaker(unitID, unitDef)
  metalMakers[unitID] = unitDef.energyUpkeep
  possibleMetalMakersUpkeep = possibleMetalMakersUpkeep + unitDef.energyUpkeep
  possibleMetalMakersMetalProduction = possibleMetalMakersMetalProduction + unitDef.makesMetal
end

local function UnregisterMetalMaker(unitID, unitDef)
  if not unitID then
    return
  end
  if not unitDef then
    unitDef = UnitDefs[GetUnitDefID(unitID)]
  end
  metalMakers[unitID] = nil

  if not unitDef then
    return
  end
  possibleMetalMakersUpkeep = possibleMetalMakersUpkeep - unitDef.energyUpkeep
  possibleMetalMakersMetalProduction = possibleMetalMakersMetalProduction - unitDef.makesMetal
end

local function isMetalMaker(unitDef)
  if
      unitDef.isBuilding and
      ((unitDef.onOffable and unitDef.makesMetal > 0 and unitDef.energyUpkeep > 0) or
        unitDef.customParams.energyconv_capacity)
  then
    return true
  else
    return false
  end
end

function widget:UnitFinished(unitID, unitDefID, unitTeam)
  if unitTeam == myTeamId then
    local candidateBuilderDef = UnitDefs[unitDefID]

    if candidateBuilderDef.isBuilder and candidateBuilderDef.canAssist and not candidateBuilderDef.isFactory then
      builderUnitIds:Add(unitID)
      builders[builderUnitIds.count] = {
        id = unitID,
        def = candidateBuilderDef,
        defID = unitDefID,
        targetId = nil,
        guards = {},
        previousBuilding = nil,
        lastOrder = 0
      }
    end
    if isMetalMaker(candidateBuilderDef) then
      RegisterMetalMaker(unitID, candidateBuilderDef)
    end
  end
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
  if unitTeam == myTeamId then
    local index = builderUnitIds.hash[unitID]
    if index ~= nil then
      builders[index] = nil
    end
    builderUnitIds:Remove(unitID)
    UnregisterMetalMaker(unitID, UnitDefs[unitDefID])
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

local function Interpolate(value, inMin, inMax, outMin, outMax)
  -- Ensure the value is within the specified range
  -- Calculate the interpolation
  return outMin +
      ((((value < inMin) and inMin or ((value > inMax) and inMax or value)) - inMin) / (inMax - inMin)) *
      (outMax - outMin)
end

local function getBuildTimeLeft(targetId, targetDef)
  local _, _, _, _, build = GetUnitHealth(targetId)
  local currentBuildSpeed = 0
  -- for builderId, _ in pairs(builders) do
  for i = 1, builderUnitIds.count do
    local builder = BuilderById(builderUnitIds.list[i])
    if builder then -- todo investigate
      local testTargetId = GetUnitIsBuilding(builder.id)
      if testTargetId == targetId and builder.id ~= targetId then
        currentBuildSpeed = currentBuildSpeed + builder.def.buildSpeed
      end
    end
  end

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

local function reclaim(builderId, unitId)
  GiveOrderToUnit(builderId, CMD.INSERT, { 0, CMD.RECLAIM, CMD.OPT_SHIFT, unitId }, { 'alt' })
end

local function reclaimByEcoType(builderId, features, _needMetal, _needEnergy)
  if _needMetal and (_needEnergy or needEnergy) and features['metalenergy'] and #features['metalenergy'] > 0 then
    features['metalenergy'] = FeatureSortByHealth(features['metalenergy'])
    reclaim(builderId, Game.maxUnits + features['metalenergy'][1].id)
  elseif _needMetal and features['metal'] and #features['metal'] > 0 then
    features['metal'] = FeatureSortByHealth(features['metal'])
    reclaim(builderId, Game.maxUnits + features['metal'][1].id)
  elseif (_needEnergy or needEnergy) and features['energy'] and #features['energy'] > 0 then
    features['energy'] = FeatureSortByHealth(features['energy'])
    reclaim(builderId, Game.maxUnits + features['energy'][1].id)
  end
end

local function isBeingReclaimed(targetId)
  return reclaimTargetsPrev.hash[targetId] ~= nil or reclaimTargets.hash[targetId] ~= nil
end

local function purgeRepairs(builderId, cmdQueue, queueSize)
  if not cmdQueue then
    return {}
  end
  local cmd
  local removeCommands = {}
  for i = 1, #cmdQueue do
    cmd = cmdQueue[i]
    local targetId = cmd.params[1]
    -- if IsUnitSelectedLog(builderId) then
    -- end

    if cmd.id == CMD.REPAIR then -- 40
      local health, maxHealth, _, _, targetBuild = GetUnitHealth(targetId)
      if
          (targetBuild ~= nil and health ~= nil and targetBuild >= 1 and health >= maxHealth) or
          isBeingReclaimed(targetId)
      then
        -- local _, _, cmdTag2 = GetUnitCurrentCommand(builderId, i + 1)
        table.insert(removeCommands, { CMD.REMOVE, { cmd.tag }, { 'ctrl' } })
        -- GiveOrderToUnit(builderId, CMD.REMOVE, { cmdTag2, cmd.tag }, { "ctrl" })
        if not targetBuild then
          reclaimTargets:Remove(targetId)
          reclaimTargetsPrev:Remove(targetId)
        end
      end
    elseif cmd.id == CMD.RECLAIM then -- 90
      reclaimTargets:Add(targetId)
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
          -- dont purge finished and healthy
          if (targetBuild ~= nil and health ~= nil and targetBuild >= 1 and health >= maxHealth) then
            -- local _, _, cmdTag2 = GetUnitCurrentCommand(builderId, i + 1)
            table.insert(removeCommands, { CMD.REMOVE, { cmd.tag }, { 'ctrl' } })
          elseif isBeingReclaimed(buildingUnitId) then -- purge repairs of reclaimees
            table.insert(removeCommands, { CMD.REMOVE, { cmd.tag }, { 'ctrl' } })
            reclaimTargets:Remove(buildingUnitId)
            reclaimTargetsPrev:Remove(buildingUnitId)
          end
        end
      end
    end
  end

  if #removeCommands > 0 then
    -- if IsUnitSelectedLog(builderId) then
    -- log('purging', #removeCommands)
    -- end
    Spring.GiveOrderArrayToUnit(builderId, removeCommands)
  end
  return GetUnitCommands(builderId, queueSize)
end

local function repair(builderId, targetId, shift)
  -- log('repairing', builderId, targetId, alt, Spring.GetGameFrame())
  if shift then
    GiveOrderToUnit(builderId, CMD.INSERT, { 0, CMD.REPAIR, CMD.OPT_CTRL, targetId }, { 'shift' })
  else
    GiveOrderToUnit(builderId, CMD.INSERT, { 0, CMD.REPAIR, CMD.OPT_CTRL, targetId }, { 'alt' })
  end
  SetBuilderLastOrder(builderId)
end

local function getMetalMakersUpkeep()
  local totalUpKeep = 0
  for unitID, upKeep in pairs(metalMakers) do
    local state = GetUnitStates(unitID)
    if state.active then
      -- totalUpKeep = totalUpKeep + upKeep
    end
    local _, metal, _, energy = GetUnitResources(unitID)
    totalUpKeep = totalUpKeep + energy
  end

  return totalUpKeep
end

local function UpdateResourceNeeds()
  local metalCurrent, metalStorage, metalExpenseWanted, metalIncome, metalExpenseActual =
      GetTeamResources(myTeamId, 'metal')
  local energyCurrent, energyStorage, energyExpenseWanted, energyIncome, energyExpenseActual =
      GetTeamResources(myTeamId, 'energy')

  regularizationCounter = regularizationCounter > 5 and 1 or regularizationCounter + 1
  local currentMetalIncomeExpense = metalIncome - metalExpenseActual
  local currentEnergyIncomeExpense = energyIncome - energyExpenseActual
  regularizedResourceDerivativesMetal[regularizationCounter] = currentMetalIncomeExpense > 0
  regularizedResourceDerivativesEnergy[regularizationCounter] = currentEnergyIncomeExpense > 0
  regularizedPositiveMetal = table.full_of(regularizedResourceDerivativesMetal, true)
  regularizedPositiveEnergy = table.full_of(regularizedResourceDerivativesEnergy, true)
  regularizedNegativeMetal = table.full_of(regularizedResourceDerivativesMetal, false)
  regularizedNegativeEnergy = table.full_of(regularizedResourceDerivativesEnergy, false)

  -- regularizedPositiveMetal = metalIncome > metalExpenseActual
  -- regularizedPositiveEnergy = energyIncome > energyExpenseActual
  -- regularizedNegativeEnergy = energyIncome < energyExpenseActual

  metalLevel = metalCurrent / metalStorage
  energyLevel = energyCurrent / energyStorage

  metalMakersLevel = Spring.GetTeamRulesParam(myTeamId, 'mmLevel') + 0.12
  positiveMMLevel = getMetalMakersUpkeep() >= possibleMetalMakersUpkeep and energyLevel > metalMakersLevel
  -- log('positiveMMLevel', positiveMMLevel, 'upkeep', getMetalMakersUpkeep(), 'possible', possibleMetalMakersUpkeep, 'energyLevel', energyLevel, 'metalMakersLevel', metalMakersLevel)
  -- log('energyLevel - 0.3 < metalMakersLevel', energyLevel - 0.3 < metalMakersLevel)
  -- local mmOn = metalMakers.count / 2
  -- if energyLevel - 0.3 < metalMakersLevel then
  --   for unitId, upkeep in pairs(metalMakers) do
  --     if unitId then
  --       local health, _, _, _, build = GetUnitHealth(unitId)
  --       local _, _, _, energy = GetUnitResources(unitId)
  --       -- mmOn = i
  --       local unitDef = UnitIdDef(unitId)
  --       if health > 0 and build == 1 and energy < (tonumber(unitDef.customParams.energyconv_capacity) or unitDef.energyUpkeep) then
  --         positiveMMLevel = false
  --         break
  --       end
  --     end
  --   end
  -- end
  -- mmOn = mmOn / metalMakers.count

  isMetalStalling = metalLevel < 0.01 and not regularizedPositiveMetal
  isEnergyStalling = energyLevel < 0.01 and not regularizedPositiveEnergy
  isMetalLeaking = metalLevel > 0.99 and regularizedPositiveMetal
  isEnergyLeaking = energyLevel > 0.99 and regularizedPositiveEnergy

  needPower =
      (metalLevel > 0.8 or (regularizedPositiveMetal and metalLevel > 0.15)) and
      (positiveMMLevel or not regularizedNegativeEnergy)
  needEnergy = (not (regularizedPositiveEnergy and isEnergyLeaking and positiveMMLevel)) or isEnergyStalling
  needMM = positiveMMLevel and (not regularizedNegativeEnergy or isEnergyLeaking or isMetalStalling)

  -- log('energy status', energyExpenseActual, energyIncome, energyCurrent, (energyExpenseActual - energyIncome) / energyCurrent)
  -- log('any stall m', anyBuildWillMStall, 'e', anyBuildWillEStall)
  if anyBuildWillMStall or anyBuildWillEStall or isMetalStalling or isEnergyStalling then
    -- elseif anyBuildWillMStall or anyBuildWillEStall then
    --   powerNeed = 0.5
    -- log('power stall', anyBuildWillMStall, anyBuildWillEStall)
    powerNeed = 0
  elseif not anyBuildWillStall then
    log('power no stall 1')
    powerNeed = 1
  elseif anyBuildWillMStall or anyBuildWillEStall then
    -- powerNeed = Interpolate(metalCurrent, 0, 840, 0, 0.5) + Interpolate(energyCurrent, 0, 12800, 0, 0.5)
    -- log('power no stall 2 ', powerNeed)
    powerNeed = 0
  elseif positiveMMLevel then
    -- log('power some stall pos mm')
    powerNeed =
        math.max(
          0,
          math.min(
            1,
            (regularizedNegativeMetal and Interpolate((metalExpenseActual - metalIncome) / metalCurrent, 0, 10, 1, 0) or
              metalLevel) *
            -- * (energyIncome / energyExpenseActual)
            (regularizedNegativeEnergy and Interpolate((energyExpenseActual - energyIncome) / energyCurrent, 0, 10, 1, 0) or
              (not needMM and metalLevel or energyLevel))
          )
        )
  else
    -- log('power some stall neg mm')
    powerNeed =
        math.max(
          0,
          math.min(
            1,
            (regularizedNegativeMetal and Interpolate((metalExpenseActual - metalIncome) / metalCurrent, 0, 10, 1, 0) or
              metalLevel) *
            -- * (energyIncome / energyExpenseActual)
            (regularizedNegativeEnergy and Interpolate((energyExpenseActual - energyIncome) / energyCurrent, 0, 10, 1, 0) or
              energyLevel)
          )
        )
  end

  energyNeed = 0
  mMMNeed = 0
  if positiveMMLevel or not (regularizedNegativeEnergy and regularizedPositiveEnergy) then
    if positiveMMLevel then
      energyNeed =
          Interpolate(
            1 - (energyLevel - metalMakersLevel) - (getMetalMakersUpkeep() >= possibleMetalMakersUpkeep and 0.5 or 0),
            0,
            1,
            0,
            0.5
          )
      -- energyNeed = (1 - Interpolate(energyLevel, metalMakersLevel, 1, 0, 1))

      if positiveMMLevel then
        if regularizedPositiveEnergy and energyIncome > math.max(energyExpenseActual, energyExpenseWanted) then
          log('mm pos e', energyLevel, metalMakersLevel)
          if energyExpenseWanted > energyExpenseActual and metalExpenseWanted > metalExpenseActual then
            local eRatio = energyExpenseWanted / energyExpenseActual
            local mRatio = metalExpenseWanted / metalExpenseActual
            energyNeed = eRatio / (eRatio + mRatio)
            mMMNeed = mRatio / (eRatio + mRatio)
            log(string.format('ratios e %0.2f m %0.2f need e %0.2f m %0.2f', eRatio, mRatio, energyNeed, mMMNeed))
          else
            mMMNeed = Interpolate(energyLevel, metalMakersLevel, 1, 0.75, 1)
          end
        elseif not regularizedPositiveEnergy and energyIncome <= math.max(energyExpenseActual, energyExpenseWanted) then
          log('mm neg e', energyLevel, metalMakersLevel)
          energyNeed = 1
          mMMNeed = 0
        elseif (anyBuildWillEStall) then
          -- elseif (anyBuildWillMStall or anyBuildWillEStall) then
          -- log('mm stall', energyLevel, metalMakersLevel)
          -- mMMNeed = 0
          mMMNeed = 0
        else
          -- log('mm stable', energyLevel, metalMakersLevel, regularizedNegativeEnergy, currentEnergyIncomeExpense)
          mMMNeed = Interpolate(energyLevel, metalMakersLevel, 1, 0.5, 1)
        end
        -- MMNeed = math.max(0, math.min(1, (positiveMMLevel and 1 or 0) * (energyIncome / energyExpenseActual) * Interpolate(energyLevel, metalMakersLevel, 1, 0, 1) * (1 - metalLevel)))

        -- log('power', 'needMM', needMM, (metalLevel + (not needMM and 1 or energyLevel)) / 2)
        -- log('energy', needEnergy, (not (regularizedPositiveEnergy and isEnergyLeaking and positiveMMLevel)))
        -- log('MM', 'positiveMMLevel', positiveMMLevel, 'regularizedPositiveMetal', 'regularizedNegativeEnergy', regularizedNegativeEnergy, 'isEnergyLeaking', isEnergyLeaking, 'isMetalStalling', isMetalStalling)
      end
    elseif not (regularizedNegativeEnergy and regularizedPositiveEnergy) then
      -- log('e stable e', energyLevel, metalMakersLevel)
      -- stable
      if anyBuildWillMStall or anyBuildWillEStall then
        -- energyNeed = (1 - Interpolate(energyLevel, metalMakersLevel, 1, 0, 1)) and (1 - Interpolate(energyLevel, metalMakersLevel, 1, 0, 1)) or Interpolate(energyExpenseActual / energyIncome, 2, 1, 0.5, 0.5) * (1 - energyLevel)
        energyNeed = Interpolate(energyLevel, 0, metalMakersLevel, 1, 0.75)
      else
        energyNeed = 0.5
      end
      mMMNeed = 0
    end
  elseif regularizedNegativeEnergy then
    -- log('e neg e', energyLevel, metalMakersLevel)
    energyNeed = Interpolate(energyLevel, 0, metalMakersLevel, 0.5, 1)
    mMMNeed = 0
  elseif regularizedPositiveEnergy then
    -- log('e pos e', energyLevel, metalMakersLevel)
    energyNeed = Interpolate(energyLevel, 0, metalMakersLevel, 1, 0.75)
  end
  -- mMMNeed = math.max(0, math.min(1, (needMM and 1 or 0) * Interpolate(energyLevel, metalMakersLevel, 1, 0, 1) * (1 - metalLevel)))
  -- mMMNeed = math.max(0, math.min(1, (positiveMMLevel and 1 or 0) * (regularizedNegativeEnergy and 1 or 0.5) * Interpolate(energyLevel, metalMakersLevel, 1, 0, 1) * (1 - metalLevel)))

  -- mMMNeed = math.max(0, math.min(1, (positiveMMLevel and 1 or 0) * (energyIncome / energyExpenseActual) * Interpolate(energyLevel, metalMakersLevel, 1, 0, 1) * (1 - metalLevel)))
end

local function GetResourceStatus(type)
  local lvl, storage, pullExpWanted, inc, expActual, shareSlider, sent, recieved = GetTeamResources(myTeamId, type)

  if not inc then
    return
  end
  -- local total = recieved + inc - exp
  --  todo maybe remove
  local total = recieved
  local exp = 0
  local units = GetTeamUnits(myTeamId)

  if type == 'metal' then
    for _, unitID in ipairs(units) do
      local metalMake, metalUse = GetUnitResources(unitID)
      total = total + metalMake - metalUse
      exp = exp + metalUse
    end
  else
    for _, unitID in ipairs(units) do
      local _, _, energyMake, energyUse = GetUnitResources(unitID)
      total = total + energyMake - energyUse
      exp = exp + energyUse
    end
  end

  local alreadyInStall = pullExpWanted > lvl or exp > lvl

  return total, lvl, storage, exp, alreadyInStall
end

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

local function traceUpkeep(unitID, alreadyCounted)
  if alreadyCounted[unitID] then
    return 0, 0
  end

  local builder = BuilderById(unitID)
  if not builder then
    return 0, 0
  end

  local metalMake, metal, energyMake, energy = GetUnitResources(unitID)

  for _, guardID in ipairs(builder.guards) do
    if BuilderById(guardID).owned then
      local guarderMetal, guarderEnergy = traceUpkeep(guardID, alreadyCounted)
      metal = metal + guarderMetal
      energy = energy + guarderEnergy
    end
  end

  alreadyCounted[unitID] = unitID

  return metal - metalMake + builder.def.metalMake, energy - energyMake + builder.def.energyMake
end

local function getUnitsUpkeep()
  local alreadyCounted = {}

  local metal = 0
  local energy = 0

  for _, unitId in ipairs(GetTeamUnits(myTeamId)) do
    local _unitDef = UnitIdDef(unitId)
    if _unitDef.canAssist then
      local metalUse, energyUse = traceUpkeep(unitId, alreadyCounted)
      metal = metal + metalUse
      energy = energy + energyUse
    end
  end
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
  return mStall or eStall, mStall, eStall
end

local function SortMAndMM(a, b)
  return ((a.def.extractsMetal / a.def.cost) > (b.def.extractsMetal / b.def.cost)) or
      (MetalMakingEfficiencyDef(a.def) > MetalMakingEfficiencyDef(b.def))
end

-- -- TODO Not Implemented
-- local function BuildQueueSkipPriority(builderId)
--   local commands = Spring.GetCommandQueue(builderId, 500)

--   if not commands or #commands == 0 then
--     return
--   end

--   local ecoBuildings = {}
--   local previousCommand = nil
--   for i = 1, #commands do
--     local command = commands[i]

--     if ecoBuildDefIds[-command.id] then
--       return
--     end
--     if previousCommand then
--       table.insert(ecoBuildings, command)
--     end
--   end
-- end

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
    GiveOrderToUnit(builder.id, CMD.REMOVE, { cmdQueueTag }, { 'ctrl' }) -- was 0 instead of 'ctrl' for a while
    builder.previousBuilding = targetId
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
    if not table.has_value({ 'armcom', 'legcom', 'corcom' }, featureRessurrect) then
      local metal, _, energy = GetFeatureResources(featureId)

      nAll = nAll + 1
      features['all'][nAll] = { id = featureId }
      if metal > 0 and energy > 0 then
        nME = nME + 1
        features['metalenergy'][nME] = { id = featureId }
      elseif metal > 0 then
        nM = nM + 1
        features['metal'][nM] = { id = featureId }
      elseif energy > 0 then
        nE = nE + 1
        features['energy'][nE] = { id = featureId }
      end
    end
  end
  return features, nAll
end

local function SortFactor(a, b)
  -- Convert boolean comparison to 1 or 0
  local buildSpeedA = a.def.buildoptions and #a.def.buildoptions > 0 and 1.01 or Interpolate(a.def.buildSpeed, 0, 1000, 0, 1)
  local buildSpeedB = a.def.buildoptions and #a.def.buildoptions > 0 and 1.01 or Interpolate(b.def.buildSpeed, 0, 1000, 0, 1)
  -- Calculate energy efficiency ratios
  local energyMakeDefA = EnergyMakeDef(a.def) / a.def.cost
  local energyMakeDefB = EnergyMakeDef(b.def) / b.def.cost
  -- Determine energy factor
  local energyMakeDef = 0
  if energyMakeDefA > 0 and energyMakeDefB > 0 then
    energyMakeDef = Interpolate(energyMakeDefA / energyMakeDefB, 0.2, 2, 0, 1)
  elseif energyMakeDefA > 0 then
    energyMakeDef = 1
  end

  -- Get M and MM sort factor
  local sortMAndMM = SortMAndMM(a, b) and 1 or 0
  -- Calculate scores for each option
  local scoreA = powerNeed * buildSpeedA + energyNeed * energyMakeDef + mMMNeed * sortMAndMM
  local scoreB = powerNeed * buildSpeedB + energyNeed * (1 - energyMakeDef) + mMMNeed * (1 - sortMAndMM)

  -- Log results if needed
  -- log('sort2', a.def.name, b.def.name,
  --   scoreA,
  --   scoreB,
  --   'b a',
  --   buildSpeedA,
  --   'b b',
  --   buildSpeedB,
  --   'e a',
  --   energyMakeDefA,
  --   'e b',
  --   energyMakeDefB,
  --   'm m',
  --   sortMAndMM,
  --   'p',
  --   powerNeed,
  --   'e',
  --   energyNeed,
  --   'm',
  --   mMMNeed
  -- )

  -- Return true if A scores higher than B
  return scoreA > scoreB
end

local function SortBuildEcoPrio(a, b)
  if a == nil or b == nil then
    return false
  end
  -- log('sort1', a.def.translatedHumanName, b.def.translatedHumanName, SortFactor(a, b))
  local result =
      ((a.defId == b.defId) and (a.build > b.build)) or SortFactor(a, b) or
      (not needPower and not needEnergy and not needMM and
        ((a.def.buildSpeed / a.def.cost) > (b.def.buildSpeed / b.def.cost)))
  -- if a and b then
  -- log('Sort Eco p', powerNeed, 'e', energyNeed, 'm', mMMNeed, result, a.def.translatedHumanName, b.def.translatedHumanName, energyMakeDef(a.def) / a.def.cost, energyMakeDef(b.def) / b.def.cost, a.build, b.build)
  -- log('SortBuildEcoPrio p', math.floor(0.5 + powerNeed * 100), 'e', math.floor(0.5 + energyNeed * 100), 'm', math.floor(0.5 + mMMNeed * 100), result, a.def.translatedHumanName, b.def.translatedHumanName, energyMakeDef(a.def) / a.def.cost, energyMakeDef(b.def) / b.def.cost, a.build, b.build)
  -- log(string.format('sort %s p %.0f e %.0f m %.0f %s %s', tostring(result), powerNeed * 100, energyNeed * 100, mMMNeed * 100, a.def.translatedHumanName, b.def.translatedHumanName))
  -- end
  return result
end

local function GetPurgedUnitCommands(builderId, queueSize)
  if queueSize == nil then
    queueSize = 100
  end
  local commandQueue = GetUnitCommands(builderId, queueSize)
  if commandQueue == nil then
    widget:UnitDestroyed(builderId, nil, myTeamId)
    return nil, 0
  end

  commandQueue = purgeRepairs(builderId, commandQueue, queueSize)
  return commandQueue, #commandQueue
end

local function IdlingCandidates(builder, targetId, cmdQueue, nCmdQueue, gameFrame, isBuildingFetchCandidatesOnly)
  local builderId = builder.id

  local isBuildingEco =
      nCmdQueue == 0 or
      (cmdQueue[1] and
        (((cmdQueue[1].id == CMD.REPAIR) and (ecoBuildDefIds[GetUnitDefID(cmdQueue[1].params[1])])) or
          ((ecoBuildDefIds[-cmdQueue[1].id]) and GetUnitIsBuilding(builderId) ~= nil)))

  local notHasBuildingQueue =
      not (cmdQueue and ((cmdQueue[1] and cmdQueue[1].id < 0) or (cmdQueue[2] and cmdQueue[2].id < 0)))

  -- dont disturb buildqueuers, ecoers and pass through candidate fetching
  if not (notHasBuildingQueue or isBuildingEco or isBuildingFetchCandidatesOnly) then
    return {}, 0, nil, 0
  end

  local builderDef = builder.def
  local features = {}
  local nFeaturesAll = 0
  local builderPosX, _, builderPosZ = GetUnitPosition(builderId, true)
  -- log('builder ', builderId, builderDef.translatedHumanName, builder.def.radius)
  local candidateIds = GetUnitsInCylinder(builderPosX, builderPosZ, builderDef.buildDistance + 96, myTeamId)
  local candidatesDamaged = {}
  local candidatesUnfinished = {}
  local nCandidatesUnfinished = 0
  local nCandidatesDamaged = 0
  local isRepairingDamaged = false
  local candidatesGuardBuilders = {}

  -- log('IdlingCandidates', builderId, builder.def.translatedHumanName, 'isBuildingEco', isBuildingEco, 'notHasBuildingQueue', notHasBuildingQueue, cmdQueue[1] and cmdQueue[1].id, cmdQueue[2] and cmdQueue[2].id)

  for j = 1, #candidateIds do
    local candidateId = candidateIds[j]
    if candidateId ~= builderId then
      local candidateHealth, candidateMaxHealth, _, _, candidateBuild = GetUnitHealth(candidateId)
      if
          candidateHealth ~= nil and candidateMaxHealth ~= nil and
          (candidateHealth < candidateMaxHealth or candidateBuild < 1)
      then
        local candidateDefId = GetUnitDefID(candidateId)
        local def = UnitDefs[candidateDefId]
        if GetUnitSeparation(builderId, candidateId, true, true) + builder.def.radius < builderDef.buildDistance then
          local candidate = {
            id = candidateId,
            defId = candidateDefId,
            def = def,
            health = candidateHealth,
            maxHealth = candidateMaxHealth,
            build = candidateBuild,
            healthRatio = candidateHealth / candidateMaxHealth
          }
          if candidateBuild < 1 then
            -- log('CandidatesUnfinished', candidateId, candidateHealth, candidateMaxHealth, candidateBuild, candidate.healthRatio, candidate.def.translatedHumanName, nCandidatesUnfinished)
            nCandidatesUnfinished = nCandidatesUnfinished + 1
            candidatesUnfinished[nCandidatesUnfinished] = candidate
          elseif candidateHealth < candidateMaxHealth then
            -- log('neighboursDamaged', candidateId, candidateHealth, candidateMaxHealth, candidateBuild, candidate.healthRatio, candidate.def.translatedHumanName, nNeighboursDamaged)
            nCandidatesDamaged = nCandidatesDamaged + 1
            candidatesDamaged[nCandidatesDamaged] = candidate
          else
            local candidateQueue = GetPurgedUnitCommands(candidateId)
            if candidateQueue and #candidateQueue > 0 and candidateQueue[1].id < 0 then
              table.insert(candidatesGuardBuilders, candidateId)
            end
          end
        end
      end
    end
  end
  -- log(builder.def.translatedHumanName, '#CandidatesUnfinished', #CandidatesUnfinished, nCandidatesUnfinished)

  local targetHealthRatio = 1
  if nCandidatesDamaged > 0 then
    table.sort(candidatesDamaged, SortHealthAsc)
    local damagedTarget = candidatesDamaged[1]
    local damagedTargetId = damagedTarget.id
    if targetId then
      local targetHealth, targetMaxHealth = GetUnitHealth(targetId)
      targetHealthRatio = targetHealth / targetMaxHealth

      if
          targetId ~= damagedTargetId and
          (not targetHealthRatio or targetHealthRatio == 0 or damagedTarget.healthRatio * 0.95 < targetHealthRatio) and
          not isBeingReclaimed(damagedTargetId) and
          AllowBuilderOrder(builderId, gameFrame)
      then
        targetId = damagedTargetId
        -- log('repair damaged', targetId, 'not isBeingReclaimed(targetId)', not isBeingReclaimed(targetId))
        if not isBuildingFetchCandidatesOnly then
          repair(builderId, targetId, false)
          isRepairingDamaged = true
        end
      end
    end
  end
  -- log('gotoContinue', 'neighboursDamaged', 'targetId', targetId, 'damagedTargetId', damagedTargetId, 'targetHealthRatio', targetHealthRatio, 'damagedTarget.healthRatio', damagedTarget.healthRatio)
  -- log('gotoContinue neighboursDamaged')
  if nCandidatesUnfinished > 0 and (not isRepairingDamaged or isBuildingFetchCandidatesOnly) then
    -- log('sort', builder.def.translatedHumanName, #candidatesUnfinished, nCandidatesUnfinished)
    table.sort(candidatesUnfinished, SortBuildEcoPrio)
    -- local candidateId = candidatesUnfinished[1].id
    -- if targetId ~= candidateId then
    -- targetId = candidateId
    -- if not isBuildingFetchCandidatesOnly then
    -- log('repair unfinished', candidatesUnfinished[1].def.translatedHumanName, targetId)
    -- WG["ObjectSpotlight"].addSpotlight('unit', 'me', builderId, { 1, 0, 0, 1 }, { duration = 25, radius = 2, heightCoefficient = 5 })
    -- repair(builderId, targetId, false)
    -- end
    -- end
  end

  -- if not isRepairingDamaged and not returnForEasyFinish then
  -- if builder.def.name:match('.*armcom.*') then
  --   log('isBuildingFetchCandidatesOnly', not isBuildingFetchCandidatesOnly
  --     and (not isRepairingDamaged or
  --       (isRepairingDamaged and (
  --         ((energyNeed > (1 - targetHealthRatio))
  --           or (mMMNeed > (1 - targetHealthRatio))
  --           or (energyLevel < targetHealthRatio)
  --           or (metalLevel < targetHealthRatio)
  --         )
  --         and (nCandidatesDamaged < 5))
  --       )
  --     ))
  -- end
  if
      not isBuildingFetchCandidatesOnly and
      (not isRepairingDamaged or
        (isRepairingDamaged and
          (((energyNeed > (1 - targetHealthRatio)) or (mMMNeed > (1 - targetHealthRatio)) or
              (energyLevel < targetHealthRatio) or
              (metalLevel < targetHealthRatio)) and
            (nCandidatesDamaged < 5)))) and
      (nCandidatesUnfinished == 0 or isEnergyStalling or isMetalStalling or
        (nCandidatesUnfinished > 0 and (anyBuildWillEStall or anyBuildWillMStall) and
          (builderDef.buildSpeed < 0.2 * totalBuildSpeed or (metalLevel < 0.05 and energyLevel < 0.05))))
  then
    local _needMetal = metalLevel < 0.9
    local _needEnergy = needEnergy or energyLevel < 0.9
    cmdQueue, nCmdQueue = GetPurgedUnitCommands(builderId)
    if
        not isMetalLeaking and not isEnergyLeaking and builderDef and
        (#builderDef.buildOptions == 0 or nCmdQueue == 0 or not isBuildingEco)
    then
      features, nFeaturesAll = getReclaimableFeatures(builderPosX, builderPosZ, builderDef.buildDistance)
      if features then
        -- log('idlingcandidates reclaimCheckAction', builderDef.translatedHumanName, builderDef.buildSpeed)
        if _needMetal and _needEnergy then
          reclaimByEcoType(builderId, features, true, true)
        elseif _needMetal then
          reclaimByEcoType(builderId, features, true, false)
        elseif _needEnergy then
          reclaimByEcoType(builderId, features, false, true)
        end
        -- log('gotoContinue reclaimCheckAction can reclaim')
      end
    elseif
        cmdQueue and nCmdQueue > 0 and cmdQueue[1].id == CMD.RECLAIM and
        (metalLevel > 0.97 or energyLevel > 0.97 or isMetalLeaking or isEnergyLeaking)
    then
      -- log('should stop reclaim', builderDef.translatedHumanName)
      features, nFeaturesAll = getReclaimableFeatures(builderPosX, builderPosZ, builderDef.buildDistance)
      local featureId = cmdQueue[1].params[1]
      local metal, _, energy = GetFeatureResources(featureId)

      if metal and metal > 0 and (metalLevel > 0.97 or isMetalLeaking) then
        GiveOrderToUnit(builderId, CMD.REMOVE, { nil }, { 'ctrl' })
      elseif energy and energy > 0 and (energyLevel > 0.97 or isEnergyLeaking) then
        GiveOrderToUnit(builderId, CMD.REMOVE, { nil }, { 'ctrl' })
      end
    else
      local reclaiming = false
      if MRandom() < (builderDef.translatedHumanName == 'Base Builder' and 0.6 or 0.16) then
        features, nFeaturesAll = getReclaimableFeatures(builderPosX, builderPosZ, builderDef.buildDistance)
        if nFeaturesAll > 0 then
          -- log('randomly reclaiming', builderDef.translatedHumanName)
          local featuresAll = FeatureSortByHealth(features.all)
          local feature
          for i = 1, nFeaturesAll do
            feature = featuresAll[i]
            if feature and feature.health and feature.health < 81 then
              -- log('random reclaiming', builderDef.translatedHumanName, feature.id)
              GiveOrderToUnit(
                builderId,
                CMD.INSERT,
                { 0, CMD.RECLAIM, CMD.OPT_SHIFT, Game.maxUnits + feature.id },
                { 'alt' }
              )
              reclaiming = true
              break
            elseif feature and feature.health and feature.health >= 81 then
              break
            end
          end
        end
      end

      if not reclaiming and #candidatesGuardBuilders > 0 then
        log('guarding', builderDef.translatedHumanName, '->', candidatesGuardBuilders[1])
        GiveOrderToUnit(builderId, CMD.INSERT, { 0, CMD.GUARD, CMD.OPT_SHIFT, candidatesGuardBuilders[1] }, { 'alt' })
      end
    end
  end

  return candidatesUnfinished, nCandidatesUnfinished, features, nFeaturesAll
end

--[[
  local commands = {}
  local nCommands = 0
  for _, command in pairs(mergedCommands) do
  nCommands = nCommands + 1
  commands[nCommands] = {command.id, command.params, command.options, buildSpeed=0, assistersBuildSpeeds={}, isShield=isShieldDefId[-command.id], x=command.params and command.params[1], z=command.params and command.params[3]}
  if command.params[1] and command.params[3] then

    for j = 1, #allImmobileBuilders do
    if Distance(allImmobileBuilders[j].x, allImmobileBuilders[j].z, command.params[1], command.params[3]) < allImmobileBuilders[j].buildDistance then

      local buildSpeed = unitIdBuildSpeeds:get(allImmobileBuilders[j].id)
      if buildSpeed == nil then
      buildSpeed = UnitDefs[Spring.GetUnitDefID(allImmobileBuilders[j].id)].buildSpeed
      unitIdBuildSpeeds:put(allImmobileBuilders[j].id, buildSpeed)
      end

      if buildSpeed > 0 then
      commands[nCommands].buildSpeed = commands[nCommands].buildSpeed + buildSpeed

--]]
local function SortBuildBuildSpeed(a, b)
  return (a.buildSpeed * a.build) > (b.buildSpeed * b.build)
end

local function BatchOrder(gameFrame)
  local needs = {
    { 'power',  powerNeed },
    { 'energy', energyNeed },
    { 'mMM',    mMMNeed }
  }

  table.sort(
    needs,
    function(a, b)
      return math.abs(a[2]) > math.abs(b[2])
    end
  )

  table.remove(needs)
  -- normalize need values so that they sum to 1
  local sum = 0
  for _, need in ipairs(needs) do
    sum = sum + need[2]
  end
  for _, need in ipairs(needs) do
    need[2] = need[2] / sum
  end

  local assignedBuilders = {}
  local nAssignedBuilders = 0
  for _, need in ipairs(needs) do
    local needName = need[1]
    local needValue = need[2]
    -- Get the ecoBuildingDefIds[type].map for the current need type
    local ecoBuildingMap = ecoBuildingTypeDefIds[needName].map
    local ecoBuildingList = ecoBuildingTypeDefIds[needName].list

    -- Get candidates for alternative builds (units to assist or start new builds)
    local candidateAlternatives = {}
    local candidateAlternativeUnitIds = Spring.GetTeamUnitsByDefs(myTeamId, ecoBuildingList)

    for i = 1, #candidateAlternativeUnitIds do
      local unitId = candidateAlternativeUnitIds[i]
      local build = select(5, GetUnitHealth(unitId))
      if build < 1 then
        table.insert(
          candidateAlternatives,
          { id = unitId, build = build, buildSpeed = 0, builderIds = {}, alreadyBuilding = {} }
        )
      end
    end

    -- Filter builders not selected and not throttled
    local candidateBuilders = {}
    local correctTypeBuilders = 0
    local incorrectTypeBuilders = 0
    for i = 1, builderUnitIds.count do
      local builder = BuilderById(builderUnitIds.list[i])
      if builder and not assignedBuilders[builder.id] then
        local commandQueue = GetPurgedUnitCommands(builder.id, 3)

        local busy = false
        if commandQueue and #commandQueue > 0 then
          local command = commandQueue[1]
          busy = busyCommands[command.id] or (command.id < 0) or false
        end

        if not busy then
          if not builder.targetId then
            builder.targetId = GetUnitIsBuilding(builder.id)
          end

          local targetDefId = builder.targetId and GetUnitDefID(builder.targetId)
          -- log('ecoBuildingMap', table.tostring(ecoBuildingMap))
          -- log('ecoBuildingMap[targetDefId]', builder.id, builder.targetId, targetDefId, ecoBuildingMap[targetDefId])
          if builder.targetId ~= builder.id then
            if targetDefId then
              if ecoBuildingMap[targetDefId] then
                correctTypeBuilders = correctTypeBuilders + 1
              else
                -- log('incorrectTypeBuilders', builder.id, builder.targetId, builder.def.translatedHumanName)
                incorrectTypeBuilders = incorrectTypeBuilders + 1
              end
            end

            if not selectedUnits[builder.id] and AllowBuilderOrder(builder.id, gameFrame) then
              table.insert(candidateBuilders, builder)
              -- local x, _, z = Spring.GetUnitPosition(builder.id)
              for j = 1, #candidateAlternatives do
                local candidate = candidateAlternatives[j]
                -- log(
                --   'builder.targetId',
                --   builder.targetId,
                --   'candidate.id',
                --   candidate.id,
                --   builder.targetId ~= candidate.id
                -- )
                -- if Distance(candidate.x, candidate.z, x, z) <= builder.def.buildDistance + 96 then
                if GetUnitSeparation(builder.id, candidate.id, true, true) < builder.def.buildDistance - 12 then
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
    end

    -- log(needName, 'candidateAlternatives', table.tostring(candidateAlternatives))
    -- for i = 1, #allImmobileBuilders do
    --   local x, _, z = Spring.GetUnitPosition(allImmobileBuilders[i])
    -- end

    -- Sort by build power * construction progress
    table.sort(candidateAlternatives, SortBuildBuildSpeed)

    -- Assign a subset of builders to assist or start new builds
    local targets = {}
    local nTotalBuilders = math.max(correctTypeBuilders + incorrectTypeBuilders, #candidateBuilders)
    local fulfilledNeed = 0
    -- log(needName, 'total', nTotalBuilders, 'correct', correctTypeBuilders, 'incorrect', incorrectTypeBuilders)
    for _, candidateAlternative in ipairs(candidateAlternatives) do
      for _, builderId in ipairs(candidateAlternative.builderIds) do
        if not assignedBuilders[builderId] then
          if fulfilledNeed <= needValue then
            if targets[candidateAlternative.id] == nil then
              targets[candidateAlternative.id] = {}
            end

            assignedBuilders[builderId] = true
            nAssignedBuilders = nAssignedBuilders + 1
            fulfilledNeed = nAssignedBuilders / nTotalBuilders

            if not candidateAlternative.alreadyBuilding[builderId] then
              table.insert(targets[candidateAlternative.id], builderId)
              WG["ObjectSpotlight"].addSpotlight('unit', 'me', builderId, { 0, 1, 0, 1 }, { duration = 25, radius = 2, heightCoefficient = 5 })
              BuilderById(builderId).targetId = candidateAlternative.id
              SetBuilderLastOrder(builderId)
            end
          else
            break
          end
        end
      end
      if fulfilledNeed > needValue then
        break
      end
    end

    -- If there are builders to assign, issue a batch order
    if nAssignedBuilders > 0 then
      for targetId, _builders in pairs(targets) do
        if #_builders > 1 then
          -- log(string.format('p %0i e %i m %i', powerNeed * 100, energyNeed * 100, mMMNeed * 100))
          log(
            needName ..
            string.format(' batch %.2f builders %s/%s %s target ', needValue, #_builders, nTotalBuilders, table.tostring(_builders)) ..
            targetId,
            UnitDefs[GetUnitDefID(targetId)].translatedHumanName,
            gameFrame
          )

          Spring.GiveOrderToUnitArray(_builders, CMD.INSERT, { 0, CMD.REPAIR, CMD.OPT_CTRL, targetId }, { 'alt' })
        end
      end
    end
  end
end

local function Builders(gameFrame)
  totalBuildSpeed = 0
  anyBuildWillMStall = false
  anyBuildWillEStall = false
  anyBuildWillStall = false
  assignedTargetBuildSpeed = {}
  for i = 1, builderUnitIds.count do
    local builder = BuilderById(builderUnitIds.list[i])
    if builder then
      builder.targetId = GetUnitIsBuilding(builder.id)
      if builder.targetId then
        assignedTargetBuildSpeed[builder.targetId] =
            (assignedTargetBuildSpeed[builder.targetId] or 0) + builder.def.buildSpeed
      end
    else
      widget:UnitDestroyed(builderUnitIds.list[i], nil, myTeamId)
    end
  end

  for i = 1, builderUnitIds.count do
    local builder = BuilderById(builderUnitIds.list[i])
    if builder then
      if builder.targetId then
        local _, mStall, eStall = TargetWillStall(builder.targetId)
        anyBuildWillMStall = anyBuildWillMStall or mStall
        anyBuildWillEStall = anyBuildWillEStall or eStall
        anyBuildWillStall = anyBuildWillStall or anyBuildWillMStall or anyBuildWillEStall
      end
      totalBuildSpeed = totalBuildSpeed + builder.def.buildSpeed
    end
  end

  UpdateResourceNeeds()

  selectedUnits = {}
  if not isUnitLogActive then
    local selectedUnitsList = Spring.GetSelectedUnits()
    for i = 1, #selectedUnitsList do
      selectedUnits[selectedUnitsList[i]] = true
    end
  end

  -- if math.random(20) == 20 then
  if gameFrame % 4 == 0 then
    BatchOrder(gameFrame)
  end

  for i = 1, builderUnitIds.count do
    if i % buildersJitterModulo == 0 then
      if not selectedUnits[builderUnitIds.list[i]] or isUnitLogActive then
        local builder = BuilderById(builderUnitIds.list[i])
        if builder and AllowBuilderOrder(builder.id, gameFrame) then
          -- if builder.def.name:match('.*armcom.*') then
          --   log('builder', table.tostring(builder))
          -- end
          local builderId = builder.id
          local builderDef = builder.def
          local commandQueue, nCommandQueue = GetPurgedUnitCommands(builderId)

          -- dont wait if has queued stuff and leaking
          if
              commandQueue and nCommandQueue > 0 and (isMetalLeaking or isEnergyLeaking) and
              commandQueue[1].id == CMD.WAIT
          then
            GiveOrderToUnit(builderId, CMD.REMOVE, { nil }, { 'ctrl' })
            commandQueue, nCommandQueue = GetPurgedUnitCommands(builderId)
          end

          local features = nil
          local nFeaturesAll = 0
          if commandQueue then
            local builderPosX, _, builderPosZ

            -- log('builder ', builderId, builderDef.translatedHumanName, 'cmdQueue', table.tostring(cmdQueue))

            local targetId = builder.targetId

            local isBuildingFetchCandidatesOnly, isManualActionCommand
            if nCommandQueue > 0 then
              local nextCommandId = commandQueue and commandQueue[1] and commandQueue[1].id
              isBuildingFetchCandidatesOnly =
                  nextCommandId < 1 and commandQueue[2] and commandQueue[2].id and commandQueue[2].id < 0
              isManualActionCommand = busyCommands[nextCommandId]
            else
              isBuildingFetchCandidatesOnly = false
            end

            local candidatesUnfinished = {}
            local nCandidatesUnfinished = 0
            if (targetId and not isManualActionCommand) or nCommandQueue == 0 then
              candidatesUnfinished, nCandidatesUnfinished, features, nFeaturesAll =
                  IdlingCandidates(
                    builder,
                    targetId,
                    commandQueue,
                    nCommandQueue,
                    gameFrame,
                    isBuildingFetchCandidatesOnly
                  )
            end

            -- queue fast forward / skip ahead
            -- if builder.def.name == 'armck' then
            --   log('isMultiBuilding', isMultiBuilding, 'targetId', targetId)
            -- end
            -- if IsUnitSelectedLog(builderId) then
            --   log('ff targetId', targetId, 'isBuildingFetchCandidatesOnly', isBuildingFetchCandidatesOnly)
            -- end
            if targetId and isBuildingFetchCandidatesOnly then
              -- BuildQueueSkipPriority(builder)
              -- if builder.def.name == 'armck' then
              --   log('ff?', nCmdQueue, cmdQueue and cmdQueue[1] and cmdQueue[1].id, cmdQueue and cmdQueue[2] and cmdQueue[2].id, cmdQueue and cmdQueue[3] and cmdQueue[3].id)
              -- end
              BuildQueueSkipAssisted(builder, targetId, commandQueue[1].tag, commandQueue[2].tag)
              -- else
              -- log('idling?', builderId, targetId, isBuildingFetchCandidatesOnly)
            end

            -- 90 == reclaim cmd
            if
                not isManualActionCommand and not isBuildingFetchCandidatesOnly and not isMetalLeaking and
                not isEnergyLeaking and
                not (commandQueue and nCommandQueue > 0 and
                  (commandQueue[1].id == CMD.RECLAIM or (commandQueue[1].id == CMD.REPAIR and gameFrame < 60 * 30)))
            then
              if not features then
                builderPosX, _, builderPosZ = GetUnitPosition(builderId, true)
                features, nFeaturesAll = getReclaimableFeatures(builderPosX, builderPosZ, builderDef.buildDistance)
              end
              if nFeaturesAll > 0 then
                -- log(
                --   'builder iter reclaimCheckAction',
                --   builderDef.translatedHumanName,
                --   builderDef.buildSpeed,
                --   totalBuildSpeed
                -- )
                if isMetalStalling and isEnergyStalling then
                  reclaimByEcoType(builderId, features, true, true)
                elseif isMetalStalling and not isEnergyLeaking then
                  -- elseif isEnergyStalling and not isMetalLeaking then
                  reclaimByEcoType(builderId, features, true, false)
                else
                  reclaimByEcoType(builderId, features, false, true)
                end
                -- log('gotoContinue reclaimCheckAction isstalling')
              end
            end

            -- easy finish neighbour
            if AllowBuilderOrder(builderId, gameFrame, 2) then
              -- refresh for possible target change
              targetId = GetUnitIsBuilding(builderId)
              -- if builder.def.name == 'armck' then
              --   log('ef', 'targetId', targetId, 'nCandidatesUnfinished', nCandidatesUnfinished)
              -- end
              if targetId then
                local targetDefId = GetUnitDefID(targetId)

                local _, _, _, _, targetBuild = GetUnitHealth(targetId)
                for j = 1, nCandidatesUnfinished do
                  local candidate = candidatesUnfinished[j]
                  local candidateId = candidate.id
                  -- if builder.def.name == 'armck' then
                  -- log('ef'
                  -- -- , candidate.def.translatedHumanName
                  -- , candidate.defId, targetDefId, candidateId, targetId
                  -- )
                  -- end
                  -- same type and not actually same building
                  if
                      candidate.defId == targetDefId and candidateId ~= targetId and candidate.build and
                      candidate.build < 1 and
                      candidate.build > targetBuild and
                      AllowBuilderOrder(builderId, gameFrame)
                  then
                    -- if builder.def.name == 'armck' then
                    log('ef repair', candidate.id, candidate.def.translatedHumanName, candidate.build, 'instead of', candidatesUnfinished[j + 1] and candidatesUnfinished[j + 1].def.translatedHumanName .. ' ' .. candidatesUnfinished[j + 1].build, not isBuildingFetchCandidatesOnly)
                    -- end
                    -- repair(builderId, candidateId, not isBuildingFetchCandidatesOnly) -- dont think it worked
                    repair(builderId, candidateId, false)
                    WG["ObjectSpotlight"].addSpotlight('unit', 'me', builderId, { 1, 1, 0, 1 }, { duration = 25, radius = 2, heightCoefficient = 5 })
                    -- repair(builderId, candidateId, false) -- shift = false seems to fix issue with builders
                    break
                  end
                end
              end
            end
          end
        end
      end
    end
  end
  reclaimTargetsPrev = reclaimTargets
  reclaimTargets = NewSetList()
end

local function GameFrameModulo()
  local nBuilderUnitIds = builderUnitIds.count
  return math.floor(
    0.5 +
    (nBuilderUnitIds > 200 and Interpolate(nBuilderUnitIds, 201, 300, 40, 90) or
      nBuilderUnitIds > 100 and Interpolate(nBuilderUnitIds, 101, 200, 21, 40) or
      nBuilderUnitIds > 50 and Interpolate(nBuilderUnitIds, 51, 100, 11, 20) or
      nBuilderUnitIds > 15 and Interpolate(nBuilderUnitIds, 15, 50, 2, 15) or
      1)
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
  modulo = math.floor(0.5 + modulo)
  return modulo > 1 and math.random(modulo - 1, modulo + 1) or 1
end

function widget:GameFrame(gameFrame)
  -- Spring.SendLuaRulesMsg(string.format(string.char(137) .. '%i', 55))
  if metalLevel and metalLevel > 0.96 then
    -- log('setting conversion ', metalMakersLevel, string.format(string.char(137) .. '%i', math.min(95, math.floor(metalMakersLevel * 100 + 2))))
    Spring.SendLuaRulesMsg(
      string.format(
        string.char(137) .. '%i',
        math.min(88, math.floor(Spring.GetTeamRulesParam(myTeamId, 'mmLevel') * 100 + 2))
      )
    )
  end

  gameFrameModulo = GameFrameModulo()

  if gameFrame % gameFrameModulo == 0 then
    buildersJitterModulo = BuildersJitterModulo()

    log(
      string.format('gameframe mod %s (%.1fs) builders mod %s (%s/%s) - - - p %.0f e %.0f m %.0f',
        gameFrameModulo,
        gameFrameModulo / 30,
        buildersJitterModulo,
        math.floor(builderUnitIds.count / buildersJitterModulo),
        builderUnitIds.count,
        powerNeed * 100, energyNeed * 100, mMMNeed * 100
      )
    )

    Builders(gameFrame)
  end

  if gameFrame % 100 == 0 then
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

  if gameFrame % 300 == 0 then
    local myUnits = GetTeamUnits(myTeamId)
    for _, unitID in ipairs(myUnits) do
      if not builders[builderUnitIds.hash[unitID]] then
        local unitDefID = GetUnitDefID(unitID)
        local candidateBuilderDef = UnitDefs[unitDefID]

        if candidateBuilderDef.isBuilder and candidateBuilderDef.canAssist and not candidateBuilderDef.isFactory then
          builderUnitIds:Add(unitID)
          builders[builderUnitIds.count] = {
            id = unitID,
            def = candidateBuilderDef,
            defID = unitDefID,
            targetId = nil,
            guards = {},
            previousBuilding = nil,
            lastOrder = 0
          }
        end
      end
    end
  end
end

function widget:KeyPress(key, mods, isRepeat)
  if key == KEYSYMS.L and mods['ctrl'] then
    isUnitLogActive = not isUnitLogActive
    log('isUnitLogActive ' .. tostring(isUnitLogActive))
    return true
  end
end

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
