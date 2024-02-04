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

local GetFeatureResources = Spring.GetFeatureResources
local GetFeatureResurrect = Spring.GetFeatureResurrect
local GetFeaturesInCylinder = Spring.GetFeaturesInCylinder
local GetGameRulesParam = Spring.GetGameRulesParam
local GetTeamResources = Spring.GetTeamResources
local GetTeamRulesParam = Spring.GetTeamRulesParam
local GetTeamUnitDefCount = Spring.GetTeamUnitDefCount
local GetTeamUnits = Spring.GetTeamUnits
local GetUnitCommands = Spring.GetUnitCommands
local GetUnitDefID = Spring.GetUnitDefID
local GetUnitHealth = Spring.GetUnitHealth
local GetUnitIsBuilding = Spring.GetUnitIsBuilding
local GetUnitPosition = Spring.GetUnitPosition
local GetUnitResources = Spring.GetUnitResources
local GetUnitsInCylinder = Spring.GetUnitsInCylinder
local GiveOrderToUnit = Spring.GiveOrderToUnit
local UnitDefNames = UnitDefNames
local UnitDefs = UnitDefs

local abandonedTargetIDs = {}
local builders = {}
local log = Spring.Echo
local myTeamId = Spring.GetMyTeamID()
local possibleMetalMakersProduction = 0
local possibleMetalMakersUpkeep = 0
local regularizedResourceDerivativesEnergy = { true }
local regularizedResourceDerivativesMetal = { true }
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

function widget:Initialize()
  if Spring.GetSpectatingState() or Spring.IsReplay() then
    widgetHandler:RemoveWidget()
  end

  local myUnits = GetTeamUnits(myTeamId)
  for _, unitID in ipairs(myUnits) do
    local unitDefID = GetUnitDefID(unitID)
    registerUnit(unitID, unitDefID, teamID)
  end
end

function registerUnit(unitID, unitDefID)
  if not unitDefID then
    return
  end

  local unitDef = UnitDefs[unitDefID]

  if unitDef.isBuilder and unitDef.canAssist and not unitDef.isFactory then
    builders[unitID] = {
      id = unitID,
      buildSpeed = unitDef.buildSpeed,
      originalBuildSpeed = unitDef.buildSpeed,
      def = unitDef,
      defID = unitDefID,
      targetId = nil,
      guards = {},
      previousBuilding = nil
    }
    nBuilders = nBuilders + 1
  end
end

function widget:UnitCreated(unitID, unitDefID, unitTeam)
  registerUnit(unitID, unitDefID)
end

function widget:UnitGiven(unitID, unitDefID, unitTeam, oldTeam)
  if unitTeam == myTeamId then
    registerUnit(unitID, unitDefID)
  end
end

function getBuildersBuildSpeed(tempBuilders)
  local totalSpeed = 0

  for _, unitID in pairs(tempBuilders) do
    local targetId = builders[unitID].targetId
    if not targetId or not isAlreadyInTable(targetId, tempBuilders) then
      totalSpeed = totalSpeed + builders[unitID].buildSpeed
    end
  end

  return totalSpeed
end

function getBuildTimeLeft(targetId, targetDef)
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

function getUnitsBuildingUnit(unitID)
  local building = {}

  for builderId, _ in pairs(builders) do
    local targetId = GetUnitIsBuilding(builderId)
    if targetId == unitID then
      building[builderId] = builderId
    end
  end
  return building
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

  if n % 1000 == 0 then
    if GetGameRulesParam('raptorTechAnger') > 66 and (
          GetTeamUnitDefCount(myTeamId, UnitDefNames['armamd'].id) == 0 and
          GetTeamUnitDefCount(myTeamId, UnitDefNames['armscab'].id) == 0 and
          GetTeamUnitDefCount(myTeamId, UnitDefNames['corfmd'].id) == 0 and
          GetTeamUnitDefCount(myTeamId, UnitDefNames['cormabm'].id) == 0
        ) then
      log('ANTI NUKE WARNING!!!')
    end
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

function builderIteration(n)
  local gotoContinue

  table.insert(regularizedResourceDerivativesMetal, 1, isPositiveMetalDerivative)
  table.insert(regularizedResourceDerivativesEnergy, 1, isPositiveEnergyDerivative)
  -- getn handles nil
  if #regularizedResourceDerivativesMetal > 11 then
    table.remove(regularizedResourceDerivativesMetal)
    table.remove(regularizedResourceDerivativesEnergy)
  end
  regularizedPositiveMetal = table.full_of(regularizedResourceDerivativesMetal, true)
  regularizedPositiveEnergy = table.full_of(regularizedResourceDerivativesEnergy, true)
  -- regularizedNegativeMetal = table.full_of(regularizedResourceDerivativesMetal, false)
  regularizedNegativeEnergy = table.full_of(regularizedResourceDerivativesEnergy, false)
  updateFastResourceStatus()

  -- for i = 1, #builders do
  for builderId, builder in pairs(builders) do
    gotoContinue = false
    -- local builderDef = UnitDefs[GetUnitDefID(builderId)]
    -- local builder = builders[i]
    -- local builderId = builder.id
    local builderDef = builder.def
    local cmdQueue = GetUnitCommands(builderId, 3)
    local builderPosX, _, builderPosZ

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
        -- prepare outside command queue heuristical candidates/targets
        local neighbourIds = GetUnitsInCylinder(builderPosX, builderPosZ, builderDef.buildDistance, myTeamId)

        --      local candidateNeighboursExclusive = {}
        -- for i, candidateId in ipairs(neighbours) do
        for i = 1, #neighbourIds do
          local candidateId = neighbourIds[i]
          local candidateHealth, candidateMaxHealth, _, _, candidateBuild = GetUnitHealth(candidateId)
          table.insert(neighbours, {
            id = candidateId,
            health = candidateHealth,
            maxHealth = candidateMaxHealth,
            build = candidateBuild,
          })
          if candidateBuild ~= nil and candidateBuild < 1 then
            table.insert(neighboursUnfinished, candidateId)

            --          if candidateId ~= builderId  then
            --            table.insert(candidateNeighboursExclusive, candidateId)
            --          end
          elseif not (cmdQueue and ((cmdQueue[1] and cmdQueue[1].id < 0) or (cmdQueue[2] and cmdQueue[2].id < 0))) and candidateHealth and candidateMaxHealth and candidateHealth < candidateMaxHealth then
            table.insert(neighboursDamaged, {
              id = candidateId,
              health = candidateHealth,
              maxHealth = candidateMaxHealth,
            })
          end
        end

        if #neighboursDamaged > 0 then
          table.sort(neighboursDamaged, function(a, b) return a.health < b.health end)
          local damagedTargetId = neighboursDamaged[1].id
          if targetId ~= damagedTargetId then
            repair(builderId, damagedTargetId)
          end
          gotoContinue = true
        end
      end

      local features
      local needMetal = metalLevel < 0.15
      local needEnergy = energyLevel < 0.15
      -- if not gotoContinue and (needMetal or needEnergy) and not isMetalStalling and not isEnergyStalling and builderDef and
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
        -- for _, candidateId in ipairs(candidateNeighbours) do
        for i = 1, #neighbours do
          local candidate = neighbours[i]
          local candidateId = candidate.id
          local candidateDef = unitDef(candidate.id)
          -- same type and not actually same building
          if candidateId ~= targetId and candidateDef == targetDef then
            -- local _, _, _, _, candidateBuild = GetUnitHealth(candidateId)
            local candidateBuild = candidate.build
            if candidateBuild and candidateBuild < 1 and candidateBuild > targetBuild then
              -- local targetBuildTimeLeft = getBuildTimeLeft(targetId)
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
end

function reclaimCheckAction(builderId, features, needMetal, needEnergy)
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

function purgeCompleteRepairs(builderId, cmdQueue)
  -- local shitFound = true
  -- local safetyStop = 400
  -- while shitFound do
  -- shitFound = false
  -- for _, cmd in ipairs(cmdQueue) do
  for i = 1, #cmdQueue do
    local cmd = cmdQueue[i]
    if cmd.id == 40 then
      local _, _, _, _, targetBuild = GetUnitHealth(cmd.params[1])
      if not targetBuild or targetBuild == 1 then
        shitFound = true
        GiveOrderToUnit(builderId, CMD.REMOVE, { cmd.tag }, { "ctrl" })
      end
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

function builderForceAssist(assistType, builderId, targetId, targetDefID, neighbours)
  local bestCandidate = getBestCandidate(neighbours, assistType)

  if bestCandidate and targetDefID ~= bestCandidate[2] then
    -- GetUnitDefID not a number arg one
    -- log('repair bestCandidate ' .. bestCandidate[1] .. ' ' .. bestCandidate[3].translatedHumanName)
    repair(builderId, bestCandidate[1])
  end
end

function repair(builderId, targetId)
  GiveOrderToUnit(builderId, CMD.INSERT, { 0, CMD.REPAIR, CMD.OPT_CTRL, targetId }, { "alt" })
end

function sortHeuristicallyBuildPower(a, b)
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

function sortHeuristicallyEnergy(a, b)
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

function sortHeuristicallyMM(a, b)
  --  log('compare ' .. a[3].humanName .. ' '.. getMetalMakingEfficiency(a[2]))
  return getMetalMakingEfficiency(a[2]) > getMetalMakingEfficiency(b[2])
end

function getBestCandidate(candidatesOriginal, assistType)
  if #candidatesOriginal == 0 or assistType == 'metal' then
    return false
  end
  -- local candidatesFull = deepcopy(candidatesOriginal)
  local candidates = {}

  for i = 1, #candidatesOriginal do
    local candidateId = candidatesOriginal[i]
    local candidateDefId = GetUnitDefID(candidateId)
    local candidateDef = UnitDefs[candidateDefId]
    local MMEff = getMetalMakingEfficiencyDef(candidateDef)
    -- if assistType == 'mm' then -- and MMEff and MMEff <= 0 then
    --   log(candidateDef.translatedHumanName .. ' mm eff ' .. MMEff)
    -- end
    if
    --    candidateDef and (assistType == 'mm' and MMEff) and
        (assistType == 'buildPower' and candidateDef.buildSpeed > 0) or
        (assistType == 'energy' and (candidateDef['energyMake'] > 0)) or
        (assistType == 'mm' and MMEff > 0) then
      table.insert(candidates, { candidateId, candidateDefId, candidateDef })
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
    table.sort(candidates, sortHeuristicallyMM)
  end
  -- log('table.tostring(candidates) ' .. table.tostring(candidates))
  return candidates[1]
end

function deepcopy(orig)
  local orig_type = type(orig)
  local copy
  if orig_type == 'table' then
    copy = {}
    for orig_key, orig_value in next, orig, nil do
      copy[deepcopy(orig_key)] = deepcopy(orig_value)
    end
    setmetatable(copy, deepcopy(getmetatable(orig)))
  else -- number, string, boolean, etc
    copy = orig
  end
  return copy
end

function updateFastResourceStatus()
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

function getUnitResourceProperties(unitDefID, unitDef)
  local metalMakingEfficiency = getMetalMakingEfficiencyDef(unitDef)
  if metalMakingEfficiency == nil then
    metalMakingEfficiency = 0
  end
  local energyMaking = getEout(unitDef)
  return metalMakingEfficiency, energyMaking
end

function getMetalMakingEfficiency(unitDefID)
  return getMetalMakingEfficiencyDef(UnitDefs[unitDefID])
end

function getMetalMakingEfficiencyDef(unitDef)
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

function getEout(unitDef)
  local totalEOut = unitDef.energyMake or 0

  totalEOut = totalEOut + -1 * unitDef.energyUpkeep

  if unitDef.tidalGenerator > 0 and tidalStrength > 0 then
    local mult = 1 -- DEFAULT
    if unitDef.customParams then
      mult = unitDef.customParams.energymultiplier or mult
    end
    totalEOut = totalEOut + (tidalStrength * mult)
  end

  if unitDef.windGenerator > 0 then
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

-- todo
-- function getTraveltime(unitDef, A, B)
--   selectedUnits = GetSelectedUnits()
--   local totalBuildSpeed = getBuildersBuildSpeed(getUnitsBuildingUnit(targetId))
--   local secondsLeft = getBuildTimeLeft(targetId)
--   local unitDef = UnitDefs[GetUnitDefID(targetId)]
--   if isTimeToMoveOn(secondsLeft, builderId, unitDef, totalBuildSpeed) and not targetWillStall(targetId, unitDef, totalBuildSpeed, secondsLeft) then
--     moveOnFromBuilding(builderId, targetId, cmdQueueTag, cmdQueueTagg)
--   end
-- end

function doFastForwardDecision(builder, targetId, cmdQueueTag, cmdQueueTagg)
  local targetDef = UnitDefs[GetUnitDefID(targetId)]
  local totalBuildSpeed = getBuildersBuildSpeed(getUnitsBuildingUnit(targetId))
  local secondsLeft = getBuildTimeLeft(targetId, targetDef)
  if isTimeToMoveOn(secondsLeft, builder.id, builder.def, totalBuildSpeed) and not targetWillStall(targetId, targetDef, totalBuildSpeed, secondsLeft) then
    moveOnFromBuilding(builder.id, targetId, cmdQueueTag, cmdQueueTagg)
  end
end

function moveOnFromBuilding(builderId, targetId, cmdQueueTag, cmdQueueTagg)
  GiveOrderToUnit(builderId, CMD.REMOVE, { cmdQueueTag }, { "ctrl" })

  -- if not cmdQueueTagg then
  -- else
  --   GiveOrderToUnit(builderId, CMD.REMOVE, {cmdQueueTag,cmdQueueTagg}, {"ctrl"})
  -- end
  builders[builderId].previousBuilding = targetId
  abandonedTargetIDs[targetId] = true
  t1 = Spring.GetTimer()
end

function isTimeToMoveOn(secondsLeft, builderId, builderDef, totalBuildSpeed)
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

function targetWillStall(targetId, targetDef, totalBuildSpeed, secondsLeft)
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

function buildingWillStallType(type, consumption, secondsLeft, releasedExpenditures)
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

function getMyResources(type)
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

function getUnitsUpkeep()
  local alreadyCounted = {}

  local metal = 0
  local energy = 0

  for _, unitId in ipairs(GetTeamUnits(myTeamId)) do
    local unitDef = unitDef(unitId)
    if unitDef.canAssist then
      local metalUse, energyUse = traceUpkeep(unitId, alreadyCounted)
      metal = metal + metalUse
      energy = energy + energyUse
    end
  end
  return metal, energy
end

function unitDef(unitId)
  return UnitDefs[GetUnitDefID(unitId)]
end

-- function getSelectedUnitsUpkeep()
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

function traceUpkeep(unitID, alreadyCounted)
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

function getReclaimableFeatures(x, z, radius)
  local wrecksInRange = GetFeaturesInCylinder(x, z, radius)

  if #wrecksInRange == 0 then
    return
  end

  local features = {
    ['metalenergy'] = {},
    ['metal'] = {},
    ['energy'] = {},
  }
  for i = 1, #wrecksInRange do
    local featureId = wrecksInRange[i]

    local featureRessurrect = GetFeatureResurrect(featureId)
    if not table.has_value({ 'armcom', 'legcom', 'corcom' }, featureRessurrect) then
      local metal, _, energy = GetFeatureResources(featureId)

      if metal > 0 and energy > 0 then
        table.insert(features['metalenergy'], featureId)
      elseif metal > 0 then
        table.insert(features['metal'], featureId)
      elseif energy > 0 then
        table.insert(features['energy'], featureId)
      end
    end
  end
  return features
end

-- for debug

function log(s)
  Spring.Echo(s)
end

function table.has_value(tab, val)
  for _, value in ipairs(tab) do
    if value == val then
      return true
    end
  end
  return false
end

function table.full_of(tab, val)
  for _, value in ipairs(tab) do
    if value ~= val then
      return false
    end
  end
  return true
end

-- for printing tables
function table.val_to_str(v)
  if "string" == type(v) then
    v = string.gsub(v, "\n", "\\n")
    if string.match(string.gsub(v, "[^'\"]", ""), '^"+$') then
      return "'" .. v .. "'"
    end
    return '"' .. string.gsub(v, '"', '\\"') .. '"'
  else
    return "table" == type(v) and table.tostring(v) or
        tostring(v)
  end
end

function table.key_to_str(k)
  if "string" == type(k) and string.match(k, "^[_%a][_%a%d]*$") then
    return k
  else
    return "[" .. table.val_to_str(k) .. "]"
  end
end

function table.tostring(tbl)
  if type(tbl) == "string" then
    return tbl
  elseif type(tbl) ~= "table" then
    return tostring(tbl)
  end
  if not tbl then
    return 'nil'
  end
  local result, done = {}, {}
  for k, v in ipairs(tbl) do
    table.insert(result, table.val_to_str(v))
    done[k] = true
  end
  for k, v in pairs(tbl) do
    if not done[k] then
      table.insert(result,
        table.key_to_str(k) .. "=" .. table.val_to_str(v))
    end
  end
  return "{" .. table.concat(result, ",") .. "}"
end
