function widget:GetInfo()
	return {
		name    = "Copy orders",
		desc    = "Copies the guarded units orders with ctrl right click, or adds the orders with ctrl+shift right click",
		author  = "lov",
		date    = "September 2023",
		version = "1.1",
		license = "GNU GPL, v2 or later",
		layer   = 0,
		enabled = true,
	}
end

local CMD_STOP = CMD.STOP
local CMD_GUARD = CMD.GUARD
local spGiveOrderArrayToUnitArray = Spring.GiveOrderArrayToUnitArray
local spGetUnitCommands = Spring.GetUnitCommands
local spGetSelectedUnits = Spring.GetSelectedUnits

function widget:CommandNotify(id, params, options)
	if id ~= CMD_GUARD or not options.ctrl then
		return
	end
	local guardedUnit = params[1]

	local commands = spGetUnitCommands(guardedUnit, -1)
	if not commands then return end
	local newCommands = {}
	if not options.shift then
		newCommands[#newCommands + 1] = { CMD_STOP, 0, 0 }
	end
	for i = 1, #commands do
		local c = commands[i]
		newCommands[#newCommands + 1] = { c.id, c.params, c.options }
	end

	local selected = spGetSelectedUnits()
	spGiveOrderArrayToUnitArray(selected, newCommands)
	return true
end
