return {}

function widget:GetInfo()
  return {
    desc    = "Adds ability to move, rotate, copy, reverse, sync build queues",
    author  = "tetrisface",
    version = "",
    date    = "mar, 2024",
    name    = "zzz Build Queue Edit",
    license = "",
    layer   = -99990,
    enabled = true,
  }
end

VFS.Include('luaui/Widgets/.noload/misc/helpers.lua')
VFS.Include('luaui/Headers/keysym.h.lua')

local lineColors  = {
  -- local mapLineColor         = { 181, 137, 0 } -- yellow
  orange  = { 203, 75, 22 },
  red     = { 220, 50, 47 },
  magenta = { 211, 54, 130 },
  violet  = { 108, 113, 196 },
  blue    = { 38, 139, 210 },
  cyan    = { 42, 161, 152 },
  -- green   = { 133, 153, 0 }
}
local lineOptions = {
  width = 1.2,
  alpha = 0.5,
  length = 32
}
local rects       = {}
local enabled     = true
local buildingDefId
local mapMouseX
local mapMouseY
local mapMouseZ
local linesList

local function MapMousePosition()
  local mx, my = Spring.GetMouseState()
  local _, pos = Spring.TraceScreenRay(mx, my, true, false, true)
  if not pos then
    return
  end
  table.echo(pos)
  return pos[1], pos[2], pos[3]
end

local function BorderNorth(_mapMouseX, _mapMouseZ)
  _mapMouseX = _mapMouseX or 0
  _mapMouseZ = _mapMouseZ or 0
  local selectionRectangleWest = _mapMouseX - 5
  local selectionRectangleNorth = _mapMouseZ - 100000
  local selectionRectangleEast = _mapMouseX + 5
  local selectionRectangleSouth = _mapMouseZ
  local unitsAbove = Spring.GetUnitsInRectangle(selectionRectangleWest, selectionRectangleNorth, selectionRectangleEast, selectionRectangleSouth)
  if #unitsAbove <= 0 then
    return
  end
  local x = 0
  local zMax = 0
  local unitDef
  local _unitDef
  local found = false
  for i = 1, #unitsAbove do
    local unitID = unitsAbove[i]
    local _x, _, z = Spring.GetUnitPosition(unitID)
    _unitDef = UnitDefs[Spring.GetUnitDefID(unitID)]
    z = z + _unitDef.zsize * 4
    if z > zMax and _unitDef.isBuilding then
      zMax = z
      unitDef = UnitDefs[Spring.GetUnitDefID(unitID)]
      x = _x
      found = true
    end
  end
  if not found then
    return
  end
  log('found border', x, zMax, unitDef.xsize)
  return x, zMax, unitDef.xsize * 4 or lineOptions.length
end

local function DrawHorizontalRectangle(x1, z1, x2, z2, y)
  gl.Vertex(x1, y, z1)
  gl.Vertex(x2, y, z1)
  gl.Vertex(x2, y, z2)
  gl.Vertex(x1, y, z1)
  gl.Vertex(x1, y, z2)
  gl.Vertex(x2, y, z2)
end

local function DrawCreateLines()
  if #rects <= 0 then
    return
  end
  -- gl.DepthTest(GL.LEQUAL)
  gl.Color(lineColors.magenta[1] / 255, lineColors.magenta[2] / 255, lineColors.magenta[3] / 255, 0.7)
  gl.PushMatrix()

  for i = 1, #rects do
    local rectangle = rects[i]
    -- gl.Texture(read what you need here)
    -- if line.horizontal then
    table.echo(rectangle)
    -- gl.Translate(rectangle.x1, Spring.GetGroundOrigHeight(rectangle.x1, rectangle.z1) + 45, rectangle.z1)
    -- gl.Translate(rectangle.x1, mapMouseY + 45, rectangle.z1)
    gl.BeginEnd(GL.TRIANGLE_STRIP, DrawHorizontalRectangle, rectangle.x1, rectangle.z1, rectangle.x2, rectangle.z2, mapMouseY + 1)
  end
  gl.PopMatrix()
end


function widget:Update()
  _, buildingDefId = Spring.GetActiveCommand()

  if not buildingDefId or buildingDefId >= 0 then
    return
  end

  mapMouseX, mapMouseY, mapMouseZ = MapMousePosition()
  -- local x, zMax, length = BorderNorth(mapMouseX, mapMouseZ)
  -- if not x then
  --   return
  -- end

  local toBuildXSize = UnitDefs[-buildingDefId].xsize * 4
  local toBuildZSize = UnitDefs[-buildingDefId].zsize * 4
  -- rects = {
  --   {
  --     x1 = x - length or UnitDefs[-buildingDefId].xsize * 4,
  --     x2 = x + length or UnitDefs[-buildingDefId].xsize * 4,
  --     z1 = (zMax or 0) - lineOptions.width,
  --     z2 = (zMax or 0) + lineOptions.width,
  --   }
  -- }

  local screenBounds = {}
  Spring.TraceScreenRay(0, 0)

  local isNorthClosest = mapMouseX < Game.mapSizeX / 2
  local isWestClosest = mapMouseZ < Game.mapSizeZ / 2

  log('isNorthClosest', isNorthClosest, 'isWestClosest', isWestClosest)

  linesList = gl.CreateList(DrawCreateLines)
end

function widget:DrawWorld()
  if linesList then
    gl.CallList(linesList)
  end
end
