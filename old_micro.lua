function widget:GetInfo()
  return {
    name = "(old) micro",
    desc = "Nothing is copied from anywhere ʘ‿ʘ",
    author = "his_face",
    date = "mar, 2018",
    license = "GNU GPL, v2 or later",
    layer = 99,
    enabled = false
  }
end

local GetUnitWeaponHaveFreeLineOfFire = Spring.GetUnitWeaponHaveFreeLineOfFire
local ENEMY_UNITS = Spring.ENEMY_UNITS
local GetUnitAllyTeam = Spring.GetUnitAllyTeam
local GetAllyTeamList = Spring.GetAllyTeamList
local GetMyTeamID = Spring.GetMyTeamID
local GetSelectedUnits = Spring.GetSelectedUnits
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
local GetUnitsInSphere = Spring.GetUnitsInSphere
local GiveOrderToUnit = Spring.GiveOrderToUnit
local GetTimer = Spring.GetTimer
local GetUnitMaxRange = Spring.GetUnitMaxRange
local log = Spring.Echo
local UnitDefs = UnitDefs


local fighters = {}
local fighter_ids = {}
--local targets = {}
--local target_ids = {}

local mainIterationModuloLimit = 5
local myTeamId = Spring.GetMyTeamID()
local myAllyTeamId = select(6, Spring.GetTeamInfo(myTeamId))

local selectedUnits

function widget:Initialize()
  --    if Spring.GetSpectatingState() or Spring.IsReplay() then
  --        widgetHandler:RemoveWidget()
  --    end

  local myUnits = GetTeamUnits(myTeamId)
  for i = 1, #myUnits do
    local unitID = myUnits[i]
    register_my_fighter(unitID, GetUnitDefID(unitID))
  end
end

--function widget:UnitEnteredLos(unitID, unitTeam, allyTeam, unitDefID)
--  enemy out of view
--end
--function widget:UnitLeftLos(unitID, unitTeam, allyTeam, unitDefID) end

function register_my_fighter(unitID, unitDefID)
  if not unitDefID then
    return
  end

  refreshunit(unitID, unitDefID, unitDef)
end

function refreshunit(unitID, unitDefID, unitDef)
  if unitID == nil then
    return
  end
  if unitDef == nil then
    unitDefID = unitDefID or GetUnitDefID(unitID)
    unitDef = UnitDefs[unitDefID]
  end

  if not unitDef.canAttack or table.has_value({ 0, 1, 3 }, unitDef.fireState) or unitDef.noAutoFire then
    fighters[unitID] = nil
    return
  end

  --  local health, _, _, _, build = GetUnitHealth(unitID)

  local maxRange = GetUnitMaxRange(unitID)

  if maxRange > 1900 then
    return
  end

  local unit = {
    unitDef = unitDef,
    unitID = unitID,
    --    health = health
    maxRange = maxRange
  }
  fighters[unitID] = unit
  fighter_ids[#fighter_ids + 1] = unit
end

function widget:UnitCreated(unitID, unitDefID, unitTeam)
  if unitTeam == myTeamId then
    register_my_fighter(unitID, unitDefID)
  end
end

function widget:UnitGiven(unitID, unitDefID, unitTeam, oldTeam)
  if unitTeam == myTeamId then
    register_my_fighter(unitID, unitDefID)
  end
end

function widget:GameFrame(n)
  if n % mainIterationModuloLimit == 0 then
    mainIteration(n)
  end
end

function mainIteration(n)
  for i = 1, #fighter_ids do
    local target_ids = {}
    local target_set = {}
    local unitID = fighter_ids[i].unitID
    if WG.ignore_units_times[unitID] == nil then
      --      log('iter', fighters[unitID])
      local fighter = fighter_ids[i]
      local x, _, z = GetUnitPosition(unitID, true)
      if x then
        local in_range_units = GetUnitsInCylinder(x, z, fighter.maxRange, Spring.ENEMY_UNITS)
        --        log('in range units', fighter.maxRange, str_table(in_range_units))

        for ii = 1, #in_range_units do
          local in_range_unit_id = in_range_units[ii]
          --          log('in range', in_range_unit_id, health)
          --          log('free LOF', unitID, in_range_unit_id, GetUnitWeaponHaveFreeLineOfFire(unitID, 1, in_range_unit_id), TargetCanBeReached(unitID, {1}, in_range_unit_id))
          log('free LOF', unitID, in_range_unit_id, TargetCanBeReached(unitID, { 1 }, in_range_unit_id))
          if target_ids[in_range_unit_id] == nil and TargetCanBeReached(unitID, 1, in_range_unit_id) then
            local health, _ = GetUnitHealth(in_range_unit_id)

            local target = {
              unitID = in_range_unit_id,
              --            unitDef = unitDef,
              health = health,
            }
            target_ids[in_range_unit_id] = target
            target_set[#target_set + 1] = target
          end
        end

        if #target_set > 0 then
          table.sort(target_set, sortHealth)

          log(str_table(target_set))

          attack(unitID, target_set[1].unitID)
        end
      end
    end
  end
end

function TargetCanBeReached(unitID, weaponList, target)
  --  for weaponID in pairs(weaponList) do
  --    --GetUnitWeaponTryTarget tests both target type validity and target to be reachable for the moment
  --    if Spring.GetUnitWeaponTryTarget(unitID, weaponID, target) then
  --      return weaponID
  --      --FIXME: GetUnitWeaponTryTarget is broken in 99.0 for ground targets, yet Spring.GetUnitWeaponTestTarget, Spring.GetUnitWeaponTestRange and
  --      -- -- Spring.GetUnitWeaponHaveFreeLineOfFire individually work
  --      -- replace back with a single function when fixed
  --    elseif Spring.GetUnitWeaponTestTarget(unitID, weaponID, target) and
  --            Spring.GetUnitWeaponTestRange(unitID, weaponID, target) and
  --            Spring.GetUnitWeaponHaveFreeLineOfFire(unitID, weaponID, target) then
  --      return weaponID
  --    end
  --  end
  return Spring.GetUnitWeaponTryTarget(unitID, 1, target) and Spring.GetUnitWeaponTestTarget(unitID, 1, target) and Spring.GetUnitWeaponTestRange(unitID, 1, target) and
      Spring.GetUnitWeaponHaveFreeLineOfFire(unitID, 1, target)
end

function sortHealth(a, b)
  if a.health ~= nil and b.health ~= nil and a.health < b.health then
    return true
  end
  return false
end

function attack(source, dest)
  Spring.GiveOrderToUnit(source, 34923, { dest }, 0)
  --  Spring.SetUnitTarget(source, dest, false)
end

-- utils

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

-- for debug

function table.has_value(tab, val)
  for i = 1, #tab do
    if tab[i] == val then
      return true
    end
  end
  return false
end

function table.full_of(tab, val)
  for i = 1, #tab do
    if tab[i] ~= val then
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
    return "table" == type(v) and table.tostring(v) or tostring(v)
  end
end

function table.key_to_str(k)
  if "string" == type(k) and string.match(k, "^[_%a][_%a%d]*$") then
    return k
  else
    return "[" .. table.val_to_str(k) .. "]"
  end
end

function str_table(tbl)
  return table.tostring(tbl)
end

function table.tostring(tbl)
  local result, done = {}, {}
  for k, v in ipairs(tbl) do
    table.insert(result, table.val_to_str(v))
    done[k] = true
  end
  for k, v in pairs(tbl) do
    if not done[k] then
      table.insert(result, table.key_to_str(k) .. "=" .. table.val_to_str(v))
    end
  end
  return "{" .. table.concat(result, ",") .. "}"
end
