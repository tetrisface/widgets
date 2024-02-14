function widget:GetInfo()
  return {
    desc    = "Lots of code from gui_build_costs.lua by Milan Satala and also some from ecostats.lua by Jools, iirc",
    author  = "-",
    version = "",
    date    = "feb, 2016",
    name    = "cons widget",
    license = "",
    layer   = -99990,
    enabled = true,
  }
end

local NewSetList = VFS.Include('common/SetList.lua').NewSetList
VFS.Include('luaui/Widgets/helpers.lua')

local GetFeatureResources = Spring.GetFeatureResources
local GetFeatureResurrect = Spring.GetFeatureResurrect
local GetFeaturesInCylinder = Spring.GetFeaturesInCylinder
local GetTeamResources = Spring.GetTeamResources
local GetTeamRulesParam = Spring.GetTeamRulesParam
local GetTeamUnits = Spring.GetTeamUnits
local GetUnitCommands = Spring.GetUnitCommands
local GetUnitDefID = Spring.GetUnitDefID
local GetUnitHealth = Spring.GetUnitHealth
local GetUnitIsBuilding = Spring.GetUnitIsBuilding
local GetUnitPosition = Spring.GetUnitPosition
local GetUnitResources = Spring.GetUnitResources
local GetUnitsInCylinder = Spring.GetUnitsInCylinder
local GiveOrderToUnit = Spring.GiveOrderToUnit
local log = Spring.Echo
local UnitDefs = UnitDefs

local abandonedTargetIDs = {}
local builders = {}
local myTeamId = Spring.GetMyTeamID()
local possibleMetalMakersProduction = 0
local possibleMetalMakersUpkeep = 0
local regularizedResourceDerivativesEnergy = { true, true, true, true, true, true, true, true, true, true, true }
local regularizedResourceDerivativesMetal = { true, true, true, true, true, true, true, true, true, true, true }
local releasedMetal = 0
local tidalStrength = Game.tidal
local totalSavedTime = 0

local energyLevel = 0.5
local isEnergyLeaking = true
local isEnergyStalling = false
local isMetalLeaking = true
local isMetalStalling = false
local isPositiveEnergyDerivative = false
local isPositiveMetalDerivative = false
local metalLevel = 0.5
local metalMakersLevel = 0.5
local positiveMMLevel = true
local regularizedNegativeEnergy = false
local regularizedPositiveEnergy = true
local regularizedPositiveMetal = true
local windMax = Game.windMax
local windMin = Game.windMin
local mainIterationModuloLimit
local nBuilders = 0
local isReclaimTarget = NewSetList()
local isReclaimTargetPrev = NewSetList()

local function unitDef(unitId)
  return UnitDefs[GetUnitDefID(unitId)]
end

local function registerUnit(unitID, unitDefID)
  if not unitDefID then
    return
  end

  local candidateBuilderDef = UnitDefs[unitDefID]

  if candidateBuilderDef.isBuilder and candidateBuilderDef.canAssist and not candidateBuilderDef.isFactory then
    builders[unitID] = {
      id = unitID,
      buildSpeed = candidateBuilderDef.buildSpeed,
      originalBuildSpeed = candidateBuilderDef.buildSpeed,
      def = candidateBuilderDef,
      defID = unitDefID,
      targetId = nil,
      guards = {},
      previousBuilding = nil
    }
    nBuilders = nBuilders + 1
  end
end


function widget:Initialize()
  if Spring.GetSpectatingState() or Spring.IsReplay() then
    widgetHandler:RemoveWidget()
  end

  local myUnits = GetTeamUnits(myTeamId)
  for _, unitID in ipairs(myUnits) do
    local unitDefID = GetUnitDefID(unitID)
    registerUnit(unitID, unitDefID, teamID)
  end

  font = WG['fonts'].getFont("fonts/" .. Spring.GetConfigString("bar_font2", "Exo2-SemiBold.otf"))
end

function widget:UnitCreated(unitID, unitDefID, unitTeam)
  registerUnit(unitID, unitDefID)
end

function widget:UnitGiven(unitID, unitDefID, unitTeam, oldTeam)
  if unitTeam == myTeamId then
    registerUnit(unitID, unitDefID)
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



local function reclaimCheckAction(builderId, features, needMetal, needEnergy)
  if needMetal and needEnergy and #features['metalenergy'] > 0 then
    GiveOrderToUnit(builderId, CMD.INSERT,
      { 0, CMD.RECLAIM, CMD.OPT_SHIFT, Game.maxUnits + features['metalenergy'][1] },
      { 'alt' })
  elseif needMetal and #features['metal'] > 0 then
    GiveOrderToUnit(builderId, CMD.INSERT,
      { 0, CMD.RECLAIM, CMD.OPT_SHIFT, Game.maxUnits + features['metal'][1] },
      { 'alt' })
  elseif needEnergy and #features['energy'] > 0 then
    GiveOrderToUnit(builderId, CMD.INSERT,
      { 0, CMD.RECLAIM, CMD.OPT_SHIFT, Game.maxUnits + features['energy'][1] },
      { 'alt' })
  end
end

local function purgeCompleteRepairs(builderId, cmdQueue)
  -- local shitFound = true
  -- local safetyStop = 400
  -- while shitFound do
  -- shitFound = false
  -- for _, cmd in ipairs(cmdQueue) do
  for i = 1, #cmdQueue do
    local cmd = cmdQueue[i]
    local targetId = cmd.params[1]
    if cmd.id == 40 then
      local _, _, _, _, targetBuild = GetUnitHealth(targetId)
      if not targetBuild or targetBuild == 1 then
        -- shitFound = true
        GiveOrderToUnit(builderId, CMD.REMOVE, { cmd.tag }, { "ctrl" })
        isReclaimTarget:Remove(targetId)
        isReclaimTargetPrev:Remove(targetId)
      end
    elseif cmd.id == 90 then
      isReclaimTarget:Add(targetId)
    end
  end
  cmdQueue = GetUnitCommands(builderId, 3)
  -- if shitFound then
  -- end
  -- if safetyStop <= 0 then
  --   break
  -- end
  -- safetyStop = safetyStop - 1
  -- end
  return cmdQueue
end



local function repair(builderId, targetId)
  GiveOrderToUnit(builderId, CMD.INSERT, { 0, CMD.REPAIR, CMD.OPT_CTRL, targetId }, { "alt" })
end



-- local function deepcopy(orig)
--   local orig_type = type(orig)
--   local copy
--   if orig_type == 'table' then
--     copy = {}
--     for orig_key, orig_value in next, orig, nil do
--       copy[deepcopy(orig_key)] = deepcopy(orig_value)
--     end
--     setmetatable(copy, deepcopy(getmetatable(orig)))
--   else -- number, string, boolean, etc
--     copy = orig
--   end
--   return copy
-- end

local function updateFastResourceStatus()
  metalMakersLevel = GetTeamRulesParam(myTeamId, 'mmLevel')
  local m_curr, m_max, m_pull, m_inc, m_exp = GetTeamResources(myTeamId, 'metal')
  local e_curr, e_max, e_pull, e_inc, e_exp = GetTeamResources(myTeamId, 'energy')

  isPositiveMetalDerivative = m_inc > (m_pull + m_exp) / 2
  metalLevel = m_curr / m_max

  isPositiveEnergyDerivative = e_inc > (e_pull + e_exp) / 2
  energyLevel = e_curr / e_max

  if energyLevel > metalMakersLevel then
    positiveMMLevel = true
  else
    positiveMMLevel = false
  end

  isMetalStalling = metalLevel < 0.01 and not regularizedPositiveMetal
  isEnergyStalling = energyLevel < 0.01 and not regularizedPositiveEnergy
  isMetalLeaking = metalLevel > 0.99 and regularizedPositiveMetal
  isEnergyLeaking = energyLevel > 0.99 and isPositiveEnergyDerivative
end



local function getMetalMakingEfficiencyDef(unitDef)
  -- if unitDef.customParams.energyconv_capacity and unitDef.customParams.energyconv_efficiency then
  if unitDef.customParams.energyconv_efficiency then
    -- local asdf = { tonumber(unitDef.customParams.energyconv_capacity), tonumber(unitDef.customParams.energyconv_efficiency) }
    return tonumber(unitDef.customParams.energyconv_efficiency)
  else
    return 0
  end

  -- local makerDef = WG.energyConversion.convertCapacities[unitDefID]
  -- local makerDef = WG.converter_usage.convertCapacities[unitDefID]
  -- if makerDef ~= nil then
  --   return makerDef.e
  -- else
  --   return 0
  -- end
end

local function getMetalMakingEfficiency(unitDefID)
  return getMetalMakingEfficiencyDef(UnitDefs[unitDefID])
end
local function sortHeuristicallyMorMM(a, b)
  --  log('compare ' .. a[3].humanName .. ' '.. getMetalMakingEfficiency(a[2]))
  return (a.def.extractsMetal > b.def.extractsMetal)
      or getMetalMakingEfficiency(a[2]) > getMetalMakingEfficiency(b[2])
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

local function getUnitResourceProperties(unitDefID, _unitDef)
  local metalMakingEfficiency = getMetalMakingEfficiencyDef(_unitDef)
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
  t1 = Spring.GetTimer()
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
    local _unitDef = unitDef(unitId)
    if _unitDef.canAssist then
      local metalUse, energyUse = traceUpkeep(unitId, alreadyCounted)
      metal = metal + metalUse
      energy = energy + energyUse
    end
  end
  return metal, energy
end

local function isTimeToMoveOn(secondsLeft, builderId, builderDef, totalBuildSpeed)
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

local function targetWillStall(targetId, targetDef, totalBuildSpeed, secondsLeft)
  if not targetDef then
    targetDef = unitDef(targetId)
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

  if buildingWillStallType("metal", metal, secondsLeft, mDrain) or buildingWillStallType("energy", energy, secondsLeft, eDrain) then
    return true
  else
    return false
  end
end

local function sortHeuristicallyBuildPower(a, b)
  local aWillStall = targetWillStall(a[1])
  local bWillStall = targetWillStall(b[1])
  if aWillStall and bWillStall then
    return a[3]['power'] < b[3]['power']
  elseif aWillStall and not bWillStall then
    return false
  elseif not aWillStall and bWillStall then
    return true
  else
    return a[3].buildSpeed * (1 / getBuildTimeLeft(a[1])) * (1 / a[3]['power']) >
        b[3].buildSpeed * (1 / getBuildTimeLeft(b[1])) * (1 / b[3]['power'])
  end
end

local function sortHeuristicallyEnergy(a, b)
  local aWillStall = targetWillStall(a[1])
  local bWillStall = targetWillStall(b[1])
  if aWillStall and bWillStall then
    return a[3]['energyMake'] * (1 / getBuildTimeLeft(a[1]) * a[3]['power']) >
        b[3]['energyMake'] * (1 / getBuildTimeLeft(b[1]) * b[3]['power'])
  elseif aWillStall and not bWillStall then
    return false
  elseif not aWillStall and bWillStall then
    return true
  else
    return a[3]['energyMake'] * a[3]['power'] > b[3]['energyMake'] * b[3]['power']
  end
end

local function getBestCandidate(candidatesOriginal, assistType)
  if #candidatesOriginal == 0 or assistType == 'metal' then
    return false
  end
  local candidates = {}
  local nCandidates = 0

  for i = 1, #candidatesOriginal do
    local candidateId = candidatesOriginal[i]
    local candidateDefId = GetUnitDefID(candidateId)
    local candidateDef = UnitDefs[candidateDefId]
    local MMEff = getMetalMakingEfficiencyDef(candidateDef)
    local M = candidateDef.extractsMetal or 0
    -- if assistType == 'mm' then -- and MMEff and MMEff <= 0 then
    --   log(candidateDef.translatedHumanName .. ' mm eff ' .. MMEff)
    -- end
    if
    --    candidateDef and (assistType == 'mm' and MMEff) and
        (assistType == 'buildPower' and candidateDef.buildSpeed > 0) or
        (assistType == 'energy' and (candidateDef.energyMake > 0)) or
        (assistType == 'mm' and (MMEff > 0 or M > 0)) then
      -- table.insert(candidates, { candidateId, candidateDefId, candidateDef })
      nCandidates = nCandidates + 1
      candidates[nCandidates] = { candidateId, candidateDefId, candidateDef }
    end
  end

  if #candidates == 1 then
    return candidates[1]
    -- todo investigate why number
    -- elseif type(candidates[1]) == "number" or type(candidates[2]) == "number" then
    --   return false
  elseif #candidates == 0 then
    return false
  end
  if assistType == 'buildPower' then
    table.sort(candidates, sortHeuristicallyBuildPower)
  elseif assistType == 'energy' then
    table.sort(candidates, sortHeuristicallyEnergy)
  elseif assistType == 'mm' then
    --    log(table.tostring(candidates))
    table.sort(candidates, sortHeuristicallyMorMM)
  end
  -- log('table.tostring(candidates) ' .. table.tostring(candidates))
  return candidates[1]
end

local function builderForceAssist(assistType, builderId, targetId, targetDefID, neighbours)
  local bestCandidate = getBestCandidate(neighbours, assistType)

  if bestCandidate and targetDefID ~= bestCandidate[2] then
    -- GetUnitDefID not a number arg one
    -- log('repair bestCandidate ' .. bestCandidate[1] .. ' ' .. bestCandidate[3].translatedHumanName)
    repair(builderId, bestCandidate[1])
  end
end

local function doFastForwardDecision(builder, targetId, cmdQueueTag, cmdQueueTagg)
  local targetDef = UnitDefs[GetUnitDefID(targetId)]
  local totalBuildSpeed = getBuildersBuildSpeed(getUnitsBuildingUnit(targetId))
  local secondsLeft = getBuildTimeLeft(targetId, targetDef)
  if isTimeToMoveOn(secondsLeft, builder.id, builder.def, totalBuildSpeed) and not targetWillStall(targetId, targetDef, totalBuildSpeed, secondsLeft) then
    moveOnFromBuilding(builder.id, targetId, cmdQueueTag, cmdQueueTagg)
  end
end



-- local function getSelectedUnitsUpkeep()
--   local alreadyCounted = {}

--   local metal = 0
--   local energy = 0

--   for _, unitID in ipairs(selectedUnits) do
--     if builders[unitID] then
--       local metalUse, energyUse = traceUpkeep(unitID, alreadyCounted)
--       metal = metal + metalUse
--       energy = energy + energyUse
--     end
--   end
--   return { ["metal"] = metal, ["energy"] = energy }
-- end

local function getReclaimableFeatures(x, z, radius)
  local wrecksInRange = GetFeaturesInCylinder(x, z, radius)

  if #wrecksInRange == 0 then
    return
  end

  local features = {
    ['metalenergy'] = {},
    ['metal'] = {},
    ['energy'] = {},
  }
  local nME = 0
  local nM = 0
  local nE = 0
  for i = 1, #wrecksInRange do
    local featureId = wrecksInRange[i]

    local featureRessurrect = GetFeatureResurrect(featureId)
    if not table.has_value({ 'armcom', 'legcom', 'corcom' }, featureRessurrect) then
      local metal, _, energy = GetFeatureResources(featureId)

      if metal > 0 and energy > 0 then
        nME = nME + 1
        features['metalenergy'][nME] = featureId
        -- table.insert(features['metalenergy'], featureId)
      elseif metal > 0 then
        nM = nM + 1
        features['metal'][nM] = featureId
        -- table.insert(features['metal'], featureId)
      elseif energy > 0 then
        nE = nE + 1
        features['energy'][nE] = featureId
        -- table.insert(features['energy'], featureId)
      end
    end
  end
  return features
end

local function SortHealthAsc(a, b)
  return a.health < b.health
end

local function builderIteration(n)
  local gotoContinue

  local regMod = n % 11 + 1
  regularizedResourceDerivativesMetal[regMod] = isPositiveMetalDerivative
  regularizedResourceDerivativesMetal[regMod] = isPositiveEnergyDerivative
  regularizedPositiveMetal = table.full_of(regularizedResourceDerivativesMetal, true)
  regularizedPositiveEnergy = table.full_of(regularizedResourceDerivativesEnergy, true)
  regularizedNegativeEnergy = table.full_of(regularizedResourceDerivativesEnergy, false)
  updateFastResourceStatus()

  for builderId, builder in pairs(builders) do
    gotoContinue = false
    local builderDef = builder.def
    local cmdQueue = GetUnitCommands(builderId, 3)
    local builderPosX, _, builderPosZ

    -- log('builder ', builderId, builderDef.translatedHumanName, 'cmdQueue', table.tostring(cmdQueue))

    if cmdQueue == nil then
      builders[builderId] = nil
      nBuilders = nBuilders - 1
      gotoContinue = true
    end

    local neighbours = {}
    local neighboursDamaged = {}
    local neighboursUnfinished = {}
    local targetId = GetUnitIsBuilding(builderId)

    if not gotoContinue then
      builderPosX, _, builderPosZ = GetUnitPosition(builderId, true)

      -- dont wait if has queued stuff and leaking
      if cmdQueue and #cmdQueue > 0 and cmdQueue[1].id == 5 and (isMetalLeaking or isEnergyLeaking) then
        GiveOrderToUnit(builderId, CMD.REMOVE, { nil }, { "ctrl" })
      end

      cmdQueue = purgeCompleteRepairs(builderId, cmdQueue)

      if not gotoContinue then
        local neighbourIds = GetUnitsInCylinder(builderPosX, builderPosZ, builderDef.buildDistance, myTeamId)

        for i = 1, #neighbourIds do
          local candidateId = neighbourIds[i]
          local candidateHealth, candidateMaxHealth, _, _, candidateBuild = GetUnitHealth(candidateId)
          neighbours[i] = {
            id = candidateId,
            health = candidateHealth,
            maxHealth = candidateMaxHealth,
            build = candidateBuild,
          }
          if candidateBuild ~= nil and candidateBuild < 1 then
            neighboursUnfinished[#neighboursUnfinished + 1] = candidateId
          elseif not (cmdQueue and ((cmdQueue[1] and cmdQueue[1].id < 0) or (cmdQueue[2] and cmdQueue[2].id < 0))) and candidateHealth and candidateMaxHealth and candidateHealth < candidateMaxHealth then
            neighboursDamaged[#neighboursDamaged + 1] = {
              id = candidateId,
              health = candidateHealth,
              maxHealth = candidateMaxHealth,
              healthRatio = candidateHealth / candidateMaxHealth,
            }
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
                and isReclaimTarget.hash[targetId] == nil and isReclaimTargetPrev.hash[targetId] == nil then
              repair(builderId, damagedTargetId)
            end
          end
          -- log('gotoContinue', 'neighboursDamaged', 'targetId', targetId, 'damagedTargetId', damagedTargetId, 'targetHealthRatio', targetHealthRatio, 'damagedTarget.healthRatio', damagedTarget.healthRatio)
          gotoContinue = true
        end
      end

      local features
      local needMetal = metalLevel < 0.15
      local needEnergy = energyLevel < 0.15
      if not gotoContinue and (needMetal or needEnergy) and not isMetalLeaking and not isEnergyLeaking and builderDef and
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
      end
    end

    if not gotoContinue and targetId then
      -- target id recieved
      local targetDefID = GetUnitDefID(targetId)
      local targetDef = UnitDefs[targetDefID]

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
      targetId = GetUnitIsBuilding(builderId)
      targetDefID = GetUnitDefID(targetId)
      targetDef = UnitDefs[targetDefID]

      -- mm/e switcher
      local targetUnitMM, targetUnitE = getUnitResourceProperties(targetDefID, targetDef)

      --  log('targetUnitE > 0, positiveMMLevel, regpose or eleak #### ' .. tostring(targetUnitE > 0) .. ', ' .. tostring(positiveMMLevel) .. ', ' .. tostring((regularizedPositiveEnergy or isEnergyLeaking) ))
      --  if targetUnitE > 0 then
      --    log(isEnergyLeaking)
      --    log('positiveMMLevel, not regnege or eleak === ' .. tostring(positiveMMLevel) .. ', ' .. tostring((regularizedPositiveEnergy or isEnergyLeaking) ))
      --  end
      -- log(
      --   builderDef.translatedHumanName .. ' targetId ' .. targetId .. ' #candidateNeighbours ' .. #candidateNeighbours
      -- )
      -- if n % (mainIterationModuloLimit * 3) == 0 and #candidateNeighbours > 1 then
      if #neighboursUnfinished > 1 then
        -- log(
        --   'metalLevel ' .. metalLevel ..
        --   ' regularizedPositiveMetal ' .. tostring(regularizedPositiveMetal) ..
        --   ' positiveMMLevel ' .. tostring(positiveMMLevel) ..
        --   ' not regularizedNegativeEnergy ' .. tostring(not regularizedNegativeEnergy) ..
        --   ' not regularizedPositiveEnergy ' .. tostring(not regularizedPositiveEnergy) ..
        --   ' not isEnergyLeaking ' .. tostring(not isEnergyLeaking) ..
        --   ' targetUnitE > 0 ' .. tostring(targetUnitE > 0) ..
        --   ' isMetalStalling ' .. tostring(isMetalStalling) ..
        --   ' targetDef.buildSpeed ' .. tostring(targetDef.buildSpeed)
        -- )
        if (metalLevel > 0.8 or (regularizedPositiveMetal and metalLevel > 0.15)) and (positiveMMLevel or not regularizedNegativeEnergy) then
          -- log(builderDef.translatedHumanName .. ' ForceAssist buildPower target ' .. targetId .. ' ' .. targetDef.translatedHumanName .. ' regularizedPositiveMetal ' .. tostring(regularizedPositiveMetal) .. ' metalLevel ' .. metalLevel)
          builderForceAssist('buildPower', builderId, targetId, targetDefID, neighboursUnfinished)
          --
        elseif not regularizedPositiveEnergy and not isEnergyLeaking and ((targetUnitMM > 0 and not positiveMMLevel) or (targetUnitE <= 0 and isEnergyStalling)) then
          -- log(builderDef.translatedHumanName .. ' ForceAssist energy target ' .. targetId .. ' ' .. targetDef.translatedHumanName)
          builderForceAssist('energy', builderId, targetId, targetDefID, neighboursUnfinished)
        elseif positiveMMLevel and (
              (
                (not regularizedNegativeEnergy or isEnergyLeaking) and targetUnitE > 0) or
              (isMetalStalling and targetDef.buildSpeed > 0)) then
          -- log(builderDef.translatedHumanName .. ' ForceAssist mm target ' .. targetId .. ' ' .. targetDef.humanName)
          builderForceAssist('mm', builderId, targetId, targetDefID, neighboursUnfinished)
        end
      end

      -- 90 == reclaim cmd
      if (isMetalStalling or isEnergyStalling) and not (cmdQueue and #cmdQueue > 0 and cmdQueue[1].id == 90) then
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
        end
      end

      if not gotoContinue then
        -- refresh for possible target change
        targetId = GetUnitIsBuilding(builderId)
        targetDefID = GetUnitDefID(targetId)
        targetDef = UnitDefs[targetDefID]

        -- easy finish neighbour
        local _, _, _, _, targetBuild = GetUnitHealth(targetId)
        for i = 1, #neighbours do
          local candidate = neighbours[i]
          local candidateId = candidate.id
          local candidateDef = unitDef(candidate.id)
          -- same type and not actually same building
          if candidateId ~= targetId and candidateDef == targetDef then
            local candidateBuild = candidate.build
            if candidateBuild and candidateBuild < 1 and candidateBuild > targetBuild then
              if candidateBuild > targetBuild then
                repair(builderId, candidateId)
                break
              end
            end
          end
        end
      end
    end
  end
  isReclaimTargetPrev = isReclaimTarget
  isReclaimTarget = NewSetList()
end

function widget:GameFrame(n)
  mainIterationModuloLimit = 1
  if nBuilders > 300 then
    mainIterationModuloLimit = 70
  elseif nBuilders > 200 then
    mainIterationModuloLimit = 20
  elseif nBuilders > 60 then
    mainIterationModuloLimit = 5
  elseif nBuilders > 10 then
    mainIterationModuloLimit = 2
  end

  if n % mainIterationModuloLimit == 0 then
    -- log('iterationmodulo ' .. mainIterationModuloLimit .. ' nBuilders ' .. nBuilders)
    builderIteration(n)
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
