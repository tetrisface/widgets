function widget:GetInfo()
  return {
    desc    = "Some code from gui_build_costs.lua by Milan Satala and also some from ecostats.lua by Jools, iirc",
    author  = "tetrisface",
    version = "",
    date    = "feb, 2016",
    name    = "cons",
    license = "",
    layer   = -99990,
    enabled = true,
  }
end

local NewSetList = VFS.Include('common/SetList.lua').NewSetList
VFS.Include('luaui/Widgets/helpers.lua')

local GetFeatureHealth                     = Spring.GetFeatureHealth
local GetFeatureResources                  = Spring.GetFeatureResources
local GetFeatureResurrect                  = Spring.GetFeatureResurrect
local GetFeaturesInCylinder                = Spring.GetFeaturesInCylinder
local GetTeamResources                     = Spring.GetTeamResources
local GetTeamUnits                         = Spring.GetTeamUnits
local GetUnitCommands                      = Spring.GetUnitCommands
local GetUnitCurrentCommand                = Spring.GetUnitCurrentCommand
local GetUnitDefID                         = Spring.GetUnitDefID
local GetUnitHealth                        = Spring.GetUnitHealth
local GetUnitIsBuilding                    = Spring.GetUnitIsBuilding
local GetUnitPosition                      = Spring.GetUnitPosition
local GetUnitResources                     = Spring.GetUnitResources
local GetUnitsInCylinder                   = Spring.GetUnitsInCylinder
local GiveOrderToUnit                      = Spring.GiveOrderToUnit
local log                                  = Spring.Echo
local MRandom                              = math.random
local UnitDefs                             = UnitDefs

local abandonedTargetIDs                   = {}
local builders                             = {}
local myTeamId                             = Spring.GetMyTeamID()
local possibleMetalMakersProduction        = 0
local possibleMetalMakersUpkeep            = 0
local regularizedResourceDerivativesMetal  = { true }
local regularizedResourceDerivativesEnergy = { true }
local regMod                               = 1
local releasedMetal                        = 0
local tidalStrength                        = Game.tidal
local totalSavedTime                       = 0
local energyLevel                          = 0.5
local isEnergyLeaking                      = true
local isEnergyStalling                     = false
local isMetalLeaking                       = true
local isMetalStalling                      = false
local isPositiveEnergyDerivative           = false
local isPositiveMetalDerivative            = false
local metalLevel                           = 0.5
local metalMakersLevel                     = 0.5
local positiveMMLevel                      = true
local regularizedNegativeMetal             = false
local regularizedNegativeEnergy            = false
local regularizedPositiveEnergy            = true
local regularizedPositiveMetal             = true
local needPower                            = true
local needEnergy                           = true
local needMM                               = true
local powerNeed                            = 0.5
local energyNeed                           = 0.5
local mMMNeed                              = 0.5
local windMax                              = Game.windMax
local windMin                              = Game.windMin
local mainIterationModuloLimit
local builderUnitIds                       = NewSetList()
local metalMakers                          = NewSetList()
local reclaimTargets                       = NewSetList()
local reclaimTargetsPrev                   = NewSetList()
local ecoBuildDefs                         = NewSetList()
local busyCommands                         = {
  [CMD.GUARD]   = true,
  [CMD.MOVE]    = true,
  [CMD.RECLAIM] = true,
}
local anyBuildWillMStall                   = false
local anyBuildWillEStall                   = false

local function UnitIdDef(unitId)
  return UnitDefs[GetUnitDefID(unitId)]
end

local function MetalMakingEfficiencyDef(unitDef)
  -- if unitDef.customParams.energyconv_capacity and unitDef.customParams.energyconv_efficiency then
  if unitDef.customParams.energyconv_efficiency then
    -- local asdf = { tonumber(unitDef.customParams.energyconv_capacity), tonumber(unitDef.customParams.energyconv_efficiency) }
    return tonumber(unitDef.customParams.energyconv_efficiency)
  else
    return 0
  end
end

local function SetBuilderLastOrder(builderId)
  builders[builderId].lastOrder = Spring.GetGameFrame()
end

local function AllowBuilderOrder(builderId, currentGameFrame, waitGameFrames)
  currentGameFrame = currentGameFrame or Spring.GetGameFrame()
  waitGameFrames = waitGameFrames or 15
  return builders[builderId].lastOrder < currentGameFrame - waitGameFrames
end


local function RegisterUnit(unitID, unitDefID)
  local candidateBuilderDef = UnitDefs[unitDefID]

  if candidateBuilderDef.isBuilder and candidateBuilderDef.canAssist and not candidateBuilderDef.isFactory then
    builderUnitIds:Add(unitID)
    builders[unitID] = {
      id                 = unitID,
      buildSpeed         = candidateBuilderDef.buildSpeed,
      originalBuildSpeed = candidateBuilderDef.buildSpeed,
      def                = candidateBuilderDef,
      defID              = unitDefID,
      targetId           = nil,
      guards             = {},
      previousBuilding   = nil,
      lastOrder          = 0,
    }
  elseif MetalMakingEfficiencyDef(UnitDefs[unitDefID]) > 0 then
    metalMakers:Add(unitID)
  end
end

local function DeregisterUnit(unitID, unitDefID)
  builderUnitIds:Remove(unitID)
  metalMakers:Remove(unitID)
  builders[unitID] = nil
end

local function EnergyMakeDef(_unitDef)
  local totalEOut = _unitDef.energyMake or 0

  totalEOut = totalEOut + -1 * _unitDef.energyUpkeep

  if _unitDef.tidalGenerator > 0 and tidalStrength > 0 then
    local mult = 1 -- DEFAULT
    if _unitDef.customParams then
      mult = _unitDef.customParams.energymultiplier or mult
    end
    totalEOut = totalEOut + (tidalStrength * mult)
  end

  if _unitDef.windGenerator > 0 then
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

  local myUnits = GetTeamUnits(myTeamId)
  for _, unitID in ipairs(myUnits) do
    local unitDefID = GetUnitDefID(unitID)
    RegisterUnit(unitID, unitDefID)
  end

  for unitDefID, unitDef in pairs(UnitDefs) do
    if not unitDef.isFactory
        and (unitDef.isBuilder
          or unitDef.buildSpeed > 0
          or unitDef.extractsMetal > 0
          or MetalMakingEfficiencyDef(unitDef) > 0
          or unitDef.metalMake > 0
          or EnergyMakeDef(unitDef) > 0
        ) then
      ecoBuildDefs:Add(unitDefID)
    end
  end
end

function widget:UnitCreated(unitID, unitDefID, unitTeam)
  if unitTeam == myTeamId then
    RegisterUnit(unitID, unitDefID)
  end
end

function widget:UnitGiven(unitID, unitDefID, unitTeam, oldTeam)
  if unitTeam == myTeamId then
    RegisterUnit(unitID, unitDefID)
  end
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
  if unitTeam == myTeamId then
    DeregisterUnit(unitID, unitDefID)
  end
end

local function Interpolate(value, inMin, inMax, outMin, outMax)
  -- Ensure the value is within the specified range
  -- Calculate the interpolation
  return outMin + ((((value < inMin) and inMin or ((value > inMax) and inMax or value)) - inMin) / (inMax - inMin)) * (outMax - outMin)
end

local function getBuildersBuildSpeed(tempBuilders)
  local totalSpeed = 0

  for _, unitID in pairs(tempBuilders) do
    local targetId = builders[unitID].targetId
    if not targetId or not isAlreadyInTable(targetId, tempBuilders) then
      totalSpeed = totalSpeed + builders[unitID].buildSpeed
    end
  end

  return totalSpeed
end

local function getBuildTimeLeft(targetId, targetDef)
  local _, _, _, _, build = GetUnitHealth(targetId)
  local currentBuildSpeed = 0
  for builderId, _ in pairs(builders) do
    local testTargetId = GetUnitIsBuilding(builderId)
    if testTargetId == targetId and builderId ~= targetId then
      currentBuildSpeed = currentBuildSpeed + builders[builderId].originalBuildSpeed
    end
  end

  if not targetDef then
    targetDef = UnitDefs[GetUnitDefID(targetId)]
  end

  local buildLeft = (1 - build) * targetDef.buildTime

  local time = buildLeft / currentBuildSpeed

  return time
end

local function getUnitsBuildingUnit(unitID)
  local building = {}

  for builderId, _ in pairs(builders) do
    local targetId = GetUnitIsBuilding(builderId)
    if targetId == unitID then
      building[builderId] = builderId
    end
  end
  return building
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

local function reclaimCheckAction(builderId, features, _needMetal, _needEnergy)
  if _needMetal and (_needEnergy or needEnergy) and #features['metalenergy'] > 0 then
    features['metalenergy'] = FeatureSortByHealth(features['metalenergy'])
    reclaim(builderId, Game.maxUnits + features['metalenergy'][1].id)
  elseif _needMetal and #features['metal'] > 0 then
    features['metal'] = FeatureSortByHealth(features['metal'])
    reclaim(builderId, Game.maxUnits + features['metal'][1].id)
  elseif (_needEnergy or needEnergy) and #features['energy'] > 0 then
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
  local cmd
  for i = 1, #cmdQueue do
    cmd = cmdQueue[i]
    local targetId = cmd.params[1]
    if cmd.id == CMD.REPAIR then -- 40
      local health, maxHealth, _, _, targetBuild = GetUnitHealth(targetId)
      if (targetBuild ~= nil and health ~= nil and targetBuild >= 1 and health >= maxHealth) or isBeingReclaimed(targetId) then
        local _, _, cmdTag2 = GetUnitCurrentCommand(builderId, i + 1)
        GiveOrderToUnit(builderId, CMD.REMOVE, { cmd.tag }, { "ctrl" })
        -- GiveOrderToUnit(builderId, CMD.REMOVE, { cmdTag2, cmd.tag }, { "ctrl" })
        if not targetBuild then
          reclaimTargets:Remove(targetId)
          reclaimTargetsPrev:Remove(targetId)
        end
      end
    elseif cmd.id == CMD.RECLAIM then -- 90
      reclaimTargets:Add(targetId)
    end
  end
  return GetUnitCommands(builderId, 3)
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

local function UpdateResources(n)
  local metalCurrent, metalStorage, metalExpenseWanted, metalIncome, metalExpenseActual = GetTeamResources(myTeamId, 'metal')
  local energyCurrent, energyStorage, energyExpenseWanted, energyIncome, energyExpenseActual = GetTeamResources(myTeamId, 'energy')

  regMod = regMod > 11 and 1 or regMod + 1
  regularizedResourceDerivativesMetal[regMod] = metalIncome > metalExpenseActual
  regularizedResourceDerivativesEnergy[regMod] = energyIncome > energyExpenseActual
  regularizedPositiveMetal = table.full_of(regularizedResourceDerivativesMetal, true)
  regularizedPositiveEnergy = table.full_of(regularizedResourceDerivativesEnergy, true)
  regularizedNegativeMetal = table.full_of(regularizedResourceDerivativesMetal, false)
  regularizedNegativeEnergy = table.full_of(regularizedResourceDerivativesEnergy, false)

  -- regularizedPositiveMetal = metalIncome > metalExpenseActual
  -- regularizedPositiveEnergy = energyIncome > energyExpenseActual
  -- regularizedNegativeEnergy = energyIncome < energyExpenseActual

  metalLevel = metalCurrent / metalStorage
  energyLevel = energyCurrent / energyStorage

  metalMakersLevel = Spring.GetTeamRulesParam(myTeamId, 'mmLevel')
  positiveMMLevel = metalMakers.count > 0 and true or false
  -- log('energyLevel - 0.3 < metalMakersLevel', energyLevel - 0.3 < metalMakersLevel)
  -- local mmOn = metalMakers.count / 2
  if energyLevel - 0.3 < metalMakersLevel then
    for i = 1, metalMakers.count do
      local unitId = metalMakers.list[i]
      local health, _, _, _, build = GetUnitHealth(unitId)
      local _, _, _, energy = GetUnitResources(unitId)
      -- mmOn = i
      if health > 0 and build == 1 and energy < tonumber(UnitIdDef(unitId).customParams.energyconv_capacity) then
        positiveMMLevel = false
        break
      end
    end
  end
  -- mmOn = mmOn / metalMakers.count

  isMetalStalling = metalLevel < 0.01 and not regularizedPositiveMetal
  isEnergyStalling = energyLevel < 0.01 and not regularizedPositiveEnergy
  isMetalLeaking = metalLevel > 0.99 and regularizedPositiveMetal
  isEnergyLeaking = energyLevel > 0.99 and regularizedPositiveEnergy

  needPower = (metalLevel > 0.8 or (regularizedPositiveMetal and metalLevel > 0.15)) and (positiveMMLevel or not regularizedNegativeEnergy)
  needEnergy = (not (regularizedPositiveEnergy and isEnergyLeaking and positiveMMLevel)) or isEnergyStalling
  needMM = positiveMMLevel and (not regularizedNegativeEnergy or isEnergyLeaking or isMetalStalling)

  powerNeed = math.max(0, math.min(1,
    (regularizedNegativeMetal and Interpolate((metalExpenseActual - metalIncome) / metalCurrent, 0, 10, 1, 0) or 1) * metalLevel
    -- * (energyIncome / energyExpenseActual)
    * (regularizedNegativeEnergy and Interpolate((energyExpenseActual - energyIncome) / energyCurrent, 0, 10, 1, 0) or 1) * (not needMM and 1 or energyLevel)
  ))
  energyNeed = math.max(0, math.min(1, ((positiveMMLevel or not (regularizedNegativeEnergy and regularizedPositiveEnergy)) and (1 - Interpolate(energyLevel, metalMakersLevel, 1, 0, 1))
    or Interpolate(energyExpenseActual / energyIncome, 2, 1, 0.5, 0.5) * (1 - energyLevel))))
  -- mMMNeed = math.max(0, math.min(1, (needMM and 1 or 0) * Interpolate(energyLevel, metalMakersLevel, 1, 0, 1) * (1 - metalLevel)))
  -- mMMNeed = math.max(0, math.min(1, (positiveMMLevel and 1 or 0) * (regularizedNegativeEnergy and 1 or 0.5) * Interpolate(energyLevel, metalMakersLevel, 1, 0, 1) * (1 - metalLevel)))
  mMMNeed = math.max(0, math.min(1, (positiveMMLevel and 1 or 0) * (energyIncome / energyExpenseActual) * Interpolate(energyLevel, metalMakersLevel, 1, 0, 1) * (1 - metalLevel)))

  -- log('power', 'needMM', needMM, (metalLevel + (not needMM and 1 or energyLevel)) / 2)
  -- log('energy', needEnergy, (not (regularizedPositiveEnergy and isEnergyLeaking and positiveMMLevel)))
  -- log('MM', 'positiveMMLevel', positiveMMLevel, 'regularizedPositiveMetal', 'regularizedNegativeEnergy', regularizedNegativeEnergy, 'isEnergyLeaking', isEnergyLeaking, 'isMetalStalling', isMetalStalling)
end

local function moveOnFromBuilding(builderId, targetId, cmdQueueTag, cmdQueueTagg)
  -- log('moveonfrombuilding', builderId, targetId, cmdQueueTag)
  GiveOrderToUnit(builderId, CMD.REMOVE, { cmdQueueTag }, 0)

  -- if not cmdQueueTagg then
  -- else
  --   GiveOrderToUnit(builderId, CMD.REMOVE, {cmdQueueTag,cmdQueueTagg}, {"ctrl"})
  -- end
  builders[builderId].previousBuilding = targetId
  abandonedTargetIDs[targetId] = true
  -- local x, _, z = GetUnitPosition(targetId, true)
  -- Spring.MarkerAddPoint(x, 0, z)
end




local function getMyResources(type)
  local lvl, storage, pull, inc, exp, share, sent, recieved = GetTeamResources(myTeamId, type)

  if not inc then
    log("ERROR", myTeamId, type)
    return
  end

  local total = recieved
  local exp = 0
  local units = GetTeamUnits(myTeamId)

  if type == "metal" then
    for _, unitID in ipairs(units) do
      local metalMake, metalUse, energyMake, energyUse = GetUnitResources(unitID)
      total = total + metalMake - metalUse
      exp = exp + metalUse
    end
  else
    for _, unitID in ipairs(units) do
      local metalMake, metalUse, energyMake, energyUse = GetUnitResources(unitID)
      total = total + energyMake - energyUse
      exp = exp + energyUse
    end
  end

  local alreadyInStall = pull > exp and lvl < pull

  return total, lvl, storage, exp, alreadyInStall
end

local function buildingWillStallType(type, consumption, secondsLeft, releasedExpenditures)
  local currentChange, lvl, storage, _, alreadyInStall = getMyResources(type)

  local changeWhenBuilding = currentChange - consumption + releasedExpenditures

  if metalMakersControlled and type == "metal" then
    changeWhenBuilding = changeWhenBuilding - releasedMetal
  end

  releasedMetal = 0
  if metalMakersControlled and type == "energy" and possibleMetalMakersUpkeep > 0 then
    local metalMakersUpkeep = getMetalMakersUpkeep()
    if changeWhenBuilding < 0 then
      changeWhenBuilding = changeWhenBuilding + metalMakersUpkeep

      local releasedEnergy = 0
      if changeWhenBuilding > 0 then
        releasedEnergy = changeWhenBuilding
        changeWhenBuilding = 0
      else
        releasedEnergy = metalMakersUpkeep
      end
      releasedMetal = possibleMetalMakersProduction * releasedEnergy / possibleMetalMakersUpkeep
    end
  end

  local after = lvl + secondsLeft * changeWhenBuilding

  if consumption < 1 or (not alreadyInStall and after > 0) then
    return false
  else
    return true
  end
end


local function traceUpkeep(unitID, alreadyCounted)
  if alreadyCounted[unitID] then
    return 0, 0
  end

  local builder = builders[unitID]
  if not builder then
    return 0, 0
  end

  local metalMake, metal, energyMake, energy = GetUnitResources(unitID)

  for _, guardID in ipairs(builder.guards) do
    if builders[guardID].owned then
      local guarderMetal, guarderEnergy = traceUpkeep(guardID, alreadyCounted)
      metal = metal + guarderMetal
      energy = energy + guarderEnergy
    end
  end

  alreadyCounted[unitID] = unitID

  return metal - metalMake + builder.def.metalMake,
      energy - energyMake + builder.def.energyMake
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

local function IsTimeToMoveOn(secondsLeft, builderId, builderDef, totalBuildSpeed)
  local plannerBuildSpeed = builders[builderId].originalBuildSpeed
  local plannerBuildShare = plannerBuildSpeed / totalBuildSpeed
  local slowness = 45 / builderDef.speed
  if ((plannerBuildShare < 0.75 and secondsLeft < 1.2 * slowness) or (plannerBuildShare < 0.5 and secondsLeft < 3.4 * slowness) or (plannerBuildShare < 0.15 and secondsLeft < 8 * slowness) or (plannerBuildShare < 0.05 and secondsLeft < 12 * slowness)) then
    totalSavedTime = totalSavedTime + secondsLeft
    return true
  else
    return false
  end
end

local function TargetWillStall(targetId, targetDef, totalBuildSpeed, secondsLeft)
  if not targetDef then
    targetDef = UnitIdDef(targetId)
  end
  if not totalBuildSpeed then
    totalBuildSpeed = getBuildersBuildSpeed(getUnitsBuildingUnit(targetId))
  end
  if not secondsLeft then
    secondsLeft = getBuildTimeLeft(targetId, targetDef)
  end
  local speed = targetDef.buildTime / totalBuildSpeed
  local metal = targetDef.metalCost / speed
  local energy = targetDef.energyCost / speed

  local mDrain, eDrain = getUnitsUpkeep()
  local mStall = buildingWillStallType("metal", metal, secondsLeft, mDrain)
  local eStall = buildingWillStallType("energy", energy, secondsLeft, eDrain)
  return mStall or eStall, mStall, eStall
end

local function SortMAndMM(a, b)
  return ((a.def.extractsMetal / a.def.cost) > (b.def.extractsMetal / b.def.cost))
      or (MetalMakingEfficiencyDef(a.def) > MetalMakingEfficiencyDef(b.def))
end


local function doFastForwardDecision(builder, targetId, cmdQueueTag, cmdQueueTagg)
  local targetDef = UnitDefs[GetUnitDefID(targetId)]
  local totalBuildSpeed = getBuildersBuildSpeed(getUnitsBuildingUnit(targetId))
  local secondsLeft = getBuildTimeLeft(targetId, targetDef)
  if IsTimeToMoveOn(secondsLeft, builder.id, builder.def, totalBuildSpeed) and not TargetWillStall(targetId, targetDef, totalBuildSpeed, secondsLeft) then
    moveOnFromBuilding(builder.id, targetId, cmdQueueTag, cmdQueueTagg)
  end
end

local function getReclaimableFeatures(x, z, radius)
  local wrecksInRange = GetFeaturesInCylinder(x, z, radius)

  if #wrecksInRange == 0 then
    return false
  end

  local features = {
    ['metalenergy'] = {},
    ['metal'] = {},
    ['energy'] = {},
    ['all'] = {},
  }

  local nME      = 0
  local nM       = 0
  local nE       = 0
  local nAll     = 0
  for i = 1, #wrecksInRange do
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
  return features
end

local function SortFactor(a, b)
  local buildSpeed = a.def.buildSpeed > b.def.buildSpeed and 1 or 0
  -- log('SortFactor', a.def.translatedHumanName, b.def.translatedHumanName)
  -- log('SortFactor p', buildSpeed)
  local energyMakeDefA = EnergyMakeDef(a.def) / a.def.cost
  local energyMakeDefB = EnergyMakeDef(b.def) / b.def.cost
  local energyMakeDef = energyMakeDefA <= 0 and energyMakeDefB <= 0 and 0 or energyMakeDefA > 0 and energyMakeDefB > 0 and Interpolate(energyMakeDefA / energyMakeDefB, 0.2, 2, 0, 1) or energyMakeDefA > 0 and 1 or 0
  -- log('SortFactor e', energyMakeDef, energyMakeDefA, energyMakeDefB)
  local sortMAndMM = SortMAndMM(a, b) and 1 or 0
  -- log('SortFactor m', sortMAndMM)
  -- log('SortFactor comp', powerNeed * buildSpeed
  --   + energyNeed * energyMakeDef
  --   + mMMNeed * sortMAndMM, powerNeed * (1 - buildSpeed)
  --   + energyNeed * (1 - energyMakeDef)
  --   + mMMNeed * (1 - sortMAndMM))
  local result =
      powerNeed * buildSpeed
      + energyNeed * energyMakeDef
      + mMMNeed * sortMAndMM
      >
      powerNeed * (1 - buildSpeed)
      + energyNeed * (1 - energyMakeDef)
      + mMMNeed * (1 - sortMAndMM)
  return result
end

local function SortBuildEcoPrio2(a, b)
  if a == nil or b == nil then
    return false
  end
  -- log('sort defid', (a.defId == b.defId) and (a.build > b.build))
  local result = (
        (a.defId == b.defId) and (a.build > b.build)
      )
      or SortFactor(a, b)
      or (
        not needPower and
        not needEnergy and
        not needMM
        and ((a.def.buildSpeed / a.def.cost) > (b.def.buildSpeed / b.def.cost))
      )
  if a and b then
    -- log('Sort Eco p', powerNeed, 'e', energyNeed, 'm', mMMNeed, result, a.def.translatedHumanName, b.def.translatedHumanName, energyMakeDef(a.def) / a.def.cost, energyMakeDef(b.def) / b.def.cost, a.build, b.build)
    -- log('SortBuildEcoPrio p', math.floor(0.5 + powerNeed * 100), 'e', math.floor(0.5 + energyNeed * 100), 'm', math.floor(0.5 + mMMNeed * 100), result, a.def.translatedHumanName, b.def.translatedHumanName, energyMakeDef(a.def) / a.def.cost, energyMakeDef(b.def) / b.def.cost, a.build, b.build)
    log(string.format('sort %s p %.0f e %.0f m %.0f %s %s', tostring(result), powerNeed * 100, energyNeed * 100, mMMNeed * 100, a.def.translatedHumanName, b.def.translatedHumanName

    -- (
    --   ((a.def.extractsMetal / a.def.cost) / ((b.def.extractsMetal / b.def.cost) or 0.000001))
    --   + (
    --     MetalMakingEfficiencyDef(a.def) / (MetalMakingEfficiencyDef(b.def) or 0.000001)
    --   )
    -- )
    -- ,
    -- (
    --   ((b.def.extractsMetal / b.def.cost) / ((a.def.extractsMetal / a.def.cost) or 0.000001))
    --   + (
    --     MetalMakingEfficiencyDef(b.def) / (MetalMakingEfficiencyDef(a.def) or 0.000001)
    --   )
    -- )
    -- ),
    -- (MetalMakingEfficiencyDef(a.def) / (MetalMakingEfficiencyDef(b.def) or 0.000001)) or 'asdf',
    -- a.def.extractsMetal, a.def.cost, MetalMakingEfficiencyDef(a.def), b.def.extractsMetal, b.def.cost, MetalMakingEfficiencyDef(b.def)
    ))
  end
  return result
end

local every6000MSProb = 1 / (30 * 6) -- 1/(30*6) = 0.005555, every 6th second max
local every2330MSProb = 1 / (30 * 2.33)
local every1333MSProb = 1 / (30 * 1.333)
local every166MSProb = 1 / (30 * 0.1666)
local every66MSProb = 1 / (30 * 0.0666)

local function NBuildersThrottle()
  return MRandom() < (
    builderUnitIds.count > 300 and Interpolate(builderUnitIds.count, 300, 1000, every2330MSProb, every6000MSProb) or
    builderUnitIds.count > 200 and Interpolate(builderUnitIds.count, 200, 300, every2330MSProb, every2330MSProb) or
    builderUnitIds.count > 100 and Interpolate(builderUnitIds.count, 100, 200, every1333MSProb, every2330MSProb) or
    builderUnitIds.count > 60 and Interpolate(builderUnitIds.count, 60, 100, every166MSProb, every1333MSProb) or
    builderUnitIds.count > 10 and Interpolate(builderUnitIds.count, 10, 60, every66MSProb, every166MSProb) or
    1)
  -- builderUnitIds.count > 1000 and ev
end

local function Builders(gameFrame)
  local gotoContinue

  UpdateResources(gameFrame)

  anyBuildWillMStall = false
  anyBuildWillEStall = false
  for i = 1, builderUnitIds.count do
    local builderId = builderUnitIds.list[i]
    local builder = builders[builderId]
    builder.target = { id = GetUnitIsBuilding(builderId) }
    if builder.target.id then
      -- local targetHealth, targetMaxHealth, _, _, targetBuild = GetUnitHealth(builder.target.id)
      -- builder.target.health                                  = targetHealth
      -- builder.target.maxHealth                               = targetMaxHealth
      -- builder.target.build                                   = targetBuild
      -- builder.target.willStall = targetWillStall(builder.target.id)
      local _, mStall, eStall = TargetWillStall(builder.target.id)
      anyBuildWillMStall = anyBuildWillMStall or mStall
      anyBuildWillEStall = anyBuildWillEStall or eStall
    end
  end

  for builderId, builder in pairs(builders) do
    if AllowBuilderOrder(builderId, gameFrame) and NBuildersThrottle() then
      gotoContinue = false
      local builderDef = builder.def
      local cmdQueue = GetUnitCommands(builderId, 3)
      local builderPosX, _, builderPosZ

      -- log('builder ', builderId, builderDef.translatedHumanName, 'cmdQueue', table.tostring(cmdQueue))

      if cmdQueue == nil then
        -- builderNItemMap:Remove(builderNItemMap.hash[builderId]) = nil
        builderUnitIds:Remove(builderId)
        builders[builderId] = nil
        -- log('gotoContinue', 'builder removed')
        gotoContinue = true
      end

      local neighbours = {}
      local nNeighbours = 0
      -- local targetId = GetUnitIsBuilding(builderId)
      -- if GetUnitIsBuilding(builderId) ~= builder.target.id then
      --   log('target match errror', builderId, builder.target.id, GetUnitIsBuilding(builderId))
      -- else
      --   log('target match success', builderId, builder.target.id)
      -- end

      local targetId = builder.target.id

      cmdQueue = purgeRepairs(builderId, cmdQueue)
      local nCmdQueue = #cmdQueue

      -- dont wait if has queued stuff and leaking
      if cmdQueue and nCmdQueue > 0 and (isMetalLeaking or isEnergyLeaking) and cmdQueue[1].id == CMD.WAIT then
        GiveOrderToUnit(builderId, CMD.REMOVE, { nil }, { "ctrl" })
      end

      if nCmdQueue > 0 and busyCommands[cmdQueue and cmdQueue[1] and cmdQueue[1].id] then
        -- log('gotoContinue busycommands', builderId, cmdQueue[1].id)
        gotoContinue = true
      end

      local features = nil

      if not gotoContinue then
        builderPosX, _, builderPosZ = GetUnitPosition(builderId, true)

        if not gotoContinue then
          local neighbourIds          = GetUnitsInCylinder(builderPosX, builderPosZ, builderDef.buildDistance, myTeamId)
          local neighboursDamaged     = {}
          local neighboursUnfinished  = {}
          local nNeighboursUnfinished = 0
          local nNeighboursDamaged    = 0

          local isBuildingEco         = nCmdQueue == 0
              or (cmdQueue[1] and (
                ((cmdQueue[1].id == CMD.REPAIR) and (ecoBuildDefs.hash[GetUnitDefID(cmdQueue[1].params[1])] ~= nil))
                or ((ecoBuildDefs.hash[-cmdQueue[1].id] ~= nil) and GetUnitIsBuilding(builderId) ~= nil)
              ))

          local notHasBuildingQueue   = not (cmdQueue and ((cmdQueue[1] and cmdQueue[1].id < 0) or (cmdQueue[2] and cmdQueue[2].id < 0)))

          --   log(builder.def.translatedHumanName, 'isBuildingEco', isBuildingEco, 'notHasBuildingQueue', notHasBuildingQueue, cmdQueue[1] and cmdQueue[1].id, cmdQueue[2] and cmdQueue[2].id)

          for i = 1, #neighbourIds do
            local candidateId = neighbourIds[i]
            if candidateId ~= builderId then
              local candidateHealth, candidateMaxHealth, _, _, candidateBuild = GetUnitHealth(candidateId)
              local candidateDefId = GetUnitDefID(candidateId)
              local candidate = {
                id = candidateId,
                defId = candidateDefId,
                def = UnitDefs[candidateDefId],
                health = candidateHealth,
                maxHealth = candidateMaxHealth,
                build = candidateBuild,
                healthRatio = candidateHealth / candidateMaxHealth,
              }
              nNeighbours = nNeighbours + 1
              neighbours[nNeighbours] = candidate
              if candidateBuild ~= nil and candidateBuild < 1 and isBuildingEco and notHasBuildingQueue then
                nNeighboursUnfinished = nNeighboursUnfinished + 1
                neighboursUnfinished[nNeighboursUnfinished] = candidate
                -- log('neighboursUnfinished', candidateId, candidateHealth, candidateMaxHealth, candidateBuild, candidate.healthRatio, candidate.def.translatedHumanName, nNeighboursUnfinished)
              elseif not notHasBuildingQueue and candidateHealth and candidateMaxHealth and candidateHealth < candidateMaxHealth then
                nNeighboursDamaged = nNeighboursDamaged + 1
                neighboursDamaged[nNeighboursDamaged] = candidate
                -- log('neighboursDamaged', candidateId, candidateHealth, candidateMaxHealth, candidateBuild, candidate.healthRatio, candidate.def.translatedHumanName, nNeighboursDamaged)
              end
            end
          end
          -- log(builder.def.translatedHumanName, '#neighboursUnfinished', #neighboursUnfinished, nNeighboursUnfinished)
          if #neighboursDamaged > 0 then
            table.sort(neighboursDamaged, SortHealthAsc)
            local damagedTarget = neighboursDamaged[1]
            local damagedTargetId = damagedTarget.id
            local targetHealthRatio
            if targetId then
              local targetHealth, targetMaxHealth = GetUnitHealth(targetId)
              targetHealthRatio = targetHealth / targetMaxHealth

              if targetId ~= damagedTargetId
                  and (not targetHealthRatio or targetHealthRatio == 0 or damagedTarget.healthRatio * 0.95 < targetHealthRatio)
                  and not isBeingReclaimed(damagedTargetId) and AllowBuilderOrder(builderId, gameFrame) then
                targetId = damagedTargetId
                -- log('repair damaged', targetId, 'not isBeingReclaimed(targetId)', not isBeingReclaimed(targetId))
                repair(builderId, targetId, false)
              end
            end
            -- log('gotoContinue', 'neighboursDamaged', 'targetId', targetId, 'damagedTargetId', damagedTargetId, 'targetHealthRatio', targetHealthRatio, 'damagedTarget.healthRatio', damagedTarget.healthRatio)
            gotoContinue = true
            -- log('gotoContinue neighboursDamaged')
          elseif #neighboursUnfinished > 0 then
            -- log('sort', builder.def.translatedHumanName, #neighboursUnfinished, nNeighboursUnfinished)
            -- table.echo(neighboursUnfinished)
            -- for i = 1, #neighboursUnfinished do
            --   if neighboursUnfinished[i] == nil then
            --     log('wtf nil', i)
            --     -- table.echo(neighboursUnfinished[i])
            --   end
            -- end
            -- if not pcall(function()
            --       table.sort(neighboursUnfinished, SortBuildEcoPrio)
            --     end) then
            --   log('sort error', #neighboursUnfinished)
            -- log(#neighboursUnfinished)
            -- table.echo(neighboursUnfinished)
            table.sort(neighboursUnfinished, SortBuildEcoPrio2)
            -- end
            -- log('sorted')
            -- table.tostring2(neighboursUnfinished)
            local candidateId = neighboursUnfinished[1].id
            if targetId ~= candidateId then
              targetId = candidateId
              -- log('repair unfinished', builderId, targetId, neighboursUnfinished[1].def.translatedHumanName)
              -- TODO protect against "move ahead remove build queue"
              repair(builderId, targetId, false)
            end
          end
        end


        if not gotoContinue then
          local _needMetal = metalLevel < 0.15
          local _needEnergy = needEnergy or energyLevel < 0.15
          if (_needMetal or _needEnergy) and not isMetalLeaking and not isEnergyLeaking and builderDef and
              (#builderDef.buildOptions == 0 or #cmdQueue == 0) then
            features = getReclaimableFeatures(builderPosX, builderPosZ, builderDef.buildDistance)
            if features then
              if _needMetal and _needEnergy then
                reclaimCheckAction(builderId, features, true, true)
              elseif _needMetal then
                reclaimCheckAction(builderId, features, true, false)
              else
                reclaimCheckAction(builderId, features, false, true)
              end
              gotoContinue = true
              -- log('gotoContinue reclaimCheckAction can reclaim')
            end
          elseif cmdQueue and #cmdQueue > 0 and cmdQueue[1].id == CMD.RECLAIM and (metalLevel > 0.97 or energyLevel > 0.97 or isMetalLeaking or isEnergyLeaking) then
            -- log('should stop reclaim', builderDef.translatedHumanName)
            features = getReclaimableFeatures(builderPosX, builderPosZ, builderDef.buildDistance)
            local featureId = cmdQueue[1].params[1]
            local metal, _, energy = GetFeatureResources(featureId)

            if metal and metal > 0 and (metalLevel > 0.97 or isMetalLeaking) then
              GiveOrderToUnit(builderId, CMD.REMOVE, { nil }, { "ctrl" })
            elseif energy and energy > 0 and (energyLevel > 0.97 or isEnergyLeaking) then
              GiveOrderToUnit(builderId, CMD.REMOVE, { nil }, { "ctrl" })
            end
          elseif MRandom() < 0.001 then -- every 30 sec?
            features = getReclaimableFeatures(builderPosX, builderPosZ, builderDef.buildDistance)
            if features then
              local featuresAll = FeatureSortByHealth(features.all)
              local feature
              for i = 1, #featuresAll do
                feature = featuresAll[i]
                if feature and feature.health and feature.health < 81 then
                  GiveOrderToUnit(builderId, CMD.INSERT, { 0, CMD.RECLAIM, CMD.OPT_SHIFT, Game.maxUnits + feature.id }, { 'alt' })
                  break
                elseif feature and feature.health and feature.health >= 81 then
                  break
                end
              end
            end
          end
        end
      end

      if not gotoContinue and targetId then
        -- target id recieved
        -- local targetDef = UnitDefs[GetUnitDefID(targetId)]

        -- queue fast forwarder
        if cmdQueue then
          if #cmdQueue > 1 and cmdQueue[1].id < 0 and cmdQueue[2].id < 0 then
            -- next command is build command
            if not abandonedTargetIDs[targetId] then
              -- target has not previously been abandoned
              -- local previousBuilding = builders[builderId].previousBuilding
              -- if not previousBuilding then
              doFastForwardDecision(builder, targetId, cmdQueue[1].tag, cmdQueue[2].tag)
              -- doFastForwardDecision(builder, targetId, cmdQueue[1].tag, cmdQueue[2].tag)
              -- end
            end
          end
        end

        -- 90 == reclaim cmd
        if not gotoContinue and (isMetalStalling or isEnergyStalling) and not (cmdQueue and #cmdQueue > 0 and cmdQueue[1].id == 90) then
          if features == nil then
            features = getReclaimableFeatures(builderPosX, builderPosZ, builderDef.buildDistance)
          end
          if features then
            if isMetalStalling and isEnergyStalling then
              reclaimCheckAction(builderId, features, true, true)
            elseif isMetalStalling and not isEnergyLeaking then
              reclaimCheckAction(builderId, features, true, false)
              -- elseif isEnergyStalling and not isMetalLeaking then
            else
              reclaimCheckAction(builderId, features, false, true)
            end
            gotoContinue = true
            -- log('gotoContinue reclaimCheckAction isstalling')
          end
        end

        -- easy finish neighbour
        -- if not gotoContinue then
        -- refresh for possible target change
        targetId = GetUnitIsBuilding(builderId)
        if targetId then
          local targetDefId = GetUnitDefID(targetId)

          local _, _, _, _, targetBuild = GetUnitHealth(targetId)
          for i = 1, #neighbours do
            local candidate = neighbours[i]
            local candidateId = candidate.id
            -- same type and not actually same building
            if candidateId ~= targetId and candidate.defId == targetDefId then
              local candidateBuild = candidate.build
              if candidateBuild and candidateBuild < 1 and candidateBuild > targetBuild then
                if candidateBuild > targetBuild and AllowBuilderOrder(builderId, gameFrame) then
                  -- log('repair easy finish', UnitIdDef(candidateId).translatedHumanName)
                  repair(builderId, candidateId, true)
                  break
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

function widget:GameFrame(gameFrame)
  mainIterationModuloLimit = 1
  if builderUnitIds.count > 300 then
    mainIterationModuloLimit = 20
  elseif builderUnitIds.count > 200 then
    mainIterationModuloLimit = 10
  elseif builderUnitIds.count > 60 then
    mainIterationModuloLimit = 5
    -- elseif builderUnitIds.count > 10 then
    -- mainIterationModuloLimit = 2
  end

  if n % mainIterationModuloLimit == 0 then
    -- log('iterationmodulo ' .. mainIterationModuloLimit .. ' nBuilders ' .. nBuilders)
    Builders(gameFrame)
  end

  if gameFrame % 100 == 0 then
    for i = 1, #abandonedTargetIDs do
      local k = abandonedTargetIDs[i]
      if k then
        local _, _, _, _, build = GetUnitHealth(k)
        if build == nil or build == 1 then
          table.remove(abandonedTargetIDs, k)
        end
      end
    end
  end
end

function widget:KeyPress(key, mods, isRepeat)
  -- if (key == 114 and mods['ctrl'] and mods['alt']) then
  --   widgetHandler:RemoveWidget()
  --   widgetHandler:
  --   return
  -- end

  if key == 113 and mods['alt'] and mods['ctrl'] then -- 'q'
    table.echo({
      -- needPower = (metalLevel > 0.8 or (regularizedPositiveMetal and metalLevel > 0.15)) and (positiveMMLevel or not regularizedNegativeEnergy)
      -- needEnergy = (not (regularizedPositiveEnergy and isEnergyLeaking and positiveMMLevel)) or isEnergyStalling
      -- needMM = positiveMMLevel and (not regularizedNegativeEnergy or isEnergyLeaking or isMetalStalling)
      needPower = (needPower and 'true' or 'false') .. ' metalLevel ' .. tostring((metalLevel > 0.8) or (regularizedPositiveMetal and metalLevel > 0.15)) .. ' positiveMMLevel ' .. positiveMMLevel .. ' not regularizedNegativeEnergy ' .. (not regularizedNegativeEnergy),
      needEnergy = (needEnergy and 'true' or 'false') .. ' not (regularizedPositiveEnergy ' .. (not regularizedPositiveEnergy) .. ' and isEnergyLeaking ' .. (not isEnergyLeaking) .. ' and positiveMMLevel ' .. (not positiveMMLevel) .. ') or isEnergyStalling ' .. (isEnergyStalling and 'true' or 'false'),
      needMM = (needMM and 'true' or 'false') .. 'positiveMMLevel ' .. positiveMMLevel .. ' '
    })
    return true
  end
end
