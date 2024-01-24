function widget:GetInfo()
  return {
    desc    = "",
    author  = "",
    version = "",
    date    = "jan, 2024",
    name    = "dps",
    license = "",
    layer   = -99990,
    enabled = false,
  }
end

local GetUnitLastAttacker = Spring.GetUnitLastAttacker
local WorldToScreenCoords = Spring.WorldToScreenCoords
local GetUnitPosition = Spring.GetUnitPosition
local GetAllUnits = Spring.GetAllUnits
local GetGameSeconds = Spring.GetGameSeconds
local GetUnitDefID = Spring.GetUnitDefID
local UnitDefs = UnitDefs
local glText = gl.Text
local units = {}

function widget:Initialize()
  if Spring.GetSpectatingState() or Spring.IsReplay() then
    widgetHandler:RemoveWidget()
  end

  local allUnits = GetAllUnits()
  for i = 1, #allUnits do
    local unitID = allUnits[i]
    local unitDefID = GetUnitDefID(unitID)
    registerUnit(unitID, unitDefID)
  end
end

function registerUnit(unitID, unitDefID)
  if not unitDefID then
    return
  end

  local unitDef = UnitDefs[unitDefID]

  if not unitDef or not unitDef.weapons or #unitDef.weapons == 0 or units[unitID] then
    return
  end

  units[unitID] = {
    ["damage"] = 0,
    ["created"] = GetGameSeconds()
  }
end

function widget:UnitCreated(unitID, unitDefID, unitTeam)
  registerUnit(unitID, unitDefID)
end

function widget:UnitGiven(unitID, unitDefID, unitTeam, oldTeam)
  registerUnit(unitID, unitDefID)
end

-- function widget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID, attackerDefID, attackerTeam)
function widget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID, attackerDefID, attackerTeam)
  attackerID = GetUnitLastAttacker(unitID)
  if units[attackerID] then
    units[attackerID].damage = units[attackerID].damage + damage
    log("total damage for " .. attackerID .. ": " .. units[attackerID].damage)
  end
end

function widget:DrawScreen()
  for unitID, unit in pairs(units) do
    if unit.damage > 0 then
      local worldX, worldY, worldZ = GetUnitPosition(unitID, true)
      if worldX and worldY then
        local x, y, z = WorldToScreenCoords(worldX, worldY, worldZ)
        log("x " .. x .. " y " .. y .. " z " .. z)
        drawText(tostring(math.floor(unit.damage)), x + 5, y + 5)
      end
    end
  end
end

function drawText(str, x, y, op)
  glText(str, x, y, 15, op or "o")
end

-- function unitDef(unitId)
--   return UnitDefs[GetUnitDefID(unitId)]
-- end

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
