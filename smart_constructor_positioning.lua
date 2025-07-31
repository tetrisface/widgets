function widget:GetInfo()
  return {
    name = 'Smart Constructor Positioning',
    desc = 'Automatically positions constructors to minimize movement during building',
    author = 'AI Assistant',
    date = '2025-07-31',
    layer = 2,
    enabled = true,
    handler = true
  }
end

local echo = Spring.Echo
local i18n = Spring.I18N
local GetSelectedUnits = Spring.GetSelectedUnits
local GetUnitDefID = Spring.GetUnitDefID
local GetUnitCommands = Spring.GetUnitCommands
local GetUnitPosition = Spring.GetUnitPosition
local GetUnitSeparation = Spring.GetUnitSeparation
local GetUnitEffectiveBuildRange = Spring.GetUnitEffectiveBuildRange
local GetUnitsInCylinder = Spring.GetUnitsInCylinder
local GetUnitIsBeingBuilt = Spring.GetUnitIsBeingBuilt
local GiveOrderToUnit = Spring.GiveOrderToUnit
local UnitDefs = UnitDefs
local CMD_MOVE = CMD.MOVE
local CMD_INSERT = CMD.INSERT

-- OpenGL imports for debug visualization
local gl = gl
local GL = GL

-- Custom command for the toggle
local CMD_SMART_POSITIONING = 28341
local CMD_SMART_POSITIONING_DESCRIPTION = {
  id = CMD_SMART_POSITIONING,
  type = CMDTYPE.ICON_MODE,
  name = 'Smart Positioning',
  cursor = nil,
  action = 'smart_positioning',
  params = {1, 'smart_positioning_off', 'smart_positioning_on'}
}

-- Localization
i18n.set('en.ui.orderMenu.' .. CMD_SMART_POSITIONING_DESCRIPTION.params[2], 'Smart Positioning Off')
i18n.set('en.ui.orderMenu.' .. CMD_SMART_POSITIONING_DESCRIPTION.params[3], 'Smart Positioning On')
i18n.set(
  'en.ui.orderMenu.' .. CMD_SMART_POSITIONING_DESCRIPTION.action .. '_tooltip',
  'Automatically position constructors for optimal building'
)

-- Settings
local SMART_POSITIONING_OFF = 0
local SMART_POSITIONING_ON = 1

-- Global variables
local myTeamID = Spring.GetMyTeamID()
local constructorUnits = {}
local constructorDefs = {}
local debugMode = true

-- Debug visualization
local debugPositions = {}

-- Initialize constructor definitions
local function initializeConstructorDefs()
  constructorDefs = {}

  for unitDefID, unitDef in pairs(UnitDefs) do
    -- Check if it's a non-air constructor that can move
    if unitDef.isBuilder and unitDef.canMove and not unitDef.isAirUnit and not unitDef.isFactory then
      constructorDefs[unitDefID] = {
        buildDistance = unitDef.buildDistance or 0,
        buildSpeed = unitDef.buildSpeed or 0
      }
    end
  end
end

-- Check if a unit is a valid constructor
local function isConstructor(unitDefID)
  return constructorDefs[unitDefID] ~= nil
end

-- Create or update a constructor unit entry
local function createConstructorUnit(unitID, unitDefID)
  if not isConstructor(unitDefID) then
    return nil
  end

  constructorUnits[unitID] = constructorUnits[unitID] or {}
  constructorUnits[unitID].mode = constructorUnits[unitID].mode or SMART_POSITIONING_ON

  if debugMode then
    echo('Added constructor ' .. unitID .. ' in SMART_POSITIONING_ON mode')
  end

  return constructorUnits[unitID]
end

-- Remove a constructor unit
local function removeConstructorUnit(unitID)
  constructorUnits[unitID] = nil
end

-- Initialize all existing constructors on the team
local function initializeExistingConstructors()
  local allUnits = Spring.GetTeamUnits(myTeamID)
  for _, unitID in ipairs(allUnits) do
    local unitDefID = GetUnitDefID(unitID)
    if unitDefID and isConstructor(unitDefID) then
      createConstructorUnit(unitID, unitDefID)
    end
  end
end

-- Validate and clean up constructor units
local function validateConstructorUnits()
  local toRemove = {}
  for constructorID, _ in pairs(constructorUnits) do
    local unitDefID = GetUnitDefID(constructorID)
    local unitTeam = Spring.GetUnitTeam(constructorID)

    if not unitDefID or not isConstructor(unitDefID) or unitTeam ~= myTeamID then
      table.insert(toRemove, constructorID)
    end
  end

  for _, constructorID in ipairs(toRemove) do
    removeConstructorUnit(constructorID)
  end
end

-- Check if unit has a move command in first or second position
local function hasEarlyMoveCommand(unitID)
  local commands = GetUnitCommands(unitID, 3)
  if not commands then
    return false
  end

  -- Check first two commands for move commands
  for i = 1, math.min(2, #commands) do
    if commands[i].id == CMD_MOVE then
      return true
    end
  end
  return false
end

-- Check if constructor is being assisted
local function isBeingAssisted(constructorID)
  local x, y, z = GetUnitPosition(constructorID)
  if not x then
    return false
  end

  -- Get current build target if any
  local currentBuildTarget = GetUnitIsBeingBuilt(constructorID)

  local nearbyUnits = GetUnitsInCylinder(x, z, 300, myTeamID)
  local assistCount = 0

  for _, unitID in ipairs(nearbyUnits) do
    if unitID ~= constructorID then
      -- Check if this unit is a builder
      local unitDefID = GetUnitDefID(unitID)
      local unitDef = UnitDefs[unitDefID]

      if unitDef and unitDef.isBuilder then
        local commands = GetUnitCommands(unitID, 10)
        if commands then
          for _, command in ipairs(commands) do
            -- Check for various assist commands
            if command.params then
              if
                (command.id == CMD.REPAIR and command.params[1] == constructorID) or
                  (command.id == CMD.GUARD and command.params[1] == constructorID) or
                  (currentBuildTarget and command.id == CMD.REPAIR and command.params[1] == currentBuildTarget)
               then
                assistCount = assistCount + 1
                break
              end
            end
          end
        end

        -- Also check if the unit is currently building the same target
        if currentBuildTarget then
          local otherBuildTarget = GetUnitIsBeingBuilt(unitID)
          if otherBuildTarget == currentBuildTarget then
            assistCount = assistCount + 1
          end
        end
      end
    end
  end

  if debugMode and assistCount > 0 then
    echo('Constructor ' .. constructorID .. ' has ' .. assistCount .. ' assisters')
  end

  return assistCount > 0
end

-- Check if constructor is standing in next building position
local function isStandingInNextBuilding(constructorID, nextBuildCommand)
  if not nextBuildCommand or not nextBuildCommand.params then
    return false
  end

  local buildeeDefID = -nextBuildCommand.id
  local buildDef = UnitDefs[buildeeDefID]

  -- Create a temporary unit at the build position to use GetUnitSeparation
  -- Since we can't create actual units, we'll use position-based calculation with building size
  local unitX, _, unitZ = GetUnitPosition(constructorID)
  local buildX, buildZ = nextBuildCommand.params[1], nextBuildCommand.params[3]

  if not unitX or not buildX then
    return false
  end

  -- Calculate distance from constructor to build position
  local distance = math.sqrt((unitX - buildX) ^ 2 + (unitZ - buildZ) ^ 2)

  -- Get building footprint for accurate collision detection
  local buildingFootprint = 32 -- Default footprint
  if buildDef then
    -- Calculate building footprint radius (convert footprint to world units)
    local xSize = (buildDef.xsize or 1) * 8 -- footprint is in 16x16 unit squares, 8 units per square
    local zSize = (buildDef.zsize or 1) * 8
    buildingFootprint = math.max(xSize, zSize) / 2 -- Use half the larger dimension as radius
  end

  -- Constructor is "standing in" the building if it's within the building's footprint
  local isInBuilding = distance <= buildingFootprint

  if debugMode then
    echo(
      'Constructor ' ..
        constructorID ..
          ' distance to build: ' ..
            distance ..
              ', building footprint: ' .. buildingFootprint .. ', in building: ' .. (isInBuilding and 'yes' or 'no')
    )
  end

  return isInBuilding
end

-- Calculate average position of build commands
local function calculateAveragePosition(commands, startIndex)
  local totalX, totalZ = 0, 0
  local count = 0

  for i = startIndex, #commands do
    local command = commands[i]
    if command.id < 0 and command.params then -- Build command
      totalX = totalX + (command.params[1] or 0)
      totalZ = totalZ + (command.params[3] or 0)
      count = count + 1
    end
  end

  if count == 0 then
    return nil
  end

  return totalX / count, totalZ / count
end

-- Find optimal position towards average while keeping next building in range
local function findOptimalPosition(constructorID, nextBuildCommand, averageX, averageZ)
  local unitX, _, unitZ = GetUnitPosition(constructorID)
  local buildX, buildZ = nextBuildCommand.params[1], nextBuildCommand.params[3]
  local buildeeDefID = -nextBuildCommand.id

  if not unitX or not buildX or not averageX then
    return nil
  end

  -- Get effective build range for this specific building
  local effectiveBuildRange = GetUnitEffectiveBuildRange(constructorID, buildeeDefID)
  if not effectiveBuildRange then
    effectiveBuildRange = constructorDefs[GetUnitDefID(constructorID)].buildDistance or 128
  end

  -- Debug output
  if debugMode then
    local constructorDefID = GetUnitDefID(constructorID)
    local baseBuildRange = constructorDefs[constructorDefID].buildDistance or 0

    echo('=== Constructor ' .. constructorID .. ' Build Range Debug ===')
    echo('  Base build distance: ' .. baseBuildRange)
    echo('  Effective build range: ' .. effectiveBuildRange)
    echo('  Building DefID: ' .. buildeeDefID)
    echo('  Constructor position: (' .. unitX .. ', ' .. unitZ .. ')')
    echo('  Build position: (' .. buildX .. ', ' .. buildZ .. ')')
    echo('  Average position: (' .. averageX .. ', ' .. averageZ .. ')')

    -- Test GetUnitSeparation if we had actual units (this won't work but shows the concept)
    local separation = GetUnitSeparation(constructorID, constructorID, false, false) -- dummy call
    if separation then
      echo('  Unit separation (self test): ' .. separation)
    end

    debugPositions[constructorID] = {
      buildPos = {x = buildX, z = buildZ},
      avgPos = {x = averageX, z = averageZ},
      range = effectiveBuildRange,
      baseRange = baseBuildRange,
      constructorPos = {x = unitX, z = unitZ}
    }
  end

  -- Calculate direction from build position towards average position
  local dirX = averageX - buildX
  local dirZ = averageZ - buildZ
  local dirLength = math.sqrt(dirX ^ 2 + dirZ ^ 2)

  if dirLength < 10 then
    return nil
  end -- Too close, no need to move

  -- Normalize direction
  dirX = dirX / dirLength
  dirZ = dirZ / dirLength

  -- Move towards average position but stay within build range
  -- Use 80% of build range to be safe
  local safeRange = effectiveBuildRange * 0.99
  local moveX = buildX + dirX * safeRange
  local moveZ = buildZ + dirZ * safeRange

  -- Check if the move position is significantly different from current position
  local moveDistance = math.sqrt((moveX - unitX) ^ 2 + (moveZ - unitZ) ^ 2)
  if moveDistance < 32 then
    return nil
  end -- Not worth moving

  return moveX, moveZ
end

-- Process smart positioning for a constructor
local function processConstructorPositioning(constructorID)
  local constructorData = constructorUnits[constructorID]
  if not constructorData or constructorData.mode == SMART_POSITIONING_OFF then
    if debugMode then
      echo('Constructor ' .. constructorID .. ' skipped: mode is OFF')
    end
    return
  end

  local unitDefID = GetUnitDefID(constructorID)
  if not isConstructor(unitDefID) then
    if debugMode then
      echo('Constructor ' .. constructorID .. ' skipped: not a valid constructor')
    end
    return
  end

  -- Get command queue
  local commands = GetUnitCommands(constructorID, 20)
  if not commands or #commands <= 2 then
    if debugMode then
      echo('Constructor ' .. constructorID .. ' skipped: queue too small (' .. (#commands or 0) .. ' commands)')
    end
    return
  end -- Need queue larger than 2

  -- Skip if already has move command in first two positions
  if hasEarlyMoveCommand(constructorID) then
    if debugMode then
      echo('Constructor ' .. constructorID .. ' skipped: already has early move command')
    end
    return
  end

  -- Check if being assisted
  if not isBeingAssisted(constructorID) then
    if debugMode then
      echo('Constructor ' .. constructorID .. ' skipped: not being assisted')
    end
    return
  end

  -- Find next build command
  local nextBuildCommand = nil
  local nextBuildIndex = nil
  for i, command in ipairs(commands) do
    if command.id < 0 then -- Build command
      nextBuildCommand = command
      nextBuildIndex = i
      break
    end
  end

  if not nextBuildCommand then
    if debugMode then
      echo('Constructor ' .. constructorID .. ' skipped: no build command found')
    end
    return
  end

  -- Check if standing in next building position
  if not isStandingInNextBuilding(constructorID, nextBuildCommand) then
    if debugMode then
      echo('Constructor ' .. constructorID .. ' skipped: not standing in next building')
    end
    return
  end

  -- Calculate average position of remaining build commands
  local averageX, averageZ = calculateAveragePosition(commands, nextBuildIndex + 1)
  if not averageX then
    if debugMode then
      echo('Constructor ' .. constructorID .. ' skipped: no remaining build commands for average')
    end
    return
  end

  -- Find optimal position
  local moveX, moveZ = findOptimalPosition(constructorID, nextBuildCommand, averageX, averageZ)
  if not moveX then
    if debugMode then
      echo('Constructor ' .. constructorID .. ' skipped: no optimal position found')
    end
    return
  end

  -- Insert move command at front of queue
  GiveOrderToUnit(constructorID, CMD_INSERT, {0, CMD_MOVE, 0, moveX, 0, moveZ}, {'alt'})

  if debugMode then
    echo('*** SMART POSITIONING ACTIVATED ***')
    echo('Moving constructor ' .. constructorID .. ' to (' .. moveX .. ', ' .. moveZ .. ')')
  end
end

-- Check if selected units have constructors
local function checkSelectedUnits(updateMode)
  local selectedUnits = GetSelectedUnits()
  local hasConstructors = false
  local foundMode = SMART_POSITIONING_ON

  for _, unitID in ipairs(selectedUnits) do
    local unitDefID = GetUnitDefID(unitID)
    if isConstructor(unitDefID) then
      hasConstructors = true

      if updateMode then
        local mode = CMD_SMART_POSITIONING_DESCRIPTION.params[1]
        local constructorData = createConstructorUnit(unitID, unitDefID)
        if constructorData then
          constructorData.mode = mode
        end
      else
        createConstructorUnit(unitID, unitDefID)
        if constructorUnits[unitID] and constructorUnits[unitID].mode then
          foundMode = constructorUnits[unitID].mode
        end
      end
    end
  end

  if not updateMode then
    CMD_SMART_POSITIONING_DESCRIPTION.params[1] = foundMode
  end

  return hasConstructors
end

-- Widget event handlers
function widget:Initialize()
  initializeConstructorDefs()

  -- Clean up if spectating
  if Spring.GetSpectatingState() or Spring.IsReplay() then
    widgetHandler:RemoveWidget()
    return
  end

  myTeamID = Spring.GetMyTeamID()
  initializeExistingConstructors()

  echo('Smart Constructor Positioning widget initialized with debug mode ON')
  echo('All constructors default to SMART_POSITIONING_ON')
  echo('Use "/luaui smartdebug" to toggle debug mode')
  echo('Use "/luaui smartinfo" to see constructor status')
end

function widget:CommandsChanged()
  if checkSelectedUnits(false) then
    local cmds = widgetHandler.customCommands
    cmds[#cmds + 1] = CMD_SMART_POSITIONING_DESCRIPTION
  end
end

function widget:CommandNotify(cmd_id, cmd_params, cmd_options)
  if cmd_id == CMD_SMART_POSITIONING then
    local mode = CMD_SMART_POSITIONING_DESCRIPTION.params[1]

    -- Check for right-click (cycle backwards)
    local nModes = #CMD_SMART_POSITIONING_DESCRIPTION.params - 1
    if cmd_options and cmd_options.shift then
      mode = (mode - 1 + nModes) % nModes
    else
      mode = (mode + 1) % nModes
    end

    CMD_SMART_POSITIONING_DESCRIPTION.params[1] = mode
    checkSelectedUnits(true)
    return true
  end
end

function widget:UnitDestroyed(unitID)
  removeConstructorUnit(unitID)
end

function widget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
  if oldTeam == myTeamID then
    removeConstructorUnit(unitID)
  elseif newTeam == myTeamID then
    createConstructorUnit(unitID, unitDefID)
  end
end

function widget:UnitCreated(unitID, unitDefID, teamID)
  if teamID == myTeamID then
    createConstructorUnit(unitID, unitDefID)
  end
end

function widget:UnitTaken(unitID, unitDefID, oldTeam, newTeam)
  if oldTeam == myTeamID then
    removeConstructorUnit(unitID)
  elseif newTeam == myTeamID then
    createConstructorUnit(unitID, unitDefID)
  end
end

function widget:GameFrame(frameNum)
  -- Only process every 15 frames to reduce CPU usage
  if frameNum % 15 ~= 0 then
    return
  end

  validateConstructorUnits()

  -- Process smart positioning for all constructors
  for constructorID, constructorData in pairs(constructorUnits) do
    if constructorData.mode and constructorData.mode == SMART_POSITIONING_ON then
      processConstructorPositioning(constructorID)
    end
  end
end

-- Debug command
function widget:TextCommand(command)
  if command == 'smartdebug' then
    debugMode = not debugMode
    echo('Smart positioning debug mode: ' .. (debugMode and 'ON' or 'OFF'))
    return true
  elseif command == 'smartinfo' then
    echo('Smart Constructor Positioning Info:')
    echo('Tracked constructors: ' .. #table.keys(constructorUnits))
    for constructorID, data in pairs(constructorUnits) do
      echo('  Constructor ' .. constructorID .. ': mode=' .. data.mode)
    end
    return true
  end
  return false
end

-- Debug drawing
function widget:DrawWorldPreUnit()
  if not debugMode then
    return
  end

  for constructorID, debugInfo in pairs(debugPositions) do
    if debugInfo and debugInfo.buildPos and debugInfo.avgPos and debugInfo.constructorPos then
      -- Draw constructor position (yellow sphere)
      gl.Color(1, 1, 0, 0.9)
      gl.PushMatrix()
      gl.Translate(
        debugInfo.constructorPos.x,
        Spring.GetGroundHeight(debugInfo.constructorPos.x, debugInfo.constructorPos.z) + 10,
        debugInfo.constructorPos.z
      )
      gl.Sphere(20, 8, false)
      gl.PopMatrix()

      -- Draw build position (red sphere)
      gl.Color(1, 0, 0, 0.8)
      gl.PushMatrix()
      gl.Translate(
        debugInfo.buildPos.x,
        Spring.GetGroundHeight(debugInfo.buildPos.x, debugInfo.buildPos.z) + 5,
        debugInfo.buildPos.z
      )
      gl.Sphere(16, 8, false)
      gl.PopMatrix()

      -- Draw average position (green sphere)
      gl.Color(0, 1, 0, 0.8)
      gl.PushMatrix()
      gl.Translate(
        debugInfo.avgPos.x,
        Spring.GetGroundHeight(debugInfo.avgPos.x, debugInfo.avgPos.z) + 5,
        debugInfo.avgPos.z
      )
      gl.Sphere(16, 8, false)
      gl.PopMatrix()

      -- Draw effective build range (blue circle)
      gl.Color(0, 0, 1, 0.3)
      gl.DrawGroundCircle(debugInfo.buildPos.x, debugInfo.buildPos.z, debugInfo.range, 32)

      -- Draw base build range for comparison (cyan circle)
      if debugInfo.baseRange and debugInfo.baseRange ~= debugInfo.range then
        gl.Color(0, 1, 1, 0.2)
        gl.DrawGroundCircle(debugInfo.buildPos.x, debugInfo.buildPos.z, debugInfo.baseRange, 32)
      end

      -- Draw line from constructor to build position
      gl.Color(1, 1, 1, 0.6)
      gl.LineWidth(2)
      gl.BeginEnd(
        GL.LINES,
        function()
          gl.Vertex(
            debugInfo.constructorPos.x,
            Spring.GetGroundHeight(debugInfo.constructorPos.x, debugInfo.constructorPos.z) + 15,
            debugInfo.constructorPos.z
          )
          gl.Vertex(
            debugInfo.buildPos.x,
            Spring.GetGroundHeight(debugInfo.buildPos.x, debugInfo.buildPos.z) + 10,
            debugInfo.buildPos.z
          )
        end
      )

      -- Draw line from build position to average position
      gl.Color(0, 1, 0, 0.6)
      gl.BeginEnd(
        GL.LINES,
        function()
          gl.Vertex(
            debugInfo.buildPos.x,
            Spring.GetGroundHeight(debugInfo.buildPos.x, debugInfo.buildPos.z) + 10,
            debugInfo.buildPos.z
          )
          gl.Vertex(
            debugInfo.avgPos.x,
            Spring.GetGroundHeight(debugInfo.avgPos.x, debugInfo.avgPos.z) + 10,
            debugInfo.avgPos.z
          )
        end
      )
      gl.LineWidth(1)
    end
  end

  gl.Color(1, 1, 1, 1)
end

function widget:GetConfigData()
  return {
    constructorSettings = constructorUnits
  }
end

function widget:SetConfigData(data)
  if data.constructorSettings then
    constructorUnits = data.constructorSettings
  end
end

-- Helper function for table.keys (if not available)
if not table.keys then
  table.keys = function(t)
    local keys = {}
    for k, _ in pairs(t) do
      table.insert(keys, k)
    end
    return keys
  end
end
