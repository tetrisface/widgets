function widget:GetInfo()
  return {
    desc = '',
    author = 'tetrisface',
    version = '',
    date = 'Oct, 2024',
    name = 'Line Drawer',
    license = '',
    layer = -99990,
    enabled = true
  }
end

VFS.Include('luaui/Headers/keysym.h.lua')

local tileSize = 192
local miniTileSize = 32

local outerRightCorner = {5 * tileSize + 4 * miniTileSize, 0}
local linesXZ = {
  -- right outer
  {{0, 0}, outerRightCorner},
  {outerRightCorner, {outerRightCorner[1], 3333}},
  -- {{outerRightCorner[1] - 2 * miniTileSize, 0}, {outerRightCorner[1], 3333}},
  -- right inner
  {{0, 2 * tileSize}, {3 * tileSize, 2 * tileSize}},
  {{3 * tileSize, 2 * tileSize}, {3 * tileSize, 3333}},
  -- left outer
  {{0, 0}, {0, -5 * tileSize - 4 * miniTileSize}},
  {{0, -5 * tileSize - 4 * miniTileSize}, {-3333, -5 * tileSize - 4 * miniTileSize}},
  -- {{0, -5 * tileSize - 2 * miniTileSize}, {-3333, -5 * tileSize - 2 * miniTileSize}},
  -- left inner
  {{-2 * tileSize, 0}, {-2 * tileSize, -3 * tileSize}},
  {{-2 * tileSize, -3 * tileSize}, {-3333, -3 * tileSize}}
  -- guns right
  -- {{2 * tileSize + 2 * miniTileSize, -3 * miniTileSize}, {5.5 * tileSize, -3 * miniTileSize}}
}

local origo
local previousOrigo
local previousUpDirection

local function determineUpDirection(topLeftPos, bottomLeftPos)
  -- Ensure valid positions; set North as default if values are missing
  if not topLeftPos or not bottomLeftPos then
    return 'North'
  end

  -- Calculate directional offsets
  local deltaX = bottomLeftPos[1] - topLeftPos[1]
  local deltaZ = bottomLeftPos[3] - topLeftPos[3]

  -- Determine upDirection based on which axis has a greater difference
  if math.abs(deltaZ) > math.abs(deltaX) then
    return (deltaZ > 0) and 'North' or 'South'
  else
    return (deltaX > 0) and 'East' or 'West'
  end
end

local function rotate(line, direction)
  local x1, z1 = line[1][1], line[1][2]
  local x2, z2 = line[2][1], line[2][2]

  -- Rotation logic based on 90-degree intervals
  if direction == 'North' then
    return {{x1, z1}, {x2, z2}}
  elseif direction == 'South' then
    return {{-x1, -z1}, {-x2, -z2}} -- Rotate 180 degrees
  elseif direction == 'East' then
    return {{z1, -x1}, {z2, -x2}} -- Rotate 90 degrees clockwise
  elseif direction == 'West' then
    return {{-z1, x1}, {-z2, x2}} -- Rotate 90 degrees counter-clockwise
  end
end

local function clampToTileSize(_origo, _tileSize)
  local x = math.floor(_origo[1] / _tileSize + 0.5) * _tileSize
  local y = _origo[2] -- Assuming we don't need to clamp the Y coordinate
  local z = math.floor(_origo[3] / _tileSize + 0.5) * _tileSize
  return {x, y, z}
end

local function PaintBase()
  local mouseX, mouseY = Spring.GetMouseState()
  _, origo = Spring.TraceScreenRay(mouseX, mouseY, true)

  if not origo then
    return
  end

  origo = clampToTileSize(origo, tileSize)

  local _, screenHeight = Spring.GetScreenGeometry()
  local _, topLeftPos = Spring.TraceScreenRay(0, screenHeight - 1, true, false, true)
  local _, bottomLeftPos = Spring.TraceScreenRay(0, 0, true)

  local upDirection = determineUpDirection(topLeftPos, bottomLeftPos)

  if previousOrigo and previousUpDirection then
    local previousRotatedLinesXZ = {}
    for _, line in ipairs(linesXZ) do
      table.insert(previousRotatedLinesXZ, rotate(line, previousUpDirection))
    end
    for _, line in ipairs(previousRotatedLinesXZ) do
      local previousOrigoX, previousOrigoY, previousOrigoZ = previousOrigo[1], previousOrigo[2], previousOrigo[3]
      local x1, z1 = line[1][1], line[1][2]
      Spring.MarkerErasePosition(previousOrigoX + x1, previousOrigoY, previousOrigoZ + z1)
      x1, z1 = line[1][1], line[1][2]
      Spring.MarkerErasePosition(previousOrigoX + x1, previousOrigoY, previousOrigoZ + z1)
    end
  end
  previousOrigo = origo
  previousUpDirection = upDirection

  local rotatedLinesXZ = {}
  for _, line in ipairs(linesXZ) do
    table.insert(rotatedLinesXZ, rotate(line, upDirection))
  end

  for _, line in ipairs(rotatedLinesXZ) do
    local origoX, origoY, origoZ = origo[1], origo[2], origo[3]
    local x1, z1 = line[1][1], line[1][2]
    local x2, z2 = line[2][1], line[2][2]
    Spring.MarkerAddLine(origoX + x1, origoY, origoZ + z1, origoX + x2, origoY, origoZ + z2)
  end
end

function widget:KeyPress(key, mods, isRepeat)
  if key == KEYSYMS.Q and mods['ctrl'] and mods['alt'] and mods['shift'] then
    PaintBase()
  end
end
