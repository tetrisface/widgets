function widget:GetInfo()
  return {
    desc    = "Lots of code from gui_build_costs.lua by Milan Satala and also some from ecostats.lua by Jools, iirc",
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
local regularizedNegativeEnergy            = false
local regularizedPositiveEnergy            = true
local regularizedPositiveMetal             = true
local windMax                              = Game.windMax
local windMin                              = Game.windMin
local mainIterationModuloLimit
local builderUnitIds                       = NewSetList()
local metalMakers                          = NewSetList()
local reclaimTargets                       = NewSetList()
local reclaimTargetsPrev                   = NewSetList()
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
      previousBuilding   = nil
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

function widget:Initialize()
  if Spring.GetSpectatingState() or Spring.IsReplay() then
    widgetHandler:RemoveWidget()
  end

  local myUnits = GetTeamUnits(myTeamId)
  for _, unitID in ipairs(myUnits) do
    local unitDefID = GetUnitDefID(unitID)
    RegisterUnit(unitID, unitDefID)
  end

  font = WG['fonts'].getFont("fonts/" .. Spring.GetConfigString("bar_font2", "Exo2-SemiBold.otf"))
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
  return a.health + a.maxHealth / 30 < b.health - b.maxHealth / 30
end

local function FeatureSortByHealth(features)
  local feature
  for i = 1, #features do
    feature = features[i]
    feature.health = GetFeatureHealth(feature.id)
  end
  table.sort(features, SortHealthAsc)
  return features
end

local function reclaimCheckAction(builderId, features, needMetal, needEnergy)
  if needMetal and needEnergy and #features['metalenergy'] > 0 then
    features['metalenergy'] = FeatureSortByHealth(features['metalenergy'])
    GiveOrderToUnit(builderId, CMD.INSERT,
      { 0, CMD.RECLAIM, CMD.OPT_SHIFT, Game.maxUnits + features['metalenergy'][1].id },
      { 'alt' })
  elseif needMetal and #features['metal'] > 0 then
    features['metal'] = FeatureSortByHealth(features['metal'])
    GiveOrderToUnit(builderId, CMD.INSERT,
      { 0, CMD.RECLAIM, CMD.OPT_SHIFT, Game.maxUnits + features['metal'][1].id },
      { 'alt' })
  elseif needEnergy and #features['energy'] > 0 then
    features['energy'] = FeatureSortByHealth(features['energy'])
    GiveOrderToUnit(builderId, CMD.INSERT,
      { 0, CMD.RECLAIM, CMD.OPT_SHIFT, Game.maxUnits + features['energy'][1].id },
      { 'alt' })
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
        GiveOrderToUnit(builderId, CMD.REMOVE, { cmdTag2, cmd.tag }, { "ctrl" })
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
  log('repairing', builderId, targetId, alt, Spring.GetGameFrame())
  if shift then
    GiveOrderToUnit(builderId, CMD.INSERT, { 0, CMD.REPAIR, CMD.OPT_CTRL, targetId }, { 'shift' })
  else
    GiveOrderToUnit(builderId, CMD.INSERT, { 0, CMD.REPAIR, CMD.OPT_CTRL, targetId }, { 'alt' })
  end
end

local function UpdateResources(n)
  regMod = regMod > 11 and 1 or regMod + 1
  regularizedResourceDerivativesMetal[regMod] = isPositiveMetalDerivative
  regularizedResourceDerivativesEnergy[regMod] = isPositiveEnergyDerivative
  regularizedPositiveMetal = table.full_of(regularizedResourceDerivativesMetal, true)
  regularizedPositiveEnergy = table.full_of(regularizedResourceDerivativesEnergy, true)
  regularizedNegativeEnergy = table.full_of(regularizedResourceDerivativesEnergy, false)

  local m_curr, metalStorage, m_pull, m_inc, m_exp = GetTeamResources(myTeamId, 'metal')
  local e_curr, energyStorage, e_pull, e_inc, e_exp = GetTeamResources(myTeamId, 'energy')

  isPositiveMetalDerivative = m_inc > (m_pull + m_exp) / 2
  metalLevel = m_curr / metalStorage

  isPositiveEnergyDerivative = e_inc > (e_pull + e_exp) / 2
  energyLevel = e_curr / energyStorage

  metalMakersLevel = Spring.GetTeamRulesParam(myTeamId, 'mmLevel')
  positiveMMLevel = true
  log('energyLevel - 0.3 < metalMakersLevel', energyLevel - 0.3 < metalMakersLevel)
  if energyLevel - 0.3 < metalMakersLevel then
    for i = 1, metalMakers.count do
      local unitId = metalMakers.list[i]
      local health, _, _, _, build = GetUnitHealth(unitId)
      local _, _, _, energy = GetUnitResources(unitId)
      if health > 0 and build == 1 and energy < tonumber(UnitIdDef(unitId).customParams.energyconv_capacity) then
        positiveMMLevel = false
        break
      end
    end
  end

  isMetalStalling = metalLevel < 0.01 and not regularizedPositiveMetal
  isEnergyStalling = energyLevel < 0.01 and not regularizedPositiveEnergy
  isMetalLeaking = metalLevel > 0.99 and regularizedPositiveMetal
  isEnergyLeaking = energyLevel > 0.99 and isPositiveEnergyDerivative
end

local function getEout(_unitDef)
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

-- todo
-- local function getTraveltime(unitDef, A, B)
--   selectedUnits = GetSelectedUnits()
--   local totalBuildSpeed = getBuildersBuildSpeed(getUnitsBuildingUnit(targetId))
--   local secondsLeft = getBuildTimeLeft(targetId)
--   local unitDef = UnitDefs[GetUnitDefID(targetId)]
--   if isTimeToMoveOn(secondsLeft, builderId, unitDef, totalBuildSpeed) and not targetWillStall(targetId, unitDef, totalBuildSpeed, secondsLeft) then
--     moveOnFromBuilding(builderId, targetId, cmdQueueTag, cmdQueueTagg)
--   end
-- end

local function getUnitResourceProperties(_unitDef)
  local metalMakingEfficiency = MetalMakingEfficiencyDef(_unitDef)
  if metalMakingEfficiency == nil then
    metalMakingEfficiency = 0
  end
  local energyMaking = getEout(_unitDef)
  return metalMakingEfficiency, energyMaking
end

local function moveOnFromBuilding(builderId, targetId, cmdQueueTag, cmdQueueTagg)
  GiveOrderToUnit(builderId, CMD.REMOVE, { cmdQueueTag }, { "ctrl" })

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

local function sortBuildPower(a, b)
  local aWillStall = TargetWillStall(a.id)
  local bWillStall = TargetWillStall(b.id)
  if aWillStall and bWillStall then
    return a.def.power < b.def.power
  elseif aWillStall and not bWillStall then
    return false
  elseif not aWillStall and bWillStall then
    return true
  else
    return a.def.buildSpeed * (1 / getBuildTimeLeft(a.id)) * (1 / a.def.power) >
        b.def.buildSpeed * (1 / getBuildTimeLeft(b.id)) * (1 / b.def.power)
        or a.build > b.build
  end
end

local function sortEnergy(a, b)
  local aWillStall = TargetWillStall(a.id)
  local bWillStall = TargetWillStall(b.id)
  if aWillStall and bWillStall then
    return a.def.energyMake * (1 / getBuildTimeLeft(a.id) * a.def.power) >
        b.def.energyMake * (1 / getBuildTimeLeft(b.id) * b.def.power)
  elseif aWillStall and not bWillStall then
    return false
  elseif not aWillStall and bWillStall then
    return true
  else
    return a.def.energyMake * a.def.power > b.def.energyMake * b.def.power
        or a.build > b.build
  end
end

local function sortMAndMMAndBuild(a, b)
  return (a.def.extractsMetal > b.def.extractsMetal)
      or (MetalMakingEfficiencyDef(a.def) > MetalMakingEfficiencyDef(b.def))
      or (a.build > b.build)
end

local function sortMAndMM(a, b)
  return (a.def.extractsMetal > b.def.extractsMetal)
      or (MetalMakingEfficiencyDef(a.def) > MetalMakingEfficiencyDef(b.def))
end

local function getBestCandidate(candidatesOriginal, assistType)
  if #candidatesOriginal == 0 or assistType == 'metal' then
    return false
  end
  local candidates = {}
  local nCandidates = 0

  for i = 1, #candidatesOriginal do
    local candidateOriginal = candidatesOriginal[i]
    local candidateId = candidateOriginal.id
    -- local candidateDefId = GetUnitDefID(candidateId)
    -- local candidateDefId = GetUnitDefID(candidateId)
    local candidateDef = candidateOriginal.def
    local MMEff = MetalMakingEfficiencyDef(candidateDef)
    local M = candidateDef.extractsMetal or 0
    if
        (assistType == 'buildPower' and candidateDef.buildSpeed > 0) or
        (assistType == 'energy' and (candidateDef.energyMake > 0)) or
        (assistType == 'mm' and (MMEff > 0 or M > 0)) then
      nCandidates = nCandidates + 1
      candidates[nCandidates] = candidateOriginal
    end
  end

  if #candidates == 1 then
    return candidates[1]
  elseif #candidates == 0 then
    return false
  end
  log('candidates', table.tostring(candidates))
  if assistType == 'buildPower' then
    table.sort(candidates, sortBuildPower)
  elseif assistType == 'energy' then
    table.sort(candidates, sortEnergy)
  elseif assistType == 'mm' then
    table.sort(candidates, sortMAndMMAndBuild)
  end
  return candidates[1]
end

local function builderForceAssist(assistType, builderId, targetId, neighbours)
  local bestCandidate = getBestCandidate(neighbours, assistType)

  if bestCandidate and targetId ~= bestCandidate.id then
    log('forceassisting', assistType, bestCandidate.def.translatedHumanName)
    -- repair(builderId, bestCandidate.id)
    return true
  end
  return false
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

local function SortBuildEcoPrio(a, b)
  local nilDesc = (a == nil and 0 or 1) > (b == nil and 0 or 1)
  if anyBuildWillMStall and anyBuildWillEStall then
    -- log('sortbuildecoprio anyBuildWillMStall and anyBuildWillEStall', a, b)
    return nilDesc
        or a.build > b.build
        or a.def.power > b.def.power
  elseif not anyBuildWillMStall and anyBuildWillEStall then
    -- log('sortbuildecoprio not anyBuildWillMStall and anyBuildWillEStall', a, b)
    return nilDesc
        or a.def.energyMake > b.def.energyMake
        or a.build > b.build
        or a.def.power > b.def.power
  elseif anyBuildWillMStall and not anyBuildWillEStall then
    -- log('sortbuildecoprio anyBuildWillMStall and not anyBuildWillEStall', a, b)
    return nilDesc
        or sortMAndMMAndBuild(a, b)
2  end
  -- log('sortbuildecoprio default', a, b)
  -- log('  conds',
  --   ((metalLevel > 0.8 or (regularizedPositiveMetal and metalLevel > 0.15)) and (positiveMMLevel or not regularizedNegativeEnergy)),
  --   (not regularizedPositiveEnergy and not isEnergyLeaking and not positiveMMLevel),
  --   (positiveMMLevel and (not regularizedNegativeEnergy or isEnergyLeaking or isMetalStalling)),
  --   ' --- ', tostring(not regularizedPositiveEnergy), tostring(not isEnergyLeaking), tostring(not positiveMMLevel)
  -- )
  local _return = nilDesc
      or (
        (a.defId == b.defId) and a.build > b.build
      )
      or (
      -- sort by buildpower
        ((metalLevel > 0.8 or (regularizedPositiveMetal and metalLevel > 0.15)) and (positiveMMLevel or not regularizedNegativeEnergy))
        and (a.def.buildSpeed > b.def.buildSpeed)
      )
      -- or (function(_a, _b)
      --   log('  no sort build power', _a.def.translatedHumanName, _b.def.translatedHumanName, _a.def.buildSpeed, _b.def.buildSpeed)
      --   return false
      -- end)(a, b)
      or (
      -- failed sorting build power, try energy
        (not regularizedPositiveEnergy and not isEnergyLeaking and not positiveMMLevel) and (a.def.energyMake > b.def.energyMake)
      )
      -- or (function(_a, _b)
      --   log('  no sort energy, try metal', _a.def.translatedHumanName, _b.def.translatedHumanName)
      --   return false
      -- end)(a, b)
      or (
      -- failed sorting energy, try metal
        (positiveMMLevel and (not regularizedNegativeEnergy or isEnergyLeaking or isMetalStalling)) and sortMAndMM(a, b) or false
      )
      -- or (function(_a, _b)
      --   log('  no sort bp, e and m', _a.def.translatedHumanName, _b.def.translatedHumanName)
      --   return false
      -- end)(a, b)
      or (
        not (metalLevel > 0.8 or (regularizedPositiveMetal and metalLevel > 0.15)) and (positiveMMLevel or not regularizedNegativeEnergy) and
        not (not regularizedPositiveEnergy and not isEnergyLeaking and not positiveMMLevel) and
        not (positiveMMLevel and (not regularizedNegativeEnergy or isEnergyLeaking or isMetalStalling))
        and a.def.energyMake > b.def.energyMake
      )
  if a and b then
    log('  Sort Eco', _return, a.def.translatedHumanName, b.def.translatedHumanName, a.def.energyMake, b.def.energyMake, a.build, b.build)
  end
  return _return
  -- or a.build > b.build
  -- or a.def.power > b.def.power
end

local function BuilderIteration(n)
  local gotoContinue

  UpdateResources(n)

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
    -- if builderId == 1707 then
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
    local neighboursDamaged = {}
    local neighboursUnfinished = {}
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
        local neighbourIds = GetUnitsInCylinder(builderPosX, builderPosZ, builderDef.buildDistance, myTeamId)

        for i = 1, #neighbourIds do
          local candidateId = neighbourIds[i]
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
          neighbours[i] = candidate
          if candidateBuild ~= nil and candidateBuild < 1 then
            neighboursUnfinished[#neighboursUnfinished + 1] = candidate
            -- log('neighboursUnfinished', candidateId, candidateHealth, candidateMaxHealth, candidateBuild, candidate.healthRatio)
          elseif not (cmdQueue and ((cmdQueue[1] and cmdQueue[1].id < 0) or (cmdQueue[2] and cmdQueue[2].id < 0))) and candidateHealth and candidateMaxHealth and candidateHealth < candidateMaxHealth then
            neighboursDamaged[#neighboursDamaged + 1] = candidate
            -- log('neighboursDamaged', candidateId, candidateHealth, candidateMaxHealth, candidateBuild, candidate.healthRatio)
          end
        end

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
                and not isBeingReclaimed(damagedTargetId) then
              targetId = damagedTargetId
              -- log('repair damaged', targetId, 'not isBeingReclaimed(targetId)', not isBeingReclaimed(targetId))
              repair(builderId, targetId, true)
            end
          end
          -- log('gotoContinue', 'neighboursDamaged', 'targetId', targetId, 'damagedTargetId', damagedTargetId, 'targetHealthRatio', targetHealthRatio, 'damagedTarget.healthRatio', damagedTarget.healthRatio)
          gotoContinue = true
          -- log('gotoContinue neighboursDamaged')
        elseif #neighboursUnfinished > 0 and nCmdQueue == 0 then
          table.sort(neighboursUnfinished, SortBuildEcoPrio)
          local candidateId = neighboursUnfinished[1].id
          if targetId ~= candidateId then
            targetId = candidateId
            -- log('repair unfinished', UnitIdDef(targetId).translatedHumanName)
            repair(builderId, targetId, true)
          end
        end
      end


      if not gotoContinue then
        local needMetal = metalLevel < 0.15
        local needEnergy = energyLevel < 0.15
        if (needMetal or needEnergy) and not isMetalLeaking and not isEnergyLeaking and builderDef and
            (#builderDef.buildOptions == 0 or #cmdQueue == 0) then
          features = getReclaimableFeatures(builderPosX, builderPosZ, builderDef.buildDistance)
          if features then
            if needMetal and needEnergy then
              reclaimCheckAction(builderId, features, true, true)
            elseif needMetal then
              reclaimCheckAction(builderId, features, true, false)
            else
              reclaimCheckAction(builderId, features, false, true)
            end
            gotoContinue = true
            -- log('gotoContinue reclaimCheckAction can reclaim')
          end
        elseif cmdQueue and #cmdQueue > 0 and cmdQueue[1].id == 90 and (metalLevel > 0.97 or energyLevel > 0.97 or isMetalLeaking or isEnergyLeaking) then
          features = getReclaimableFeatures(builderPosX, builderPosZ, builderDef.buildDistance)
          local featureId = cmdQueue[1].params[1]
          local metal, _, energy = GetFeatureResources(featureId)

          if metal and metal > 0 and (metalLevel > 0.97 or isMetalLeaking) then
            GiveOrderToUnit(builderId, CMD.REMOVE, { nil }, { "ctrl" })
          elseif energy and energy > 0 and (energyLevel > 0.97 or isEnergyLeaking) then
            GiveOrderToUnit(builderId, CMD.REMOVE, { nil }, { "ctrl" })
          end
        elseif math.random() < 0.2 then
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
      local targetDef = UnitDefs[GetUnitDefID(targetId)]

      -- queue fast forwarder
      if cmdQueue then
        if #cmdQueue > 2 and cmdQueue[3].id < 0 then
          -- next command is build command
          if not abandonedTargetIDs[targetId] then
            -- target has not previously been abandoned
            local previousBuilding = builders[builderId].previousBuilding
            if not previousBuilding then
              doFastForwardDecision(builder, targetId, cmdQueue[1].tag, cmdQueue[2].tag)
            else
              local _, _, _, _, prevBuild = GetUnitHealth(previousBuilding)
              if prevBuild == nil or prevBuild == 1 then
                -- previous building is gone/done
                doFastForwardDecision(builder, targetId, cmdQueue[1].tag, cmdQueue[2].tag)
              end
            end
          end
        end
      end

      -- refresh for possible target change
      builder.target.id = GetUnitIsBuilding(builderId)
      targetId = builder.target.id
      local targetUnitMM = 0
      local targetUnitE = 0
      if targetId then
        targetDef = UnitDefs[GetUnitDefID(targetId)]
        targetUnitMM, targetUnitE = getUnitResourceProperties(targetDef)
      else
        targetDef = nil
      end

      -- mm/e switcher

      --  log('targetUnitE > 0, positiveMMLevel, regpose or eleak #### ' .. tostring(targetUnitE > 0) .. ', ' .. tostring(positiveMMLevel) .. ', ' .. tostring((regularizedPositiveEnergy or isEnergyLeaking) ))
      --  if targetUnitE > 0 then
      --    log(isEnergyLeaking)
      --    log('positiveMMLevel, not regnege or eleak === ' .. tostring(positiveMMLevel) .. ', ' .. tostring((regularizedPositiveEnergy or isEnergyLeaking) ))
      --  end
      -- log(
      --   builderDef.translatedHumanName .. ' targetId ' .. targetId .. ' #candidateNeighbours ' .. #candidateNeighbours
      -- )
      -- if n % (mainIterationModuloLimit * 3) == 0 and #candidateNeighbours > 1 then
      if not gotoContinue and #neighboursUnfinished > 1 then
        -- log(
        --   'metalLevel ' .. metalLevel ..
        --   ' regularizedPositiveMetal ' .. tostring(regularizedPositiveMetal) ..
        --   ' positiveMMLevel ' .. tostring(positiveMMLevel) ..
        --   ' not regularizedNegativeEnergy ' .. tostring(not regularizedNegativeEnergy) ..
        --   ' not regularizedPositiveEnergy ' .. tostring(not regularizedPositiveEnergy) ..
        --   ' not isEnergyLeaking ' .. tostring(not isEnergyLeaking) ..
        --   ' targetUnitMM > 0 ' .. tostring(targetUnitMM > 0) ..
        --   ' targetUnitE > 0 ' .. tostring(targetUnitE > 0) ..
        --   ' isMetalStalling ' .. tostring(isMetalStalling) ..
        --   ' targetDef.buildSpeed ' .. tostring(targetDef and targetDef.buildSpeed or nil)
        -- )

        local shouldAssisstPower = (metalLevel > 0.8 or (regularizedPositiveMetal and metalLevel > 0.15)) and (positiveMMLevel or not regularizedNegativeEnergy)
        local foundPowerCandidate = false
        if (shouldAssisstPower) then
          -- log('ForceAssist buildPower target ' .. builderDef.translatedHumanName) -- .. (targetId or '-') .. ' ' .. (targetDef and targetDef.translatedHumanName or '-') .. ' regularizedPositiveMetal ' .. tostring(regularizedPositiveMetal) .. ' metalLevel ' .. metalLevel)
          foundPowerCandidate = builderForceAssist('buildPower', builderId, targetId, neighboursUnfinished)
        end
        if (not shouldAssisstPower or not foundPowerCandidate)
            and not regularizedPositiveEnergy and not isEnergyLeaking
            and ((targetUnitMM > 0 and not positiveMMLevel) or (targetUnitE <= 0 and isEnergyStalling)) then
          log('ForceAssist energy target ' .. builderDef.translatedHumanName) -- .. (targetId or '-') .. ' ' .. (targetDef and targetDef.translatedHumanName or '-'))
          builderForceAssist('energy', builderId, targetId, neighboursUnfinished)
        elseif positiveMMLevel and (((not regularizedNegativeEnergy or isEnergyLeaking) and targetUnitE > 0)
              or (isMetalStalling and (targetDef and targetDef.buildSpeed > 0 or true))) then
          log('ForceAssist mm target ' .. builderDef.translatedHumanName) -- .. (targetId or '-') .. ' ' .. (targetDef and targetDef.translatedHumanName or '-'))
          builderForceAssist('mm', builderId, targetId, neighboursUnfinished)
        else
          log('no eco force hit sort', positiveMMLevel, isEnergyLeaking, not regularizedPositiveEnergy, not regularizedNegativeEnergy)
          table.sort(neighboursUnfinished, SortBuildEcoPrio)
          local candidateId = neighboursUnfinished[1].id
          if targetId ~= candidateId then
            targetId = candidateId
            repair(builderId, targetId)
            log('sort assist', UnitIdDef(targetId).translatedHumanName)
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
              if candidateBuild > targetBuild then
                repair(builderId, candidateId, false)
                break
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

function widget:GameFrame(n)
  mainIterationModuloLimit = 1
  if builderUnitIds.count > 300 then
    mainIterationModuloLimit = 70
  elseif builderUnitIds.count > 200 then
    mainIterationModuloLimit = 20
  elseif builderUnitIds.count > 60 then
    mainIterationModuloLimit = 5
  elseif builderUnitIds.count > 10 then
    mainIterationModuloLimit = 2
  end

  if n % mainIterationModuloLimit == 0 then
    -- log('iterationmodulo ' .. mainIterationModuloLimit .. ' nBuilders ' .. nBuilders)
    BuilderIteration(n)
  end

  if n % 100 == 0 then
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
