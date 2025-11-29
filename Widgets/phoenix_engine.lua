function widget:GetInfo()
	return {
		name = 'Phoenix Engine',
		desc = 'Automatically reclaims blocking units when placing buildings over them.',
		author = 'timuela',
		date = '2025-10-02',
		layer = 0,
		enabled = true,
		handler = true
	}
end

VFS.Include('luaui/Headers/keysym.h.lua')

local GetSelectedUnits = Spring.GetSelectedUnits
local GetUnitDefID = Spring.GetUnitDefID
local GetUnitPosition = Spring.GetUnitPosition
local GiveOrderToUnitArray = Spring.GiveOrderToUnitArray
local GetUnitTeam = Spring.GetUnitTeam
local GetMyTeamID = Spring.GetMyTeamID
local GetUnitHealth = Spring.GetUnitHealth
local GetUnitsInRectangle = Spring.GetUnitsInRectangle
local GetUnitIsBeingBuilt = Spring.GetUnitIsBeingBuilt
local UnitDefs = UnitDefs
local CMD_RECLAIM = CMD.RECLAIM
local CMD_INSERT = CMD.INSERT
local CMD_OPT_SHIFT = CMD.OPT_SHIFT

-- Command definitions
local CMD_AUTO_REPLACE = 28341
local MODE_AUTO_REPLACE_OFF = 0
local MODE_AUTO_REPLACE_ON = 1
local CMD_AUTO_REPLACE_DESCRIPTION = {
	id = CMD_AUTO_REPLACE,
	type = (CMDTYPE or {ICON_MODE = 5}).ICON_MODE,
	name = 'Auto Replace',
	cursor = nil,
	action = 'auto_replace',
	params = {1, 'auto_replace_off', 'auto_replace_on'}
}

Spring.I18N.set('en.ui.orderMenu.auto_replace_off', 'Auto Replace Off')
Spring.I18N.set('en.ui.orderMenu.auto_replace_on', 'Auto Replace On')
Spring.I18N.set('en.ui.orderMenu.auto_replace_tooltip', 'Automatically reclaim blocking units when placing buildings')

-- Target definitions
local factions = {'arm', 'cor', 'leg'}

local reclaimableTargets = {
	-- wind
	'win',
	'wint2',
	-- metal makers
	'makr',
	'fmkr',
	'mmkr',
	'uwmmm',
	-- nanos
	'nanotc',
	'nanotcplat',
	'nanotct2',
	'nanotc2plat',
	'nanotct3',
	'wint2',
	'afus'
}

local buildableTypes = {
	'afust3',
	'mmkrt3',
	'adveconvt3',
	'flak'
}

local reclaimPriorityOrderNames = {
	'afust3_200',
	'afust3',
	'mmkrt3',
	'adveconvt3',
	'afust2',
	'adveconvt2',
	'nanotct3',
	'nanotc3plat',
	'nanotct2',
	'nanotc2plat',
	'nanotc',
	'nanotcplat',
	'wint2',
	'win'
}

-- add _scav postfix for all items
local scavEntries = {}
for _, name in ipairs(reclaimPriorityOrderNames) do
	table.insert(scavEntries, name .. '_scav')
end
for _, scavName in ipairs(scavEntries) do
	table.insert(reclaimPriorityOrderNames, scavName)
end

local TARGET_UNITDEF_NAMES = {}
local BUILDABLE_UNITDEF_NAMES = {}
local reclaimPriorityOrder = {}

for _, faction in ipairs(factions) do
	for _, reclaimableTarget in ipairs(reclaimableTargets) do
		table.insert(TARGET_UNITDEF_NAMES, faction .. reclaimableTarget)
	end
end
for _, faction in ipairs({'arm', 'cor', 'leg'}) do
	for _, buildableType in ipairs(buildableTypes) do
		table.insert(BUILDABLE_UNITDEF_NAMES, faction .. buildableType)
	end
	for _, placingPrio in ipairs(reclaimPriorityOrderNames) do
		if UnitDefNames[faction .. placingPrio] then
			table.insert(reclaimPriorityOrder, UnitDefNames[faction .. placingPrio].id)
		end
	end
end

reclaimPriorityOrder = table.invert(reclaimPriorityOrder)

-- Build equality groups: maps unitDefID -> set of equivalent unitDefIDs (same building, different factions)
local UNIT_EQUALITY_GROUPS = {}

local TARGET_UNITDEF_IDS,
	builderDefs,
	NANO_DEFS,
	BUILDABLE_UNITDEF_IDS,
	NEVER_RECLAIMABLE_UNITDEF_IDS,
	ECONOMICAL_UNITDEF_IDS = {}, {}, {}, {}, {}, {}

for _, name in ipairs(TARGET_UNITDEF_NAMES) do
	local def = UnitDefNames and UnitDefNames[name]
	if def then
		TARGET_UNITDEF_IDS[def.id] = true
	end
end

for _, target in ipairs({'gate', 'gatet3'}) do
	for _, faction in ipairs(factions) do
		local name = faction .. target
		local def = UnitDefNames and UnitDefNames[name]
		if def then
			NEVER_RECLAIMABLE_UNITDEF_IDS[def.id] = true
		end
	end
end

for _, name in ipairs(BUILDABLE_UNITDEF_NAMES) do
	local def = UnitDefNames and UnitDefNames[name]
	if def then
		BUILDABLE_UNITDEF_IDS[def.id] = true
	end
end

-- Function to detect economical buildings (from gui_spectator_hud.lua)
local function IsEconomicalBuilding(unitDefID, unitDef)
	if not unitDef.isBuilding then
		return false
	end

	-- Check if unitgroup is metal or energy
	if
		(unitDef.customParams and unitDef.customParams.unitgroup == 'metal') or
			(unitDef.customParams and unitDef.customParams.unitgroup == 'energy')
	 then
		return true
	end

	-- Check if it's a nano turret (builder but not factory and not mobile)
	if unitDef.isBuilder and not unitDef.isFactory and not unitDef.canMove then
		return true
	end

	-- Check if it's an energy converter (metal maker)
	if unitDef.customParams and unitDef.customParams.energyconv_capacity and unitDef.customParams.energyconv_efficiency then
		return true
	end

	-- Check if it produces resources (metal extraction, energy production)
	if
		(unitDef.extractsMetal and unitDef.extractsMetal > 0) or (unitDef.energyMake and unitDef.energyMake > 0) or
			(unitDef.energyUpkeep and unitDef.energyUpkeep < 0)
	 then
		return true
	end

	return false
end

local function UnitDefHasShield(unitDefID)
	return UnitDefs[unitDefID] and (UnitDefs[unitDefID].hasShield)
end

local function UnitDefTechLevel(unitDefID)
	return UnitDefs[unitDefID] and UnitDefs[unitDefID].customParams and UnitDefs[unitDefID].customParams.techlevel and
		tonumber(UnitDefs[unitDefID].customParams.techlevel) or
		1
end

for uDefID, uDef in pairs(UnitDefs) do
	if uDef.isBuilder then
		builderDefs[uDefID] = true
	end
	if uDef.isBuilder and not uDef.canMove and not uDef.isFactory then
		NANO_DEFS[uDefID] = uDef.buildDistance or 0
	end

	-- Build economical buildings mapping
	if IsEconomicalBuilding(uDefID, uDef) then
		ECONOMICAL_UNITDEF_IDS[uDefID] = true
	end
end

-- Build equality groups table - links faction equivalents together
-- First, create a temp mapping: baseName -> {faction defIDs}
local baseNameToDefIDs = {}
for uDefID, uDef in pairs(UnitDefs) do
	if uDef.isBuilding then
		local name = uDef.name
		-- Extract base name by removing faction prefix (arm, cor, leg)
		local baseName = name
		if name:sub(1, 3) == 'arm' then
			baseName = name:sub(4)
		elseif name:sub(1, 3) == 'cor' then
			baseName = name:sub(4)
		elseif name:sub(1, 3) == 'leg' then
			baseName = name:sub(4)
		end

		if baseName ~= name then -- Only process if a faction prefix was found
			if not baseNameToDefIDs[baseName] then
				baseNameToDefIDs[baseName] = {}
			end
			table.insert(baseNameToDefIDs[baseName], uDefID)
		end
	end
end

-- Now build the equality groups: each unitDefID maps to a set of its equivalents
for baseName, defIDs in pairs(baseNameToDefIDs) do
	if #defIDs > 1 then -- Only create groups if multiple factions have this building
		for _, defID in ipairs(defIDs) do
			UNIT_EQUALITY_GROUPS[defID] = {}
			for _, otherDefID in ipairs(defIDs) do
				if otherDefID ~= defID then
					UNIT_EQUALITY_GROUPS[defID][otherDefID] = true
				end
			end
		end
	end
end

-- Configuration
local DEFAULT_PIPELINE_SIZE = 3
local MEDIUM_PIPELINE_SIZE = 6
local SMALL_PIPELINE_SIZE = 20
local NANO_CACHE_UPDATE_INTERVAL = 90
local RECLAIM_RETRY_DELAY = 150
local MAX_RECLAIM_RETRIES = 200

-- States
-- AUTO_REPLACE_ENABLED stores mode: 0 = off, 1 = on
local AUTO_REPLACE_ENABLED, builderPipelines, buildOrderCounter = {}, {}, 0
local nanoCache = {turrets = {}, lastUpdate = 0, needsUpdate = true}
local visualIndicators = {}
local ALT = {'alt'}
local CMD_CACHE = {0, CMD_RECLAIM, CMD_OPT_SHIFT, 0}
local F14_MODIFIER_ACTIVE = false

-- Sequential execution tracking
local RECLAIM_SEQUENTIAL_MODE = true -- Enable sequential reclaim (only reclaim for first 2 positions in queue)

-- Helper functions
local function getReclaimPriority(unitDefID)
	return reclaimPriorityOrder[unitDefID]
end

local function canReplaceUnit(existingUnitDefID, placingUnitDefID, mode, modifierActive)
	-- Never replace: same unit
	if existingUnitDefID == placingUnitDefID then
		return false
	end

	-- Never replace: faction equivalents (different faction, same building)
	if UNIT_EQUALITY_GROUPS[existingUnitDefID] and UNIT_EQUALITY_GROUPS[existingUnitDefID][placingUnitDefID] then
		return false
	end

	local existingDef = UnitDefs[existingUnitDefID]
	if not existingDef then
		return false
	end

	-- Never replace: non-buildings (moving units)
	if existingDef.canMove then
		return false
	end

	-- Never replace: gates
	if NEVER_RECLAIMABLE_UNITDEF_IDS[existingUnitDefID] then
		return false
	end

	-- Never replace: T3+ shields
	if UnitDefHasShield(existingUnitDefID) and UnitDefTechLevel(existingUnitDefID) >= 3 then
		return false
	end

	-- Mode-specific rules
	if mode == MODE_AUTO_REPLACE_OFF then
		if not modifierActive then
			-- Mode 0, no modifier: Never replace
			return false
		else
			-- Mode 0 + modifier: Keep simple for future expansion
			-- For now, keep it off
			return false
		end
	elseif mode == MODE_AUTO_REPLACE_ON then
		if not modifierActive then
			-- Mode 2, no modifier: Replace economical buildings including nanos
			return (ECONOMICAL_UNITDEF_IDS[existingUnitDefID] == true or
				(getReclaimPriority(placingUnitDefID) or 0) < (getReclaimPriority(existingUnitDefID) or 0))
		else
			-- Mode 2 + modifier: Replace almost everything EXCEPT nanos
			if NANO_DEFS[existingUnitDefID] then
				return false
			end
			-- Replace all buildings that aren't shields/gates/nanos
			return true
		end
	end

	return false
end

local function getPipelineSize(unitDefID)
	local unitDef = UnitDefs[unitDefID]
	if not unitDef then
		return DEFAULT_PIPELINE_SIZE
	end

	local footprintArea = (unitDef.xsize or 4) * (unitDef.zsize or 4)

	-- EFUS-sized buildings (16x16 = 256) get pipeline size 3
	-- Smaller buildings get larger pipelines
	if footprintArea >= 256 then
		return DEFAULT_PIPELINE_SIZE
	elseif footprintArea >= 64 then -- 8x8 buildings
		return MEDIUM_PIPELINE_SIZE
	else -- Smaller buildings
		return SMALL_PIPELINE_SIZE
	end
end

local function getBuilderPipeline(builderID)
	if not builderPipelines[builderID] then
		builderPipelines[builderID] = {
			builderID = builderID,
			pendingBuilds = {},
			currentlyProcessing = {},
			buildingsUnderConstruction = {},
			reclaimStarted = {},
			reclaimRetries = {},
			lastReclaimAttempt = {}
		}
	end
	return builderPipelines[builderID]
end

local function updateNanoCache()
	local myTeam = GetMyTeamID()
	nanoCache.turrets = {}
	for _, uid in ipairs(Spring.GetTeamUnits(myTeam)) do
		local buildDist = NANO_DEFS[GetUnitDefID(uid)]
		if buildDist then
			local x, _, z = GetUnitPosition(uid)
			if x then
				nanoCache.turrets[uid] = {x = x, z = z, buildDist = buildDist}
			end
		end
	end
	nanoCache.lastUpdate, nanoCache.needsUpdate = Spring.GetGameFrame(), false
end

local function nanosNearUnit(targetUnitID)
	local tx, _, tz = GetUnitPosition(targetUnitID)
	if not tx then
		return {}
	end
	local unitIDs = {}
	for uid, turret in pairs(nanoCache.turrets) do
		if uid ~= targetUnitID then
			local dx, dz = tx - turret.x, tz - turret.z
			local distance = math.sqrt(dx * dx + dz * dz)
			if turret.buildDist > distance then
				unitIDs[#unitIDs + 1] = uid
			end
		end
	end
	return unitIDs
end

-- Visual indicator functions
local function addVisualIndicator(builderID, x, z, areaX, areaZ)
	visualIndicators[builderID] = visualIndicators[builderID] or {}
	table.insert(visualIndicators[builderID], {x, z, areaX, areaZ})
end

local function removeVisualIndicator(builderID, x, z)
	local indicators = visualIndicators[builderID]
	if not indicators then
		return
	end
	for i = #indicators, 1, -1 do
		local ind = indicators[i]
		if math.abs(ind[1] - x) < 1 and math.abs(ind[2] - z) < 1 then
			table.remove(indicators, i)
		end
	end
	if #indicators == 0 then
		visualIndicators[builderID] = nil
	end
end

local function clearAllVisualIndicators(builderID)
	visualIndicators[builderID] = nil
end

local function findBlockersAtPosition(x, z, xsize, zsize, facing, builderID, placedUnitDefID)
	local blockers = {}
	local areaX, areaZ =
		(facing == 1 or facing == 3) and zsize * 4 or xsize * 4,
		(facing == 1 or facing == 3) and xsize * 4 or zsize * 4

	local mode = AUTO_REPLACE_ENABLED[builderID] or MODE_AUTO_REPLACE_ON

	for _, uid in ipairs(GetUnitsInRectangle(x - areaX, z - areaZ, x + areaX, z + areaZ)) do
		if GetUnitTeam(uid) == GetMyTeamID() then
			local unitDefID = GetUnitDefID(uid)

			if canReplaceUnit(unitDefID, placedUnitDefID, mode, F14_MODIFIER_ACTIVE) then
				local ux, _, uz = GetUnitPosition(uid)
				if ux and math.abs(ux - x) <= areaX and math.abs(uz - z) <= areaZ then
					blockers[#blockers + 1] = uid
				end
			end
		end
	end
	return blockers, areaX, areaZ
end

local function giveReclaimOrdersFromNanos(targetUnitIDs)
	for _, targetUnitID in ipairs(targetUnitIDs) do
		local unitIDs = nanosNearUnit(targetUnitID)
		CMD_CACHE[4] = targetUnitID
		GiveOrderToUnitArray(unitIDs, CMD_INSERT, CMD_CACHE, ALT)
	end
end

local function checkUnits(update)
	local ids, found = GetSelectedUnits(), false
	for i = 1, #ids do
		local id = ids[i]
		if builderDefs[GetUnitDefID(id)] then
			found = true
			if update then
				local mode = CMD_AUTO_REPLACE_DESCRIPTION.params[1]
				local wasEnabled = (AUTO_REPLACE_ENABLED[id] or MODE_AUTO_REPLACE_ON) ~= MODE_AUTO_REPLACE_OFF
				AUTO_REPLACE_ENABLED[id] = mode

				-- Clear visual indicators when toggling off
				if wasEnabled and mode == MODE_AUTO_REPLACE_OFF then
					clearAllVisualIndicators(id)
				end
			end
		end
	end
	return found
end

local function isAutoReplaceEnabledForSelection()
	for _, id in ipairs(GetSelectedUnits()) do
		if builderDefs[GetUnitDefID(id)] and (AUTO_REPLACE_ENABLED[id] or MODE_AUTO_REPLACE_ON) ~= MODE_AUTO_REPLACE_OFF then
			return true
		end
	end
	return false
end

-- Helper functions for pipeline processing
local function shouldRetryReclaim(pipeline, order, currentFrame)
	local lastAttempt = pipeline.lastReclaimAttempt[order] or 0
	local retries = pipeline.reclaimRetries[order] or 0
	return (currentFrame - lastAttempt) >= RECLAIM_RETRY_DELAY and retries < MAX_RECLAIM_RETRIES
end

-- Count how many build commands a builder has in their actual queue
local function countBuilderQueuedBuilds(builderID)
	local commands = Spring.GetUnitCommands(builderID, -1)
	if not commands then
		return 0
	end
	
	local count = 0
	for _, cmd in ipairs(commands) do
		-- Negative command IDs are build commands
		if cmd.id < 0 then
			count = count + 1
		end
	end
	return count
end

-- Check if we should reclaim for this build based on position in processing queue
local function shouldReclaimForBuild(pipeline, buildOrder, positionInQueue)
	if not RECLAIM_SEQUENTIAL_MODE then
		return true -- Reclaim for all builds in non-sequential mode
	end

	-- Get builder's actual queue length (non-blocked builds that went through)
	local queuedBuilds = countBuilderQueuedBuilds(pipeline.builderID)
	
	-- Total position = queued non-blocked builds + position in our blocked pipeline
	local effectivePosition = queuedBuilds + positionInQueue
	
	-- Only reclaim for first 2 positions overall
	return effectivePosition <= 2
end

local function isBuildComplete(constructionInfo)
	local wx, wz = constructionInfo.position[1], constructionInfo.position[2]
	local hx, hz = constructionInfo.footprint[1], constructionInfo.footprint[2]
	for _, uid in ipairs(GetUnitsInRectangle(wx - hx, wz - hz, wx + hx, wz + hz)) do
		if
			GetUnitDefID(uid) == constructionInfo.unitDefID and GetUnitTeam(uid) == GetMyTeamID() and
				not GetUnitIsBeingBuilt(uid)
		 then
			return true
		end
	end
	return false
end

local function getAliveBuilders(builders)
	local alive = {}
	for _, uid in ipairs(builders) do
		local health = GetUnitHealth(uid)
		if health and health > 0 then
			alive[#alive + 1] = uid
		end
	end
	return alive
end

local function clearPipelineOrder(pipeline, order)
	pipeline.reclaimStarted[order] = nil
	pipeline.reclaimRetries[order] = nil
	pipeline.lastReclaimAttempt[order] = nil
end

local function cleanupPipelineForBuilder(builderID)
	local pipeline = builderPipelines[builderID]
	if not pipeline then
		return
	end
	
	-- Clear all visual indicators for this builder
	clearAllVisualIndicators(builderID)
	
	-- Clean up all tracking
	for order, _ in pairs(pipeline.reclaimStarted) do
		clearPipelineOrder(pipeline, order)
	end
	
	-- Clear all positions from visual indicators
	for _, p in ipairs(pipeline.pendingBuilds) do
		local bx, bz = p.params[1], p.params[3]
		removeVisualIndicator(builderID, bx, bz)
	end
	for _, p in ipairs(pipeline.currentlyProcessing) do
		local bx, bz = p.params[1], p.params[3]
		removeVisualIndicator(builderID, bx, bz)
	end
	
	-- Remove the pipeline
	builderPipelines[builderID] = nil
end


-- Main game frame processing
function widget:GameFrame(n)
	if nanoCache.needsUpdate or (n - nanoCache.lastUpdate) >= NANO_CACHE_UPDATE_INTERVAL then
		updateNanoCache()
	end
	if n % 30 ~= 0 then
		return
	end

	local currentFrame = Spring.GetGameFrame()
	for builderID, pipeline in pairs(builderPipelines) do
		if
			(AUTO_REPLACE_ENABLED[builderID] or MODE_AUTO_REPLACE_ON) == MODE_AUTO_REPLACE_OFF or
				(#pipeline.pendingBuilds + #pipeline.currentlyProcessing == 0)
		 then
			builderPipelines[builderID] = nil
		else
			table.sort(
				pipeline.pendingBuilds,
				function(a, b)
					return a.order < b.order
				end
			)

			-- Get pipeline size for the first pending build
			local currentPipelineSize = DEFAULT_PIPELINE_SIZE
			if #pipeline.pendingBuilds > 0 then
				currentPipelineSize = getPipelineSize(-pipeline.pendingBuilds[1].cmdID)
			elseif #pipeline.currentlyProcessing > 0 then
				currentPipelineSize = getPipelineSize(-pipeline.currentlyProcessing[1].cmdID)
			end

			Spring.Echo(
				'currentPipelineSize',
				currentPipelineSize,
				'pendingBuilds',
				#pipeline.pendingBuilds,
				'currentlyProcessing',
				#pipeline.currentlyProcessing
			)

			while #pipeline.currentlyProcessing < currentPipelineSize and #pipeline.pendingBuilds > 0 do
				pipeline.currentlyProcessing[#pipeline.currentlyProcessing + 1] = table.remove(pipeline.pendingBuilds, 1)
			end
			
			local i = 1
			while i <= #pipeline.currentlyProcessing do
				local p = pipeline.currentlyProcessing[i]
				local bx, bz = p.params[1], p.params[3]
				local buildingDefIDBeingPlaced = -p.cmdID
				local shouldStart = not pipeline.reclaimStarted[p.order]
				local shouldRetry = pipeline.reclaimStarted[p.order] and shouldRetryReclaim(pipeline, p.order, currentFrame)

				-- Check if we should reclaim for this build based on position in queue
				local shouldReclaimForThisBuild = shouldReclaimForBuild(pipeline, p.order, i)

				-- Handle reclaim retry logic
				if shouldRetry and shouldReclaimForThisBuild then
					local blockers = findBlockersAtPosition(bx, bz, p.xsize, p.zsize, p.facing, builderID, buildingDefIDBeingPlaced)
					if #blockers > 0 then
						pipeline.reclaimRetries[p.order] = (pipeline.reclaimRetries[p.order] or 0) + 1
						giveReclaimOrdersFromNanos(blockers)
						pipeline.lastReclaimAttempt[p.order] = currentFrame
					end
				elseif shouldStart and shouldReclaimForThisBuild then
					local blockers = findBlockersAtPosition(bx, bz, p.xsize, p.zsize, p.facing, builderID, buildingDefIDBeingPlaced)
					if #blockers > 0 then
						giveReclaimOrdersFromNanos(blockers)
						pipeline.reclaimStarted[p.order] = true
						pipeline.lastReclaimAttempt[p.order] = currentFrame
					end
				end

				-- Check if building is under construction
				local constructionInfo = pipeline.buildingsUnderConstruction[p.order]
				if constructionInfo then
					if isBuildComplete(constructionInfo) then
						pipeline.buildingsUnderConstruction[p.order] = nil
						clearPipelineOrder(pipeline, p.order)
						removeVisualIndicator(builderID, bx, bz)
						table.remove(pipeline.currentlyProcessing, i)
					else
						i = i + 1
					end
				else
					-- Check if ready to build
					local blockers = findBlockersAtPosition(bx, bz, p.xsize, p.zsize, p.facing, builderID, buildingDefIDBeingPlaced)
					if #blockers == 0 then
						local aliveBuilders = getAliveBuilders(p.builders)
						if #aliveBuilders > 0 then
							GiveOrderToUnitArray(aliveBuilders, p.cmdID, p.params, {'shift'})
							pipeline.buildingsUnderConstruction[p.order] = {
								position = {bx, bz},
								footprint = {p.xsize / 2, p.zsize / 2},
								unitDefID = -p.cmdID
							}
						else
							clearPipelineOrder(pipeline, p.order)
							removeVisualIndicator(builderID, bx, bz)
							table.remove(pipeline.currentlyProcessing, i)
						end
					else
						i = i + 1
					end
				end
			end
		end
	end
end

-- Command handling
function widget:CommandsChanged()
	local found_mode = MODE_AUTO_REPLACE_ON
	for _, id in ipairs(GetSelectedUnits()) do
		local mode = AUTO_REPLACE_ENABLED[id]
		if mode then
			found_mode = mode
			break
		end
	end
	CMD_AUTO_REPLACE_DESCRIPTION.params[1] = found_mode
	if checkUnits(false) then
		widgetHandler.customCommands[#widgetHandler.customCommands + 1] = CMD_AUTO_REPLACE_DESCRIPTION
	end
end

function widget:CommandNotify(cmdID, cmdParams, cmdOptions)
	if cmdID == CMD_AUTO_REPLACE then
		local mode = CMD_AUTO_REPLACE_DESCRIPTION.params[1]
		Spring.Echo('Phoenix Engine: Button clicked, current mode:', mode)
		-- Cycle through modes like holo_place does
		local n_modes = #CMD_AUTO_REPLACE_DESCRIPTION.params - 1
		mode = (mode + 1) % n_modes
		CMD_AUTO_REPLACE_DESCRIPTION.params[1] = mode
		Spring.Echo('Phoenix Engine: New mode:', CMD_AUTO_REPLACE_DESCRIPTION.params[1])
		checkUnits(true)
		return true
	end
	
	-- Handle CMD.STOP - clear pipeline for selected builders
	if cmdID == CMD.STOP then
		for _, builderID in ipairs(GetSelectedUnits()) do
			if builderPipelines[builderID] then
				cleanupPipelineForBuilder(builderID)
			end
		end
		return false -- Let the stop command through
	end
	
	if type(cmdID) ~= 'number' or cmdID >= 0 or not isAutoReplaceEnabledForSelection() then
		return false
	end

	local buildingDefID = -cmdID
	local bx, by, bz = tonumber(cmdParams[1]), tonumber(cmdParams[2]), tonumber(cmdParams[3])
	if not (bx and by and bz) then
		return false
	end

	local buildingDef = UnitDefs[buildingDefID]
	if not buildingDef or not buildingDef.xsize or not buildingDef.zsize then
		return false
	end
	local xsize, zsize = buildingDef.xsize, buildingDef.zsize
	local facing = cmdParams[4] or 0
	local assignedBuilderID = nil
	for _, builderID in ipairs(GetSelectedUnits()) do
		if (AUTO_REPLACE_ENABLED[builderID] or MODE_AUTO_REPLACE_ON) ~= MODE_AUTO_REPLACE_OFF then
			assignedBuilderID = builderID
			break
		end
	end
	if not assignedBuilderID then
		return false
	end
	local blockers, buildingAreaX, buildingAreaZ =
		findBlockersAtPosition(bx, bz, xsize, zsize, facing, assignedBuilderID, buildingDefID)
	if #blockers == 0 then
		return false
	end
	buildOrderCounter = buildOrderCounter + 1
	local pipeline = getBuilderPipeline(assignedBuilderID)
	pipeline.pendingBuilds[#pipeline.pendingBuilds + 1] = {
		builders = GetSelectedUnits(),
		cmdID = cmdID,
		params = cmdParams,
		xsize = xsize,
		zsize = zsize,
		facing = facing,
		order = buildOrderCounter,
		blockers = blockers
	}
	addVisualIndicator(assignedBuilderID, bx, bz, buildingAreaX, buildingAreaZ)

	-- Reset F14 modifier after command is processed
	if F14_MODIFIER_ACTIVE then
		F14_MODIFIER_ACTIVE = false
		Spring.Echo('Phoenix Engine Modifier: OFF (auto-reset)')
	end

	return true
end

-- Event handlers
widget.UnitDestroyed = function(_, unitID)
	AUTO_REPLACE_ENABLED[unitID] = nil
	if builderPipelines[unitID] then
		cleanupPipelineForBuilder(unitID)
	end
	if nanoCache.turrets[unitID] then
		nanoCache.needsUpdate = true
	end
end
widget.UnitTaken = widget.UnitDestroyed

widget.UnitFinished = function(_, unitID, unitDefID)
	if NANO_DEFS[unitDefID] then
		nanoCache.needsUpdate = true
	end
end

widget.UnitGiven = function(_, unitID, unitDefID)
	if NANO_DEFS[unitDefID] then
		nanoCache.needsUpdate = true
	end
end

function widget:Initialize()
	widgetHandler.actionHandler:AddAction(
		self,
		'auto_replace',
		function()
			checkUnits(true)
		end,
		nil,
		'p'
	)
	nanoCache.needsUpdate = true
end

function widget:Shutdown()
	widgetHandler.actionHandler:RemoveAction(self, 'auto_replace', 'p')
	builderPipelines, buildOrderCounter, AUTO_REPLACE_ENABLED = {}, 0, {}
	visualIndicators = {}
end

-- Visual rendering
function widget:DrawWorld()
	if not next(visualIndicators) then
		return
	end

	local gl = gl
	gl.PushAttrib(GL.ALL_ATTRIB_BITS)
	gl.Color(1, 0.5, 0, 0.8) -- Orange
	gl.DepthTest(true)
	gl.LineWidth(2)

	local HEIGHT_OFFSET = 15
	local CORNER_SIZE = 8

	for builderID, indicators in pairs(visualIndicators) do
		for _, ind in ipairs(indicators) do
			local x, z, areaX, areaZ = ind[1], ind[2], ind[3], ind[4]
			local x1, z1, x2, z2 = x - areaX, z - areaZ, x + areaX, z + areaZ
			local y = Spring.GetGroundHeight(x, z) + HEIGHT_OFFSET
			gl.BeginEnd(
				GL.LINE_LOOP,
				function()
					gl.Vertex(x1, y, z1)
					gl.Vertex(x2, y, z1)
					gl.Vertex(x2, y, z2)
					gl.Vertex(x1, y, z2)
				end
			)
			gl.BeginEnd(
				GL.LINES,
				function()
					gl.Vertex(x1, y, z1)
					gl.Vertex(x1 + CORNER_SIZE, y, z1)
					gl.Vertex(x1, y, z1)
					gl.Vertex(x1, y, z1 + CORNER_SIZE)
					gl.Vertex(x2, y, z1)
					gl.Vertex(x2 - CORNER_SIZE, y, z1)
					gl.Vertex(x2, y, z1)
					gl.Vertex(x2, y, z1 + CORNER_SIZE)
					gl.Vertex(x2, y, z2)
					gl.Vertex(x2 - CORNER_SIZE, y, z2)
					gl.Vertex(x2, y, z2)
					gl.Vertex(x2, y, z2 - CORNER_SIZE)
					gl.Vertex(x1, y, z2)
					gl.Vertex(x1 + CORNER_SIZE, y, z2)
					gl.Vertex(x1, y, z2)
					gl.Vertex(x1, y, z2 - CORNER_SIZE)
				end
			)
		end
	end

	gl.LineWidth(1)
	gl.Color(1, 1, 1, 1)
	gl.PopAttrib()
end

function widget:KeyPress(key, modifier, isRepeat)
	if isRepeat then
		return false
	end
	if key == KEYSYMS.F14 then
		F14_MODIFIER_ACTIVE = not F14_MODIFIER_ACTIVE
		Spring.Echo('Phoenix Engine Modifier: ', F14_MODIFIER_ACTIVE and 'ON' or 'OFF')
		return true
	end
end
