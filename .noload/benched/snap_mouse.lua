function widget:GetInfo()
  return {
    desc    = "",
    author  = "tetrisface",
    version = "",
    date    = "apr, 2024",
    name    = "Snap Mouse",
    license = "",
    layer   = -99990,
    enabled = true,
  }
end

VFS.Include('luaui/Widgets/.noload/misc/helpers.lua')

local GetUnitCommands    = Spring.GetUnitCommands
local GetSelectedUnits   = Spring.GetSelectedUnits
local GetMyTeamID        = Spring.GetMyTeamID
local GetTeamUnitsByDefs = Spring.GetTeamUnitsByDefs
local GetTimer           = Spring.GetTimer
local DiffTimers         = Spring.DiffTimers
local UnitDefs           = UnitDefs

local active             = false
local previousWorldPosXNew
local previousWorldPosZNew

function widget:Initialize()
  active = false
end

function widget:MousePress(x, y, button)
end

function widget:Update()
  if not active then
    return
  end

  local _, cmd = Spring.GetActiveCommand()
  if not cmd or cmd > 0 then
    return
  end

  local def = UnitDefs[-cmd]
  if not def then
    return
  end

  local buildingSizeX = def.xsize
  local buildingSizeZ = def.zsize

  local mouseX, mouseY = Spring.GetMouseState()
  local _, worldPos = Spring.TraceScreenRay(mouseX, mouseY, true)
  if not worldPos then
    return
  end
  local perSquareSide = math.floor(0.5 + 24 / buildingSizeX)
  local dotsPerBuildSquare = 8
  log('worldPos ' .. worldPos[1] .. ' ' .. worldPos[3] .. ' perSquareSide ' .. perSquareSide .. ' ' .. buildingSizeX .. ' ' .. buildingSizeZ)
  local worldPosXNew = math.floor((worldPos[1] / dotsPerBuildSquare + 0 * buildingSizeX / 2) / perSquareSide + 0.5) * perSquareSide
  local worldPosZNew = math.floor((worldPos[3] / dotsPerBuildSquare + 0 * buildingSizeZ / 2) / perSquareSide + 0.5) * perSquareSide
  worldPosXNew = (worldPosXNew * dotsPerBuildSquare + 0 * buildingSizeX / 2)
  worldPosZNew = (worldPosZNew * dotsPerBuildSquare + 0 * buildingSizeZ / 2)
  if previousWorldPosXNew == worldPosXNew and previousWorldPosZNew == worldPosZNew then
    return
  end

  local mouseXNew, mouseYNew = Spring.WorldToScreenCoords(worldPosXNew, worldPos[2], worldPosZNew)

  log('warping to ' .. worldPosXNew .. ' ' .. worldPosZNew)
  Spring.WarpMouse(mouseXNew, mouseYNew)
  previousWorldPosXNew = worldPosXNew
  previousWorldPosZNew = worldPosZNew
end

function widget:KeyPress(key, mods, isRepeat)
  if key == 294 then
    active = true
  end
  return false
end

function widget:KeyRelease(key, mods, isRepeat)
  if key == 294 then
    active = false
  end
  return false
end
