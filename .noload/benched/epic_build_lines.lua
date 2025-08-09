return {}

function widget:GetInfo()
  return {
    desc    = "displays lines when",
    author  = "tetrisface",
    version = "",
    date    = "mar, 2024",
    name    = "zzz Epic Build Lines",
    license = "",
    layer   = -99990,
    enabled = true,
  }
end

VFS.Include('LuaUI/Widgets/helpers.lua')
VFS.Include('luaui/Headers/keysym.h.lua')

local mapLineColor             = { 181 / 255, 137 / 255, 0 / 255 } -- yellow
local lineColors               = {
  blue    = { 38 / 255, 139 / 255, 210 / 255 },
  magenta = { 211 / 255, 54 / 255, 130 / 255 },
  violet  = { 108 / 255, 113 / 255, 196 / 255 },
  cyan    = { 42 / 255, 161 / 255, 152 / 255 },
  red     = { 220 / 255, 50 / 255, 47 / 255 },
  orange  = { 203 / 255, 75 / 255, 22 / 255 },
  -- green   = { 133, 153, 0 }
}
local directionColors          = {
  lineColors.blue,
  lineColors.magenta,
  lineColors.violet,
  lineColors.cyan,
}
local lineOptions              = {
  width = 1.2,
  alpha = 0.5,
  length = 32
}

local previousTimer            = Spring.GetTimer()
local lineSegments             = {}
local nLineSegments            = 0
local buildingBordersXZSquares = {}
local addedBuildings           = {}
local activeBuildingDef
local buildingDefId
local previousBuildingDefId
local previousIsDefaultFacing
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
  local x = math.min(math.max(pos[4], 0), Game.mapSizeX)
  local z = math.min(math.max(pos[6], 0), Game.mapSizeZ)
  return x, pos[2], z
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
  if nLineSegments <= 0 then
    return
  end
  gl.DepthTest(GL.LEQUAL)
  gl.PushMatrix()

  for i = 1, nLineSegments do
    local lineSegment = lineSegments[i]
    -- if line.horizontal then
    -- log('drawing lineSegment', i, nLineSegments)
    -- table.echo(lineSegment)
    -- gl.Translate(rectangle.x1, Spring.GetGroundOrigHeight(rectangle.x1, rectangle.z1) + 45, rectangle.z1)
    -- gl.Translate(rectangle.x1, mapMouseY + 45, rectangle.z1)
    gl.Color(lineSegment.color[1], lineSegment.color[2], lineSegment.color[3], lineSegment.alpha)
    gl.BeginEnd(GL.TRIANGLE_STRIP, DrawHorizontalRectangle, lineSegment.x1, lineSegment.z1, lineSegment.x2, lineSegment.z2, mapMouseY + 1)
  end
  gl.PopMatrix()
end

local function AddBuilding(unitId, unitDef)
  local x, _, z = Spring.GetUnitPosition(unitId)
  local defaultFacing = Spring.GetUnitBuildFacing(unitId) == 0 or Spring.GetUnitBuildFacing(unitId) == 2
  local xsize = defaultFacing and unitDef.xsize or unitDef.zsize
  local zsize = defaultFacing and unitDef.zsize or unitDef.xsize
  local xStartSquare = math.floor(0.5 + x / 4) - xsize
  local zStartSquare = math.floor(0.5 + z / 4) - zsize
  for i = 0, xsize * 2 - 1 do
    if not buildingBordersXZSquares[xStartSquare + i] then
      buildingBordersXZSquares[xStartSquare + i] = {}
    end
    buildingBordersXZSquares[xStartSquare + i][zStartSquare]         = {
      id        = unitId,
      direction = 1,
    }
    buildingBordersXZSquares[xStartSquare + i][zStartSquare + zsize] = {
      id        = unitId,
      direction = 3,
    }
  end
  for j = 1, zsize * 2 do
    if not buildingBordersXZSquares[xStartSquare] then
      buildingBordersXZSquares[xStartSquare] = {}
    end
    if not buildingBordersXZSquares[xStartSquare + xsize] then
      buildingBordersXZSquares[xStartSquare + xsize] = {}
    end
    buildingBordersXZSquares[xStartSquare][zStartSquare + j]         = {
      id        = unitId,
      direction = 2,
    }
    buildingBordersXZSquares[xStartSquare + xsize][zStartSquare + j] = {
      id        = unitId,
      direction = 4,
    }
  end
  addedBuildings[unitId] = true
end

local function AddLineSegment(x1, z1, x2, z2, color, alpha, direction)
  nLineSegments = nLineSegments + 1
  lineSegments[nLineSegments] = {
    x1 = x1,
    z1 = z1,
    x2 = x2,
    z2 = z2,
    color = color,
    alpha = alpha,
    direction = direction,
  }
end

local function ViewWorldBounds()
  local viewSizeX, viewSizeY = Spring.GetViewGeometry()

  local onlyCoords           = true
  local includeSky           = true
  local _, topLeft           = Spring.TraceScreenRay(0, viewSizeY - 1, onlyCoords, false, includeSky)
  local _, topRight          = Spring.TraceScreenRay(viewSizeX - 1, viewSizeY - 1, onlyCoords, false, includeSky)
  local _, bottomLeft        = Spring.TraceScreenRay(0, 0, onlyCoords, false, includeSky)
  local _, bottomRight       = Spring.TraceScreenRay(viewSizeX - 1, 0, onlyCoords, false, includeSky)

  local maxX                 = math.min(Game.mapSizeX, math.floor(1 + math.max(topLeft[4], topRight[4], bottomLeft[4], bottomRight[4])))
  local maxZ                 = math.min(Game.mapSizeZ, math.floor(1 + math.max(topLeft[6], topRight[6], bottomLeft[6], bottomRight[6])))
  local minX                 = math.max(0, math.floor(math.min(topLeft[4], topRight[4], bottomLeft[4], bottomRight[4])))
  local minZ                 = math.max(0, math.floor(math.min(topLeft[6], topRight[6], bottomLeft[6], bottomRight[6])))
  return math.floor(0.5 + minX / 4), math.floor(0.5 + maxX / 4), math.floor(0.5 + minZ / 4), math.floor(0.5 + maxZ / 4)
end
local previousMinX, previousMaxX, previousMinZ, previousMaxZ


local function Interpolate(value, inMin, inMax, outMin, outMax)
  -- Ensure the value is within the specified range
  value = (value < inMin) and inMin or ((value > inMax) and inMax or value)

  -- Calculate the interpolation
  return outMin + ((value - inMin) / (inMax - inMin)) * (outMax - outMin)
end

local function BuildingBordersXZ()
  local minX, maxX, minZ, maxZ = ViewWorldBounds()

  local units = Spring.GetVisibleUnits()
  local foundNewBuilding = false
  for i = 1, #units do
    local unitId = units[i]
    local unitDef = UnitDefs[Spring.GetUnitDefID(unitId)]

    if unitDef.isBuilding and not addedBuildings[unitId] then
      foundNewBuilding = true
      break
    end
  end

  local isDefaultFacing = Spring.GetBuildFacing() == 0 or Spring.GetBuildFacing() == 2

  if not foundNewBuilding
      and (previousMinX == minX and previousMaxX == maxX and previousMinZ == minZ and previousMaxZ == maxZ)
      and buildingDefId == previousBuildingDefId
      and isDefaultFacing == previousIsDefaultFacing
  then
    return
  end

  previousMinX             = minX
  previousMaxX             = maxX
  previousMinZ             = minZ
  previousMaxZ             = maxZ
  previousBuildingDefId    = buildingDefId
  previousIsDefaultFacing  = isDefaultFacing
  lineSegments             = {}
  nLineSegments            = 0

  buildingBordersXZSquares = {}
  addedBuildings           = {}
  for i = 1, #units do
    local unitId = units[i]
    local unitDef = UnitDefs[Spring.GetUnitDefID(unitId)]

    if unitDef.isBuilding and not addedBuildings[unitId] then
      AddBuilding(unitId, unitDef)
    end
  end

  local isNorthClosest = mapMouseZ < Game.mapSizeZ / 2
  local isWestClosest  = mapMouseX < Game.mapSizeX / 2

  -- log('isNorthClosest', isNorthClosest, 'isWestClosest', isWestClosest, 'mapMouseX', mapMouseX, 'mapMouseZ', mapMouseZ)
  local xStart, xDirection, xBound, zStart, zDirection, zBound
  if isNorthClosest then
    zStart     = 0
    zDirection = 1
    zBound     = maxZ
  else
    zStart     = Game.mapSizeZ
    zDirection = -1
    zBound     = minZ
  end

  if isWestClosest then
    xStart     = 0
    xDirection = 1
    xBound     = maxX / 2
  else
    xStart     = Game.mapSizeX
    xDirection = -1
    xBound     = minX / 2
  end

  log('will search', xStart, xDirection, xBound, '---', zStart, zDirection, zBound)
  -- vertical search
  if (xBound - xStart) + (zBound - zStart) > 1100 then
    log('too much map to search vertically', zStart, zDirection, maxZ)
    return
  end


  -- vertical search
  local zsize = isDefaultFacing and activeBuildingDef.zsize or activeBuildingDef.xsize
  for x = xStart, xBound, xDirection do
    local previousZLine = zStart
    for z = zStart, zBound, zDirection do
      if buildingBordersXZSquares[x] and buildingBordersXZSquares[x][z] then
        break
      elseif z == previousZLine + zDirection * zsize * 2 then
        local alpha = Interpolate(z, zStart, zBound, 0.7, 0.4)
        log('alpha', alpha)
        AddLineSegment(x * 4 - 2, z * 4 - lineOptions.width, x * 4 + 2, z * 4 + lineOptions.width, mapLineColor, alpha)
        previousZLine = z
      end
    end
  end

  -- horizontal search
  local xsize = isDefaultFacing and activeBuildingDef.xsize or activeBuildingDef.zsize
  for z = zStart, zBound, zDirection do
    local previousXLine = xStart
    for x = xStart, xBound, xDirection do
      if (buildingBordersXZSquares[x] and buildingBordersXZSquares[x][z]) then
        break
      end
      if x == previousXLine + xDirection * xsize * 2 then
        local alpha = Interpolate(x, xStart, xBound, 0.7, 0.4)
        AddLineSegment(x * 4 - lineOptions.width, z * 4 - 2, x * 4 + lineOptions.width, z * 4 + 2, mapLineColor, alpha)
        previousXLine = x
      end
    end
  end
  return true
end

function widget:Update()
  if Spring.DiffTimers(Spring.GetTimer(), previousTimer) < 2 then
    return
  end
  previousTimer = Spring.GetTimer()
  _, buildingDefId = Spring.GetActiveCommand()

  if not buildingDefId or buildingDefId >= 0 then
    return
  end

  activeBuildingDef = UnitDefs[-buildingDefId]
  if not activeBuildingDef then
    return
  end
  mapMouseX, mapMouseY, mapMouseZ = MapMousePosition()
  if BuildingBordersXZ() then
  end
  -- widgetHandler:RemoveWidget()
  linesList = gl.CreateList(DrawCreateLines)
end

function widget:DrawWorld()
  if linesList then
    gl.CallList(linesList)
  end
end
