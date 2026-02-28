function widget:GetInfo()
  return {
    name = 'building_states',
    desc = 'Manage building on/off states and bulk state control',
    author = 'tetrisface',
    date = '2025-07-14',
    license = 'GNU GPL v2 or later',
    layer = 2,
    enabled = true,
    handler = true
  }
end

local GetSelectedUnits = Spring.GetSelectedUnits
local GetUnitDefID = Spring.GetUnitDefID
local GetUnitStates = Spring.GetUnitStates
local GiveOrderToUnit = Spring.GiveOrderToUnit
local UnitDefs = UnitDefs
local CMD = CMD

-- Custom commands
local CMD_AUTO_BUILT = 28341
local CMD_FORCE_STATE = 28342

-- Auto Built modes
local AUTO_BUILT_DEFAULT = 0
local AUTO_BUILT_OFF = 1
local AUTO_BUILT_ON = 2

-- Force State modes
local FORCE_STATE_OFF = 0
local FORCE_STATE_ON = 1

local CMD_AUTO_BUILT_DESCRIPTION = {
  id = CMD_AUTO_BUILT,
  type = CMDTYPE.ICON_MODE,
  name = 'Auto Built',
  cursor = nil,
  action = 'auto_built',
  params = {AUTO_BUILT_DEFAULT, 'auto_built_default', 'auto_built_off', 'auto_built_on'}
}

local CMD_FORCE_STATE_DESCRIPTION = {
  id = CMD_FORCE_STATE,
  type = CMDTYPE.ICON_MODE,
  name = 'Force State',
  cursor = nil,
  action = 'force_state',
  params = {FORCE_STATE_OFF, 'force_state_off', 'force_state_on'}
}

-- Localization
local i18n = Spring.I18N
i18n.set('en.ui.orderMenu.' .. CMD_AUTO_BUILT_DESCRIPTION.params[2], 'Built Default')
i18n.set('en.ui.orderMenu.' .. CMD_AUTO_BUILT_DESCRIPTION.params[3], 'Built Off')
i18n.set('en.ui.orderMenu.' .. CMD_AUTO_BUILT_DESCRIPTION.params[4], 'Built On')
i18n.set(
  'en.ui.orderMenu.' .. CMD_AUTO_BUILT_DESCRIPTION.action .. '_tooltip',
  'Set default on/off state for buildings after construction'
)

i18n.set('en.ui.orderMenu.' .. CMD_FORCE_STATE_DESCRIPTION.params[2], 'Off 2')
i18n.set('en.ui.orderMenu.' .. CMD_FORCE_STATE_DESCRIPTION.params[3], 'On 2')
i18n.set(
  'en.ui.orderMenu.' .. CMD_FORCE_STATE_DESCRIPTION.action .. '_tooltip',
  'Force selected units on or off'
)

-- Global variables
local myTeamID = Spring.GetMyTeamID()
local builderUnits = {} -- [unitID] = {mode = AUTO_BUILT_*}
local canToggleBuildingDefIds = {} -- [unitDefID] = true if unit can build on/off-able buildings
local pendingBuilds = {} -- [builtUnitID] = builderID (track buildings in progress)

-- Initialize which units can build toggleable buildings
local function initializeToggleableBuildingDefs()
  canToggleBuildingDefIds = {}
  
  for unitDefID, unitDef in pairs(UnitDefs) do
    if unitDef.buildOptions and #unitDef.buildOptions > 0 then
      -- Check if any of the buildings this unit can build are toggleable
      for _, buildDefID in ipairs(unitDef.buildOptions) do
        local buildDef = UnitDefs[buildDefID]
        if buildDef and buildDef.onoffable then
          canToggleBuildingDefIds[unitDefID] = true
          break
        end
      end
    end
  end
end

-- Check if a unit can build toggleable buildings
local function canBuildToggleableBuildings(unitDefID)
  return canToggleBuildingDefIds[unitDefID] ~= nil
end

-- Create or update a builder unit entry
local function createBuilderUnit(unitID, unitDefID)
  if not canBuildToggleableBuildings(unitDefID) then
    return nil
  end

  builderUnits[unitID] = builderUnits[unitID] or {}
  builderUnits[unitID].mode = builderUnits[unitID].mode or AUTO_BUILT_DEFAULT

  return builderUnits[unitID]
end

-- Remove a builder unit
local function removeBuilderUnit(unitID)
  builderUnits[unitID] = nil
end

-- Initialize all existing builders on the team
local function initializeExistingBuilders()
  local allUnits = Spring.GetTeamUnits(myTeamID)
  for _, unitID in ipairs(allUnits) do
    local unitDefID = GetUnitDefID(unitID)
    if unitDefID and canBuildToggleableBuildings(unitDefID) then
      createBuilderUnit(unitID, unitDefID)
    end
  end
end

-- Validate and clean up builder units
local function validateBuilderUnits()
  local toRemove = {}
  for builderID, _ in pairs(builderUnits) do
    local unitDefID = GetUnitDefID(builderID)
    local unitTeam = Spring.GetUnitTeam(builderID)

    if not unitDefID or not canBuildToggleableBuildings(unitDefID) or unitTeam ~= myTeamID then
      table.insert(toRemove, builderID)
    end
  end

  for _, builderID in ipairs(toRemove) do
    removeBuilderUnit(builderID)
  end
end

-- Check if selected units have builders that can build toggleable buildings
local function checkSelectedUnits(updateMode)
  local selectedUnits = GetSelectedUnits()
  local hasBuilders = false
  local foundMode = AUTO_BUILT_DEFAULT

  for _, unitID in ipairs(selectedUnits) do
    local unitDefID = GetUnitDefID(unitID)
    if canBuildToggleableBuildings(unitDefID) then
      hasBuilders = true

      if updateMode then
        local mode = CMD_AUTO_BUILT_DESCRIPTION.params[1]
        local builderData = createBuilderUnit(unitID, unitDefID)
        if builderData then
          builderData.mode = mode
        end
      else
        createBuilderUnit(unitID, unitDefID)
        if builderUnits[unitID] and builderUnits[unitID].mode then
          foundMode = builderUnits[unitID].mode
        end
      end
    end
  end

  if not updateMode then
    CMD_AUTO_BUILT_DESCRIPTION.params[1] = foundMode
  end

  return hasBuilders
end

-- Apply on/off state to a unit
local function applyOnOffState(unitID, state)
  if state == 1 then
    GiveOrderToUnit(unitID, CMD.ON, {}, 0)
  elseif state == 0 then
    GiveOrderToUnit(unitID, CMD.OFF, {}, 0)
  end
end

-- Widget event handlers
function widget:Initialize()
  initializeToggleableBuildingDefs()

  if Spring.GetSpectatingState() or Spring.IsReplay() then
    widgetHandler:RemoveWidget()
    return
  end

  myTeamID = Spring.GetMyTeamID()

  initializeExistingBuilders()
end

function widget:CommandsChanged()
  local selectedUnits = GetSelectedUnits()
  if #selectedUnits == 0 then
    return
  end

  local hasBuilders = checkSelectedUnits(false)
  local hasOnOffable = false
  
  -- Check if any selected unit is on/off-able
  for _, unitID in ipairs(selectedUnits) do
    local unitDefID = GetUnitDefID(unitID)
    local unitDef = UnitDefs[unitDefID]
    if unitDef and unitDef.onoffable then
      hasOnOffable = true
      break
    end
  end
  
  local cmds = widgetHandler.customCommands
  if cmds then
    if hasBuilders then
      cmds[#cmds + 1] = CMD_AUTO_BUILT_DESCRIPTION
    end
    
    if hasOnOffable then
      cmds[#cmds + 1] = CMD_FORCE_STATE_DESCRIPTION
    end
  end
end

function widget:CommandNotify(cmd_id, cmd_params, cmd_options)
  if cmd_id == CMD_AUTO_BUILT then
    local mode = CMD_AUTO_BUILT_DESCRIPTION.params[1]
    mode = (mode + 1) % 3
    CMD_AUTO_BUILT_DESCRIPTION.params[1] = mode
    checkSelectedUnits(true)
    return true
  end

  if cmd_id == CMD_FORCE_STATE then
    -- Left-click without ctrl: set to ON
    -- Right-click or Ctrl+click: set to OFF
    local targetState = 1 -- default to ON
    
    if (cmd_options and cmd_options.right) or (cmd_options and cmd_options.ctrl) then
      targetState = 0 -- OFF
    end

    local selectedUnits = GetSelectedUnits()
    for _, unitID in ipairs(selectedUnits) do
      applyOnOffState(unitID, targetState)
    end

    return true
  end
end

function widget:UnitCreated(unitID, unitDefID, teamID)
  if teamID == myTeamID then
    createBuilderUnit(unitID, unitDefID)
  end
end

function widget:UnitDestroyed(unitID)
  removeBuilderUnit(unitID)
end

function widget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
  if oldTeam == myTeamID then
    removeBuilderUnit(unitID)
  elseif newTeam == myTeamID then
    createBuilderUnit(unitID, unitDefID)
  end
end

function widget:UnitTaken(unitID, unitDefID, oldTeam, newTeam)
  widget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
end

function widget:GameFrame(frameNum)
  -- Only process every 10 frames to reduce CPU usage
  if frameNum % 10 ~= 0 then
    return
  end

  validateBuilderUnits()

  -- Track buildings in progress from each builder
  for builderID, builderData in pairs(builderUnits) do
    local commands = Spring.GetUnitCommands(builderID, 100)
    if commands then
      for _, cmd in ipairs(commands) do
        -- Build commands have negative IDs
        if cmd.id < 0 then
          local builtDefID = -cmd.id
          local buildDef = UnitDefs[builtDefID]
          if buildDef and buildDef.onoffable then
            -- Find the built unit (there may be multiple, track the most recent)
            local teamUnits = Spring.GetTeamUnitsByDefs(myTeamID, {builtDefID})
            if teamUnits and #teamUnits > 0 then
              for _, builtUnitID in ipairs(teamUnits) do
                -- Only track if not already tracked and unit is still being built
                if not pendingBuilds[builtUnitID] then
                  local health = Spring.GetUnitHealth(builtUnitID)
                  local maxHealth = Spring.GetUnitMaxHealth(builtUnitID)
                  if health and maxHealth and health < maxHealth then
                    pendingBuilds[builtUnitID] = builderID
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  -- Clean up dead builders from pending builds
  local toRemove = {}
  for builtUnitID, builderID in pairs(pendingBuilds) do
    if not Spring.ValidUnitID(builderID) then
      table.insert(toRemove, builtUnitID)
    end
  end
  for _, builtUnitID in ipairs(toRemove) do
    pendingBuilds[builtUnitID] = nil
  end
end

function widget:UnitFinished(unitID, unitDefID, unitTeam)
  if unitTeam ~= myTeamID then
    return
  end

  local unitDef = UnitDefs[unitDefID]
  if not unitDef or not unitDef.onoffable then
    return
  end

  -- Look up which builder created this unit
  local builderID = pendingBuilds[unitID]
  if builderID and Spring.ValidUnitID(builderID) and builderUnits[builderID] then
    local mode = builderUnits[builderID].mode
    
    if mode == AUTO_BUILT_OFF then
      applyOnOffState(unitID, 0)
    elseif mode == AUTO_BUILT_ON then
      applyOnOffState(unitID, 1)
    end
  end

  -- Clean up
  pendingBuilds[unitID] = nil
end

function widget:GetConfigData()
  return {
    builderSettings = builderUnits
  }
end

function widget:SetConfigData(data)
  if data.builderSettings then
    builderUnits = data.builderSettings
  end
end
