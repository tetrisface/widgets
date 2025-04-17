function widget:GetInfo()
	return {
		name = 'Reclaim Selected',
		desc = 'Reclaim selected units with nearby nano turrets',
		author = 'manshanko',
		date = '2025-04-01',
		layer = 2,
		enabled = false,
		handler = true,
	}
end

local CONFIG = {
	-- shuffle reclaim selected orders when shuffle key is held
	-- default keybind is space (32)
	shuffle_key = 32,
}

local i18n = Spring.I18N
local GetSelectedUnits = Spring.GetSelectedUnits
local GetUnitDefID = Spring.GetUnitDefID
local GetUnitPosition = Spring.GetUnitPosition
local GetUnitSeparation = Spring.GetUnitSeparation
local GetUnitsInCylinder = Spring.GetUnitsInCylinder
local GiveOrderToUnitArray = Spring.GiveOrderToUnitArray
local UnitDefs = UnitDefs
local CMD_RECLAIM = CMD.RECLAIM
local CMD_INSERT = CMD.INSERT
local CMD_OPT_SHIFT = CMD.OPT_SHIFT

local CMD_RECLAIM_SELECTED = 28329
local CMD_RECLAIM_SELECTED_DESCRIPTION = {
	id = CMD_RECLAIM_SELECTED,
	type = CMDTYPE.ICON,
	name = 'Reclaim Units',
	cursor = nil,
	action = 'reclaim_selected',
}

i18n.set('en.ui.orderMenu.' .. CMD_RECLAIM_SELECTED_DESCRIPTION.action, 'Reclaim Selected')
i18n.set('en.ui.orderMenu.' .. CMD_RECLAIM_SELECTED_DESCRIPTION.action .. '_tooltip', 'Reclaim selected units')

local NANO_DEFS = {}
local MAX_DISTANCE = 0

for unit_def_id, unit_def in pairs(UnitDefs) do
	if unit_def.isBuilder and not unit_def.canMove and not unit_def.isFactory then
		NANO_DEFS[unit_def_id] = unit_def.buildDistance
		if unit_def.buildDistance > MAX_DISTANCE then
			MAX_DISTANCE = unit_def.buildDistance
		end
	end
end

local ALT = { 'alt' }
local CMD_CACHE = { 0, CMD_RECLAIM, CMD_OPT_SHIFT, 0 }
local SHUFFLE_MODIFIER = false

local function ntNearUnit(target_unit_id)
	local pos = { GetUnitPosition(target_unit_id) }
	local units_near = GetUnitsInCylinder(pos[1], pos[3], MAX_DISTANCE, -3)
	local unit_ids = {}
	for _, id in ipairs(units_near) do
		local dist = NANO_DEFS[GetUnitDefID(id)]
		if dist ~= nil and target_unit_id ~= id then
			if dist > GetUnitSeparation(target_unit_id, id, true) then
				unit_ids[#unit_ids + 1] = id
			end
		end
	end

	return unit_ids
end

local function signalReclaim(target_unit_id)
	local unit_ids = ntNearUnit(target_unit_id)

	CMD_CACHE[4] = target_unit_id
	GiveOrderToUnitArray(unit_ids, CMD_INSERT, CMD_CACHE, ALT)
end

local function signalReclaimShuffle(target_unit_ids)
	local tasks = {}
	for i = 1, #target_unit_ids do
		local unit_ids = ntNearUnit(target_unit_ids[i])
		table.shuffle(unit_ids)
		tasks[i] = {
			num_units = #unit_ids,
			unit_ids = unit_ids,
			target_unit_id = target_unit_ids[i],
		}
	end

	local num_tasks = #tasks
	local split = num_tasks
	while num_tasks > 0 do
		for i, group in pairs(tasks) do
			local grp_unit_ids = group.unit_ids
			local num_units = group.num_units
			local take = math.ceil(math.min(math.max(4, num_units / split), num_units))
			group.num_units = group.num_units - take

			local unit_ids = {}
			for i = 1, take do
				unit_ids[i] = grp_unit_ids[num_units - i]
			end

			if group.num_units == 0 then
				tasks[i] = nil
				num_tasks = num_tasks - 1
			end

			CMD_CACHE[4] = group.target_unit_id
			GiveOrderToUnitArray(unit_ids, CMD_INSERT, CMD_CACHE, ALT)
		end
	end
end

local function handleReclaimSelected()
	local unit_ids = GetSelectedUnits()

	for _, unit_id in ipairs(unit_ids) do
		signalReclaim(unit_id)
	end
end

local function handleReclaimSelectedShuffle()
	signalReclaimShuffle(GetSelectedUnits())
end

function widget:CommandsChanged()
	local unit_ids = GetSelectedUnits()
	if #unit_ids > 0 then
		local cmds = widgetHandler.customCommands
		cmds[#cmds + 1] = CMD_RECLAIM_SELECTED_DESCRIPTION
	end
end

function widget:CommandNotify(cmd_id)
	if cmd_id == CMD_RECLAIM_SELECTED then
		if SHUFFLE_MODIFIER then
			handleReclaimSelectedShuffle()
		else
			handleReclaimSelected()
		end
	end
end

function widget:KeyPress(key, _, is_repeat)
	if key == CONFIG.shuffle_key and not is_repeat then
		SHUFFLE_MODIFIER = true
	end
end

function widget:KeyRelease(key)
	if key == CONFIG.shuffle_key then
		SHUFFLE_MODIFIER = false
	end
end

function widget:Initialize()
	widgetHandler.actionHandler:AddAction(self, 'reclaim_selected', handleReclaimSelected, nil, 'p')
	widgetHandler.actionHandler:AddAction(self, 'reclaim_selected_shuffle', handleReclaimSelectedShuffle, nil, 'p')
end

function widget:Shutdown()
	widgetHandler.actionHandler:RemoveAction(self, 'reclaim_selected', 'p')
	widgetHandler.actionHandler:RemoveAction(self, 'reclaim_selected_shuffle', 'p')
end
