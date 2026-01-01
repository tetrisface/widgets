function widget:GetInfo()
  return {
    name = 'commanders',
    desc = 'Automatically makes commanders d-gun enemies within range',
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
local GetUnitStockpile = Spring.GetUnitStockpile
local GetUnitStates = Spring.GetUnitStates
local GetUnitsInCylinder = Spring.GetUnitsInCylinder
local GetUnitPosition = Spring.GetUnitPosition
local GetUnitTeam = Spring.GetUnitTeam
local GetMyTeamID = Spring.GetMyTeamID
local GetMyAllyTeamID = Spring.GetMyAllyTeamID
local AreTeamsAllied = Spring.AreTeamsAllied
local GiveOrderToUnit = Spring.GiveOrderToUnit
local UnitDefs = UnitDefs
local WeaponDefs = WeaponDefs
local CMD = CMD
local activeDgunCommand = 3
local CMD_DGUN = CMD.DGUN
local CMD_REPEAT = CMD.REPEAT

-- Custom command for the setting
local CMD_AUTO_DGUN = 28340

-- Settings
local AUTO_DGUN_OFF = 0
local AUTO_DGUN_STOCKPILE_MAX = 1
local AUTO_DGUN_ALWAYS = 2

local AUTO_DGUN_DEFAULT = Spring.Utilities.Gametype.IsScavengers() and AUTO_DGUN_STOCKPILE_MAX or AUTO_DGUN_OFF

local CMD_AUTO_DGUN_DESCRIPTION = {
  id = CMD_AUTO_DGUN,
  type = CMDTYPE.ICON_MODE,
  name = 'Auto D-Gun',
  cursor = nil,
  action = 'auto_dgun',
  params = {AUTO_DGUN_DEFAULT, 'auto_dgun_off', 'auto_dgun_stockpile_max', 'auto_dgun_always'}
}

local nModes = #CMD_AUTO_DGUN_DESCRIPTION.params - 1

-- Localization
local i18n = Spring.I18N
i18n.set('en.ui.orderMenu.' .. CMD_AUTO_DGUN_DESCRIPTION.params[2], 'Auto D-Gun Off')
i18n.set('en.ui.orderMenu.' .. CMD_AUTO_DGUN_DESCRIPTION.params[3], 'Auto D-Gun Fill')
i18n.set('en.ui.orderMenu.' .. CMD_AUTO_DGUN_DESCRIPTION.params[4], 'Auto D-Gun Deplete')
i18n.set(
  'en.ui.orderMenu.' .. CMD_AUTO_DGUN_DESCRIPTION.action .. '_tooltip',
  'Automatically d-gun enemies within range'
)

-- Global variables
local myTeamID = GetMyTeamID()
local commanderDefs = {}
local commanderUnits = {}
local originalRepeatStates = {}

-- Check if a unit is a commander
local function isCommander(unitDefID)
  return commanderDefs[unitDefID] ~= nil
end

-- Save original repeat state
local function saveOriginalRepeatState(commanderID)
  local states = GetUnitStates(commanderID)
  if states then
    originalRepeatStates[commanderID] = states['repeat']
  end
end

-- Restore original repeat state
local function restoreOriginalRepeatState(commanderID)
  if originalRepeatStates[commanderID] ~= nil then
    GiveOrderToUnit(commanderID, CMD_REPEAT, {originalRepeatStates[commanderID] and 1 or 0}, 0)
    originalRepeatStates[commanderID] = nil
  end
end

-- Check if unit has repeat enabled and manage repeat state for dgun
local function manageRepeatStateForDgun(commanderID)
  local states = GetUnitStates(commanderID)
  if not states then
    return false
  end

  local currentRepeat = states['repeat']

  -- If repeat is already disabled, no need to manage it
  if not currentRepeat then
    return false
  end

  -- Save current repeat state and disable it
  saveOriginalRepeatState(commanderID)
  GiveOrderToUnit(commanderID, CMD_REPEAT, {0}, 0)
  return true
end

-- Create or update a commander unit entry
local function createCommanderUnit(unitID, unitDefID)
  if not isCommander(unitDefID) then
    return nil
  end

  commanderUnits[unitID] = commanderUnits[unitID] or {}
  commanderUnits[unitID].mode = commanderUnits[unitID].mode or AUTO_DGUN_DEFAULT

  return commanderUnits[unitID]
end

-- Remove a commander unit and clean up its state
local function removeCommanderUnit(unitID)
  if commanderUnits[unitID] then
    restoreOriginalRepeatState(unitID)
    commanderUnits[unitID] = nil
  end
  originalRepeatStates[unitID] = nil
end

-- Initialize all existing commanders on the team
local function initializeExistingCommanders()
  local allUnits = Spring.GetTeamUnits(myTeamID)
  for _, unitID in ipairs(allUnits) do
    local unitDefID = GetUnitDefID(unitID)
    if unitDefID and isCommander(unitDefID) then
      createCommanderUnit(unitID, unitDefID)
    end
  end
end

-- Validate and clean up commander units (remove dead/invalid ones)
local function validateCommanderUnits()
  local toRemove = {}
  for commanderID, _ in pairs(commanderUnits) do
    local unitDefID = GetUnitDefID(commanderID)
    local unitTeam = GetUnitTeam(commanderID)

    -- Remove if unit doesn't exist, isn't a commander, or isn't on our team
    if not unitDefID or not isCommander(unitDefID) or unitTeam ~= myTeamID then
      table.insert(toRemove, commanderID)
    end
  end

  for _, commanderID in ipairs(toRemove) do
    removeCommanderUnit(commanderID)
  end
end

-- Initialize commander unit definitions
local function initializeCommanderDefs()
  commanderDefs = {}

  for unitDefID, unitDef in pairs(UnitDefs) do
    -- Check if it's a commander using customParams.iscommander
    if unitDef.customParams and unitDef.customParams.iscommander then --and unitDef.name:find('armcom') then
      commanderDefs[unitDefID] = {
        dgunWeaponName = nil,
        dgunWeaponDef = nil,
        dgunRange = 0
      }

      -- Find the d-gun weapon
      if unitDef.weapons then
        for weaponName, weapon in ipairs(unitDef.weapons) do
          local weaponDef = WeaponDefs[weapon.weaponDef]
          if weaponDef and weaponDef.stockpile then
            commanderDefs[unitDefID].dgunWeaponName = weaponName
            commanderDefs[unitDefID].dgunWeaponDef = weaponDef
            commanderDefs[unitDefID].dgunRange = weaponDef.range
            break
          end
        end
      end
    end
  end
end

-- Get enemy units within range, sorted by health (highest first)
local function getEnemyTargetsInRange(commanderID, range)
  -- Spring.Echo('getEnemyTargetsInRange', commanderID, range)
  local x, _, z = GetUnitPosition(commanderID)
  if not x then
    return {}
  end

  local unitsInRange = GetUnitsInCylinder(x, z, range)
  local enemies = {}

  -- Spring.Echo('unitsInRange', unitsInRange)

  for _, unitID in ipairs(unitsInRange) do
    local unitTeam = GetUnitTeam(unitID)
    if unitTeam and not AreTeamsAllied(myTeamID, unitTeam) then
      -- Spring.Echo('unitTeam', unitTeam, myTeamID, AreTeamsAllied(myTeamID, unitTeam))
      local unitDefID = GetUnitDefID(unitID)
      local unitDef = UnitDefs[unitDefID]
      if unitDef then
        table.insert(
          enemies,
          {
            unitID = unitID,
            unitDefMaxHealth = unitDef.health
          }
        )
      end
    end
  end

  -- Sort by health (highest first)
  table.sort(
    enemies,
    function(a, b)
      return a.unitDefMaxHealth > b.unitDefMaxHealth
    end
  )
  -- Spring.Echo('enemies', enemies)
  return enemies
end

-- Check if commander can fire d-gun
local function canFireDgun(commanderID, commanderDefID, mode)
  local commanderDef = commanderDefs[commanderDefID]
  if not commanderDef or not commanderDef.dgunWeaponName then
    return false
  end

  local numStockpiled, numStockpileQueued = GetUnitStockpile(commanderID)

  if not numStockpiled then
    return false
  end

  if mode == AUTO_DGUN_STOCKPILE_MAX then
    -- Check if stockpile is at maximum (no more queued stockpiles)
    return numStockpiled > 0 and (not numStockpileQueued or numStockpileQueued == 0)
  elseif mode == AUTO_DGUN_ALWAYS then
    -- Check if we have any stockpile available
    return numStockpiled > 0
  end

  return false
end

-- Process auto d-gun for a commander
local function processCommanderAutoDgun(commanderID)
  -- Spring.Echo('processCommanderAutoDgun', commanderID)
  local commanderDefID = GetUnitDefID(commanderID)
  local commanderData = commanderUnits[commanderID]

  if not commanderData or not isCommander(commanderDefID) then
    return
  end

  local mode = commanderData.mode
  if mode == AUTO_DGUN_OFF then
    return
  end

  -- Skip if commander is selected and has active d-gun command (manual control)
  local selectedUnits = GetSelectedUnits()
  local isSelected = false
  for _, unitID in ipairs(selectedUnits) do
    if unitID == commanderID then
      isSelected = true
      break
    end
  end

  if isSelected then
    local activeCmd = Spring.GetActiveCommand()
    if activeCmd == activeDgunCommand then
      return
    end
  end

  local commanderDef = commanderDefs[commanderDefID]
  if not commanderDef or not commanderDef.dgunRange then
    return
  end

  -- Check if we can fire
  if not canFireDgun(commanderID, commanderDefID, mode) then
    return
  end

  -- Get enemy targets
  local enemies = getEnemyTargetsInRange(commanderID, commanderDef.dgunRange)
  if #enemies == 0 then
    return
  end

  -- Target the highest health enemy
  local target = enemies[1]

  -- Manage repeat state and give dgun order
  local needsRepeatRestore = manageRepeatStateForDgun(commanderID)

  -- Give dgun order (insert at beginning of queue)
  GiveOrderToUnit(commanderID, CMD.INSERT, {0, CMD_DGUN, CMD.OPT_CTRL, target.unitID}, {'alt'})

  -- Restore repeat state immediately - Spring's command queue will handle timing
  if needsRepeatRestore then
    restoreOriginalRepeatState(commanderID)
  end
end

-- Check if selected units have commanders
local function checkSelectedUnits(updateMode)
  local selectedUnits = GetSelectedUnits()
  local hasCommanders = false
  local foundMode = AUTO_DGUN_DEFAULT

  for _, unitID in ipairs(selectedUnits) do
    local unitDefID = GetUnitDefID(unitID)
    if isCommander(unitDefID) then
      hasCommanders = true

      if updateMode then
        local mode = CMD_AUTO_DGUN_DESCRIPTION.params[1]
        -- Ensure commander is tracked and update its mode
        local commanderData = createCommanderUnit(unitID, unitDefID)
        if commanderData then
          commanderData.mode = mode

          if mode == AUTO_DGUN_OFF then
            -- Clean up any existing orders/states
            restoreOriginalRepeatState(unitID)
          end
        end
      else
        -- Check existing mode for UI display, ensuring commander is tracked
        createCommanderUnit(unitID, unitDefID)
        if commanderUnits[unitID] and commanderUnits[unitID].mode then
          foundMode = commanderUnits[unitID].mode
        end
      end
    end
  end

  if not updateMode then
    CMD_AUTO_DGUN_DESCRIPTION.params[1] = foundMode
  end

  return hasCommanders
end

-- Widget event handlers
function widget:Initialize()
  initializeCommanderDefs()

  -- Clean up if spectating
  if Spring.GetSpectatingState() or Spring.IsReplay() then
    widgetHandler:RemoveWidget()
    return
  end

  myTeamID = GetMyTeamID()
  myAllyTeamID = GetMyAllyTeamID()

  -- Initialize all existing commanders
  initializeExistingCommanders()
end

function widget:CommandsChanged()
  if checkSelectedUnits(false) then
    local cmds = widgetHandler.customCommands
    cmds[#cmds + 1] = CMD_AUTO_DGUN_DESCRIPTION
  end
end

function widget:CommandNotify(cmd_id, cmd_params, cmd_options)
  if cmd_id == CMD_AUTO_DGUN then
    local mode = CMD_AUTO_DGUN_DESCRIPTION.params[1]

    -- Check for right-click (cycle backwards)
    if cmd_options and cmd_options.shift then
      mode = (mode - 1 + nModes) % nModes
    else
      mode = (mode + 1) % nModes
    end

    CMD_AUTO_DGUN_DESCRIPTION.params[1] = mode
    checkSelectedUnits(true)
    return true
  end
end

function widget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
  if oldTeam == myTeamID then
    -- Unit was given away from our team
    removeCommanderUnit(unitID)
  elseif newTeam == myTeamID then
    -- Unit was given to our team
    createCommanderUnit(unitID, unitDefID)
  end
end

function widget:UnitTaken(unitID, unitDefID, oldTeam, newTeam)
  widget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
end

function widget:UnitCreated(unitID, unitDefID, teamID)
  if teamID == myTeamID then
    createCommanderUnit(unitID, unitDefID)
  end
end

function widget:UnitDestroyed(unitID)
  removeCommanderUnit(unitID)
end

function widget:GameFrame(frameNum)
  -- Only process every 5 frames to reduce CPU usage
  if frameNum % 5 ~= 0 then
    return
  end

    validateCommanderUnits()
  -- Spring.Echo('GameFrame', frameNum)

  -- Process auto d-gun for all commanders
  for commanderID, commanderData in pairs(commanderUnits) do
    if commanderData.mode and commanderData.mode ~= AUTO_DGUN_OFF then
      processCommanderAutoDgun(commanderID)
    end
  end
end

function widget:GetConfigData()
  return {
    commanderSettings = commanderUnits
  }
end

function widget:SetConfigData(data)
  if data.commanderSettings then
    commanderUnits = data.commanderSettings
  end
end
