function widget:GetInfo()
	return {
		name = 'Commands',
		desc = 'some commands for editing constructor build queue, and automatic geo toggling',
		author = '-',
		date = 'dec, 2016',
		license = 'GNU GPL, v3 or later',
		layer = 99,
		enabled = true
	}
end

VFS.Include('LuaUI/Widgets/helpers.lua')
VFS.Include('luaui/Headers/keysym.h.lua')

local selectPrios = {
	'ack_scav',
	'ack',
	'aca_scav',
	'aca',
	'acv_scav',
	'acv',
	'ca_scav',
	'ca',
	'ck_scav',
	'ck',
	'cv',
	'cv_scav'
}
local selectPriosAir = {'aca_scav', 'aca', 'ca'}
local selectPriosNonScav = {'ack', 'aca', 'acv', 'ca', 'ck', 'cv'}
local selectPriosAirNonScav = {'aca', 'ca'}
local factionPrios = {'arm', 'cor', 'leg'}
local immobileBuilderDefIds = {
	UnitDefNames['armnanotc'].id,
	UnitDefNames['armnanotc2plat'].id,
	UnitDefNames['armnanotcplat'].id,
	UnitDefNames['armnanotct2'].id,
	UnitDefNames['armrespawn'].id,
	UnitDefNames['cornanotc'].id,
	UnitDefNames['cornanotc2plat'].id,
	UnitDefNames['cornanotcplat'].id,
	UnitDefNames['cornanotct2'].id,
	UnitDefNames['correspawn'].id,
	UnitDefNames['legnanotc'] and UnitDefNames['legnanotc'].id or nil,
	UnitDefNames['legnanotcbase'] and UnitDefNames['legnanotcbase'].id or nil,
	UnitDefNames['legnanotcplat'] and UnitDefNames['legnanotcplat'].id or nil,
	UnitDefNames['legnanotct2'] and UnitDefNames['legnanotct2'].id or nil,
	UnitDefNames['legnanotct2plat'] and UnitDefNames['legnanotct2plat'].id or nil
}

local spamUnitNames = {
	'armpnix',
	'armpnix_scav',
	'armsb',
	'armsb_scav',
	'armthund',
	'armthund_scav',
	'armthundt4',
	'armthundt4_scav',
	'corhurc',
	'corhurc_scav',
	'corhurc',
	'corhurc_scav',
	'corhurc',
	'corhurc_scav',
	'corcrw',
	'corcrw_scav',
	'corcrwh',
	'corcrwh_scav',
	'corcrwt4',
	'corcrwt4_scav',
	'corape',
	'corape_scav',
	'corsb',
	'corsb_scav',
	'corshad',
	'corshad_scav',
	'legkam',
	'legkam_scav',
	'legkam',
	'legkam_scav',
	'legkam',
	'legkam_scav',
	'legmos',
	'legmos_scav',
	'legphoenix',
	'legphoenix_scav',
	'legfort',
	'legfort_scav',
	'legmost3',
	'legmost3_scav',
	'legfortt4',
	'legfortt4',
	'legfortt4',
	'legfortt4_scav',
	'legfortt4_scav',
	'legfortt4_scav'
}

local spamUnits = {}
for _, unitName in ipairs(spamUnitNames) do
	if UnitDefNames[unitName] then
		table.insert(spamUnits, {-UnitDefNames[unitName].id})
	end
end
table.insert(spamUnits, {CMD.REPEAT, 1})
table.insert(spamUnits, {34570, 0})
table.insert(spamUnits, {34569, 0})

local replacementMap = {}
local mousePos = {0, 0, 0}

-- Fill replacementMap: for each unitdef, strip faction prefix and find all faction alternatives
local factionPrefixes = {'arm', 'cor', 'leg'}
local function stripFaction(name)
	for _, prefix in ipairs(factionPrefixes) do
		if name:sub(1, #prefix) == prefix then
			return name:sub(#prefix + 1)
		end
	end
	return nil
end
-- Build a map from stripped name to all unitdefids with that base name
local baseNameToIds = {}
for id, unitDef in pairs(UnitDefs) do
	local basename = stripFaction(unitDef.name)
	if basename ~= nil then
		baseNameToIds[basename] = baseNameToIds[basename] or {}
		table.insert(baseNameToIds[basename], id)
	else
	end
end
-- Now, for each unitdef, if it has a base name, set replacementMap[id] to all other ids with the same base name (excluding itself)
for id, unitDef in pairs(UnitDefs) do
	local base = stripFaction(unitDef.name)
	if base and baseNameToIds[base] then
		replacementMap[id] = {}
		for _, altId in ipairs(baseNameToIds[base]) do
			if altId ~= id then
				table.insert(replacementMap[id], altId)
			end
		end
	end
end
-- some edge cases with mismatching baseNameToIds
-- replacementMap

local myTeamId = Spring.GetMyTeamID()

local immobileBuilderDefs = {}
local selectedPos = {}
local unitIdBuildSpeeds = LRUCache:new(100)
local isShieldDefId = {}
local conCycleNumber
local transposeMode = nil -- will be auto-detected on first use, then toggles between 'row_first' and 'col_first'
local cornerRotation = 0 -- 0=closest corner, 1=next clockwise, 2=opposite, 3=next counter-clockwise
local lastBuildOrderSignature = nil -- simple signature to detect new build orders
function widget:Initialize()
	Spring.SendCommands('bind Shift+Alt+sc_q buildfacing inc')
	Spring.SendCommands('bind Shift+Alt+sc_e buildfacing dec')

	for _, immobileBuilderDefId in ipairs(immobileBuilderDefIds) do
		immobileBuilderDefs[immobileBuilderDefId] = UnitDefs[immobileBuilderDefId].buildDistance + 96
	end

	for unitDefId, unitDef in pairs(UnitDefs) do
		if unitDef.isBuilding and unitDef.hasShield then
			isShieldDefId[unitDefId] = unitDef.customParams and unitDef.customParams.shield_radius and 1 or 0
		end
		if
			unitDef.isBuilder and unitDef.isBuilding and unitDef.canAssist and
				not table.contains(immobileBuilderDefIds, unitDefId)
		 then
			immobileBuilderDefIds[unitDefId] = unitDef.buildDistance + 96
		end
	end
end

local function SelectSubset(selected_units, nPartitions)
	if not nPartitions or not selected_units or #selected_units == 0 then
		return
	end

	selected_units = sort(selected_units)

	local nUnits = #selected_units
	local nUnitsPerPartition = math.ceil(nUnits / nPartitions)
end

local function removeFirstCommand(unit_id)
	local cmd_queue = Spring.GetUnitCommands(unit_id, 4)
	if #cmd_queue > 1 and cmd_queue[2]['id'] == 70 then
		Spring.GiveOrderToUnit(unit_id, CMD.REMOVE, {cmd_queue[2].tag}, {nil})
	end
	Spring.GiveOrderToUnit(unit_id, CMD.REMOVE, {cmd_queue[1].tag}, {nil})
end

local function removeLastCommand(unit_id)
	local cmd_queue = Spring.GetUnitCommands(unit_id, 5000)
	local remove_cmd = cmd_queue[#cmd_queue]
	if remove_cmd['id'] == 0 then
		Spring.GiveOrderToUnit(unit_id, CMD.REMOVE, {cmd_queue[#cmd_queue - 1].tag}, {nil})
	end
	Spring.GiveOrderToUnit(unit_id, CMD.REMOVE, {cmd_queue[#cmd_queue].tag}, {nil})
end

local function unitDef(unitId)
	return UnitDefs[Spring.GetUnitDefID(unitId)]
end

local function reverseQueue(unit_id)
	local queue = Spring.GetCommandQueue(unit_id, 10000)
	Spring.GiveOrderToUnit(unit_id, CMD.INSERT, {-1, CMD.STOP, CMD.OPT_SHIFT}, {'alt'})
	if queue then
		for i = #queue, 1, -1 do
			local v = queue[i]
			local options = v.options
			if not options.internal then
				local new_options = {}
				if options.alt then
					table.insert(new_options, 'alt')
				end
				if options.ctrl then
					table.insert(new_options, 'ctrl')
				end
				if options.right then
					table.insert(new_options, 'right')
				end
				table.insert(new_options, CMD.OPT_SHIFT)
				Spring.GiveOrderToUnit(unit_id, v.id, -1, v.params, options.coded)
			end
		end
	end

	if build_queue ~= nil then
		for udid, buildPair in ipairs(build_queue) do
			local udid, count = next(buildPair, nil)
			Spring.AddBuildOrders(unit_id, udid, count)
		end
	end
end

local function KeyUnits(key, mods)
	local faction = (key == KEYSYMS.D and 'leg') or (key == KEYSYMS.S and 'cor') or 'arm'
	local builders

	local selectList
	if mods['shift'] then
		selectList = mods['ctrl'] and selectPriosAirNonScav or selectPriosNonScav
	else
		selectList = mods['ctrl'] and selectPriosAir or selectPrios
	end
	for j = 0, #factionPrios do
		for i = 1, #selectList do
			local unitName = (j == 0 and faction or factionPrios[j]) .. selectList[i]
			if UnitDefNames[unitName] then
				builders = Spring.GetTeamUnitsByDefs(myTeamId, {UnitDefNames[unitName].id})
				if builders and #builders > 0 then
					break
				end
			end
		end
		if builders and #builders > 0 then
			break
		end
	end
	return builders
end

local function median(temp)
	if #temp == 0 then
		return 0
	elseif #temp == 2 then
		return (temp[1] + temp[2]) / 2
	end

	table.sort(temp)

	if math.fmod(#temp, 2) == 0 then
		return (temp[#temp / 2] + temp[(#temp / 2) + 1]) / 2
	else
		return temp[math.ceil(#temp / 2)]
	end
end

local function Distance(x1, y1, x2, y2)
	if x1 == nil or y1 == nil or x2 == nil or y2 == nil then
		return 1000000000
	end
	return math.sqrt((x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2)) or 1000000000
end

local lookahead_steps = 10

local function DistancePoints(p1, p2)
	if not p1 or not p1.x or not p1.z or not p2 or not p2.x or not p2.z then
		return 1000000000
	end
	return math.sqrt((p1.x - p2.x) ^ 2 + (p1.z - p2.z) ^ 2) or 1000000000
end

local function SortbuildSpeedDistance(a, b)
	if a == nil then
		return false
	elseif b == nil then
		return true
	end

	if (a.isShield or 0) > (b.isShield or 0) then
		return true
	elseif (a.isShield or 0) < (b.isShield or 0) then
		return false
	end

	if (a.buildSpeed or 0) > (b.buildSpeed or 0) then
		return true
	elseif (a.buildSpeed or 0) < (b.buildSpeed or 0) then
		return false
	end

	if not a.x or not a.z or not b.x or not b.z then
		return false
	end

	local aDistanceToSelected =
		(a.x - selectedPos.x) * (a.x - selectedPos.x) + (a.z - selectedPos.z) * (a.z - selectedPos.z)

	local bDistanceToSelected =
		(b.x - selectedPos.x) * (b.x - selectedPos.x) + (b.z - selectedPos.z) * (b.z - selectedPos.z)
	return aDistanceToSelected < bDistanceToSelected
end

local current_direction = 'horizontal'

local function is_in_line(current, next_building, direction)
	if direction == 'horizontal' then
		return current.z == next_building.z
	else
		return current.x == next_building.x
	end
end

local function evaluate_path(current_building, remaining_commands, direction, steps)
	local total_buildSpeed = 0
	local path_commands = {}
	local future_building = current_building

	for step = 1, steps do
		local best_next_building = nil
		local best_distance = math.huge

		for i, building in ipairs(remaining_commands) do
			if is_in_line(future_building, building, direction) then
				local dist = DistancePoints(future_building, building)
				if dist < best_distance then
					best_distance = dist
					best_next_building = building
				end
			end
		end

		if best_next_building then
			table.insert(path_commands, best_next_building)
			total_buildSpeed = total_buildSpeed + best_next_building.buildSpeed
			future_building = best_next_building
		else
			break
		end
	end

	return total_buildSpeed, path_commands
end

local function snake_sort_with_lookahead(commands, _lookahead_steps)
	local sorted_commands = {}
	local current_building = table.remove(commands, 1)
	table.insert(sorted_commands, current_building)

	while #commands > 0 do
		local best_direction = nil
		local best_path_buildings = nil
		local highest_buildSpeed = -math.huge

		for _, direction in ipairs({'horizontal', 'vertical'}) do
			local total_buildSpeed, path_commands = evaluate_path(current_building, commands, direction, _lookahead_steps)

			if total_buildSpeed > highest_buildSpeed then
				highest_buildSpeed = total_buildSpeed
				best_direction = direction
				best_path_buildings = path_commands
			end
		end

		if not best_path_buildings or #best_path_buildings == 0 then
			local closest_distance = math.huge
			for i, building in ipairs(commands) do
				local dist = DistancePoints(current_building, building)
				if dist < closest_distance then
					closest_distance = dist
					best_path_buildings = {building}
				end
			end
		end

		if #best_path_buildings > 0 then
			local next_building = table.remove(best_path_buildings, 1)

			for i, building in ipairs(commands) do
				if building == next_building then
					table.remove(commands, i)
					break
				end
			end

			current_building = next_building
			table.insert(sorted_commands, current_building)
		end
	end

	return sorted_commands
end

local function manhattan_distance(p1, p2)
	if p1 == nil or p2 == nil or p1.x == nil or p1.z == nil or p2.x == nil or p2.z == nil then
		return 0
	end
	return math.abs(p1.x - p2.x) + math.abs(p1.z - p2.z)
end

local function calculate_centroid(cluster)
	local sum_x, sum_z = 0, 0
	for _, point in ipairs(cluster) do
		if point ~= nil and point.x ~= nil and point.z ~= nil then
			sum_x = sum_x + point.x
			sum_z = sum_z + point.z
		end
	end
	return {x = sum_x / #cluster, z = sum_z / #cluster}
end

local function kmeans(commands, k, max_iterations)
	local centroids = {}
	for i = 1, k do
		table.insert(centroids, commands[math.random(1, #commands)])
	end

	local clusters = {}
	local prev_centroids = nil
	local iterations = 0

	while iterations < max_iterations do
		clusters = {}
		for i = 1, k do
			clusters[i] = {}
		end

		for _, command in ipairs(commands) do
			local closest_centroid = 1
			local min_distance = manhattan_distance(command, centroids[1])

			for i = 2, k do
				local dist = manhattan_distance(command, centroids[i])
				if dist < min_distance then
					closest_centroid = i
					min_distance = dist
				end
			end
			table.insert(clusters[closest_centroid], command)
		end

		prev_centroids = centroids
		for i = 1, k do
			if #clusters[i] > 0 then
				centroids[i] = calculate_centroid(clusters[i])
			end
		end

		local converged = true
		for i = 1, k do
			if manhattan_distance(prev_centroids[i], centroids[i]) > 0.01 then
				converged = false
				break
			end
		end

		if converged then
			break
		end
		iterations = iterations + 1
	end

	return clusters, centroids
end

local function calculateDistance(x1, z1, x2, z2)
	if x1 == nil or z1 == nil or x2 == nil or z2 == nil then
		return math.huge
	end
	return math.sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2)
end

-- Filter out non-build commands (command.id >= 0)
local function getBuildCommandsOnly(commands)
	local buildCommands = {}
	for _, command in ipairs(commands) do
		if command.id < 0 then
			table.insert(buildCommands, command)
		end
	end
	return buildCommands
end

-- Generate signature from all build command positions
local function generateBuildOrderSignature(commands)
	local positions = {}
	for _, command in ipairs(commands) do
		if command.x and command.z then
			table.insert(positions, tostring(command.x) .. '_' .. tostring(command.z))
		end
	end
	table.sort(positions) -- Sort to make signature order-independent
	return table.concat(positions, '|')
end

-- Generate unique signature for a single command (id + position)
local function generateCommandSignature(command)
	if command.id and command.params and command.params[1] and command.params[3] then
		return tostring(command.id) .. '_' .. tostring(command.params[1]) .. '_' .. tostring(command.params[3])
	end
	return nil
end

-- Check if two signatures are 90% similar
local function signaturesAreSimilar(sig1, sig2, threshold)
	threshold = threshold or 0.9
	if sig1 == nil or sig2 == nil then
		return false
	end
	if sig1 == sig2 then
		return true
	end

	local positions1 = {}
	local positions2 = {}
	for pos in sig1:gmatch('[^|]+') do
		positions1[pos] = true
	end
	for pos in sig2:gmatch('[^|]+') do
		positions2[pos] = true
	end

	local totalPositions = 0
	local matchingPositions = 0

	for pos in pairs(positions1) do
		totalPositions = totalPositions + 1
		if positions2[pos] then
			matchingPositions = matchingPositions + 1
		end
	end

	for pos in pairs(positions2) do
		if not positions1[pos] then
			totalPositions = totalPositions + 1
		end
	end

	return totalPositions > 0 and (matchingPositions / totalPositions) >= threshold
end

-- Handles Ctrl+Alt+Shift+W cheat key
local function handleCheatGiveUnits()
	-- Spring.SendCommands('give 1 armbanth')
	-- Spring.SendCommands('give 1 armcomlvl10')
	-- Spring.SendCommands('give 1 armlun')
	-- Spring.SendCommands('give 1 armmar')
	-- Spring.SendCommands('give 1 armprowl')
	-- Spring.SendCommands('give 1 armraz')
	-- Spring.SendCommands('give 1 armthor')
	-- Spring.SendCommands('give 1 armvang')
	-- Spring.SendCommands('give 1 corcat')
	-- Spring.SendCommands('give 1 cordemon')
	-- Spring.SendCommands('give 1 corjugg')
	-- Spring.SendCommands('give 1 corkarg')
	-- Spring.SendCommands('give 1 corkorg')
	-- Spring.SendCommands('give 1 corshiva')
	-- Spring.SendCommands('give 1 corsok')
	-- Spring.SendCommands('give 1 leegmech')
	-- Spring.SendCommands('give 1 legeheatraymech')
	-- Spring.SendCommands('give 1 legerailtank')
	-- Spring.SendCommands('give 1 legeshotgunmech')
	-- Spring.SendCommands('give 1 legjav')
	-- Spring.SendCommands('give 1 legkeres')

	-- Spring.SendCommands('give 1 armca')
	-- Spring.SendCommands('give 1 corca')
	-- Spring.SendCommands('give 1 legca')

	-- Spring.SendCommands('give 1 corjugg 2')

	Spring.SendCommands('give 1 armcom')
	Spring.SendCommands('give 1 armcomlvl2')
	Spring.SendCommands('give 1 armcomlvl3')
	Spring.SendCommands('give 1 armcomlvl4')
	Spring.SendCommands('give 1 corcom')
	Spring.SendCommands('give 1 corcomlvl2')
	Spring.SendCommands('give 1 corcomlvl3')
	Spring.SendCommands('give 1 corcomlvl4')
	Spring.SendCommands('give 1 legcom')
	Spring.SendCommands('give 1 legcomlvl2')
	Spring.SendCommands('give 1 legcomlvl3')
	Spring.SendCommands('give 1 legcomlvl4')
	Spring.SendCommands('give 1 legcomt2com')

	Spring.SendCommands('give 1 armt3aide')
	Spring.SendCommands('give 1 armt3airaide')
	Spring.SendCommands('give 1 cort3aide')
	Spring.SendCommands('give 1 cort3airaide')
	Spring.SendCommands('give 1 legt3aide')
	Spring.SendCommands('give 1 legt3airaide')
end

local function SortMouseDistance(a, b)
	if a == nil or b == nil then
		return false
	end
	local distanceA = math.sqrt((a.x - mousePos[1]) ^ 2 + (a.z - mousePos[3]) ^ 2)
	local distanceB = math.sqrt((b.x - mousePos[1]) ^ 2 + (b.z - mousePos[3]) ^ 2)
	return distanceA < distanceB
end

-- Handles Alt+A/S/D for command queue editing and builder cycling
local function conQueueSliceCommand(key, selectedUnitIds, mods)
	if mods.shift and not mods.ctrl then
		return false
	end

	local foundCommandQueue = false
	if key ~= KEYSYMS.A and #selectedUnitIds > 0 then
		for i = 1, #selectedUnitIds do
			local unit_id = selectedUnitIds[i]
			local cmd_queue = Spring.GetUnitCommands(unit_id, 200)
			if cmd_queue and (#cmd_queue > 0) then
				foundCommandQueue = true
				if key == KEYSYMS.S then
					removeFirstCommand(unit_id)
				elseif key == KEYSYMS.D then
					removeLastCommand(unit_id)
				end
				if #cmd_queue == 2 then
					Spring.GiveOrderToUnit(unit_id, CMD.INSERT, {-1, CMD.STOP, CMD.OPT_SHIFT}, {'alt'})
				end
			end
		end
		if foundCommandQueue then
			return true
		end
	end

	if (conCycleNumber == nil or #selectedUnitIds == 0) and not foundCommandQueue then
		conCycleNumber = 1
	end

	if #selectedUnitIds == 0 or (#selectedUnitIds > 0 and conCycleNumber ~= nil) then
		local builderIds = KeyUnits(key, mods)
		local builders = {}
		if #builderIds > 0 then
			for i = 1, #builderIds do
				local unit_id = builderIds[i]
				local x, _, z = Spring.GetUnitPosition(unit_id)
				builders[i] = {id = unit_id, x = x, z = z}
			end
			local mouseX, mouseY = Spring.GetMouseState()
			_, mousePos = Spring.TraceScreenRay(mouseX, mouseY, true)
			table.sort(builders, SortMouseDistance)
			conCycleNumber = ((conCycleNumber - 1) % #builderIds) + 1
			Spring.SelectUnit(builders[conCycleNumber].id)
			conCycleNumber = conCycleNumber + 1
		end
	end
	return false
end

-- Handles Shift+Alt+F for optimal build power pooling
local function buildQueueOptimalPooling(selectedUnitIds, mods)
	if #selectedUnitIds == 0 then
		return
	end

	-- Filter and analyze commands (merge duplicates to prevent cancellation)
	local mergedCommands = {}
	for i = 1, #selectedUnitIds do
		local commands = Spring.GetUnitCommands(selectedUnitIds[i], 1000)
		if commands then
			for j = 1, #commands do
				local command = commands[j]
				if command and command.id and command.id < 0 and command.params then
					local commandString =
						tostring(command.id) ..
						' ' ..
							tostring(command.params[1] or 0) ..
								' ' .. tostring(command.params[2] or 0) .. ' ' .. tostring(command.params[3] or 0)
					if mergedCommands[commandString] == nil then
						mergedCommands[commandString] = command
					end
				end
			end
		end
	end

	-- Calculate builder positions and total mobile build power
	local builders = {}
	local totalMobileBuildPower = 0
	for i = 1, #selectedUnitIds do
		local unitId = selectedUnitIds[i]
		if unitId then
			local x, _, z = Spring.GetUnitPosition(unitId)
			if x and z then
				local unitDefId = Spring.GetUnitDefID(unitId)
				local def = UnitDefs[unitDefId]
				if def and def.buildOptions and #def.buildOptions > 0 then
					local buildSpeed = def.buildSpeed or 1
					table.insert(builders, {
						id = unitId,
						x = x,
						z = z,
						buildSpeed = buildSpeed,
						buildOptions = def.buildOptions,
						unitDefId = unitDefId
					})
					totalMobileBuildPower = totalMobileBuildPower + buildSpeed
				end
			end
		end
	end

	if #builders == 0 then
		return
	end

	-- Calculate median builder position
	local xPositions, zPositions = {}, {}
	for _, builder in ipairs(builders) do
		table.insert(xPositions, builder.x)
		table.insert(zPositions, builder.z)
	end
	selectedPos = {x = median(xPositions), z = median(zPositions)}

	-- Get immobile builders (nano turrets, etc.)
	local allImmobileBuilders = Spring.GetTeamUnitsByDefs(myTeamId, immobileBuilderDefIds) or {}
	for i = 1, #allImmobileBuilders do
		if allImmobileBuilders[i] then
			local x, _, z = Spring.GetUnitPosition(allImmobileBuilders[i])
			if x and z then
				local unitDefId = Spring.GetUnitDefID(allImmobileBuilders[i])
				local unitDef = UnitDefs[unitDefId]
				allImmobileBuilders[i] = {
					id = allImmobileBuilders[i],
					x = x,
					z = z,
					buildDistance = immobileBuilderDefs[unitDefId],
					buildSpeed = (unitDef and unitDef.buildSpeed) or 0
				}
			end
		end
	end

	-- Create enhanced command list with build power analysis
	local commands, nCommands = {}, 0
	if mergedCommands then
		for _, command in pairs(mergedCommands) do
			if command then
				nCommands = nCommands + 1
				local immobileBuildPower = 0
				local nearbyNanos = {}

				if command.params and command.params[1] and command.params[3] then
					for j = 1, #allImmobileBuilders do
						local builder = allImmobileBuilders[j]
						if builder and builder.buildDistance and builder.x and builder.z then
							if Distance(builder.x, builder.z, command.params[1], command.params[3]) < builder.buildDistance then
								immobileBuildPower = immobileBuildPower + (builder.buildSpeed or 0)
								table.insert(nearbyNanos, builder)
							end
						end
					end
				end

				commands[nCommands] = {
					command.id,
					command.params,
					command.options,
					id = command.id,
					params = command.params,
					options = command.options,
					x = command.params and command.params[1],
					z = command.params and command.params[3],
					immobileBuildPower = immobileBuildPower,
					nearbyNanos = nearbyNanos,
					priority = (immobileBuildPower or 0) + math.random() * 0.1, -- Add slight randomness to break ties
					isShield = isShieldDefId[-command.id]
				}
			end
		end
	end

	if nCommands == 0 then
		return
	end


	-- Determine optimal number of queues based on builder count and build complexity
	local optimalQueues = math.min(math.max(2, math.ceil(#builders / 3)), 4)
	if #builders <= 2 then
		optimalQueues = 1
	end
	if nCommands < optimalQueues then
		optimalQueues = nCommands
	end



	-- Sort commands by priority (immobile build power + shields)
	table.sort(
		commands,
		function(a, b)
			if (a.isShield or 0) > (b.isShield or 0) then
				return true
			elseif (a.isShield or 0) < (b.isShield or 0) then
				return false
			end
			return a.priority > b.priority
		end
	)

		-- First assign builders to spatial clusters for efficient movement
	local clusters = kmeans(commands, optimalQueues, 100)

	-- Debug cluster sizes
	local totalCommandsInClusters = 0
	for i, cluster in ipairs(clusters) do
		totalCommandsInClusters = totalCommandsInClusters + #cluster
	end

	-- Create queues with builder assignments based on proximity
	local queues = {}
	local unassignedBuilders = table.copy(builders)

	for i = 1, optimalQueues do
		queues[i] = {commands = {}, totalPriority = 0, assignedBuilders = {}, totalBuildPower = 0}
	end

	-- Assign builders to clusters with load balancing
	local builderAssignments = {}
	for i = 1, optimalQueues do
		builderAssignments[i] = 0
	end

	-- First pass: assign builders with load balancing
	local buildersPerQueue = math.ceil(#builders / optimalQueues)
	local queueIndex = 1

	for _, builder in ipairs(builders) do
		-- Find the queue with the least builders that has commands
		local bestQueue = 1
		local minBuilders = math.huge

		for i = 1, optimalQueues do
			if #clusters[i] > 0 and #queues[i].assignedBuilders < minBuilders then
				minBuilders = #queues[i].assignedBuilders
				bestQueue = i
			end
		end

		-- If all queues have equal builders, use proximity
		if minBuilders >= buildersPerQueue then
			local bestDistance = math.huge
			for i, cluster in ipairs(clusters) do
				if #cluster > 0 then
					local clusterCentroid = calculate_centroid(cluster)
					local dist = calculateDistance(builder.x, builder.z, clusterCentroid.x, clusterCentroid.z)
					if dist < bestDistance then
						bestDistance = dist
						bestQueue = i
					end
				end
			end
		end

		table.insert(queues[bestQueue].assignedBuilders, builder)
		queues[bestQueue].totalBuildPower = queues[bestQueue].totalBuildPower + (builder.buildSpeed or 0)
		builderAssignments[bestQueue] = builderAssignments[bestQueue] + 1
	end

	-- Second pass: redistribute builders if any queue has no builders
	for i = 1, optimalQueues do
		if #queues[i].assignedBuilders == 0 and #clusters[i] > 0 then
			-- Find the queue with the most builders
			local maxBuilders, maxQueue = 0, 1
			for j = 1, optimalQueues do
				if #queues[j].assignedBuilders > maxBuilders then
					maxBuilders = #queues[j].assignedBuilders
					maxQueue = j
				end
			end

			-- Move one builder from the most loaded queue to this empty queue
			if maxBuilders > 1 then
				local builderToMove = table.remove(queues[maxQueue].assignedBuilders)
				if builderToMove then
					table.insert(queues[i].assignedBuilders, builderToMove)
					queues[i].totalBuildPower = queues[i].totalBuildPower + (builderToMove.buildSpeed or 0)
					queues[maxQueue].totalBuildPower = queues[maxQueue].totalBuildPower - (builderToMove.buildSpeed or 0)
				end
			end
		end
	end

	-- Debug builder assignments
	for i, queue in ipairs(queues) do
	end

	-- Now distribute commands based on available build power per queue
	for i, command in ipairs(commands) do
		-- Find which cluster this command belongs to
		local commandCluster = 1
		local minDistanceToCluster = math.huge

		for j, cluster in ipairs(clusters) do
			for _, clusterCommand in ipairs(cluster) do
				if clusterCommand == command then
					commandCluster = j
					break
				end
			end
		end

		-- Assign command to the queue with the most available build power in that cluster
		local targetQueue = queues[commandCluster]
		if targetQueue then
			table.insert(targetQueue.commands, command)
			targetQueue.totalPriority = targetQueue.totalPriority + (command.priority or 0)
		end
	end

	-- Debug command distribution before load balancing
	local totalDistributedCommands = 0
	for i, queue in ipairs(queues) do
		totalDistributedCommands = totalDistributedCommands + #queue.commands
	end

	-- Balance workload: move commands from overloaded to underloaded queues
	local maxIterations = 3
	for iter = 1, maxIterations do
		local moved = false

		-- Calculate work density (commands per build power) for each queue
		local queueWorkDensity = {}
		for i, queue in ipairs(queues) do
			if queue.totalBuildPower > 0 then
				queueWorkDensity[i] = #queue.commands / queue.totalBuildPower
			else
				queueWorkDensity[i] = math.huge
			end
		end

		-- Find most overloaded and least loaded queues
		local maxDensity, maxDensityQueue = -1, nil
		local minDensity, minDensityQueue = math.huge, nil

		for i, density in ipairs(queueWorkDensity) do
			if density > maxDensity and #queues[i].commands > 1 then
				maxDensity = density
				maxDensityQueue = i
			end
			if density < minDensity and queues[i].totalBuildPower > 0 then
				minDensity = density
				minDensityQueue = i
			end
		end

		-- Move a command from overloaded to underloaded queue if beneficial
		if maxDensityQueue and minDensityQueue and maxDensityQueue ~= minDensityQueue and maxDensity > minDensity * 1.5 then
			local commandToMove = table.remove(queues[maxDensityQueue].commands)
			if commandToMove then
				table.insert(queues[minDensityQueue].commands, commandToMove)
				queues[maxDensityQueue].totalPriority = queues[maxDensityQueue].totalPriority - (commandToMove.priority or 0)
				queues[minDensityQueue].totalPriority = queues[minDensityQueue].totalPriority + (commandToMove.priority or 0)
				moved = true
			end
		end

		if not moved then break end
	end

	-- Debug final queue state after load balancing
	local finalDistributedCommands = 0
	for i, queue in ipairs(queues) do
		finalDistributedCommands = finalDistributedCommands + #queue.commands
	end

	-- Apply optimized queues to builders
	for _, queue in ipairs(queues) do
		if #queue.assignedBuilders > 0 and #queue.commands > 0 then
			-- Sort commands within queue by priority and distance
			table.sort(
				queue.commands,
				function(a, b)
					if (a.isShield or 0) > (b.isShield or 0) then
						return true
					elseif (a.isShield or 0) < (b.isShield or 0) then
						return false
					end
					if (a.priority or 0) > (b.priority or 0) then
						return true
					elseif (a.priority or 0) < (b.priority or 0) then
						return false
					end
					-- Distance tiebreaker
					local aDistanceToSelected =
						(a.x and selectedPos.x) and ((a.x - selectedPos.x) ^ 2 + (a.z - selectedPos.z) ^ 2) or math.huge
					local bDistanceToSelected =
						(b.x and selectedPos.x) and ((b.x - selectedPos.x) ^ 2 + (b.z - selectedPos.z) ^ 2) or math.huge
					return aDistanceToSelected < bDistanceToSelected
				end
			)
			local optimizedCommands = queue.commands

			for _, builder in ipairs(queue.assignedBuilders) do
				if builder and builder.buildOptions then
					local builderCommands = {}
					for _, command in ipairs(optimizedCommands) do
						if command and command.id then
							if builder.buildOptions and #builder.buildOptions > 0 then
								if table.contains(builder.buildOptions, -command.id) then
									table.insert(builderCommands, command)
								elseif replacementMap[-command.id] then
									for replacementN = 1, #replacementMap[-command.id] or 0 do
										local replacementId = replacementMap[-command.id][replacementN]
										if table.contains(builder.buildOptions, replacementId) then
											local temp = table.copy(command)
											temp[1] = -replacementId
											table.insert(builderCommands, temp)
											break
										end
									end
								end
							end
						end
					end


					Spring.GiveOrderToUnit(builder.id, CMD.STOP, {}, {})
					local maxNCommands = 510
					if #builderCommands > maxNCommands then
						for k = #builderCommands, maxNCommands + 1, -1 do
							builderCommands[k] = nil
						end
					end
					Spring.GiveOrderArrayToUnit(builder.id, builderCommands)
				end
			end
		end
	end
end

-- Handles Ctrl+F for merging and sorting build commands
local function buildQueueDistributeTransform(selectedUnitIds, mods)
	if #selectedUnitIds == 0 then
		return
	end
	local mergedCommands = {}
	for i = 1, #selectedUnitIds do
		local commands = Spring.GetUnitCommands(selectedUnitIds[i], 1000)
		for j = 1, #commands do
			local command = commands[j]
			if command.id < 1 then
				local commandString =
					tostring(commands[j].id) ..
					' ' ..
						tostring(commands[j].params[1]) ..
							' ' .. tostring(commands[j].params[2]) .. ' ' .. tostring(commands[j].params[3])
				if mergedCommands[commandString] == nil then
					mergedCommands[commandString] = command
				end
			end
		end
	end
	local xPositions, zPositions = {}, {}
	for i = #selectedUnitIds, 1, -1 do
		local x, _, z = Spring.GetUnitPosition(selectedUnitIds[i])
		local defId = Spring.GetUnitDefID(selectedUnitIds[i])
		if not defId or not UnitDefs[defId].buildOptions or #UnitDefs[defId].buildOptions == 0 then
			table.remove(selectedUnitIds, i)
		else
			table.insert(xPositions, x)
			table.insert(zPositions, z)
		end
	end
	selectedPos = {x = median(xPositions), z = median(zPositions)}
	local allImmobileBuilders = Spring.GetTeamUnitsByDefs(myTeamId, immobileBuilderDefIds)
	for i = 1, #allImmobileBuilders do
		local x, _, z = Spring.GetUnitPosition(allImmobileBuilders[i])
		if x and z then
			allImmobileBuilders[i] = {
				id = allImmobileBuilders[i],
				x = x,
				z = z,
				buildDistance = immobileBuilderDefs[Spring.GetUnitDefID(allImmobileBuilders[i])]
			}
		end
	end
	local commands, nCommands = {}, 0
	for _, command in pairs(mergedCommands) do
		nCommands = nCommands + 1
		commands[nCommands] = {
			command.id,
			command.params,
			command.options,
			id = command.id,
			params = command.params,
			options = command.options,
			buildSpeed = 0,
			assistersBuildSpeeds = {},
			isShield = isShieldDefId[-command.id],
			x = command.params and command.params[1],
			z = command.params and command.params[3]
		}
		if command.params[1] and command.params[3] then
			for j = 1, #allImmobileBuilders do
				local builder = allImmobileBuilders[j]
				if
					builder.buildDistance and
						Distance(builder.x, builder.z, command.params[1], command.params[3]) < builder.buildDistance
				 then
					local buildSpeed = unitIdBuildSpeeds:get(allImmobileBuilders[j].id)
					if buildSpeed == nil then
						buildSpeed = UnitDefs[Spring.GetUnitDefID(allImmobileBuilders[j].id)].buildSpeed
						unitIdBuildSpeeds:put(allImmobileBuilders[j].id, buildSpeed)
					end
					if buildSpeed > 0 then
						commands[nCommands].buildSpeed = commands[nCommands].buildSpeed + buildSpeed
						commands[nCommands].assistersBuildSpeeds[allImmobileBuilders[j].id] = buildSpeed
					end
				end
			end
		end
	end
	if nCommands == 0 then
		return
	end

	-- Ctrl+Alt+F - Snake sort
	if not mods['shift'] and mods['alt'] then
		table.sort(commands, SortbuildSpeedDistance)
		commands = snake_sort_with_lookahead(commands, lookahead_steps)
		Spring.GiveOrderToUnitArray(selectedUnitIds, CMD.STOP, {}, {})
		Spring.GiveOrderArrayToUnitArray(selectedUnitIds, commands)
	-- Ctrl+Shift+F - K-Means clustering
	elseif mods['shift'] and not mods['alt'] then
		local builders = {}
		for i = 1, #selectedUnitIds do
			local unitId = selectedUnitIds[i]
			local x, _, z = Spring.GetUnitPosition(unitId)
			local def = UnitDefs[Spring.GetUnitDefID(unitId)]
			if def and def.buildOptions and #def.buildOptions > 0 then
				table.insert(builders, {id = unitId, x = x, z = z, buildSpeed = 1, def = def})
			end
		end
		local clusters = kmeans(commands, #builders, 100)
		local snakeSortedClusters = {}
		for i, cluster in ipairs(clusters) do
			table.sort(cluster, SortbuildSpeedDistance)
			snakeSortedClusters[i] = snake_sort_with_lookahead(cluster, lookahead_steps)
		end

		-- Calculate cluster centroids for better distance measurement
		local clusterCentroids = {}
		for i, cluster in ipairs(snakeSortedClusters) do
			if #cluster > 0 then
				clusterCentroids[i] = calculate_centroid(cluster)
			end
		end

		-- Improved greedy assignment: find globally optimal assignments
		local builderAssignments, assignedClusters = {}, {}
		local unassignedBuilders = {}
		for i = 1, #builders do
			table.insert(unassignedBuilders, i)
		end
		local unassignedClusters = {}
		for i = 1, #snakeSortedClusters do
			if #snakeSortedClusters[i] > 0 then
				table.insert(unassignedClusters, i)
			end
		end

		-- Assign builders to clusters greedily based on global minimum distance
		while #unassignedBuilders > 0 and #unassignedClusters > 0 do
			local minDistance, bestBuilder, bestCluster = math.huge, nil, nil

			for _, builderIdx in ipairs(unassignedBuilders) do
				local builder = builders[builderIdx]
				for _, clusterIdx in ipairs(unassignedClusters) do
					local centroid = clusterCentroids[clusterIdx]
					if centroid then
						local distance = calculateDistance(builder.x, builder.z, centroid.x, centroid.z)
						if distance < minDistance then
							minDistance = distance
							bestBuilder = builderIdx
							bestCluster = clusterIdx
						end
					end
				end
			end

			if bestBuilder and bestCluster then
				builderAssignments[bestBuilder] = snakeSortedClusters[bestCluster]

				-- Remove assigned builder and cluster from unassigned lists
				for i, builderIdx in ipairs(unassignedBuilders) do
					if builderIdx == bestBuilder then
						table.remove(unassignedBuilders, i)
						break
					end
				end
				for i, clusterIdx in ipairs(unassignedClusters) do
					if clusterIdx == bestCluster then
						table.remove(unassignedClusters, i)
						break
					end
				end
			else
				break -- No valid assignments left
			end
		end

		for i, builder in ipairs(builders) do
			local builderCommands = table.copy(builderAssignments[i] or {})
			for _, clusterCommands in ipairs(snakeSortedClusters) do
				if builderAssignments[i] ~= clusterCommands then
					-- Toggle between forward and backwards looping based on whether i is even or odd
					local loopStart, loopEnd, loopStep
					if i % 2 == 1 then
						loopStart, loopEnd, loopStep = #clusterCommands, 1, -1
					else
						loopStart, loopEnd, loopStep = 1, #clusterCommands, 1
					end

					for k = loopStart, loopEnd, loopStep do
						local clusterCommand = clusterCommands[k]
						if table.contains(builder.def.buildOptions, -clusterCommand.id) then
							table.insert(builderCommands, clusterCommand)
						elseif replacementMap[-clusterCommand.id] then
							for replacementN = 1, #replacementMap[-clusterCommand.id] or 0 do
								local replacementId = replacementMap[-clusterCommand.id][replacementN]
								if table.contains(builder.def.buildOptions, replacementId) then
									local temp = table.copy(clusterCommand)
									temp[1] = -replacementId
									table.insert(builderCommands, temp)
									break
								end
							end
						end
					end
				end
			end
			Spring.GiveOrderToUnit(builder.id, CMD.STOP, {}, {})
			local maxNCommands = 510
			if #builderCommands > maxNCommands then
				-- Truncate the table to maxNCommands elements
				for k = #builderCommands, maxNCommands + 1, -1 do
					builderCommands[k] = nil
				end
			end
			Spring.GiveOrderArrayToUnit(builder.id, builderCommands)
		end
	-- Ctrl+F - Transpose
	elseif not mods['alt'] and not mods['shift'] then
		-- Filter to only build commands and generate signature
		commands = getBuildCommandsOnly(commands)
		local currentSignature = generateBuildOrderSignature(commands)

		-- Reset states if working with new build orders (less than 90% similar)
		if not signaturesAreSimilar(lastBuildOrderSignature, currentSignature) then
			transposeMode = nil
			cornerRotation = 0
			lastBuildOrderSignature = currentSignature
		end

		if transposeMode == nil then
			-- First use: auto-detect current mode and use the OPPOSITE as starting mode
			local detectedMode = 'row_first' -- default fallback

			-- Analyze current queue to detect traversal pattern
			if #commands >= 3 then
				local firstThree = {commands[1], commands[2], commands[3]}
				local isRowFirst = true
				local isColFirst = true

				-- Check if first 3 commands follow row-first pattern (same Z, different X)
				if
					firstThree[1].z and firstThree[2].z and firstThree[3].z and firstThree[1].x and firstThree[2].x and firstThree[3].x
				 then
					if not (math.abs(firstThree[1].z - firstThree[2].z) < 1 and math.abs(firstThree[2].z - firstThree[3].z) < 1) then
						isRowFirst = false
					end
					if not (math.abs(firstThree[1].x - firstThree[2].x) < 1 and math.abs(firstThree[2].x - firstThree[3].x) < 1) then
						isColFirst = false
					end
				end

				if isRowFirst and not isColFirst then
					detectedMode = 'row_first'
				elseif isColFirst and not isRowFirst then
					detectedMode = 'col_first'
				end
			end

			-- Set to OPPOSITE of detected mode (so first press gives you the transposed version)
			transposeMode = (detectedMode == 'row_first') and 'col_first' or 'row_first'
		else
			-- Subsequent uses: just toggle
			transposeMode = (transposeMode == 'row_first') and 'col_first' or 'row_first'
		end

		local builders = {}
		for i = 1, #selectedUnitIds do
			local unitId = selectedUnitIds[i]
			local x, _, z = Spring.GetUnitPosition(unitId)
			local def = UnitDefs[Spring.GetUnitDefID(unitId)]
			if def and def.buildOptions and #def.buildOptions > 0 then
				table.insert(builders, {id = unitId, x = x, z = z, def = def})
			end
		end

		if #builders == 0 or #commands == 0 then
			return
		end

		-- Analyze spatial positions to determine grid structure
		local uniqueX, uniqueZ = {}, {}
		for _, command in ipairs(commands) do
			if command.x and command.z then
				uniqueX[command.x] = true
				uniqueZ[command.z] = true
			end
		end

		local xPositions, zPositions = {}, {}
		for x in pairs(uniqueX) do
			table.insert(xPositions, x)
		end
		for z in pairs(uniqueZ) do
			table.insert(zPositions, z)
		end
		table.sort(xPositions)
		table.sort(zPositions)

		local numCols, numRows = #xPositions, #zPositions
		if numCols == 0 or numRows == 0 then
			return
		end

		-- Create spatial matrix: map each command to its grid position
		local spatialMatrix = {}
		for row = 1, numRows do
			spatialMatrix[row] = {}
		end

		for _, command in ipairs(commands) do
			if command.x and command.z then
				local col, row = nil, nil
				for i, x in ipairs(xPositions) do
					if math.abs(command.x - x) < 1 then
						col = i
						break
					end
				end
				for i, z in ipairs(zPositions) do
					if math.abs(command.z - z) < 1 then
						row = i
						break
					end
				end
				if col and row then
					spatialMatrix[row][col] = command
				end
			end
		end

		-- Find the starting corner using same logic as corner rotation command
		local builderCentroid = {x = selectedPos.x or 0, z = selectedPos.z or 0}
		local corners = {
			{row = 1, col = 1}, -- bottom-left
			{row = 1, col = numCols}, -- bottom-right
			{row = numRows, col = numCols}, -- top-right
			{row = numRows, col = 1} -- top-left
		}

		-- Find natural starting corner (closest to builders) then apply rotation
		local naturalCornerIndex = 1
		local minDistance = math.huge
		for i, corner in ipairs(corners) do
			local x = xPositions[corner.col]
			local z = zPositions[corner.row]
			local dist = (x - builderCentroid.x) ^ 2 + (z - builderCentroid.z) ^ 2
			if dist < minDistance then
				minDistance = dist
				naturalCornerIndex = i
			end
		end

		-- Apply current corner rotation
		local startCornerIndex = ((naturalCornerIndex - 1 + cornerRotation) % 4) + 1
		local startCorner = corners[startCornerIndex]

		-- Snake traversal based on mode and starting corner
		local orderedCommands = {}
		if transposeMode == 'row_first' then
			-- Snake row-first: alternate column direction for each row
			local rowStep = (startCorner.row == 1) and 1 or -1
			local baseColStep = (startCorner.col == 1) and 1 or -1

			for r = 0, numRows - 1 do
				local row = startCorner.row + (r * rowStep)
				if row < 1 then
					row = numRows + row
				end
				if row > numRows then
					row = row - numRows
				end

				-- Alternate column direction for snake pattern
				local colStep = (r % 2 == 0) and baseColStep or -baseColStep
				local colStart = (colStep == 1) and 1 or numCols
				local colEnd = (colStep == 1) and numCols or 1

				for c = colStart, colEnd, colStep do
					if spatialMatrix[row] and spatialMatrix[row][c] then
						table.insert(orderedCommands, spatialMatrix[row][c])
					end
				end
			end
		else
			-- Snake column-first: alternate row direction for each column
			local colStep = (startCorner.col == 1) and 1 or -1
			local baseRowStep = (startCorner.row == 1) and 1 or -1

			for c = 0, numCols - 1 do
				local col = startCorner.col + (c * colStep)
				if col < 1 then
					col = numCols + col
				end
				if col > numCols then
					col = col - numCols
				end

				-- Alternate row direction for snake pattern
				local rowStep = (c % 2 == 0) and baseRowStep or -baseRowStep
				local rowStart = (rowStep == 1) and 1 or numRows
				local rowEnd = (rowStep == 1) and numRows or 1

				for r = rowStart, rowEnd, rowStep do
					if spatialMatrix[r] and spatialMatrix[r][col] then
						table.insert(orderedCommands, spatialMatrix[r][col])
					end
				end
			end
		end

		Spring.GiveOrderToUnitArray(selectedUnitIds, CMD.STOP, {})
		Spring.GiveOrderArrayToUnitArray(selectedUnitIds, orderedCommands)
	-- Ctrl+Alt+Shift+F - Rotate starting corner clockwise
	elseif mods['alt'] and mods['shift'] then
		-- Filter to only build commands and generate signature
		commands = getBuildCommandsOnly(commands)
		local currentSignature = generateBuildOrderSignature(commands)

		-- Reset states if working with new build orders (less than 90% similar)
		if not signaturesAreSimilar(lastBuildOrderSignature, currentSignature) then
			transposeMode = nil
			cornerRotation = 0
			lastBuildOrderSignature = currentSignature
		end

		-- Ctrl+Alt+Shift+F: Rotate starting corner clockwise
		cornerRotation = (cornerRotation + 1) % 4

		local builders = {}
		for i = 1, #selectedUnitIds do
			local unitId = selectedUnitIds[i]
			local x, _, z = Spring.GetUnitPosition(unitId)
			local def = UnitDefs[Spring.GetUnitDefID(unitId)]
			if def and def.buildOptions and #def.buildOptions > 0 then
				table.insert(builders, {id = unitId, x = x, z = z, def = def})
			end
		end

		if #builders == 0 or #commands == 0 then
			return
		end

		-- Analyze spatial positions to determine grid structure
		local uniqueX, uniqueZ = {}, {}
		for _, command in ipairs(commands) do
			if command.x and command.z then
				uniqueX[command.x] = true
				uniqueZ[command.z] = true
			end
		end

		local xPositions, zPositions = {}, {}
		for x in pairs(uniqueX) do
			table.insert(xPositions, x)
		end
		for z in pairs(uniqueZ) do
			table.insert(zPositions, z)
		end
		table.sort(xPositions)
		table.sort(zPositions)

		local numCols, numRows = #xPositions, #zPositions
		if numCols == 0 or numRows == 0 then
			return
		end

		-- Create spatial matrix: map each command to its grid position
		local spatialMatrix = {}
		for row = 1, numRows do
			spatialMatrix[row] = {}
		end

		for _, command in ipairs(commands) do
			if command.x and command.z then
				local col, row = nil, nil
				for i, x in ipairs(xPositions) do
					if math.abs(command.x - x) < 1 then
						col = i
						break
					end
				end
				for i, z in ipairs(zPositions) do
					if math.abs(command.z - z) < 1 then
						row = i
						break
					end
				end
				if col and row then
					spatialMatrix[row][col] = command
				end
			end
		end

		-- Define corners in clockwise order: bottom-left, bottom-right, top-right, top-left
		local corners = {
			{row = 1, col = 1}, -- bottom-left
			{row = 1, col = numCols}, -- bottom-right
			{row = numRows, col = numCols}, -- top-right
			{row = numRows, col = 1} -- top-left
		}

		-- Find natural starting corner (closest to builders) then rotate from it
		local builderCentroid = {x = selectedPos.x or 0, z = selectedPos.z or 0}
		local naturalCornerIndex = 1
		local minDistance = math.huge
		for i, corner in ipairs(corners) do
			local x = xPositions[corner.col]
			local z = zPositions[corner.row]
			local dist = (x - builderCentroid.x) ^ 2 + (z - builderCentroid.z) ^ 2
			if dist < minDistance then
				minDistance = dist
				naturalCornerIndex = i
			end
		end

		-- Apply corner rotation
		local startCornerIndex = ((naturalCornerIndex - 1 + cornerRotation) % 4) + 1
		local startCorner = corners[startCornerIndex]

		-- Snake traverse using current transpose mode from the rotated starting corner
		local orderedCommands = {}
		if transposeMode == 'row_first' then
			-- Snake row-first: alternate column direction for each row
			local rowStep = (startCorner.row == 1) and 1 or -1
			local baseColStep = (startCorner.col == 1) and 1 or -1

			for r = 0, numRows - 1 do
				local row = startCorner.row + (r * rowStep)
				if row < 1 then
					row = numRows + row
				end
				if row > numRows then
					row = row - numRows
				end

				-- Alternate column direction for snake pattern
				local colStep = (r % 2 == 0) and baseColStep or -baseColStep
				local colStart = (colStep == 1) and 1 or numCols
				local colEnd = (colStep == 1) and numCols or 1

				for c = colStart, colEnd, colStep do
					if spatialMatrix[row] and spatialMatrix[row][c] then
						table.insert(orderedCommands, spatialMatrix[row][c])
					end
				end
			end
		else
			-- Snake column-first: alternate row direction for each column
			local colStep = (startCorner.col == 1) and 1 or -1
			local baseRowStep = (startCorner.row == 1) and 1 or -1

			for c = 0, numCols - 1 do
				local col = startCorner.col + (c * colStep)
				if col < 1 then
					col = numCols + col
				end
				if col > numCols then
					col = col - numCols
				end

				-- Alternate row direction for snake pattern
				local rowStep = (c % 2 == 0) and baseRowStep or -baseRowStep
				local rowStart = (rowStep == 1) and 1 or numRows
				local rowEnd = (rowStep == 1) and numRows or 1

				for r = rowStart, rowEnd, rowStep do
					if spatialMatrix[r] and spatialMatrix[r][col] then
						table.insert(orderedCommands, spatialMatrix[r][col])
					end
				end
			end
		end

		Spring.GiveOrderToUnitArray(selectedUnitIds, CMD.STOP, {})
		Spring.GiveOrderArrayToUnitArray(selectedUnitIds, orderedCommands)
	end
end

-- Handles Alt+E for reclaim command
local function handleAltEKey(selectedUnitIds)
	local reclaimers, reclaimCommands = {}, {}
	for i = 1, #selectedUnitIds do
		local unitID = selectedUnitIds[i]
		if unitDef(unitID).canReclaim then
			table.insert(reclaimers, unitID)
		else
			table.insert(reclaimCommands, {CMD.RECLAIM, unitID, {'shift'}})
		end
	end
	Spring.GiveOrderArrayToUnitArray(reclaimers, reclaimCommands)
end

local function handleSpamFactories(selectedUnitIds)
	local factories = {}
	for i = 1, #selectedUnitIds do
		local unitID = selectedUnitIds[i]
		local def = unitDef(unitID)
		if def.isBuilder and def.isBuilding then
			table.insert(factories, unitID)
		end
	end
	Spring.GiveOrderArrayToUnitArray(factories, spamUnits)
end

-- Calculate distance between chunks (last command of chunk1 to first command of chunk2)
local function calculateChunkDistance(chunk1, chunk2)
	if not chunk1.commands or #chunk1.commands == 0 or
	   not chunk2.commands or #chunk2.commands == 0 then
		return math.huge
	end

	local lastCmd = chunk1.commands[#chunk1.commands]
	local firstCmd = chunk2.commands[1]

	if lastCmd.params and lastCmd.params[1] and lastCmd.params[3] and
	   firstCmd.params and firstCmd.params[1] and firstCmd.params[3] then
		return Distance(lastCmd.params[1], lastCmd.params[3], firstCmd.params[1], firstCmd.params[3])
	end

	return math.huge
end

-- Optimize chunk order using a simple greedy approach (nearest neighbor)
local function optimizeChunkOrder(chunks, builderPos)
	if #chunks <= 1 then
		return chunks
	end

	local optimizedOrder = {}
	local remaining = {}
	for i, chunk in ipairs(chunks) do
		remaining[i] = chunk
	end

	-- Start with chunk closest to builder position
	local startIndex = 1
	local minDistance = math.huge
	for i, chunk in ipairs(remaining) do
		if chunk.commands and #chunk.commands > 0 then
			local cmd = chunk.commands[1]
			if cmd.params and cmd.params[1] and cmd.params[3] and builderPos then
				local dist = Distance(builderPos.x or 0, builderPos.z or 0, cmd.params[1], cmd.params[3])
				if dist < minDistance then
					minDistance = dist
					startIndex = i
				end
			end
		end
	end

	table.insert(optimizedOrder, remaining[startIndex])
	table.remove(remaining, startIndex)

	-- Greedily select next closest chunk
	while #remaining > 0 do
		local currentChunk = optimizedOrder[#optimizedOrder]
		local nextIndex = 1
		local minChunkDistance = math.huge

		for i, chunk in ipairs(remaining) do
			local dist = calculateChunkDistance(currentChunk, chunk)
			if dist < minChunkDistance then
				minChunkDistance = dist
				nextIndex = i
			end
		end

		table.insert(optimizedOrder, remaining[nextIndex])
		table.remove(remaining, nextIndex)
	end

	return optimizedOrder
end

-- Handles Shift+Q for build queue redundancy - distributes all build commands to all builders
local function buildQueueRedundancy(selectedUnitIds, mods)
	if #selectedUnitIds < 2 then
		return  -- Need at least 2 units for redundancy
	end

	-- Get all builders from selected units
	local builders = {}
	for i = 1, #selectedUnitIds do
		local unitId = selectedUnitIds[i]
		local unitDefId = Spring.GetUnitDefID(unitId)
		local def = UnitDefs[unitDefId]
		if def and def.buildOptions and #def.buildOptions > 0 then
			local x, _, z = Spring.GetUnitPosition(unitId)
			table.insert(builders, {
				id = unitId,
				def = def,
				buildOptions = def.buildOptions,
				x = x,
				z = z
			})
		end
	end

	if #builders < 2 then
		return  -- Need at least 2 builders for redundancy
	end

	-- Collect all build commands from all builders
	local allCommandChunks = {}  -- Array of {builderId, commands}
	local allUniqueCommands = {}  -- Map of signature -> command

	for _, builder in ipairs(builders) do
		local commands = Spring.GetUnitCommands(builder.id, 1000)
		if commands then
			local buildCommands = getBuildCommandsOnly(commands)
			if #buildCommands > 0 then
				table.insert(allCommandChunks, {
					builderId = builder.id,
					commands = buildCommands
				})

				-- Add to unique commands collection (for duplicate detection)
				for _, command in ipairs(buildCommands) do
					local signature = generateCommandSignature(command)
					if signature then
						allUniqueCommands[signature] = command
					end
				end
			end
		end
	end

	if #allCommandChunks == 0 then
		return  -- No build commands found
	end

	-- For each builder, create new command queue with optimized chunk order
	for _, targetBuilder in ipairs(builders) do
		local newCommands = {}
		local existingSignatures = {}

		-- First, get existing commands for this builder to avoid duplicates
		local existingCommands = Spring.GetUnitCommands(targetBuilder.id, 1000)
		if existingCommands then
			local existingBuildCommands = getBuildCommandsOnly(existingCommands)
			for _, command in ipairs(existingBuildCommands) do
				local signature = generateCommandSignature(command)
				if signature then
					existingSignatures[signature] = true
					table.insert(newCommands, command)  -- Keep existing commands
				end
			end
		end

		-- Get chunks from other builders (not this builder's own commands)
		local chunksToAdd = {}
		for _, chunk in ipairs(allCommandChunks) do
			if chunk.builderId ~= targetBuilder.id then
				local chunkCommands = {}

				-- Filter commands this builder can actually build
				for _, command in ipairs(chunk.commands) do
					local signature = generateCommandSignature(command)
					if signature and not existingSignatures[signature] then
						-- Check if builder can build this unit
						if table.contains(targetBuilder.buildOptions, -command.id) then
							table.insert(chunkCommands, command)
							existingSignatures[signature] = true
						end
					end
				end

				if #chunkCommands > 0 then
					table.insert(chunksToAdd, {
						builderId = chunk.builderId,
						commands = chunkCommands
					})
				end
			end
		end

		-- Optimize chunk order for this builder
		if #chunksToAdd > 0 then
			local optimizedChunks = optimizeChunkOrder(chunksToAdd, {x = targetBuilder.x, z = targetBuilder.z})

			-- Add optimized chunks to command queue
			for _, chunk in ipairs(optimizedChunks) do
				for _, command in ipairs(chunk.commands) do
					table.insert(newCommands, command)
				end
			end
		end

		-- Apply new command queue to builder
		if #newCommands > 0 then
			-- Stop current commands and give new ones
			Spring.GiveOrderToUnit(targetBuilder.id, CMD.STOP, {}, {})

			-- Limit to max commands to avoid overwhelming the unit
			local maxNCommands = 500
			if #newCommands > maxNCommands then
				for k = #newCommands, maxNCommands + 1, -1 do
					newCommands[k] = nil
				end
			end

			Spring.GiveOrderArrayToUnit(targetBuilder.id, newCommands)
		end
	end
end

function widget:KeyPress(key, mods, isRepeat)
	if isRepeat then
		return false
	end

	if key == KEYSYMS.W and mods['ctrl'] and mods['alt'] and mods['shift'] then
		handleCheatGiveUnits()
		return
	end

	local activeCommand = select(2, Spring.GetActiveCommand())
	if activeCommand ~= nil and activeCommand ~= 0 then
		conCycleNumber = nil
		return false
	end

	local selectedUnitIds = Spring.GetSelectedUnits()

	if (key == KEYSYMS.A or key == KEYSYMS.S or key == KEYSYMS.D) and mods['alt'] then
		return conQueueSliceCommand(key, selectedUnitIds, mods)
	elseif (key == KEYSYMS.F) and mods['ctrl'] then
		buildQueueDistributeTransform(selectedUnitIds, mods)
	elseif (key == KEYSYMS.F) and mods['shift'] and mods['alt'] and not mods['ctrl'] then
		buildQueueOptimalPooling(selectedUnitIds, mods)
	elseif key == KEYSYMS.Q and mods['shift'] and not mods['alt'] and not mods['ctrl'] then
		buildQueueRedundancy(selectedUnitIds, mods)
	elseif key == KEYSYMS.E and mods['alt'] and not mods['shift'] and mods['ctrl'] then
		handleAltEKey(selectedUnitIds)
	elseif key == KEYSYMS.G and mods.alt then
		handleSpamFactories(selectedUnitIds)
	end
end
