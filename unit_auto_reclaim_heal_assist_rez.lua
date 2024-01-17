function widget:GetInfo()
	return {
		name    = "Auto Reclaim/Heal/Assist/Rez",
		desc    =
		"Makes idle unselected builders automatically repair nearby damages units, reclaim nearby wrecks, assist nearby construction, and resurrect nearby units. (Gives Fight command at builder's location with \"alt\" modifier)",
		author  = "dyth68 + ChrisClark13",
		date    = "2020 + 2023",
		license = "PD", -- should be compatible with Spring
		layer   = 11,
		enabled = false
	}
end

-- Spring functions
local sp_GetUnitPosition = Spring.GetUnitPosition
local sp_GiveOrderToUnit = Spring.GiveOrderToUnit
local sp_GetMyTeamID = Spring.GetMyTeamID
local sp_GetUnitDefID = Spring.GetUnitDefID
local sp_GetUnitCommands = Spring.GetUnitCommands
local sp_IsUnitSelected = Spring.IsUnitSelected
local sp_GetUnitStates = Spring.GetUnitStates


-- initialization
local myTeamId = sp_GetMyTeamID()
local TrackedUnitsConControllers = {}

local UPDATE_FRAME = 30
local ConStack = {}

local defIDsToTrack = {}


for unitDefID, unitDef in pairs(UnitDefs) do
    if
        unitDef
		and unitDef.canReclaim
        and not unitDef.isFactory
        and not unitDef.customParams.iscommander
	then
		defIDsToTrack[unitDefID] = true
	end
end

local function deepcopy(orig)
	local orig_type = type(orig)
	local copy
	if orig_type == 'table' then
		copy = {}
		for orig_key, orig_value in next, orig, nil do
			copy[deepcopy(orig_key)] = deepcopy(orig_value)
		end
		setmetatable(copy, deepcopy(getmetatable(orig)))
	else
		copy = orig
	end
	return copy
end


local ConController = {
	unitID,
	unitDefID,
    cmdParams,

	new = function(self, unitID, unitDefID)
		self = deepcopy(self)
		self.unitID = unitID
        self.unitDefID = unitDefID
		
		TrackedUnitsConControllers[unitID] = self

		return self
	end,

	unset = function(self)
        sp_GiveOrderToUnit(self.unitID, CMD.STOP, {}, { "" }, 1)
		TrackedUnitsConControllers[self.unitID] = nil
		return nil
    end,

    handle = function(self)
		self.beingUpdated = true;

		local cmdQueue = sp_GetUnitCommands(self.unitID, 3);
		if (#cmdQueue == 0) then
			-- if the unit is not cloaked and not selected
			if (not sp_IsUnitSelected(self.unitID) and (not sp_GetUnitStates(self.unitID)["cloak"])) then
				self.cmdParams = { sp_GetUnitPosition(self.unitID) }
				sp_GiveOrderToUnit(self.unitID, CMD.FIGHT, self.cmdParams, { "alt" })
			end
		elseif self.cmdParams and #cmdQueue == 2 and cmdQueue[1].id == CMD.FIGHT and cmdQueue[2].id == CMD.FIGHT then
			-- Want to issue the order to stop doing stuff if con has
			-- finished its work and is returning to its original location
			-- so that the con can get through reclaim fields

			-- Also want to be very very sure we're only issuing this stop command
			-- if the only commands the unit has is the one this widget inserted

			local posCmd1 = cmdQueue[1].params
			local posCmd2 = cmdQueue[2].params

			if
				posCmd2[1] == self.cmdParams[1] and posCmd2[2] == self.cmdParams[2] and posCmd2[3] == self.cmdParams[3]
				and posCmd1[1] == self.cmdParams[1] and posCmd1[2] == self.cmdParams[2] and posCmd1[3] == self.cmdParams[3]
			then
				sp_GiveOrderToUnit(self.unitID, CMD.STOP, {}, {})
				self.cmdParams = nil
			end
		end
	end
}

local function AddToTrackingStack(unitID, unitDefID)
	if not defIDsToTrack[unitDefID] then
		return
	end

	ConStack[unitID % UPDATE_FRAME][unitID] = ConController:new(unitID, unitDefID)
end

local function RemoveFromTrackingStack(unitID, unitDefID)
	if not defIDsToTrack[unitDefID] then
		return
	end

	if ConStack[unitID % UPDATE_FRAME][unitID] ~= nil then
		ConStack[unitID % UPDATE_FRAME][unitID] = ConStack[unitID % UPDATE_FRAME][unitID]:unset()
	end
end


function widget:UnitFinished(unitID, unitDefID, unitTeam)
	if unitTeam == myTeamId then
		AddToTrackingStack(unitID, unitDefID)
	end
end

function widget:UnitDestroyed(unitID, unitDefID)
	RemoveFromTrackingStack(unitID, unitDefID)
end

function widget:GameFrame(n)
    for _, Con in pairs(ConStack[n % UPDATE_FRAME]) do
        Con:handle()
    end
end


-- The rest of the code is there to disable the widget for spectators
local function DisableForSpec()
	if Spring.GetSpectatingState() then
		widgetHandler:RemoveWidget()
		return true
	end

	return false
end

-- this breaks commshare very badly by not allowing them to issue orders to our cons unless they rapidly issue orders to them.
local function DisableForCommshare()
	if sp_GetMyTeamID() ~= myTeamId or #Spring.GetPlayerList(sp_GetMyTeamID()) > 1 then
		widgetHandler:RemoveWidget()
		return true
	end

	return false
end

function widget:Initialize()
	if DisableForSpec() or DisableForCommshare() then
		return
	end

	local myUnits = Spring.GetTeamUnits(sp_GetMyTeamID())

	for i = 0, UPDATE_FRAME + 1 do
		ConStack[i] = {}
	end

	for i = 1, #myUnits do
		AddToTrackingStack(myUnits[i], sp_GetUnitDefID(myUnits[i]))
	end
end

function widget:PlayerChanged(_)
	DisableForSpec()
	DisableForCommshare()
end

function widget:Shutdown()
	for _, controller in pairs(TrackedUnitsConControllers) do
		controller:unset()
	end

    ConStack = {}
	TrackedUnitsConControllers = {}
end
