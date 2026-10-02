-- luacheck: globals AREA_RECLAIM_SPREAD_TEST
-- luacheck: no self

function widget:GetInfo()
	return {
		name = 'Area Reclaim Spread',
		desc = 'Spreads units sharing an area reclaim/resurrect over individual features so nobody walks to a feature that is gone before they arrive',
		author = 'tetrisface',
		date = '2026-09-28',
		license = 'Public Domain',
		layer = 0,
		enabled = true
	}
end

local Echo = Spring.Echo
local GetFeatureDefID = Spring.GetFeatureDefID
local GetFeatureHealth = Spring.GetFeatureHealth
local GetFeaturePosition = Spring.GetFeaturePosition
local GetFeatureRadius = Spring.GetFeatureRadius
local GetFeatureResources = Spring.GetFeatureResources
local GetFeatureResurrect = Spring.GetFeatureResurrect
local GetFeaturesInCylinder = Spring.GetFeaturesInCylinder
local GetTeamResources = Spring.GetTeamResources
local GetTeamUnitsByDefs = Spring.GetTeamUnitsByDefs
local GetUnitCommands = Spring.GetUnitCommands
local GetUnitDefID = Spring.GetUnitDefID
local GetUnitPosition = Spring.GetUnitPosition
local GiveOrderToUnit = Spring.GiveOrderToUnit
local ValidFeatureID = Spring.ValidFeatureID

local TICK_FRAMES = 15
local ECO_SAMPLE_FRAMES = 30
local RESTEER_COOLDOWN_FRAMES = 60
local MAX_QUEUE_SCAN = 200
local MAX_CANDIDATES = 64
local HORIZON_SECONDS = 120 -- an uncovered feature counts as finishing this late
local STALL_LEVEL = 0.1
local LEAK_LEVEL = 0.95
local ENERGY_PER_METAL = 70 -- metal maker rate, makes energy features comparable to metal ones
local GROUND_TORTUOSITY = 1.25 -- ponytail: Euclidean times a factor; Spring.RequestPath when cliff maps misrank
local FEATURE_ID_OFFSET = (Engine.FeatureSupport and Engine.FeatureSupport.noOffsetForFeatureID) and 0 or Game.maxUnits

local EMPTY = {}
local huge = math.huge
local kindByCmd = {[CMD.RECLAIM] = 'reclaim', [CMD.RESURRECT] = 'resurrect'}
local cmdByKind = {reclaim = CMD.RECLAIM, resurrect = CMD.RESURRECT}

--------------------------------------------------------------------------------
-- Pure core. No Spring calls; plain tables in, plain tables out.
-- unit:    {id, kind, x, z, speed (elmos/s), range, immobile, tortuosity, workSpeed}
-- feature: {id, x, z, radius, work (workSpeed times seconds left), metal, energy}
-- load:    featureID -> {kind, assignees = {{id, arrival, speed}, ...}}
--------------------------------------------------------------------------------

local function arrivalSeconds(unit, feature)
	local dx, dz = unit.x - feature.x, unit.z - feature.z
	local gap = math.sqrt(dx * dx + dz * dz) - unit.range - feature.radius
	if gap <= 0 then return 0 end
	if unit.immobile or unit.speed <= 0 then return huge end
	return gap / unit.speed * unit.tortuosity
end

local function byArrival(a, b)
	return a.arrival < b.arrival
end

-- Seconds until the feature's remaining work is done, given who is coming and when.
local function finishSeconds(feature, assignees, excludeId)
	local coming = {}
	for i = 1, #assignees do
		if assignees[i].id ~= excludeId then coming[#coming + 1] = assignees[i] end
	end
	table.sort(coming, byArrival)
	local work, rate, t = feature.work, 0, 0
	for i = 1, #coming do
		local a = coming[i]
		if rate > 0 then
			local done = rate * (a.arrival - t)
			if done >= work then return t + work / rate end
			work = work - done
		end
		t, rate = a.arrival, rate + a.speed
	end
	if rate <= 0 then return work <= 0 and 0 or huge end
	return t + work / rate
end

local function isDoomed(unit, feature, assignees)
	return arrivalSeconds(unit, feature) >= finishSeconds(feature, assignees, unit.id)
end

local function joined(assignees, unit, feature)
	local result = {}
	for i = 1, #assignees do result[i] = assignees[i] end
	result[#result + 1] = {id = unit.id, arrival = arrivalSeconds(unit, feature), speed = unit.workSpeed}
	return result
end

-- Metal-seconds the feature finishes earlier because the unit joins; nil when it adds nothing.
local function marginalGain(unit, feature, assignees, value)
	if value <= 0 then return nil end
	local before = math.min(finishSeconds(feature, assignees), HORIZON_SECONDS)
	local after = finishSeconds(feature, joined(assignees, unit, feature))
	if after >= before then return nil end
	return value * (before - after)
end

local scoreByMode = {
	-- gradual reclaim pays from first contact, so earliest contact on metal wins
	immediate = function(unit, feature, assignees)
		if feature.metal <= 0 or isDoomed(unit, feature, assignees) then return nil end
		return -arrivalSeconds(unit, feature)
	end,
	throughput = function(unit, feature, assignees)
		return marginalGain(unit, feature, assignees, feature.metal + feature.energy / ENERGY_PER_METAL)
	end,
	-- full metal storage: only energy is worth a trip
	leak = function(unit, feature, assignees)
		return marginalGain(unit, feature, assignees, feature.energy / ENERGY_PER_METAL)
	end
}

-- Sequential greedy: each free unit takes its best candidate given everyone committed so far.
-- Returns {unitID = featureID}; load is left untouched.
local function assign(freeUnits, candidatesByUnit, load, mode)
	local score = scoreByMode[mode]
	local result = {}
	if not score then return result end
	local committed = {}
	for fid, entry in pairs(load) do committed[fid] = entry end
	for i = 1, #freeUnits do
		local unit = freeUnits[i]
		local bestScore, bestFeature
		local candidates = candidatesByUnit[unit.id] or EMPTY
		for j = 1, #candidates do
			local feature = candidates[j]
			local entry = committed[feature.id]
			if not entry or entry.kind == unit.kind then
				local s = score(unit, feature, entry and entry.assignees or EMPTY)
				if s and (not bestScore or s > bestScore) then bestScore, bestFeature = s, feature end
			end
		end
		if bestFeature then
			result[unit.id] = bestFeature.id
			local entry = committed[bestFeature.id]
			committed[bestFeature.id] = {kind = unit.kind, assignees = joined(entry and entry.assignees or EMPTY, unit, bestFeature)}
		end
	end
	return result
end

local function decodeFeatureId(param)
	if FEATURE_ID_OFFSET > 0 then
		return param > FEATURE_ID_OFFSET and param - FEATURE_ID_OFFSET or nil
	end
	-- no-offset engines share the id space with units; a live feature id is the best available test
	return ValidFeatureID(param) and param or nil
end

-- The reclaim block at the front of a queue: kind, current feature target, area order, queued feature ids.
-- nil when the front is not shared reclaim work (a lone single-target order is the player's own choice).
local function blockOf(commands)
	local front = commands and commands[1]
	local kind = front and kindByCmd[front.id]
	if not kind then return nil end
	local block = {kind = kind, queued = {}}
	local count = 0
	for i = 1, #commands do
		local cmd = commands[i]
		if kindByCmd[cmd.id] ~= kind then break end
		local params, options = cmd.params or EMPTY, cmd.options or EMPTY
		if #params == 4 then
			if not block.area and not options.meta then
				block.area, block.areaCtrl, block.areaMeta = params, options.ctrl, options.meta
			end
			count = count + 1
		elseif #params == 1 then
			local fid = decodeFeatureId(params[1])
			if fid then
				if i == 1 then block.target = fid end
				block.queued[#block.queued + 1] = fid
				count = count + 1
			end
		end
	end
	if count < 2 and not block.area then return nil end
	return block
end

if AREA_RECLAIM_SPREAD_TEST then
	return {
		arrivalSeconds = arrivalSeconds,
		finishSeconds = finishSeconds,
		isDoomed = isDoomed,
		assign = assign,
		blockOf = blockOf,
		scoreByMode = scoreByMode
	}
end

--------------------------------------------------------------------------------
-- Spring glue
--------------------------------------------------------------------------------

local myTeamID
local gameStarted = false
local debugEnabled = false
local modeOverride -- /reclaimspread mode ...
local mode = 'throughput'
local lastSample
local reclaimerDefIDs = {}
local unitTraits = {} -- unitDefID -> movement and work speeds
local steeredAt = {} -- unitID -> frame of the last insert

local function maybeRemoveSelf()
	if Spring.GetSpectatingState() and (Spring.GetGameFrame() > 0 or gameStarted) then
		widgetHandler:RemoveWidget()
	end
end

function widget:Initialize()
	myTeamID = Spring.GetMyTeamID()
	for defID, def in pairs(UnitDefs) do
		if def.canReclaim or def.canResurrect then
			reclaimerDefIDs[#reclaimerDefIDs + 1] = defID
			unitTraits[defID] = {
				speed = def.speed or 0,
				range = def.buildDistance or 0,
				immobile = not def.canMove,
				tortuosity = def.canFly and 1 or GROUND_TORTUOSITY,
				reclaimSpeed = def.reclaimSpeed or 0,
				resurrectSpeed = def.resurrectSpeed or 0
			}
		end
	end
	if Spring.IsReplay() or Spring.GetGameFrame() > 0 then maybeRemoveSelf() end
end

function widget:GameStart()
	gameStarted = true
	maybeRemoveSelf()
end

function widget:PlayerChanged()
	myTeamID = Spring.GetMyTeamID()
	maybeRemoveSelf()
end

local function unitRecord(unitID, kind)
	local traits = unitTraits[GetUnitDefID(unitID)]
	if not traits then return nil end
	local workSpeed = kind == 'reclaim' and traits.reclaimSpeed or traits.resurrectSpeed
	if workSpeed <= 0 then return nil end
	local x, _, z = GetUnitPosition(unitID)
	if not x then return nil end
	return {
		id = unitID, kind = kind, x = x, z = z, speed = traits.speed, range = traits.range,
		immobile = traits.immobile, tortuosity = traits.tortuosity, workSpeed = workSpeed
	}
end

-- Kind-specific feature record, cached per tick. false in the cache marks a feature this kind cannot use.
local function featureRecord(fid, kind, cache)
	local byKind = cache[kind]
	local record = byKind[fid]
	if record ~= nil then return record or nil end
	local metal, _, energy, _, reclaimLeft, reclaimTime = GetFeatureResources(fid)
	local x, _, z = GetFeaturePosition(fid)
	if not metal or not x then
		byKind[fid] = false
		return nil
	end
	local radius = GetFeatureRadius(fid) or 0
	if kind == 'reclaim' then
		record = {id = fid, x = x, z = z, radius = radius, metal = metal, energy = energy, reclaimLeft = reclaimLeft, work = reclaimTime * reclaimLeft}
	else
		local def = UnitDefNames[GetFeatureResurrect(fid) or '']
		if not def then
			byKind[fid] = false
			return nil
		end
		local _, _, progress = GetFeatureHealth(fid)
		-- a partially reclaimed wreck is repaired back to whole before resurrection starts
		local work = reclaimTime * (1 - reclaimLeft) + def.buildTime * (1 - (progress or 0))
		record = {id = fid, x = x, z = z, radius = radius, metal = def.metalCost, energy = 0, reclaimLeft = reclaimLeft, work = work}
	end
	byKind[fid] = record
	return record
end

local function areaAllows(fid, block)
	if block.kind == 'resurrect' then return true end
	local def = FeatureDefs[GetFeatureDefID(fid)]
	return def and def.reclaimable and (block.areaCtrl or def.autoreclaim)
end

-- Scav Constructor Guard keeps some wrecks for resurrection
local function isGuarded(fid)
	local guard = WG['scav_constructor_guard']
	return guard ~= nil and guard.isProtectedFeature(fid)
end

local function candidatesFor(unit, block, cache)
	local list, seen = {}, {}
	local function add(fid, fromArea)
		if seen[fid] then return end
		seen[fid] = true
		if fromArea and not areaAllows(fid, block) then return end
		if block.kind == 'reclaim' and isGuarded(fid) then return end
		local feature = featureRecord(fid, block.kind, cache)
		if not feature then return end
		if fromArea and block.areaMeta and feature.reclaimLeft < 1 then return end
		list[#list + 1] = feature
	end
	for i = 1, #block.queued do add(block.queued[i], false) end
	if block.area then
		local ids = GetFeaturesInCylinder(block.area[1], block.area[3], block.area[4])
		for i = 1, #ids do add(ids[i], true) end
	end
	table.sort(list, function(a, b)
		return arrivalSeconds(unit, a) < arrivalSeconds(unit, b)
	end)
	for i = #list, MAX_CANDIDATES + 1, -1 do list[i] = nil end
	return list
end

local function addLoad(load, fid, kind, assignee)
	local entry = load[fid] or {kind = kind, assignees = {}}
	entry.assignees[#entry.assignees + 1] = assignee
	load[fid] = entry
end

local function dropLoad(load, fid, unitID)
	local entry = load[fid]
	if not entry then return end
	local kept = {}
	for i = 1, #entry.assignees do
		if entry.assignees[i].id ~= unitID then kept[#kept + 1] = entry.assignees[i] end
	end
	entry.assignees = kept
end

local function needsTarget(unit, block, load, cache, frame)
	local fid = block.target
	if not fid then return true end
	local feature = featureRecord(fid, block.kind, cache)
	if not feature then return true end
	if frame - (steeredAt[unit.id] or -huge) < RESTEER_COOLDOWN_FRAMES then return false end
	if arrivalSeconds(unit, feature) == 0 then return false end
	local entry = load[fid]
	return isDoomed(unit, feature, entry and entry.assignees or EMPTY)
end

local function steer(assignments, unitsById, frame)
	for unitID, fid in pairs(assignments) do
		local unit = unitsById[unitID]
		GiveOrderToUnit(unitID, CMD.INSERT, {0, cmdByKind[unit.kind], 0, fid + FEATURE_ID_OFFSET}, {'alt'})
		steeredAt[unitID] = frame
		if debugEnabled then
			Echo(string.format('reclaimspread: unit %d -> feature %d (%s, %s)', unitID, fid, unit.kind, modeOverride or mode))
		end
	end
end

local function tick(frame, activeMode)
	local cache = {reclaim = {}, resurrect = {}}
	local load = {}
	local participants = {}
	local units = GetTeamUnitsByDefs(myTeamID, reclaimerDefIDs) or EMPTY
	for i = 1, #units do
		local unitID = units[i]
		local block = blockOf(GetUnitCommands(unitID, 2))
		local unit = block and unitRecord(unitID, block.kind)
		if unit then
			participants[#participants + 1] = {unit = unit, block = block}
			local feature = block.target and featureRecord(block.target, block.kind, cache)
			if feature then
				local arrival = arrivalSeconds(unit, feature)
				if arrival < huge then
					addLoad(load, block.target, block.kind, {id = unitID, arrival = arrival, speed = unit.workSpeed})
				end
			end
		end
	end

	local freeUnits, candidatesByUnit, unitsById = {}, {}, {}
	for i = 1, #participants do
		local unit, block = participants[i].unit, participants[i].block
		if needsTarget(unit, block, load, cache, frame) then
			if block.target then dropLoad(load, block.target, unit.id) end
			local fullBlock = blockOf(GetUnitCommands(unit.id, MAX_QUEUE_SCAN)) or block
			freeUnits[#freeUnits + 1] = unit
			unitsById[unit.id] = unit
			candidatesByUnit[unit.id] = candidatesFor(unit, fullBlock, cache)
		end
	end
	if #freeUnits == 0 then return end
	steer(assign(freeUnits, candidatesByUnit, load, activeMode), unitsById, frame)
end

-- ponytail: local thresholds; read WG['eco_cons'] instead once it exposes its stall/leak state
local function sampleEcoMode()
	local current, storage, pull, income, expense = GetTeamResources(myTeamID, 'metal')
	if not current or storage <= 0 then return 'throughput' end
	local level = current / storage
	if level < STALL_LEVEL and pull > income then return 'immediate' end
	if level > LEAK_LEVEL and income > expense then return 'leak' end
	return 'throughput'
end

function widget:GameFrame(frame)
	if frame % ECO_SAMPLE_FRAMES == 0 then
		local sample = sampleEcoMode()
		if sample == lastSample then mode = sample end -- two agreeing samples switch the mode
		lastSample = sample
	end
	if frame % TICK_FRAMES ~= 0 then return end
	local activeMode = modeOverride or mode
	if activeMode == 'off' then return end
	tick(frame, activeMode)
end

function widget:TextCommand(command)
	local arg = command:match('^reclaimspread%s*(.*)$')
	if not arg then return false end
	local wanted = arg:match('^mode%s+(%w+)$')
	if arg == 'debug' then
		debugEnabled = not debugEnabled
	elseif wanted == 'auto' then
		modeOverride = nil
	elseif wanted and (scoreByMode[wanted] or wanted == 'off') then
		modeOverride = wanted
	else
		Echo('reclaimspread: usage /reclaimspread mode auto|immediate|throughput|leak|off, /reclaimspread debug')
		return true
	end
	Echo(string.format('reclaimspread: mode %s%s, debug %s', modeOverride or mode, modeOverride and ' (manual)' or ' (auto)', tostring(debugEnabled)))
	return true
end
