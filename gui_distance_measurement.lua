function widget:GetInfo()
  return {
    name = 'Distance Measurement',
    desc = 'Measure distances on the map with Shift+B. Shows distance from selected unit to cursor or click to set measurement points.',
    author = 'Assistant',
    date = '2025',
    license = 'GNU GPL, v2 or later',
    layer = 5,
    enabled = true
  }
end

VFS.Include('luaui/Widgets/helpers.lua')

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local measurementActive = false
local startPoint = nil -- {x, y, z} when measuring point-to-point
local font

-- Speedups
local spGetMouseState = Spring.GetMouseState
local spGetModKeyState = Spring.GetModKeyState
local spTraceScreenRay = Spring.TraceScreenRay
local spGetSelectedUnits = Spring.GetSelectedUnits
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitCommands = Spring.GetUnitCommands
local spGetUnitSeparation = Spring.GetUnitSeparation
local spGetUnitsInRectangle = Spring.GetUnitsInRectangle
local spGetUnitRadius = Spring.GetUnitRadius
local spEcho = Spring.Echo
local math_sqrt = math.sqrt
local math_floor = math.floor
local math_min = math.min
local math_max = math.max
local string_format = string.format

-- OpenGL speedups
local glBeginEnd = gl.BeginEnd
local glVertex = gl.Vertex
local glColor = gl.Color
local glLineWidth = gl.LineWidth
local glDepthTest = gl.DepthTest
local GL_LINES = GL.LINES

local vsx, vsy = Spring.GetViewGeometry()

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

function widget:Initialize()
  widget:ViewResize()
end

function widget:ViewResize()
  vsx, vsy = Spring.GetViewGeometry()
  font = WG['fonts'].getFont(1, 1.2)
end

--------------------------------------------------------------------------------
-- Key handling
--------------------------------------------------------------------------------

function widget:KeyPress(key, mods, isRepeat)
  -- Check for Shift+B (key code for 'b' is 98, but let's also try KEYSYMS if available)
  local bKey = KEYSYMS and KEYSYMS.b or 98
  if key == bKey and mods.shift then
    measurementActive = not measurementActive
    if not measurementActive then
      -- Reset measurement state when turning off
      startPoint = nil
    end
    return true -- consume the key press
  end
  return false
end

--------------------------------------------------------------------------------
-- Mouse handling
--------------------------------------------------------------------------------

function widget:MousePress(x, y, button)
  if not measurementActive then
    return false
  end

  -- Left mouse button to set starting point when no unit selected
  if button == 1 then
    local selectedUnits = spGetSelectedUnits()
    if #selectedUnits == 0 then
      -- Set starting measurement point
      local _, worldPos = spTraceScreenRay(x, y, true)
      if worldPos then
        startPoint = {worldPos[1], worldPos[2], worldPos[3]}
        return true -- consume mouse press
      end
    end
  end

  return false
end

--------------------------------------------------------------------------------
-- Distance calculation
--------------------------------------------------------------------------------

local function calculateDistance(pos1, pos2)
  if not pos1 or not pos2 then
    return 0
  end

  local dx = pos1[1] - pos2[1]
  local dy = pos1[2] - pos2[2]
  local dz = pos1[3] - pos2[3]

  return math_sqrt(dx * dx + dy * dy + dz * dz)
end

local function formatDistance(distance)
  return string_format('%.2f', distance)
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

function widget:DrawWorld()
  if not measurementActive then
    return
  end

  local x, y = spGetMouseState()
  local _, cursorWorldPos = spTraceScreenRay(x, y, true)

  if not cursorWorldPos then
    return
  end

  local selectedUnits = spGetSelectedUnits()
  local startPos = nil

  if #selectedUnits > 0 then
    -- Mode 1: Line from selected unit to cursor
    local unitID = selectedUnits[1]
    local ux, uy, uz = spGetUnitPosition(unitID)
    if ux then
      startPos = {ux, uy, uz}
    end
  elseif startPoint then
    -- Mode 2: Line from set point to cursor
    startPos = startPoint
  end

  if startPos then
    -- Draw line between start point and cursor
    glLineWidth(2.0)
    glColor(1, 1, 1, 0.8) -- White with some transparency

    glBeginEnd(
      GL_LINES,
      function()
        glVertex(startPos[1], startPos[2], startPos[3])
        glVertex(cursorWorldPos[1], cursorWorldPos[2], cursorWorldPos[3])
      end
    )
  end
end

function widget:DrawScreen()
  if not measurementActive or not font then
    return
  end

  local x, y = spGetMouseState()
  local _, cursorWorldPos = spTraceScreenRay(x, y, true)

  if not cursorWorldPos then
    return
  end

  local selectedUnits = spGetSelectedUnits()
  local distance = 0
  local distanceText = ''

  if #selectedUnits > 0 then
    -- Mode 1: Distance from selected unit to cursor
    local unitID = selectedUnits[1] -- Use first selected unit
    local ux, uy, uz = spGetUnitPosition(unitID)
    if ux then
      local unitPos = {ux, uy, uz}
      distance = calculateDistance(unitPos, cursorWorldPos)
      distanceText = 'Ø ' .. formatDistance(distance)
    end
  elseif startPoint then
    -- Mode 2: Distance from set point to cursor
    distance = calculateDistance(startPoint, cursorWorldPos)
    distanceText = 'Ø ' .. formatDistance(distance)
  else
    -- Mode 2: No start point set yet
    distanceText = 'Click to set start point'
  end

  if distanceText ~= '' then
    -- Draw text next to cursor
    local textWidth = font:GetTextWidth(distanceText) * 14 -- approximate text width
    local textX = x + 44 -- offset from cursor
    local textY = y - 6

    -- Keep text on screen
    if textX + textWidth > vsx then
      textX = x - textWidth - 15
    end
    if textY < 15 then
      textY = y + 25
    end

    font:Begin()
    font:SetOutlineColor(0, 0, 0, 0.8)
    font:SetTextColor(1, 1, 1, 1)
    font:Print(distanceText, textX, textY, 14, 'o')
    font:End()
  end
end

-- function widget:Update(deltaTime)
--   -- Get currently selected units
--   local selectedUnits = spGetSelectedUnits()
--   if #selectedUnits == 0 then
--     return
--   end

--   local selectedUnitID = selectedUnits[1] -- Use first selected unit

--   -- Get queued commands for the selected unit
--   local commands = spGetUnitCommands(selectedUnitID, 1) -- Get first command only
--   if not commands or #commands == 0 then
--     return
--   end

--   local cmd = commands[1]
--   if not cmd or cmd.id >= 0 then -- Only interested in build commands (negative IDs)
--     return
--   end

--   -- Get unit positions
--   local unitX, unitY, unitZ = spGetUnitPosition(selectedUnitID)
--   if not unitX then
--     return
--   end

--   local unitPos = {unitX, unitY, unitZ}
--   local buildPos = {cmd.params[1], cmd.params[2], cmd.params[3]}

--   -- Calculate distances using different methods

--   -- 1. Simple positional calculation
--   local simpleDistance = calculateDistance(unitPos, buildPos)

--   -- 2. Effective build ranges for the queued command
--   local effectiveBuildRange = Spring.GetUnitEffectiveBuildRange(selectedUnitID, -cmd.id) -- cmd.id is negative for build commands
--   local effectiveBuildRangePatched = GetUnitEffectiveBuildRangePatched(selectedUnitID, -cmd.id)

--   -- Check if build position is within range
--   local isInRange = simpleDistance <= effectiveBuildRange
--   local isInRangePatched = simpleDistance <= effectiveBuildRangePatched

--   -- 3. Find unit at build position for GetUnitSeparation comparison
--   local unitAtBuildPos = nil
--   local searchRadius = 50 -- Small radius to find unit at exact build position
--   local minX = buildPos[1] - searchRadius
--   local maxX = buildPos[1] + searchRadius
--   local minZ = buildPos[3] - searchRadius
--   local maxZ = buildPos[3] + searchRadius

--   local unitsAtPos = spGetUnitsInRectangle(minX, minZ, maxX, maxZ)
--   for i, unitID in ipairs(unitsAtPos) do
--     if unitID ~= selectedUnitID then
--       local ux, uy, uz = spGetUnitPosition(unitID)
--       if ux then
--         local distance = calculateDistance({ux, uy, uz}, buildPos)
--         if distance <= searchRadius then
--           unitAtBuildPos = unitID
--           break -- Found a unit at/near the build position
--         end
--       end
--     end
--   end

--   -- Print the distance data (only every ~2 seconds to avoid spam)
--   if not self.lastPrintTime then
--     self.lastPrintTime = 0
--   end
--   self.lastPrintTime = self.lastPrintTime + deltaTime

--   if self.lastPrintTime >= 2.0 then
--     self.lastPrintTime = 0

--     -- Always output distance analysis for queued commands
--     spEcho("=== Queued Command Distance Analysis ===")
--     spEcho(string_format("Simple Distance to Build Pos: %.2f", simpleDistance))
--     spEcho(string_format("Effective Build Range: %.2f", effectiveBuildRange))
--     spEcho(string_format("Effective Build Range Patched: %.2f", effectiveBuildRangePatched))
--     spEcho(string_format("Range Status (Standard): %s", isInRange and "IN RANGE" or "OUT OF RANGE"))
--     spEcho(string_format("Range Status (Patched): %s", isInRangePatched and "IN RANGE" or "OUT OF RANGE"))
--     spEcho(string_format("Distance vs Standard Range: %.2f", simpleDistance - effectiveBuildRange))
--     spEcho(string_format("Distance vs Patched Range: %.2f", simpleDistance - effectiveBuildRangePatched))

--     -- GetUnitSeparation analysis with unit at build position
--     if unitAtBuildPos then
--       local unitRadius = spGetUnitRadius(selectedUnitID) or 0
--       local targetRadius = spGetUnitRadius(unitAtBuildPos) or 0

--       -- GetUnitSeparation without radii subtraction
--       local sepNoRadii = spGetUnitSeparation(unitAtBuildPos, selectedUnitID, false, false)
--       -- GetUnitSeparation with radii subtraction
--       local sepWithRadii = spGetUnitSeparation(unitAtBuildPos, selectedUnitID, false, true)

--       spEcho("")
--       spEcho("=== GetUnitSeparation Analysis ===")
--       spEcho(string_format("Unit at Build Position ID: %d", unitAtBuildPos))
--       spEcho(string_format("Selected Unit Radius: %.2f", unitRadius))
--       spEcho(string_format("Target Unit Radius: %.2f", targetRadius))
--       spEcho(string_format("GetUnitSeparation (no radii): %.2f", sepNoRadii or 0))
--       spEcho(string_format("GetUnitSeparation (with radii): %.2f", sepWithRadii or 0))
--       spEcho(string_format("Radii difference: %.2f", (sepNoRadii or 0) - (sepWithRadii or 0)))

--       -- Compare GetUnitSeparation with simple distance
--       spEcho(string_format("Simple Distance vs GetUnitSeparation (no radii): %.2f", simpleDistance - (sepNoRadii or 0)))
--       spEcho(string_format("Simple Distance vs GetUnitSeparation (with radii): %.2f", simpleDistance - (sepWithRadii or 0)))

--       -- Range checks using GetUnitSeparation
--       spEcho(string_format("GetUnitSeparation (no radii) <= Standard Range: %.1f", effectiveBuildRange - (sepNoRadii or 0)))
--       spEcho(string_format("GetUnitSeparation (with radii) <= Standard Range: %.1f", effectiveBuildRange - (sepWithRadii or 0)))
--       spEcho(string_format("GetUnitSeparation (no radii) <= Patched Range: %.1f", effectiveBuildRangePatched - (sepNoRadii or 0)))
--       spEcho(string_format("GetUnitSeparation (with radii) <= Patched Range: %.1f", effectiveBuildRangePatched - (sepWithRadii or 0)))
--     else
--       spEcho("")
--       spEcho("=== GetUnitSeparation Analysis ===")
--       spEcho("No unit found at build position for GetUnitSeparation comparison")
--     end
--   end
-- end

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------

function widget:Shutdown()
  -- Clean up any resources if needed
end
