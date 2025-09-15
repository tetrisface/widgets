function widget:GetInfo()
  return {
    name = 'Animated Pacman',
    desc = 'CTRL+SHIFT+ALT+T to toggle. ALT+click and drag to start eating markers with line-drawn Pacman!',
    author = 'AI Assistant',
    date = '2025-01-13',
    license = 'MIT',
    layer = 0,
    enabled = false
  }
end

------------------------------------------------------------------------------------------
-- User Preferences
------------------------------------------------------------------------------------------
local pacmanSpeed = 32 -- units per second
local pacmanSize = 166 -- radius in game units
local eraseRadius = 8 -- radius for marker erasing
local mouthAnimSpeed = 1/3 -- mouth open/close cycles per second (6 frames per cycle at 1 FPS)

------------------------------------------------------------------------------------------
-- State Variables
------------------------------------------------------------------------------------------
local widgetActive = true -- Global toggle for the entire widget
local clickState = 'waiting' -- "waiting", "setting_direction", "running"
local startPos = nil
local direction = nil
local currentPos = nil
local pacmanTimer = 0
local mouthTimer = 0
local mouthOpen = 0 -- 0 to 1, how open the mouth is
local draggingDirection = false
local lastPacmanLines = {} -- Store lines from last Pacman draw for cleanup
local customTimer = 0 -- Custom timer for controlling update rate
local updateInterval = 1 -- 1 FPS (every 1 second)

------------------------------------------------------------------------------------------
-- Utility Functions
------------------------------------------------------------------------------------------

-- Convert screen coordinates to world coordinates
local function ScreenToWorld(mx, my)
  local _, pos = Spring.TraceScreenRay(mx, my, true)
  return pos
end

-- Normalize a vector
local function Normalize(x, z)
  local len = math.sqrt(x * x + z * z)
  if len > 0 then
    return x / len, z / len
  end
  return 0, 0
end

------------------------------------------------------------------------------------------
-- Pacman Animation & Drawing (Line-Based)
------------------------------------------------------------------------------------------

-- Define Pacman shape as line segments
local function GetPacmanLines(centerX, centerZ, directionAngle, mouthOpenRatio)
  local lines = {}
  local segments = 12
  local mouthAngle = mouthOpenRatio * math.pi * 0.8 -- Max 144 degree mouth (more visible)
  local radius = pacmanSize

  -- Calculate mouth direction (facing direction)
  local mouthDirX = math.cos(directionAngle)
  local mouthDirZ = math.sin(directionAngle)

  for i = 0, segments - 1 do
    local segmentAngle = (i / segments) * 2 * math.pi

    -- Calculate angle relative to mouth direction
    local relativeAngle = segmentAngle - directionAngle
    while relativeAngle > math.pi do
      relativeAngle = relativeAngle - 2 * math.pi
    end
    while relativeAngle < -math.pi do
      relativeAngle = relativeAngle + 2 * math.pi
    end

    -- Only draw segments outside the mouth area
    if math.abs(relativeAngle) > mouthAngle then
      local nextSegment = ((i + 1) % segments) / segments * 2 * math.pi
      local nextRelativeAngle = nextSegment - directionAngle
      while nextRelativeAngle > math.pi do
        nextRelativeAngle = nextRelativeAngle - 2 * math.pi
      end
      while nextRelativeAngle < -math.pi do
        nextRelativeAngle = nextRelativeAngle + 2 * math.pi
      end

      -- Only draw if next segment is also outside mouth
      if math.abs(nextRelativeAngle) > mouthAngle then
        local x1 = centerX + math.cos(segmentAngle) * radius
        local z1 = centerZ + math.sin(segmentAngle) * radius
        local x2 = centerX + math.cos(nextSegment) * radius
        local z2 = centerZ + math.sin(nextSegment) * radius

        table.insert(lines, {x1, z1, x2, z2})
      end
    end
  end

  -- Add mouth closing lines (always visible when moving, but varies with animation)
  if mouthOpenRatio > 0.05 then  -- Lower threshold so mouth is always visible
    -- Draw mouth lines from center to the edges of the mouth opening
    -- The mouth should be at the front (in the direction Pacman is facing)
    local mouthLeftX = centerX + math.cos(directionAngle + mouthAngle) * radius
    local mouthLeftZ = centerZ + math.sin(directionAngle + mouthAngle) * radius
    local mouthRightX = centerX + math.cos(directionAngle - mouthAngle) * radius
    local mouthRightZ = centerZ + math.sin(directionAngle - mouthAngle) * radius

    -- Draw lines from center to mouth edges
    table.insert(lines, {centerX, centerZ, mouthLeftX, mouthLeftZ})
    table.insert(lines, {centerX, centerZ, mouthRightX, mouthRightZ})

    -- Also draw a connecting line between the mouth edges for better visibility
    table.insert(lines, {mouthLeftX, mouthLeftZ, mouthRightX, mouthRightZ})

    -- Debug: Show mouth is being drawn
    if math.floor(mouthTimer * 10) % 20 == 0 then  -- Debug every 2 seconds at 1 FPS
      Spring.Echo(string.format("[Pacman] Mouth angle: %.2f radians (%.1f degrees)", mouthAngle, math.deg(mouthAngle)))
    end
  end

  return lines
end

local function DrawPacmanLines(centerX, centerZ, directionAngle, mouthOpenRatio)
  -- Clear previous Pacman lines
  for _, line in ipairs(lastPacmanLines) do
    Spring.MarkerErasePosition(line[1], 100, line[2]) -- Erase start point
    Spring.MarkerErasePosition(line[3], 100, line[4]) -- Erase end point
  end

  -- Get new Pacman lines
  local lines = GetPacmanLines(centerX, centerZ, directionAngle, mouthOpenRatio)
  lastPacmanLines = {}

  -- Draw new Pacman lines
  for _, line in ipairs(lines) do
    local x1, z1, x2, z2 = line[1], line[2], line[3], line[4]
    Spring.MarkerAddLine(x1, 100, z1, x2, 100, z2)
    table.insert(lastPacmanLines, {x1, z1, x2, z2})
  end

  -- Debug: Show line count occasionally
  if #lines > 0 and math.floor(mouthTimer * 10) % 20 == 0 then  -- Debug every 2 seconds at 1 FPS
    Spring.Echo(string.format("[Pacman] Drew %d lines (body + mouth)", #lines))
  end
end

local function UpdatePacman()
  if clickState ~= 'running' or not currentPos or not direction then
    return
  end

  -- Update mouth animation (using custom timer for mouth animation)
  mouthTimer = mouthTimer + updateInterval * mouthAnimSpeed
  mouthOpen = (math.sin(mouthTimer * math.pi) + 1) * 0.5 -- 0 to 1

  -- Debug: Show mouth animation values every few frames
  if math.floor(mouthTimer * 10) % 20 == 0 then  -- Debug every 2 seconds at 1 FPS
    Spring.Echo(string.format("[Pacman] Mouth: %.2f, Timer: %.2f, Direction: %.1f°", mouthOpen, mouthTimer, math.deg(math.atan2(direction.z, direction.x))))
  end

  -- Move pacman (using update interval for consistent movement)
  local moveDistance = updateInterval * pacmanSpeed

  currentPos.x = currentPos.x + direction.x * moveDistance
  currentPos.z = currentPos.z + direction.z * moveDistance

  -- Calculate direction angle for drawing
  local directionAngle = math.atan2(direction.z, direction.x)

  -- Draw Pacman at new position
  DrawPacmanLines(currentPos.x, currentPos.z, directionAngle, mouthOpen)

  -- Erase markers in path
  EraseMarkersAt(currentPos.x, currentPos.z)
end

function EraseMarkersAt(worldX, worldZ)
  -- Get ground height for the Y coordinate
  local worldY = Spring.GetGroundHeight(worldX, worldZ)

  -- Erase markers in a radius around the pacman
  for dx = -eraseRadius, eraseRadius, 8 do
    for dz = -eraseRadius, eraseRadius, 8 do
      local distance = math.sqrt(dx * dx + dz * dz)
      if distance <= eraseRadius then
        Spring.MarkerErasePosition(worldX + dx, worldY, worldZ + dz)
      end
    end
  end
end

------------------------------------------------------------------------------------------
-- Mouse Handling
------------------------------------------------------------------------------------------

function widget:MousePress(mx, my, button)
  if not widgetActive then
    return false
  end

  if button == 1 then -- Left mouse button
    local altPressed = Spring.GetKeyState(308) -- ALT key
    local ctrlPressed = Spring.GetKeyState(306) -- CTRL key

    local pos = ScreenToWorld(mx, my)
    if not pos then
      return false
    end

    if ctrlPressed then
      -- CTRL + click: Stop Pacman
      if clickState == 'running' then
        -- Clear all Pacman lines when stopping
        for _, line in ipairs(lastPacmanLines) do
          Spring.MarkerErasePosition(line[1], 100, line[2])
          Spring.MarkerErasePosition(line[3], 100, line[4])
        end
        lastPacmanLines = {}

        clickState = 'waiting'
        startPos = nil
        direction = nil
        currentPos = nil
        customTimer = 0 -- Reset custom timer
        Spring.Echo('[Pacman] Stopped eating!')
        return true
      end
    elseif altPressed then
      -- ALT + click: Start setting direction
      startPos = {x = pos[1], z = pos[3]}
      draggingDirection = true
      clickState = 'setting_direction'
      Spring.Echo('[Pacman] Setting direction... release to start!')
      return true
    end
  end

  return false
end

function widget:MouseMove(mx, my, dx, dy, button)
  if not widgetActive then
    return
  end

  if button == 1 and draggingDirection and startPos then
    -- Update direction while dragging
    local pos = ScreenToWorld(mx, my)
    if pos then
      local endPos = {x = pos[1], z = pos[3]}
      local dx = endPos.x - startPos.x
      local dz = endPos.z - startPos.z

      if math.abs(dx) > 1 or math.abs(dz) > 1 then
        direction = {}
        direction.x, direction.z = Normalize(dx, dz)
      end
    end
  end
end

function widget:MouseRelease(mx, my, button)
  if not widgetActive then
    return false
  end

  if button == 1 and draggingDirection then
    -- Finish setting direction and start Pacman
    draggingDirection = false

    if direction and startPos then
      currentPos = {x = startPos.x, z = startPos.z}
      clickState = 'running'
      pacmanTimer = 0
      mouthTimer = 0
      customTimer = 0 -- Reset custom timer for consistent updates
      Spring.Echo('[Pacman] Started eating! CTRL+click to stop.')
      return true
    else
      clickState = 'waiting'
      startPos = nil
      Spring.Echo('[Pacman] Direction too small. Try dragging further.')
    end
  end
  return false
end

function widget:KeyPress(key, mods, isRepeat)
  -- CTRL+SHIFT+ALT+T to toggle the widget
  if key == 116 and mods.ctrl and mods.shift and mods.alt then -- T key
    -- Stop any running Pacman first
    if clickState == 'running' then
      -- Clear all Pacman lines when stopping
      for _, line in ipairs(lastPacmanLines) do
        Spring.MarkerErasePosition(line[1], 100, line[2])
        Spring.MarkerErasePosition(line[3], 100, line[4])
      end
      lastPacmanLines = {}
      clickState = 'waiting'
      startPos = nil
      direction = nil
      currentPos = nil
      customTimer = 0 -- Reset custom timer
    end

    -- Toggle widget active state
    widgetActive = not widgetActive

    if widgetActive then
      Spring.Echo('[Pacman] Widget enabled! 1 FPS animation (6 frames per mouth cycle) ready!')
    else
      Spring.Echo('[Pacman] Widget disabled! Press CTRL+SHIFT+ALT+T to re-enable.')
    end

    return true
  end

  return false
end

-- No GL drawing - everything uses map markers and lines!

------------------------------------------------------------------------------------------
-- Widget Lifecycle
------------------------------------------------------------------------------------------

function widget:Initialize()
  Spring.Echo('[Pacman] Widget enabled! 1 FPS animation (6 frames per mouth cycle). CTRL+SHIFT+ALT+T to toggle. ALT+click and drag to start eating! CTRL+click to stop.')
end

function widget:DrawScreen()
  if not widgetActive then
    return
  end

  -- Draw instruction text
  if clickState == 'setting_direction' and startPos then
    local vsx, vsy = gl.GetViewSizes()
    gl.Color(1, 1, 0, 1)
    gl.Text('Release to start Pacman!', vsx / 2 - 120, vsy * 0.8, 18, 'o')
  elseif clickState == 'running' then
    local vsx, vsy = gl.GetViewSizes()
    gl.Color(1, 1, 0, 1)
    gl.Text('CTRL+click to stop', vsx / 2 - 80, vsy * 0.9, 14, 'o')
  end
end

function widget:DrawWorld()
  if not widgetActive then
    return
  end

  -- Pacman drawing is handled by DrawPacmanLines() in UpdatePacman()
  -- No GL drawing needed - everything uses map markers!
end

function widget:Update(dt)
  if not widgetActive then
    return
  end

  -- Accumulate time in custom timer
  customTimer = customTimer + dt

  -- Only update when enough time has passed (1 FPS = every 1 second)
  if customTimer >= updateInterval then
    customTimer = customTimer - updateInterval -- Reset timer, keeping any overflow
    UpdatePacman()
  end
end
