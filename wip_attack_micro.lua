function widget:GetInfo()
  return {
    desc    = "",
    author  = "",
    version = "",
    date    = "jan, 2024",
    name    = "attack micro",
    license = "",
    layer   = -99990,
    enabled = false,
  }
end

local myTeamId                  = Spring.GetMyTeamID()
local allies                    = Spring.GetTeamList(myTeamId)

local GetAllUnits               = Spring.GetAllUnits
local GetGameSeconds            = Spring.GetGameSeconds
local GetProjectileDefID        = Spring.GetProjectileDefID
local GetProjectilesInRectangle = Spring.GetProjectilesInRectangle
local GetProjectileTarget       = Spring.GetProjectileTarget
local GetUnitCommands           = Spring.GetUnitCommands
local GetUnitDefID              = Spring.GetUnitDefID
local GetUnitHealth             = Spring.GetUnitHealth
local GetUnitLastAttacker       = Spring.GetUnitLastAttacker
local GetUnitPosition           = Spring.GetUnitPosition
local GetUnitsInCylinder        = Spring.GetUnitsInCylinder
local GetUnitStates             = Spring.GetUnitStates
local GetUnitTeam               = Spring.GetUnitTeam
local GiveOrderToUnit           = Spring.GiveOrderToUnit
local SetUnitTargetasdf         = Spring.SetUnitTarget
local UnitDefs                  = UnitDefs
local units                     = {}
local WeaponDefs                = WeaponDefs
local WorldToScreenCoords       = Spring.WorldToScreenCoords
local overkillRatio             = 1.2

function iteration()
  local minX, maxX, minZ, maxZ = Game.mapSizeX, 0, Game.mapSizeZ, 0
  local aliveUnits = {}
  for i = 1, #units do
    local unit = units[i]
    local x, y, z = GetUnitPosition(unit.id, true)

    if x ~= nil then
      table.insert(aliveUnits, unit)
      local maxRange = unit.maxRange

      minX = math.min(minX, x - maxRange)
      maxX = math.max(maxX, x + maxRange)
      minZ = math.min(minZ, z - maxRange)
      maxZ = math.max(maxZ, z + maxRange)
    end
  end

  units = aliveUnits

  local targets = {}
  local projectiles = GetProjectilesInRectangle(minX, minZ, maxX, maxZ)
  -- log('rectangle: ' .. math.floor(minX) .. ' ' .. math.floor(maxX) .. ' ' .. math.floor(minZ) .. ' ' .. math.floor(maxZ))
  -- log("projectiles: " .. table.tostring(projectiles))
  for i = 1, #projectiles do
    local projectileID = projectiles[i]
    local targetType, targetID = GetProjectileTarget(projectileID)
    if targetID and type(targetID) == 'number' then
      -- avoid low cost targets
      local weaponDefID = GetProjectileDefID(projectileID)
      if weaponDefID then
        local weaponDef = WeaponDefs[weaponDefID]
        if weaponDef then
          if targets[targetID] then
            targets[targetID]['incomingDamage'] = targets[targetID]['incomingDamage'] + median(weaponDef.damages)
          else
            -- log('target: ' .. targetID)
            local targetDef = UnitDefs[GetUnitDefID(targetID)]
            if targetDef then
              targets[targetID] = {
                ['incomingDamage'] = median(weaponDef.damages),
                ['totalHealth'] = targetDef.health,
                ['cost'] = targetDef.cost
              }
            end
          end
        end
      end
    end
  end

  for i = 1, #units do
    -- local commandQueue = GetUnitCommands(units[i].id, 1)
    -- log('commandqueue for ' .. units[i].id .. ': ' .. tostring(commandQueue))
    local unit = units[i]

    if unit.team == myTeamId and unit.def.isBuilding then
      assignTarget2(unit, targets)
    end
  end
end

function widget:GameFrame(n)
  local mainIterationModuloLimit = 1
  if #units > 1000 then
    mainIterationModuloLimit = 20
  elseif #units > 80 then
    mainIterationModuloLimit = 5
  elseif #units > 40 then
    mainIterationModuloLimit = 2
  end

  if n % mainIterationModuloLimit == 0 then
    iteration()
  end
end

function assignTarget1(unit, targets)
  local avoidTargets = {}
  for targetID, target in pairs(targets) do
    if target['incomingDamage'] / target['totalHealth'] > overkillRatio then
      table.insert(avoidTargets, targetID)
    end
  end

  local unitStates = GetUnitStates(unit.id)
  -- fight 16, attack 20
  -- if commandQueue and #commandQueue > 0 and commandQueue[1].params[1] == 20 then
  if unitStates and unitStates.firestate == 2 then
    local posX, posY, posZ = GetUnitPosition(unit.id, true)
    local inRangeUnits = GetUnitsInCylinder(posX, posZ, unit.maxRange)
    local inRangeEnemyUnits = {}
    for j = 1, #inRangeUnits do
      if not table.has_value(allies, GetUnitTeam(inRangeUnits[j])) and targets[inRangeUnits[j]] then
        table.insert(inRangeEnemyUnits, targets[inRangeUnits[j]])
      end
    end
    if inRangeEnemyUnits and #inRangeEnemyUnits > 0 then
      table.sort(inRangeEnemyUnits, function(a, b)
        local aIncTot = a['incomingDamage'] / a['totalHealth']
        local bIncTot = b['incomingDamage'] / b['totalHealth']
        return (table.has_value(avoidTargets, a['id']) and 1 or 0) < (table.has_value(avoidTargets, b['id']) and 1 or 0)
            and (aIncTot > overkillRatio and 1 or 0) > (bIncTot > overkillRatio and 1 or 0)
            and aIncTot > bIncTot
      end)
      -- Spring.GiveOrderToUnit(source, 34923, { inRangeEnemyUnits[1] }, 0)
      -- Spring.GiveOrderToUnit(unit.id, CMD.INSERT, { 0, CMD.ATTACK, CMD.OPT_SHIFT, inRangeEnemyUnits[1] }, { 'alt' })
      log(unit.id .. ' attack ' .. table.tostring(inRangeEnemyUnits[1]))
      Spring.SetUnitTarget(unit.id, inRangeEnemyUnits[1].id)
    end
  end
end

function assignTarget2(unit, targets)
  local posX, posY, posZ = GetUnitPosition(unit.id, true)
  local inRangeTargets = GetUnitsInCylinder(posX, posZ, unit.maxRange)
  local expandedTargets = {}
  -- log('#targets: ' .. #inRangeTargets .. '')
  for j = 1, #inRangeTargets do
    local inRangeTargetID = inRangeTargets[j]
    if not table.has_value(allies, GetUnitTeam(inRangeTargetID)) then
      local def = UnitDefs[GetUnitDefID(inRangeTargetID)]
      if def and inRangeTargetID and targets[inRangeTargetID] then
        -- log('target def ' .. table.tostring(def.translatedHumanName) .. ' targets[inRangeTarget]: ' .. table.tostring(targets[inRangeTargetID]))
        table.insert(expandedTargets, {
          ['id'] = inRangeTargetID,
          ['incomingDamage'] = targets[inRangeTargetID]['incomingDamage'],
          ['totalHealth'] = def.health,
          ['speed'] = def.speed,
        })
      end
    end
  end
  if expandedTargets and #expandedTargets > 0 then
    -- log('#expandedTargets: ' .. #expandedTargets)
    table.sort(expandedTargets, function(a, b)
      local aIncTot = a['incomingDamage'] / a['totalHealth']
      local bIncTot = b['incomingDamage'] / b['totalHealth']
      local aOverkillRatio = a['speed'] * 0.4 / unit['minProjectileSpeed'] + 1.1
      local bOverkillRatio = b['speed'] * 0.4 / unit['minProjectileSpeed'] + 1.1
      return
      -- table.has_value(avoidTargets, a['id']) < table.has_value(avoidTargets, b['id']) and
          (aIncTot > aOverkillRatio and 1 or 0) < (bIncTot > bOverkillRatio and 1 or 0) and
          aIncTot / aOverkillRatio > bIncTot / bOverkillRatio
    end)
    -- Spring.GiveOrderToUnit(source, 34923, { inRangeEnemyUnits[1] }, 0)
    -- Spring.GiveOrderToUnit(unit.id, CMD.INSERT, { 0, CMD.ATTACK, CMD.OPT_SHIFT, inRangeEnemyUnits[1] }, { 'alt' })
    if unit.id and expandedTargets[1] and expandedTargets[1].id then
      log((unit.def.translatedHumanName or '') .. ' #' .. unit.id .. ' attack ' .. table.tostring(expandedTargets[1]))
      local sourceID = unit.id
      local targetID = expandedTargets[1].id
      -- log('source: ' .. sourceID .. ' target: ' .. targetID)
      -- SetUnitTargetasdf(source, target)
      -- SetUnitTargetasdf(123, 123)
      -- GiveOrderToUnit(sourceID, CMD.FIGHT, targetID, {})
      GiveOrderToUnit(sourceID, CMD.ATTACK, targetID, {})
      -- elseif unit.id and expandedTargets[2] then
      --   SetUnitTargetasdf(unit.id, expandedTargets[2])
      -- elseif unit.id and expandedTargets[3] then
      --   SetUnitTargetasdf(unit.id, expandedTargets[3])
      -- elseif unit.id and expandedTargets[4] then
      --   SetUnitTargetasdf(unit.id, expandedTargets[4])
    else
      log('no target found?' .. table.tostring(unit) .. ' ## ' .. table.tostring(expandedTargets))
    end
  end
end

function median(t)
  local temp = {}

  -- deep copy table so that when we sort it, the original is unchanged
  -- also weed out any non numbers
  for k, v in pairs(t) do
    if type(v) == 'number' then
      table.insert(temp, v)
    end
  end

  table.sort(temp)

  -- If we have an even number of table elements or odd.
  if math.fmod(#temp, 2) == 0 then
    -- return mean value of middle two elements
    return (temp[#temp / 2] + temp[(#temp / 2) + 1]) / 2
  else
    -- return middle element
    return temp[math.ceil(#temp / 2)]
  end
end

function widget:Initialize()
  if Spring.GetSpectatingState() or Spring.IsReplay() then
    widgetHandler:RemoveWidget()
  end

  local allUnits = GetAllUnits()
  for i = 1, #allUnits do
    local unitID = allUnits[i]
    local unitDefID = GetUnitDefID(unitID)
    registerUnit(unitID, unitDefID, GetUnitTeam(unitID))
  end
end

function registerUnit(unitID, unitDefID, unitTeam)
  -- if not unitDefID then
  --   local unitDefID
  -- end

  local unitDef = UnitDefs[unitDefID]

  if not unitDef or not unitDef.wDefs or #unitDef.wDefs == 0 or units[unitID] then
    return
  end
  -- log('unit def: ' .. table.tostring(unitDef))

  -- units[unitID] = {
  --   ["def"] = unitDef,
  --   ['id'] = unitID
  -- }
  local maxRange = 0
  local maxDamage = 0
  local minProjectileSpeed = 0
  for j = 1, #unitDef.weapons do
    -- log('weapon: ' .. table.tostring(unit.def.wDefs[j]))
    -- log(unit.def.wDefs[j])
    -- log(unit.def.weapons[j])
    maxRange = math.max(maxRange, unitDef.wDefs[j].range or 0)
    maxDamage = math.max(maxRange, unitDef.wDefs[j].damage or 0)
    log('max damage: ' .. maxDamage)
    minProjectileSpeed = math.min(minProjectileSpeed, unitDef.wDefs[j].projectilespeed or 1)
    -- log('max range: ' .. maxRange)
  end
  table.insert(units, {
    ['def'] = unitDef,
    ['id'] = unitID,
    ['maxRange'] = maxRange,
    ['minProjectileSpeed'] = minProjectileSpeed,
    ['team'] = unitTeam
  })
end

function widget:UnitCreated(unitID, unitDefID, unitTeam)
  registerUnit(unitID, unitDefID, unitTeam)
end

function widget:UnitGiven(unitID, unitDefID, unitTeam, oldTeam)
  registerUnit(unitID, unitDefID, unitTeam)
end

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
