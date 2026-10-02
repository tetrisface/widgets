-- luacheck: globals SCAV_CONSTRUCTOR_GUARD_TEST
-- luacheck: no self

function widget:GetInfo()
	return {
		name = 'Scav Constructor Guard',
		desc = 'While you own no scav constructor, keeps your units from reclaiming scav constructors or their wrecks and marks new such wrecks for you only',
		author = 'tetrisface',
		date = '2026-09-30',
		license = 'Public Domain',
		layer = 0,
		enabled = true
	}
end

local Echo = Spring.Echo
local GetFeatureDefID = Spring.GetFeatureDefID
local GetFeatureHealth = Spring.GetFeatureHealth
local GetFeaturePosition = Spring.GetFeaturePosition
local GetFeatureResurrect = Spring.GetFeatureResurrect
local GetFeaturesInCylinder = Spring.GetFeaturesInCylinder
local GetMyTeamID = Spring.GetMyTeamID
local GetSpectatingState = Spring.GetSpectatingState
local GetTeamUnitsByDefs = Spring.GetTeamUnitsByDefs
local GetUnitCommands = Spring.GetUnitCommands
local GetUnitCurrentCommand = Spring.GetUnitCurrentCommand
local GetUnitDefID = Spring.GetUnitDefID
local GetUnitPosition = Spring.GetUnitPosition
local GiveOrderArrayToUnit = Spring.GiveOrderArrayToUnit
local MarkerAddPoint = Spring.MarkerAddPoint
local MarkerErasePosition = Spring.MarkerErasePosition
local ValidFeatureID = Spring.ValidFeatureID

local CMD_RECLAIM = CMD.RECLAIM
local FEATURE_ID_OFFSET = (Engine.FeatureSupport and Engine.FeatureSupport.noOffsetForFeatureID) and 0 or Game.maxUnits

--------------------------------------------------------------------------------
-- Pure core. No Spring calls.
--------------------------------------------------------------------------------

-- A mobile _scav unit that can build a factory; minelayers and the like do not count.
local function isScavConstructor(def)
	if def.name:sub(-5) ~= '_scav' or not def.canMove then return false end
	for _, optionID in ipairs(def.buildOptions) do
		if UnitDefs[optionID].isFactory then return true end
	end
	return false
end

-- Orders that take a protected reclaim target off the front of a queue.
-- commands: the first two queue entries; findSubstitute(x, z, radius, ctrl) -> featureID or nil.
local function ordersFor(commands, findSubstitute)
	local front, nextCmd = commands[1], commands[2]
	local orders = {{CMD.REMOVE, {front.tag}, {}}}
	local params, options = front.params, front.options
	-- an explicit order is not repicked, dropping it is enough
	if not options.internal or #params ~= 5 then return orders end
	-- engine pick from an area, fight or patrol search; the order carries that search's center and radius
	local substitute = not options.meta and findSubstitute(params[2], params[4], params[5], options.ctrl)
	if substitute then
		orders[2] = {CMD.INSERT, {0, CMD_RECLAIM, 0, substitute + FEATURE_ID_OFFSET}, {'alt'}}
	elseif nextCmd and nextCmd.id == CMD_RECLAIM and #nextCmd.params == 4 then
		orders[2] = {CMD.REMOVE, {nextCmd.tag}, {}} -- nothing else left in the area, it would only repick the target
	end
	-- ponytail: fight/patrol with nothing else in reach, and a build site blocked by the wreck, repick it every
	-- slow update and nibble it; steer a resurrector onto it (engine reclaim skips wrecks being resurrected) if that bites
	return orders
end

if SCAV_CONSTRUCTOR_GUARD_TEST then
	return {isScavConstructor = isScavConstructor, ordersFor = ordersFor}
end

--------------------------------------------------------------------------------
-- Spring glue
--------------------------------------------------------------------------------

local guardActive = false
local protectedDefs = {} -- unitDefID -> true
local protectedDefIDs = {}
local reclaimerDefIDs = {}
local handledTags = {} -- unitID -> tag of the reclaim already taken off its queue
local announced = {} -- reclaim target -> true once the player was told
local markers = {} -- featureID -> {x, y, z}

local function decodeFeatureId(param)
	if FEATURE_ID_OFFSET > 0 then
		return param > FEATURE_ID_OFFSET and param - FEATURE_ID_OFFSET or nil
	end
	-- no-offset engines share the id space with units; a live feature id is the best available test
	return ValidFeatureID(param) and param or nil
end

-- The scav constructor a wreck resurrects into, or nil.
local function protectedDefOf(featureID)
	local def = UnitDefNames[GetFeatureResurrect(featureID) or '']
	return def and protectedDefs[def.id] and def or nil
end

local function isProtectedTarget(param)
	local featureID = decodeFeatureId(param)
	if featureID then return protectedDefOf(featureID) ~= nil end
	return protectedDefs[GetUnitDefID(param)] == true
end

-- The engine's area pick filters, plus wrecks under resurrection, which an explicit order would reclaim anyway.
local function isAllowedReclaim(featureID, ctrl)
	local def = FeatureDefs[GetFeatureDefID(featureID)]
	if not def or not def.reclaimable or not (ctrl or def.autoreclaim) then return false end
	local _, _, resurrectProgress = GetFeatureHealth(featureID)
	return resurrectProgress == 0 and protectedDefOf(featureID) == nil
end

local function nearestAllowedFeature(unitID, x, z, radius, ctrl)
	local ux, _, uz = GetUnitPosition(unitID)
	local best, bestDist = nil, math.huge
	local ids = GetFeaturesInCylinder(x, z, radius)
	for i = 1, #ids do
		if isAllowedReclaim(ids[i], ctrl) then
			local fx, _, fz = GetFeaturePosition(ids[i])
			local dist = (fx - ux) ^ 2 + (fz - uz) ^ 2
			if dist < bestDist then best, bestDist = ids[i], dist end
		end
	end
	return best
end

local function guard(unitID)
	if GetUnitCurrentCommand(unitID) ~= CMD_RECLAIM then return end
	local commands = GetUnitCommands(unitID, 2)
	local front = commands[1]
	local target = front.params[1]
	if #front.params == 4 or handledTags[unitID] == front.tag or not isProtectedTarget(target) then return end
	handledTags[unitID] = front.tag
	if not front.options.internal and not announced[target] then
		announced[target] = true
		Echo('Scav Constructor Guard: kept a scav constructor from being reclaimed, resurrect it instead')
	end
	GiveOrderArrayToUnit(unitID, ordersFor(commands, function(x, z, radius, ctrl)
		return nearestAllowedFeature(unitID, x, z, radius, ctrl)
	end))
end

function widget:Initialize()
	for defID, def in pairs(UnitDefs) do
		if def.canReclaim then reclaimerDefIDs[#reclaimerDefIDs + 1] = defID end
		if isScavConstructor(def) then
			protectedDefs[defID] = true
			protectedDefIDs[#protectedDefIDs + 1] = defID
		end
	end
	if #protectedDefIDs == 0 or Spring.IsReplay() then
		widgetHandler:RemoveWidget()
		return
	end
	WG['scav_constructor_guard'] = {
		isProtectedFeature = function(featureID)
			return guardActive and protectedDefOf(featureID) ~= nil
		end
	}
end

function widget:Shutdown()
	WG['scav_constructor_guard'] = nil
end

function widget:GameFrame()
	local teamID = GetMyTeamID()
	guardActive = not GetSpectatingState() and #GetTeamUnitsByDefs(teamID, protectedDefIDs) == 0
	if not guardActive then return end
	local units = GetTeamUnitsByDefs(teamID, reclaimerDefIDs)
	for i = 1, #units do guard(units[i]) end
end

function widget:UnitDestroyed(unitID)
	handledTags[unitID] = nil -- tags count per queue, a reused unitID could repeat one
end

-- ponytail: only wrecks visible when they appear get a marker; there is no callin for a wreck entering LOS
function widget:FeatureCreated(featureID)
	if not guardActive then return end
	local def = protectedDefOf(featureID)
	if not def then return end
	local x, y, z = GetFeaturePosition(featureID)
	markers[featureID] = {x, y, z}
	MarkerAddPoint(x, y, z, 'Resurrect scav ' .. (def.translatedHumanName or def.humanName), true)
end

function widget:FeatureDestroyed(featureID)
	local pos = markers[featureID]
	if not pos then return end
	markers[featureID] = nil
	MarkerErasePosition(pos[1], pos[2], pos[3], nil, true)
end
