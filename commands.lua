function widget:GetInfo()
	return {
		name = 'Commands',
		desc = 'some commands for editing constructor build queue, and automatic geo toggling',
		author = '-',
		date = 'dec, 2016',
		license = 'GNU GPL, v3 or later',
		layer = 99,
		enabled = true,
	}
end

VFS.Include('luaui/Widgets/.noload/misc/helpers.lua')
VFS.Include('luaui/Headers/keysym.h.lua')

local selectPrios = {'ack_scav', 'ack','aca_scav', 'aca', 'acv_scav','acv', 'ca_scav','ca', 'ck_scav','ck', 'cv', 'cv_scav' }
local selectPriosAir = { 'aca_scav', 'aca', 'ca'}
local selectPriosNonScav = { 'ack', 'aca', 'acv', 'ca', 'ck', 'cv' }
local selectPriosAirNonScav = { 'aca', 'ca' }
local factionPrios = { 'arm', 'cor', 'leg' }
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
	UnitDefNames['legnanotct2plat'] and UnitDefNames['legnanotct2plat'].id or nil,
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
	'legfortt4_scav',
}

local spamUnits = {}
for _, unitName in ipairs(spamUnitNames) do
	if UnitDefNames[unitName] then
		table.insert(spamUnits, {-UnitDefNames[unitName].id})
	end
end
table.insert(spamUnits, {CMD.REPEAT, 1})
table.insert(spamUnits, {34570,0})
table.insert(spamUnits, {34569,0})

local replacementMap = {}
local mousePos = {0,0,0}

-- Fill replacementMap: for each unitdef, strip faction prefix and find all faction alternatives
local factionPrefixes = { 'arm', 'cor', 'leg' }
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
		if unitDef.isBuilder and unitDef.isBuilding and unitDef.canAssist and not table.contains(immobileBuilderDefIds, unitDefId) then
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
		Spring.GiveOrderToUnit(unit_id, CMD.REMOVE, { cmd_queue[2].tag }, { nil })
	end
	Spring.GiveOrderToUnit(unit_id, CMD.REMOVE, { cmd_queue[1].tag }, { nil })
end

local function removeLastCommand(unit_id)
	local cmd_queue = Spring.GetUnitCommands(unit_id, 5000)
	local remove_cmd = cmd_queue[#cmd_queue]
	if remove_cmd['id'] == 0 then
		Spring.GiveOrderToUnit(unit_id, CMD.REMOVE, { cmd_queue[#cmd_queue - 1].tag }, { nil })
	end
	Spring.GiveOrderToUnit(unit_id, CMD.REMOVE, { cmd_queue[#cmd_queue].tag }, { nil })
end

local function unitDef(unitId)
	return UnitDefs[Spring.GetUnitDefID(unitId)]
end

local function reverseQueue(unit_id)
	local queue = Spring.GetCommandQueue(unit_id, 10000)
	Spring.GiveOrderToUnit(unit_id, CMD.INSERT, { -1, CMD.STOP, CMD.OPT_SHIFT }, { 'alt' })
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
	local faction = (key == KEYSYMS.D and 'arm') or (key == KEYSYMS.S and 'cor') or 'leg'
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
				builders = Spring.GetTeamUnitsByDefs(myTeamId, { UnitDefNames[unitName].id })
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
	elseif #temp==2 then
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

local function distance(p1, p2)
	if not p1 or not p1.x or not p1.z or not p2 or not p2.x or not p2.z then
		return 0
	end
	return math.sqrt((p1.x - p2.x) ^ 2 + (p1.z - p2.z) ^ 2)
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

	local aDistanceToSelected = (a.x - selectedPos.x) * (a.x - selectedPos.x) + (a.z - selectedPos.z) * (a.z - selectedPos.z)

	local bDistanceToSelected = (b.x - selectedPos.x) * (b.x - selectedPos.x) + (b.z - selectedPos.z) * (b.z - selectedPos.z)
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
				local dist = distance(future_building, building)
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

		for _, direction in ipairs({ 'horizontal', 'vertical' }) do
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
				local dist = distance(current_building, building)
				if dist < closest_distance then
					closest_distance = dist
					best_path_buildings = { building }
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
	return { x = sum_x / #cluster, z = sum_z / #cluster }
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

	Spring.SendCommands('give 1 armca')
	Spring.SendCommands('give 1 corca')
	Spring.SendCommands('give 1 legca')
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
local function handleAltASDKey(key, selectedUnitIds, mods)
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
					Spring.GiveOrderToUnit(unit_id, CMD.INSERT, { -1, CMD.STOP, CMD.OPT_SHIFT }, { 'alt' })
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
				builders[i] = { id = unit_id, x = x, z = z }
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

-- Handles Ctrl+F for merging and sorting build commands
local function handleCtrlFKey(selectedUnitIds, mods)
	if #selectedUnitIds == 0 then
		return
	end
	local mergedCommands = {}
	for i = 1, #selectedUnitIds do
		local commands = Spring.GetUnitCommands(selectedUnitIds[i], 1000)
		for j = 1, #commands do
			local command = commands[j]
			if command.id < 1 then
				local commandString = tostring(commands[j].id)
					.. ' '
					.. tostring(commands[j].params[1])
					.. ' '
					.. tostring(commands[j].params[2])
					.. ' '
					.. tostring(commands[j].params[3])
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
	selectedPos = { x = median(xPositions), z = median(zPositions) }
	local allImmobileBuilders = Spring.GetTeamUnitsByDefs(myTeamId, immobileBuilderDefIds)
	for i = 1, #allImmobileBuilders do
		local x, _, z = Spring.GetUnitPosition(allImmobileBuilders[i])
		if x and z then
			allImmobileBuilders[i] = {
				id = allImmobileBuilders[i],
				x = x,
				z = z,
				buildDistance = immobileBuilderDefs[Spring.GetUnitDefID(allImmobileBuilders[i])],
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
			z = command.params and command.params[3],
		}
		if command.params[1] and command.params[3] then
			for j = 1, #allImmobileBuilders do
				local builder = allImmobileBuilders[j]
				if builder.buildDistance and Distance(builder.x, builder.z, command.params[1], command.params[3]) < builder.buildDistance then
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

	if not mods['shift'] and not mods['alt'] then
		table.sort(commands, SortbuildSpeedDistance)
		commands = snake_sort_with_lookahead(commands, lookahead_steps)
		Spring.GiveOrderToUnitArray(selectedUnitIds, CMD.STOP, {}, {})
		Spring.GiveOrderArrayToUnitArray(selectedUnitIds, commands)
	elseif mods['shift'] and not mods['alt'] then
		local builders = {}
		for i = 1, #selectedUnitIds do
			local unitId = selectedUnitIds[i]
			local x, _, z = Spring.GetUnitPosition(unitId)
			local def = UnitDefs[Spring.GetUnitDefID(unitId)]
			if def and def.buildOptions and #def.buildOptions > 0 then
				table.insert(builders, { id = unitId, x = x, z = z, buildSpeed = 1, def = def })
			end
		end
		local clusters = kmeans(commands, #builders, 100)
		local snakeSortedClusters = {}
		for i, cluster in ipairs(clusters) do
			table.sort(cluster, SortbuildSpeedDistance)
			snakeSortedClusters[i] = snake_sort_with_lookahead(cluster, lookahead_steps)
		end
		local builderAssignments, assignedClusters = {}, {}
		for i, builder in ipairs(builders) do
			local minDistance, closestCluster, closestClusterIndex = math.huge, nil, nil
			for j, cluster in ipairs(snakeSortedClusters) do
				if not assignedClusters[j] then
					local firstCommand = cluster[1]
					if firstCommand ~= nil then
						local builderBuildingDistance = calculateDistance(builder.x, builder.z, firstCommand[2][1], firstCommand[2][2])
						if builderBuildingDistance < minDistance then
							minDistance = builderBuildingDistance
							closestCluster = cluster
							closestClusterIndex = j
						end
					end
				end
			end
			if closestCluster ~= nil and closestClusterIndex ~= nil then
				builderAssignments[i] = closestCluster
				assignedClusters[closestClusterIndex] = true
			end
		end
		for i, builder in ipairs(builders) do
			local builderCommands = deepcopy(builderAssignments[i] or {})
			for j, clusterCommands in ipairs(snakeSortedClusters) do
				if builderAssignments[i] ~= clusterCommands then
					for k = 1, #clusterCommands do
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
			Spring.GiveOrderArrayToUnit(builder.id, builderCommands)
		end
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
			table.insert(reclaimCommands, { CMD.RECLAIM, unitID, { 'shift' } })
		end
	end
	Spring.GiveOrderArrayToUnitArray(reclaimers, reclaimCommands)
end

local function handleSpamFactories(selectedUnitIds)
	local factories= {}
	for i = 1, #selectedUnitIds do
		local unitID = selectedUnitIds[i]
		local def = unitDef(unitID)
		if def.isBuilder and def.isBuilding then
			table.insert(factories, unitID)
		end
	end
	Spring.GiveOrderArrayToUnitArray(factories, spamUnits)
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
		return handleAltASDKey(key, selectedUnitIds, mods)
	elseif (key == KEYSYMS.F) and mods['ctrl'] then
		handleCtrlFKey(selectedUnitIds, mods)
	elseif key == KEYSYMS.E and mods['alt'] and not mods['shift'] and mods['ctrl'] then
		handleAltEKey(selectedUnitIds)
	elseif key == KEYSYMS.G and mods.alt then
		handleSpamFactories(selectedUnitIds)
	end
end
