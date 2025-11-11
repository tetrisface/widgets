function widget:GetInfo()
  return {
    name = 'Avoid Queued Buildings',
    desc = 'Prevents build commands that conflict with buildings queued by other builders.',
    author = 'tetrisface',
    date = '2025-11-01',
    layer = 0,
    enabled = true,
    handler = true
  }
end

local GetSelectedUnits = Spring.GetSelectedUnits
local GetUnitDefID = Spring.GetUnitDefID
local GetUnitTeam = Spring.GetUnitTeam
local GetMyTeamID = Spring.GetMyTeamID
local GetUnitCommands = Spring.GetUnitCommands
local GetUnitCurrentCommand = Spring.GetUnitCurrentCommand
local UnitDefs = UnitDefs

-- Command definitions
local CMD_AVOID_QUEUED = 28343
local CMD_AVOID_QUEUED_DESCRIPTION = {
  id = CMD_AVOID_QUEUED,
  type = (CMDTYPE or {ICON_MODE = 5}).ICON_MODE,
  name = 'Avoid Queued',
  cursor = nil,
  action = 'avoid_queued',
  params = {1, 'avoid_queued_off', 'avoid_queued_on'}
}

Spring.I18N.set('en.ui.orderMenu.avoid_queued_off', 'Avoid Queued Off')
Spring.I18N.set('en.ui.orderMenu.avoid_queued_on', 'Avoid Queued On')
Spring.I18N.set(
  'en.ui.orderMenu.avoid_queued_tooltip',
  'Prevents build commands that conflict with queued buildings from other builders'
)

-- State tracking
-- AVOID_QUEUED_ENABLED: builderID -> true (enabled), false (disabled), or nil (default enabled)
local AVOID_QUEUED_ENABLED = {} -- builderID -> boolean
local queuedBuilds = {} -- builderID -> {{unitDefID, x, z, facing, xsize, zsize}, ...}
local builderDefs = {} -- unitDefID -> true
local trackedBuilders = {} -- Set of builderIDs currently being tracked

-- Configuration
local UPDATE_INTERVAL = 30 -- Update every 30 frames

-- Initialize builder definitions
for uDefID, uDef in pairs(UnitDefs) do
  if uDef.isBuilder then
    builderDefs[uDefID] = true
  end
end

-- Helper function: Calculate footprint bounds accounting for facing rotation
local function calculateFootprint(x, z, xsize, zsize, facing)
  local areaX, areaZ =
    (facing == 1 or facing == 3) and zsize * 4 or xsize * 4,
    (facing == 1 or facing == 3) and xsize * 4 or zsize * 4

  return {
    x = x,
    z = z,
    minX = x - areaX / 2,
    maxX = x + areaX / 2,
    minZ = z - areaZ / 2,
    maxZ = z + areaZ / 2,
    xsize = xsize,
    zsize = zsize,
    facing = facing
  }
end

-- Helper function: Check if two building footprints overlap (even partially)
local function buildingsOverlap(footprint1, footprint2)
  return footprint1.maxX > footprint2.minX and footprint1.minX < footprint2.maxX and footprint1.maxZ > footprint2.minZ and
    footprint1.minZ < footprint2.maxZ
end

-- Helper function: Parse build command to extract building info
local function parseBuildCommand(cmdID, cmdParams)
  if type(cmdID) ~= 'number' or cmdID >= 0 then
    return nil
  end

  local buildingDefID = -cmdID
  local buildingDef = UnitDefs[buildingDefID]
  if not buildingDef or not buildingDef.xsize or not buildingDef.zsize then
    return nil
  end

  local x, y, z = tonumber(cmdParams[1]), tonumber(cmdParams[2]), tonumber(cmdParams[3])
  if not (x and y and z) then
    return nil
  end

  local facing = cmdParams[4] or 0
  local xsize, zsize = buildingDef.xsize, buildingDef.zsize

  return {
    unitDefID = buildingDefID,
    x = x,
    z = z,
    facing = facing,
    xsize = xsize,
    zsize = zsize
  }
end

-- Helper function: Check if new build conflicts with any queued builds
local function checkConflictsWithQueuedBuilds(newBuild, excludeBuilderIDs)
  local newFootprint = calculateFootprint(newBuild.x, newBuild.z, newBuild.xsize, newBuild.zsize, newBuild.facing)

  -- Create set of excluded builder IDs for fast lookup
  local excludeSet = {}
  if excludeBuilderIDs then
    for _, builderID in ipairs(excludeBuilderIDs) do
      excludeSet[builderID] = true
    end
  end

  -- Check against all queued builds from other builders
  for builderID, builds in pairs(queuedBuilds) do
    -- Skip builds from excluded builders (the ones issuing the current command)
    if not excludeSet[builderID] then
      for _, queuedBuild in ipairs(builds) do
        local queuedFootprint =
          calculateFootprint(queuedBuild.x, queuedBuild.z, queuedBuild.xsize, queuedBuild.zsize, queuedBuild.facing)

        if buildingsOverlap(newFootprint, queuedFootprint) then
          return true -- Conflict found
        end
      end
    end
  end

  return false -- No conflicts
end

-- Helper function: Update tracked builders (selected builders with build commands)
-- After initialization, we only track builders that are selected AND have a negative current command
local function updateTrackedBuilders()
  local selectedUnits = GetSelectedUnits()
  local myTeam = GetMyTeamID()

  -- Update tracking: track selected builders that are builders and have build commands
  for _, unitID in ipairs(selectedUnits) do
    if builderDefs[GetUnitDefID(unitID)] and GetUnitTeam(unitID) == myTeam then
      -- Check if builder has a build command (negative current command)
      local currentCmd = GetUnitCurrentCommand(unitID, 1)
      if currentCmd and currentCmd < 0 then
        trackedBuilders[unitID] = true
      end
    end
  end

  -- Keep existing tracked builders in the set (don't remove them, just add new ones)
  -- Clean up is done in updateQueuedBuilds
end

-- Helper function: Update queued builds for tracked builders
local function updateQueuedBuilds()
  local myTeam = GetMyTeamID()

  -- Update queued builds for all tracked builders
  for builderID, _ in pairs(trackedBuilders) do
    if GetUnitTeam(builderID) == myTeam then
      local commands = GetUnitCommands(builderID, -1) or {}
      local builds = {}

      for _, cmd in ipairs(commands) do
        if cmd.id and cmd.id < 0 then -- Build command
          local buildInfo = parseBuildCommand(cmd.id, cmd.params)
          if buildInfo then
            table.insert(builds, buildInfo)
          end
        end
      end

      if #builds > 0 then
        queuedBuilds[builderID] = builds
      else
        queuedBuilds[builderID] = nil
      end
    else
      -- Builder no longer on our team, clean up
      queuedBuilds[builderID] = nil
      trackedBuilders[builderID] = nil
    end
  end

  -- Keep all queued builds in the system (don't remove based on trackedBuilders)
  -- This allows us to check against all queued builds, not just from tracked builders
end

-- Command handling
function widget:CommandsChanged()
  local found_mode = 1
  for _, id in ipairs(GetSelectedUnits()) do
    if AVOID_QUEUED_ENABLED[id] == false then
      found_mode = 0
      break
    elseif AVOID_QUEUED_ENABLED[id] == true then
      found_mode = 1
      break
    end
    -- If nil (not set), default to 1, so found_mode stays 1
  end
  CMD_AVOID_QUEUED_DESCRIPTION.params[1] = found_mode

  -- Show command if builders are selected
  local hasBuilder = false
  for _, id in ipairs(GetSelectedUnits()) do
    if builderDefs[GetUnitDefID(id)] then
      hasBuilder = true
      break
    end
  end

  if hasBuilder then
    widgetHandler.customCommands[#widgetHandler.customCommands + 1] = CMD_AVOID_QUEUED_DESCRIPTION
  end
end

function widget:CommandNotify(cmdID, cmdParams, cmdOptions)
  -- Handle toggle command
  if cmdID == CMD_AVOID_QUEUED then
    local mode = CMD_AVOID_QUEUED_DESCRIPTION.params[1]
    CMD_AVOID_QUEUED_DESCRIPTION.params[1] = (mode + 1) % 2

    -- Update toggle state for selected builders
    local selectedUnits = GetSelectedUnits()
    for _, id in ipairs(selectedUnits) do
      if builderDefs[GetUnitDefID(id)] then
        local newMode = CMD_AVOID_QUEUED_DESCRIPTION.params[1]
        if newMode == 1 then
          AVOID_QUEUED_ENABLED[id] = true
        else
          AVOID_QUEUED_ENABLED[id] = false
        end
      end
    end

    return true
  end

  -- Handle build commands
  if type(cmdID) ~= 'number' or cmdID >= 0 then
    return false
  end

  -- Check if any selected builder has avoid_queued enabled
  local hasAvoidEnabled = false
  local issuingBuilderIDs = {}
  local selectedUnits = GetSelectedUnits()

  for _, id in ipairs(selectedUnits) do
    if builderDefs[GetUnitDefID(id)] and (AVOID_QUEUED_ENABLED[id] ~= false) then
      hasAvoidEnabled = true
      table.insert(issuingBuilderIDs, id)
    end
  end

  if not hasAvoidEnabled then
    return false -- No builders with avoid_queued enabled, allow normal execution
  end

  -- Parse the build command
  local buildInfo = parseBuildCommand(cmdID, cmdParams)
  if not buildInfo then
    return false -- Invalid build command, allow normal execution
  end

  -- Check for conflicts with queued builds
  if checkConflictsWithQueuedBuilds(buildInfo, issuingBuilderIDs) then
    -- Conflict found, block the command
    return true
  end

  -- No conflict, allow normal execution
  return false
end

-- Game frame processing
function widget:GameFrame(n)
  if n % UPDATE_INTERVAL ~= 0 then
    return
  end

  -- Update tracked builders (selected + have build command)
  updateTrackedBuilders()

  -- Update queued builds for tracked builders
  updateQueuedBuilds()
end

-- Event handlers
function widget:UnitDestroyed(unitID)
  AVOID_QUEUED_ENABLED[unitID] = nil
  queuedBuilds[unitID] = nil
  trackedBuilders[unitID] = nil
end

widget.UnitTaken = widget.UnitDestroyed

function widget:UnitGiven(unitID, unitDefID)
  -- Clean up if unit is given away or taken
  if GetUnitTeam(unitID) ~= GetMyTeamID() then
    AVOID_QUEUED_ENABLED[unitID] = nil
    queuedBuilds[unitID] = nil
    trackedBuilders[unitID] = nil
  end
end

function widget:Initialize()
  -- Initialize tracking for all team builders with queued builds
  local myTeam = GetMyTeamID()
  for _, unitID in ipairs(Spring.GetTeamUnits(myTeam)) do
    local unitDefID = GetUnitDefID(unitID)
    if builderDefs[unitDefID] then
      -- Check if builder has any build commands in queue
      local commands = GetUnitCommands(unitID, -1) or {}
      for _, cmd in ipairs(commands) do
        if cmd.id and cmd.id < 0 then
          trackedBuilders[unitID] = true
          break
        end
      end
    end
  end

  -- Initial update of queued builds for all tracked builders
  updateQueuedBuilds()
end

function widget:Shutdown()
  AVOID_QUEUED_ENABLED = {}
  queuedBuilds = {}
  trackedBuilders = {}
end
