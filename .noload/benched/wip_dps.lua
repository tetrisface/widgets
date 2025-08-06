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

VFS.Include('helpers.lua')

local GetUnitLastAttacker = Spring.GetUnitLastAttacker
local WorldToScreenCoords = Spring.WorldToScreenCoords
local GetUnitPosition = Spring.GetUnitPosition
local GetAllUnits = Spring.GetAllUnits
local GetGameSeconds = Spring.GetGameSeconds
local GetUnitDefID = Spring.GetUnitDefID
local UnitDefs = UnitDefs
local glText = gl.Text
local units = {}



local function RegisterUnit(unitID, unitDefID)
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

function widget:Initialize()
  if Spring.GetSpectatingState() or Spring.IsReplay() then
    widgetHandler:RemoveWidget()
  end

  local allUnits = GetAllUnits()
  for i = 1, #allUnits do
    local unitID = allUnits[i]
    local unitDefID = GetUnitDefID(unitID)
    RegisterUnit(unitID, unitDefID)
  end
end

function widget:UnitCreated(unitID, unitDefID, unitTeam)
  RegisterUnit(unitID, unitDefID)
end

function widget:UnitGiven(unitID, unitDefID, unitTeam, oldTeam)
  RegisterUnit(unitID, unitDefID)
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
