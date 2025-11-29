function widget:GetInfo()
	return {
		desc = '',
		author = 'tetrisface',
		version = '',
		date = 'May, 2024',
		name = 'Auto Unit Settings',
		license = '',
		layer = -99990,
		enabled = true
	}
end

VFS.Include('LuaUI/Widgets/helpers.lua')
VFS.Include('luaui/Headers/keysym.h.lua')

local antis = {
	[UnitDefNames['armamd'].id] = true,
	[UnitDefNames['armscab'].id] = true,
	[UnitDefNames['corfmd'].id] = true,
	[UnitDefNames['cormabm'].id] = true
}
if UnitDefNames['legabm'] then
	antis[UnitDefNames['legabm'].id] = true
end
local lraa = {
	[UnitDefNames['corscreamer'].id] = true,
	[UnitDefNames['armmercury'].id] = true
}
local assistDrones = {
	[UnitDefNames['armassistdrone'].id] = true,
	[UnitDefNames['corassistdrone'].id] = true,
	[UnitDefNames['legassistdrone'].id] = true
}

local cmdFly = 145

local myTeamId = Spring.GetMyTeamID()
local isFactoryDefIds = {}
local reclaimerDefIds = {}
local resurrectorDefIds = {}
local areaReclaimParams = {}
local waitReclaimUnits = {}

-- Command recording feature
local CMD_TYPE_RECORD = 28344
local CMD_TYPE_RECORD_DESCRIPTION = {
	id = CMD_TYPE_RECORD,
	type = (CMDTYPE or {ICON_MODE = 5}).ICON_MODE,
	name = 'Type Record',
	cursor = nil,
	action = 'type_record',
	params = {0, 'type_record_off', 'type_record_on'}
}

local RECORDING_ENABLED = {} -- [unitDefID] = true/false
local RECORDED_COMMANDS = {} -- [unitDefID] = {sequence of commands}
local PENDING_APPLICATIONS = {} -- [unitID] = {frame, unitDefID} for delayed application

-- Apply recorded commands to a unit
local function applyRecordedCommands(unitID, unitDefID)
	if not Spring.ValidUnitID(unitID) then
		return
	end
	
	local recorded = RECORDED_COMMANDS[unitDefID]
	if not recorded or #recorded == 0 then
		return
	end
	
	-- Build command array: STOP first, then recorded commands
	local cmdArray = {{CMD.STOP, {}, {}}}
	for i = 1, #recorded do
		local cmd = recorded[i]
		-- Convert options table to options array format
		local options = {}
		if cmd.options then
			if cmd.options.alt then
				table.insert(options, 'alt')
			end
			if cmd.options.ctrl then
				table.insert(options, 'ctrl')
			end
			if cmd.options.shift then
				table.insert(options, 'shift')
			end
			if cmd.options.right then
				table.insert(options, 'right')
			end
		end
		table.insert(cmdArray, {cmd.id, cmd.params or {}, options})
	end
	
	Spring.GiveOrderArrayToUnit(unitID, cmdArray)
end

local function isFriendlyFiringDef(def)
	return not (def.name == 'armthor' or def.name == 'armassimilator' or def.name:find 'corkarganeth' or
		def.name:find 'legpede' or
		def.name:find 'legkeres')
end

local function isT3AirAide(def)
	return def.name:find 't3airaide'
end

local function isReclaimerUnit(def)
	local isReclaimer =
		(def.canResurrect or def.canReclaim) and
		not (def.name:match '^armcom.*' or def.name:match '^corcom.*' or def.name:match '^legcom.*' or def.name == 'armthor' or
			(def.customParams and def.customParams.iscommander)) and
		not (def.buildOptions and def.buildOptions[1] ~= nil)

	-- if isReclaimer then
	--   log(
	--     def.translatedHumanName,
	--     'reclaimer',
	--     isReclaimer,
	--     not (def.buildOptions and #def.buildOptions > 0),
	--     def.buildOptions
	--   )
	-- end
	return isReclaimer
end

function widget:Initialize()
	myTeamId = Spring.GetMyTeamID()
	isFactoryDefIds = {}
	reclaimerDefIds = {}
	resurrectorDefIds = {}
	areaReclaimParams = {}
	waitReclaimUnits = {}
	RECORDING_ENABLED = {}
	RECORDED_COMMANDS = {}
	PENDING_APPLICATIONS = {}

	if Spring.GetSpectatingState() or Spring.IsReplay() then
		widgetHandler:RemoveWidget()
	end

	for unitDefID, unitDef in pairs(UnitDefs) do
		if
			unitDef.isFactory and
				not (unitDef.name:match '^armcom.*' or unitDef.name:match '^corcom.*' or unitDef.name:match '^legcom.*')
		 then
			isFactoryDefIds[unitDefID] = true
		-- log('add factory: ', unitDef.translatedHumanName)
		end

		if isReclaimerUnit(unitDef) then
			reclaimerDefIds[unitDefID] = true
			table.insert(resurrectorDefIds, unitDefID)
		-- log('add ressurector: ', unitDef.translatedHumanName)
		end
	end
end

function widget:UnitFromFactory(unitID, unitDefID, unitTeam)
	widget:UnitFinished(unitID, unitDefID, unitTeam)
end

function widget:UnitCreated(unitID, unitDefID, unitTeam, builderID)
	if unitTeam ~= myTeamId then
		return
	end
	
	-- Apply recorded commands if available
	applyRecordedCommands(unitID, unitDefID)
end

-- function widget:UnitFinished(unitID, unitDefID, unitTeam)
--   if unitTeam ~= myTeamId then
--     return
--   end

--   local def = UnitDefs[unitDefID]

--   if not isFriendlyFiringDef(def) then
--     Spring.GiveOrderToUnit(unitID, CMD.FIRE_STATE, { 2 }, 0)
--     Spring.GiveOrderToUnit(unitID, CMD.REPEAT, { 0 }, 0)
--   end
-- end

function widget:UnitFinished(unitID, unitDefID, unitTeam)
	if unitTeam ~= myTeamId then
		return
	end

	-- Apply recorded commands if available
	applyRecordedCommands(unitID, unitDefID)
	
	-- Schedule delayed application (+2 frames)
	local currentFrame = Spring.GetGameFrame()
	PENDING_APPLICATIONS[unitID] = {frame = currentFrame + 2, unitDefID = unitDefID}

	-- log('created', UnitIdUnitDef(unitID).translatedHumanName, unitID)

	local def = UnitDefs[unitDefID]

	-- evocom + thor fix
	if def.name == 'armthor' or def.name:find '^armcom.*' or def.name:find '^corcom.*' or def.name:find '^legcom.*' then
		Spring.GiveOrderToUnit(unitID, CMD.REPEAT, {0}, 0)
		return
	end
	if not isFriendlyFiringDef(def) then
		Spring.GiveOrderToUnit(unitID, CMD.FIRE_STATE, {2}, 0)
	end

	if isT3AirAide(def) or assistDrones[unitDefID] then
		Spring.GiveOrderToUnit(unitID, cmdFly, {0}, 0)
		if assistDrones[unitDefID] then
			Spring.GiveOrderToUnit(unitID, CMD.REPEAT, {1}, 0)
		end
		return
	end

	if isFactoryDefIds[unitDefID] then
		local cmdTable = {
			{CMD.MOVE_STATE, {0}, {}},
			{CMD.REPEAT, {0}, {}}
		}

		if
			(def.translatedHumanName:lower():find('aircraft', 1, true) or def.translatedHumanName:lower():find('gantry', 1, true) or
				def.translatedHumanName:lower():find('experimental', 1, true)) and
				not def.name == 'corapt3'
		 then
			table.insert(cmdTable, {CMD.FIRE_STATE, {0}, {}})
		-- log('adding aircraft factory: ', def.translatedHumanName)
		end
		-- log('Repeating 1', def.translatedHumanName)
		Spring.GiveOrderArrayToUnitArray({unitID}, cmdTable)
	elseif reclaimerDefIds[unitDefID] and #areaReclaimParams > 0 and isReclaimerUnit(def) then
		-- log('setting repeat', def.translatedHumanName)
		-- log('Repeating 2', def.translatedHumanName)
		Spring.GiveOrderToUnit(unitID, CMD.REPEAT, {1}, 0)
		waitReclaimUnits[unitID] = 1
	-- elseif vehicleCons[unitDefID] then
	--   Spring.GiveOrderToUnit(unitID, CMD.REPEAT, { 1 }, 0)
	end

	if def.canStockpile and not lraa[unitDefID] and def.isBuilding and unitID ~= nil and type(unitID) == 'number'
	and not def.name:find 'Launcher'
	 then
		Spring.GiveOrderToUnit(unitID, CMD.REPEAT, {1}, 0)
		Spring.GiveOrderToUnit(unitID, CMD.STOCKPILE, {}, {'ctrl', 'shift', 'right'})
		Spring.GiveOrderToUnit(unitID, CMD.STOCKPILE, {}, 0)
		if (def.customparams and def.customparams.unitgroup == 'antinuke') or antis[unitDefID] then
			Spring.GiveOrderToUnit(unitID, CMD.STOCKPILE, {}, CMD.OPT_SHIFT)
			Spring.GiveOrderToUnit(unitID, CMD.STOCKPILE, {}, 0)
		end
	end
end

function widget:UnitGiven(unitID, unitDefID, unitTeam, oldTeam)
	widget:UnitFinished(unitID, unitDefID, unitTeam)
end

function widget:UnitTaken(unitID, unitDefID, unitTeam, oldTeam)
	widget:UnitFinished(unitID, unitDefID, unitTeam)
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
	PENDING_APPLICATIONS[unitID] = nil
end

function widget:GameFrame(gameFrame)
	-- if gameFrame >= 100 and not isCommanderRepeatChecked then
	-- set commander repeat on
	-- local units = Spring.GetTeamUnits(myTeamId)
	-- for i = 1, #units do
	-- local unitID = units[i]
	-- if unitID and UnitIdDef(unitID).customParams and UnitIdDef(unitID).customParams.iscommander then
	-- Spring.GiveOrderToUnit(unitID, CMD.REPEAT, { 1 }, 0)
	-- end
	-- end
	-- isCommanderRepeatChecked = true
	-- end

	-- Handle delayed command application (+2 frames after UnitFinished)
	for unitID, pending in pairs(PENDING_APPLICATIONS) do
		if gameFrame >= pending.frame then
			-- Check if unit still exists
			if Spring.ValidUnitID(unitID) then
				applyRecordedCommands(unitID, pending.unitDefID)
			end
			PENDING_APPLICATIONS[unitID] = nil
		end
	end

	if gameFrame % 30 == 0 then
		if #areaReclaimParams > 1 then
			for unitId, _ in pairs(waitReclaimUnits) do
				if waitReclaimUnits[unitId] ~= 1 then
					-- log('waiting', unitId)
					waitReclaimUnits[unitId] = 2
				else
					if select(5, Spring.GetUnitHealth(unitId)) == 1 then
						Spring.GiveOrderToUnit(unitId, CMD.STOP, {}, 0)
						Spring.GiveOrderToUnit(unitId, CMD.RECLAIM, areaReclaimParams, {}, 0)
						waitReclaimUnits[unitId] = nil
					-- log('Repeating 3', UnitIdUnitDef(unitId).translatedHumanName)
					end
				end
			end

			local idleResurrectors = Spring.GetTeamUnitsByDefs(myTeamId, resurrectorDefIds)
			for i = 1, #idleResurrectors do
				local unitId = idleResurrectors[i]
				local commands = Spring.GetUnitCommands(unitId, 2)
				if
					isReclaimerUnit(UnitDefs[Spring.GetUnitDefID(unitId)]) and
						(#commands == 0 or
							(#commands == 1 and commands[1].id == CMD.MOVE and select(4, Spring.GetUnitVelocity(unitId)) < 0.02))
				 then
					-- log('Repeating 4', UnitIdUnitDef(unitId).translatedHumanName)
					Spring.GiveOrderToUnit(unitId, CMD.REPEAT, {1}, 0)
					Spring.GiveOrderToUnit(unitId, CMD.RECLAIM, areaReclaimParams, {})
				-- log('ordering reclaim idle', unitId, areaReclaimParams[1], areaReclaimParams[2], areaReclaimParams[3], areaReclaimParams[4])
				end
			end
		end
	end
end

function widget:CommandsChanged()
	local selectedUnits = Spring.GetSelectedUnits()
	if #selectedUnits == 0 then
		return
	end
	
	-- Check if any selected unit has recording enabled
	local found_mode = 0
	for _, unitID in ipairs(selectedUnits) do
		local unitDefID = Spring.GetUnitDefID(unitID)
		if RECORDING_ENABLED[unitDefID] then
			found_mode = 1
			break
		end
	end
	CMD_TYPE_RECORD_DESCRIPTION.params[1] = found_mode
	
	-- Show command if we have selected units
	widgetHandler.customCommands[#widgetHandler.customCommands + 1] = CMD_TYPE_RECORD_DESCRIPTION
end

function widget:CommandNotify(cmdID, cmdParams, cmdOptions)
	-- Handle Type Record toggle
	if cmdID == CMD_TYPE_RECORD then
		local mode = CMD_TYPE_RECORD_DESCRIPTION.params[1]
		local newMode = (mode + 1) % 2
		CMD_TYPE_RECORD_DESCRIPTION.params[1] = newMode
		
		-- Enable/disable recording for all selected unitdefids
		local selectedUnits = Spring.GetSelectedUnits()
		local unitDefIDs = {}
		for _, unitID in ipairs(selectedUnits) do
			local unitDefID = Spring.GetUnitDefID(unitID)
			if not unitDefIDs[unitDefID] then
				unitDefIDs[unitDefID] = true
				if newMode == 1 then
					RECORDING_ENABLED[unitDefID] = true
					-- Clear old recording when starting new one
					RECORDED_COMMANDS[unitDefID] = {}
				else
					RECORDING_ENABLED[unitDefID] = false
				end
			end
		end
		
		return true
	end
	
	-- Capture commands when recording is active
	local selectedUnits = Spring.GetSelectedUnits()
	if #selectedUnits == 0 then
		return false
	end
	
	-- Check if any selected unit's unitdefid has recording enabled
	local recordingUnitDefIDs = {}
	for _, unitID in ipairs(selectedUnits) do
		local unitDefID = Spring.GetUnitDefID(unitID)
		if RECORDING_ENABLED[unitDefID] then
			recordingUnitDefIDs[unitDefID] = true
		end
	end
	
	if next(recordingUnitDefIDs) then
		-- Record command for all enabled unitdefids
		-- Create a separate copy for each unitdefid to avoid reference issues
		for unitDefID, _ in pairs(recordingUnitDefIDs) do
			if not RECORDED_COMMANDS[unitDefID] then
				RECORDED_COMMANDS[unitDefID] = {}
			end
			local cmdToRecord = {
				id = cmdID,
				params = cmdParams and {unpack(cmdParams)} or {},
				options = cmdOptions and {
					alt = cmdOptions.alt or false,
					ctrl = cmdOptions.ctrl or false,
					shift = cmdOptions.shift or false,
					right = cmdOptions.right or false
				} or {}
			}
			table.insert(RECORDED_COMMANDS[unitDefID], cmdToRecord)
		end
	end
	
	return false -- Don't block the command
end

function widget:KeyPress(key, mods, isRepeat)
	if key == KEYSYMS.E and mods['alt'] and not mods['shift'] and not mods['ctrl'] then
		local selectedUnitIds = Spring.GetSelectedUnits()
		if not selectedUnitIds or #selectedUnitIds == 0 then
			areaReclaimParams = {}
			return
		end

		local unitId = selectedUnitIds[1]
		local commands = Spring.GetUnitCommands(unitId, 20)
		for i = 1, #commands do
			local cmd = commands[i]
			if cmd.id == CMD.RECLAIM and #cmd.params == 4 then
				areaReclaimParams = cmd.params
			end
		end
	end
end
