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

local myTeamId = Spring.GetMyTeamID()

-- local selectSplitKeys = {
--   [KEYSYMS.Q] = 2,
--   [KEYSYMS.W] = 3,
--   [KEYSYMS.E] = 4,
-- }
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

local selectPrios = { 'ack', 'aca', 'acv', 'ca', 'ck', 'cv' }
local factionPrios = { 'arm', 'cor', 'leg' }

local immobileBuilderDefs = {}
for _, immobileBuilderDefId in ipairs(immobileBuilderDefIds) do
	immobileBuilderDefs[immobileBuilderDefId] = UnitDefs[immobileBuilderDefId].buildDistance + 96
end

local selectedPos = {}
local unitIdBuildSpeeds = LRUCache:new(100)
local isShieldDefId = {}
local mousePos = {}
local conCycleNumber
local selectCheckTimer = Spring.GetTimer()
local splitBuilderWatch = {}

function widget:Initialize()
	Spring.SendCommands('bind Shift+Alt+sc_q buildfacing inc')
	Spring.SendCommands('bind Shift+Alt+sc_e buildfacing dec')
	if Spring.GetSpectatingState() or Spring.IsReplay() then
		widgetHandler:RemoveWidget()
	end

	for unitDefId, unitDef in pairs(UnitDefs) do
		if unitDef.isBuilding and unitDef.hasShield then
			isShieldDefId[unitDefId] = unitDef.customParams and unitDef.customParams.shield_radius and 1 or 0
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
		-- remove real command before empty one
		Spring.GiveOrderToUnit(unit_id, CMD.REMOVE, { cmd_queue[2].tag }, { nil })
	end
	Spring.GiveOrderToUnit(unit_id, CMD.REMOVE, { cmd_queue[1].tag }, { nil })
end

local function removeLastCommand(unit_id)
	local cmd_queue = Spring.GetUnitCommands(unit_id, 5000)
	local remove_cmd = cmd_queue[#cmd_queue]
	-- empty commands are somehow put between cmds,
	-- but not by the "space/add to start of cmdqueue" widget
	if remove_cmd['id'] == 0 then
		-- remove empty command
		Spring.GiveOrderToUnit(unit_id, CMD.REMOVE, { cmd_queue[#cmd_queue - 1].tag }, { nil })
	end
	-- remove the last command
	Spring.GiveOrderToUnit(unit_id, CMD.REMOVE, { cmd_queue[#cmd_queue].tag }, { nil })
end

-- function updateGeoDefs()
--   geos = {}
--   for _, unitId in ipairs(GetTeamUnits(Spring.GetMyTeamID())) do
--     local unitDefId = Spring.GetUnitDefID(unitId)
--     local udef = unitDef(unitId)
--     if udef.name:find('geo') or udef.humanName:find('[Gg]eo') or udef.humanName:match('Resource Fac') then

--       local m = udef.makesMetal - udef.metalUpkeep
--       local e = udef.energyUpkeep
--       local eff = m/e
--       geos[unitId] = {m, e, eff, true}
--     end
--   end
--   table.sort(geos, function(a,b) return a[2] < b[2] end)
-- end

-- local function setGeos()
--   updateGeoDefs()
--   Spring.GiveOrderToUnitMap(geos, CMD.ONOFF, { geos_on and 1 or 0 }, {} )
-- end

-- function widget:GameFrame(n)
--   if n % mainIterationModuloLimit == 0 then
--     local mm_level = GetTeamRulesParam(myTeamId, 'mmLevel')
--     local e_curr, e_max, e_pull, e_inc, e_exp = GetTeamResources(myTeamId, 'energy')
--     local energyLevel = e_curr/e_max
--     local isPositiveEnergyDerivative = e_inc > (e_pull+e_exp)/2

--     table.insert(regularizedResourceDerivativesEnergy, 1, isPositiveEnergyDerivative)
--     if #regularizedResourceDerivativesEnergy > 7 then
--       table.remove(regularizedResourceDerivativesEnergy)
--     end

--     regularizedPositiveEnergy = table.full_of(regularizedResourceDerivativesEnergy, true)
--     regularizedNegativeEnergy = table.full_of(regularizedResourceDerivativesEnergy, false)

--     if not geos_on and regularizedPositiveEnergy and energyLevel > mm_level then
--       geos_on = true
--       setGeos()
--     elseif geos_on and energyLevel < mm_level then
--       geos_on = false
--       setGeos()
--     end
--   end
-- end

local function unitDef(unitId)
	return UnitDefs[Spring.GetUnitDefID(unitId)]
end

-- TODO
local function reverseQueue(unit_id)
	--  local states = Spring.GetUnitStates(targetID)

	--  if (states ~= nil) then
	--    Spring.GiveOrderToUnit(unitID, CMD.FIRE_STATE, { states.firestate }, 0)
	--    Spring.GiveOrderToUnit(unitID, CMD.MOVE_STATE, { states.movestate }, 0)
	--    Spring.GiveOrderToUnit(unitID, CMD.REPEAT,     { states['repeat']  and 1 or 0 }, 0)
	--    Spring.GiveOrderToUnit(unitID, CMD.ONOFF,      { states.active     and 1 or 0 }, 0)
	--    Spring.GiveOrderToUnit(unitID, CMD.CLOAK,      { states.cloak      and 1 or 0 }, 0)
	--    Spring.GiveOrderToUnit(unitID, CMD.TRAJECTORY, { states.trajectory and 1 or 0 }, 0)
	--  end

	local queue = Spring.GetCommandQueue(unit_id, 10000)
	Spring.GiveOrderToUnit(unit_id, CMD.INSERT, { -1, CMD.STOP, CMD.OPT_SHIFT }, { 'alt' })
	--  local build_queue = Spring.GetRealBuildQueue(unit_id)

	-- log(table.tostring(queue))
	if queue then
		-- rm queue
		for k, v in ipairs(queue) do --  in order
			--    Spring.GiveOrderToUnit(unit_id, CMD.INSERT, { -1, CMD.STOP, CMD.OPT_SHIFT }, { "alt" })
		end

		--    for int k,v in ipairs(queue) do  --  in order
		--    for k,v in ipairs(queue) do  --  in order
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
				--        Spring.GiveOrderToUnit(unit_id, v.id, v.params, options.coded)
				--         log(v.id)
				--         log(v.params)
				-- --        table.insert(v.params, 1, 0)
				--         log(v.params)
				--         log(options.coded)
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

local function KeyUnits(key)
	key = (key == KEYSYMS.D and 'arm') or (key == KEYSYMS.S and 'cor') or 'leg'
	local builders

	for j = 0, #factionPrios do
		for i = 1, #selectPrios do
			local unitName = (j == 0 and key or factionPrios[j]) .. selectPrios[i]
			if UnitDefNames[unitName] then
				-- log('for', myTeamId, table.tostring({UnitDefNames[unitName].id}))
				builders = Spring.GetTeamUnitsByDefs(myTeamId, { UnitDefNames[unitName].id })
				-- log('for', j, i, factionPrios[j], key .. selectPrios[i], #builders)
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
	table.sort(temp)

	-- If we have an even number of table elements or odd.
	if math.fmod(#temp, 2) == 0 then
		-- return mean value of middle two elements
		return (temp[#temp / 2] + temp[(#temp / 2) + 1]) / 2
	else
		-- return middle element
		return temp[math.ceil(#temp / 2)]
	end
end

local function Distance(x1, y1, x2, y2)
	if x1 == nil or y1 == nil or x2 == nil or y2 == nil then
		return 1000000000
	end
	return math.sqrt((x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2)) or 1000000000
end

local lookahead_steps = 10 -- Number of steps to look ahead for better direction

-- Function to calculate distance between two points
local function distance(p1, p2)
	if not p1 or not p1.x or not p1.z or not p2 or not p2.x or not p2.z then
		return 0
	end
	return math.sqrt((p1.x - p2.x) ^ 2 + (p1.z - p2.z) ^ 2)
end

-- Sort by buildSpeed, shield, and then distance to the selected position (this is the first pass)
local function SortbuildSpeedDistance(a, b)
	if a == nil then
		return false
	elseif b == nil then
		return true
	end

	-- Sort by shield status
	if (a.isShield or 0) > (b.isShield or 0) then
		return true
	elseif (a.isShield or 0) < (b.isShield or 0) then
		return false
	end

	-- Sort by build speed
	if (a.buildSpeed or 0) > (b.buildSpeed or 0) then
		return true
	elseif (a.buildSpeed or 0) < (b.buildSpeed or 0) then
		return false
	end

	-- Sort by proximity to the selected position
	local aDistanceToSelected = (a.x - selectedPos.x) * (a.x - selectedPos.x) + (a.z - selectedPos.z) * (a.z - selectedPos.z)

	local bDistanceToSelected = (b.x - selectedPos.x) * (b.x - selectedPos.x) + (b.z - selectedPos.z) * (b.z - selectedPos.z)
	return aDistanceToSelected < bDistanceToSelected
end

-- Define the direction of movement
local current_direction = 'horizontal' -- could be "horizontal" or "vertical"

-- Function to check if a building is aligned within the tolerance
local function is_in_line(current, next_building, direction)
	if direction == 'horizontal' then
		return current.z == next_building.z
	else
		return current.x == next_building.x
	end
end

-- Helper to evaluate a potential path and its total buildSpeed
local function evaluate_path(current_building, remaining_commands, direction, steps)
	local total_buildSpeed = 0
	local path_commands = {}
	local future_building = current_building

	for step = 1, steps do
		local best_next_building = nil
		local best_distance = math.huge

		-- Look for the next best building along the current direction
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
			-- No more buildings in this direction
			break
		end
	end

	return total_buildSpeed, path_commands
end

-- Lookahead snake-like traversal with bias towards highest build power in future
local function snake_sort_with_lookahead(commands, _lookahead_steps)
	-- Start with the first building in the list
	local sorted_commands = {}
	local current_building = table.remove(commands, 1)
	table.insert(sorted_commands, current_building)

	while #commands > 0 do
		local best_direction = nil
		local best_path_buildings = nil
		local highest_buildSpeed = -math.huge

		-- Evaluate both horizontal and vertical paths
		for _, direction in ipairs({ 'horizontal', 'vertical' }) do
			local total_buildSpeed, path_commands = evaluate_path(current_building, commands, direction, _lookahead_steps)

			-- Choose the direction with the highest total buildSpeed in the lookahead window
			if total_buildSpeed > highest_buildSpeed then
				highest_buildSpeed = total_buildSpeed
				best_direction = direction
				best_path_buildings = path_commands
			end
		end

		-- If no valid path found, fallback to just picking the closest in any direction
		if not best_path_buildings or #best_path_buildings == 0 then
			-- No good direction, fallback to closest building
			local closest_distance = math.huge
			for i, building in ipairs(commands) do
				local dist = distance(current_building, building)
				if dist < closest_distance then
					closest_distance = dist
					best_path_buildings = { building }
				end
			end
		end

		-- Pick the first building from the best path
		if #best_path_buildings > 0 then
			local next_building = table.remove(best_path_buildings, 1)

			-- Remove the selected building from the original commands list
			for i, building in ipairs(commands) do
				if building == next_building then
					table.remove(commands, i)
					break
				end
			end

			-- Update the current building and add to sorted list
			current_building = next_building
			table.insert(sorted_commands, current_building)
		end
	end

	return sorted_commands
end

-- Manhattan distance (for clustering proximity check)
local function manhattan_distance(p1, p2)
	if p1 == nil or p2 == nil or p1.x == nil or p1.z == nil or p2.x == nil or p2.z == nil then
		return 0
	end
	return math.abs(p1.x - p2.x) + math.abs(p1.z - p2.z)
end

-- Calculate the centroid (average position) of a set of points
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

-- K-means clustering algorithm
local function kmeans(commands, k, max_iterations)
	-- Step 1: Randomly select initial cluster centers (centroids)
	local centroids = {}
	for i = 1, k do
		table.insert(centroids, commands[math.random(1, #commands)])
	end

	local clusters = {}
	local prev_centroids = nil
	local iterations = 0

	while iterations < max_iterations do
		-- Step 2: Clear clusters
		clusters = {}
		for i = 1, k do
			clusters[i] = {}
		end

		-- Step 3: Assign each command to the nearest centroid
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

		-- Step 4: Recalculate centroids based on the current clusters
		prev_centroids = centroids
		for i = 1, k do
			if #clusters[i] > 0 then
				centroids[i] = calculate_centroid(clusters[i])
			end
		end

		-- Step 5: Check if centroids have stopped changing (convergence)
		local converged = true
		for i = 1, k do
			if manhattan_distance(prev_centroids[i], centroids[i]) > 0.01 then -- small tolerance
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
	return math.sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2)
end

function widget:KeyPress(key, mods, isRepeat)
	if key == KEYSYMS.W and mods['ctrl'] and mods['alt'] and mods['shift'] then
		--  --[[
		Spring.SendCommands('give 1 armbanth')
		Spring.SendCommands('give 1 armcomlvl10')
		Spring.SendCommands('give 1 armlun')
		Spring.SendCommands('give 1 armmar')
		Spring.SendCommands('give 1 armprowl')
		Spring.SendCommands('give 1 armraz')
		Spring.SendCommands('give 1 armthor')
		Spring.SendCommands('give 1 armvang')
		Spring.SendCommands('give 1 corcat')
		Spring.SendCommands('give 1 cordemon')
		Spring.SendCommands('give 1 corjugg')
		Spring.SendCommands('give 1 corkarg')
		Spring.SendCommands('give 1 corkorg')
		Spring.SendCommands('give 1 corshiva')
		Spring.SendCommands('give 1 corsok')
		Spring.SendCommands('give 1 leegmech')
		Spring.SendCommands('give 1 legeheatraymech')
		Spring.SendCommands('give 1 legerailtank')
		Spring.SendCommands('give 1 legeshotgunmech')
		Spring.SendCommands('give 1 legjav')
		Spring.SendCommands('give 1 legkeres')
		-- ]]

		-- Spring.SendCommands('give armaca')
		-- Spring.SendCommands('give coraca')
		-- Spring.SendCommands('give legaca')
		-- Spring.SendCommands('give armack')
		-- Spring.SendCommands('give corack')
		-- Spring.SendCommands('give legack')
		-- Spring.SendCommands('give armacv')
		-- Spring.SendCommands('give coracv')
		-- Spring.SendCommands('give legacv')

		-- Spring.SendCommands('give armaca_scav')
		-- Spring.SendCommands('give coraca_scav')
		-- Spring.SendCommands('give legaca_scav')
		-- Spring.SendCommands('give armack_scav')
		-- Spring.SendCommands('give corack_scav')
		-- Spring.SendCommands('give legack_scav')
		-- Spring.SendCommands('give armacv_scav')
		-- Spring.SendCommands('give coracv_scav')
		-- Spring.SendCommands('give legacv_scav')
		--
		-- Spring.SendCommands('give corafus')

		return
	end
	-- if (key == 114 and mods['ctrl'] and mods['alt']) then
	--   widgetHandler:RemoveWidget()
	--   widgetHandler:
	--   return
	-- end

	-- if key == KEYSYMS.F and mods['ctrl'] and mods ['alt']  and mods['shift'] then
	--   log(Spring.GetUnitCommands(27804, 3))
	-- end
	local activeCommand = select(2, Spring.GetActiveCommand())
	if activeCommand ~= nil and activeCommand ~= 0 then
		conCycleNumber = nil
		return false
	end

	local selectedUnitIds = Spring.GetSelectedUnits()

	local foundCommandQueue = false
	if (key == KEYSYMS.A or key == KEYSYMS.S or key == KEYSYMS.D) and mods['alt'] and not mods['shift'] and not mods['ctrl'] then
		-- elseif selectSplitKeys[key] and mods['alt'] and not mods['shift'] and mods['ctrl'] then
		--   local selected_units = Spring.GetSelectedUnits()
		--   if #selected_units ~= #partitionIds then
		--     partitionIds = {}
		--   end
		--   for i = 1, #selected_units do
		--     partitionIds[selected_units[i]] = true
		--   end
		--   SelectSubset(selected_units, selectSplitKeys[key])
		-- for i, unit_id in ipairs(selected_units) do
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
						-- elseif key == KEYSYMS.A and #cmd_queue > 1 then
						--   reverseQueue(unit_id)
					end
					-- does not seem to stop when removing to an empty queue, therefore:
					if #cmd_queue == 2 then
						Spring.GiveOrderToUnit(unit_id, CMD.INSERT, { -1, CMD.STOP, CMD.OPT_SHIFT }, { 'alt' })
					end
				end
			end
			if foundCommandQueue then
				return false
			end
		end

		if (conCycleNumber == nil or #selectedUnitIds == 0) and not foundCommandQueue then
			-- log('first time')
			conCycleNumber = 1
		end

		log('asdf')
		-- log('#selected_units', #selected_units, 'conCycleNumber', conCycleNumber)

		if #selectedUnitIds == 0 or (#selectedUnitIds > 0 and conCycleNumber ~= nil) then
			local builderIds = KeyUnits(key)

			local builders = {}

			if #builderIds > 0 then
				for i = 1, #builderIds do
					local unit_id = builderIds[i]
					local x, _, z = Spring.GetUnitPosition(unit_id)
					builders[i] = { id = unit_id, x = x, z = z }
				end
				-- sort by proximity to mouse
				local mouseX, mouseY = Spring.GetMouseState()
				_, mousePos = Spring.TraceScreenRay(mouseX, mouseY, true)

				-- log('sorting', table.tostring(builders))
				table.sort(builders, SortMouseDistance)

				-- log('cycleI 1', conCycleNumber)
				conCycleNumber = ((conCycleNumber - 1) % #builderIds) + 1
				-- log('cycleI 2', conCycleNumber)

				Spring.SelectUnit(builders[conCycleNumber].id)
				conCycleNumber = conCycleNumber + 1
			end
		end
	elseif (key == KEYSYMS.F) and mods['ctrl'] then
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

		-- local selectedUnitsMap = {}
		local xPositions = {}
		local zPositions = {}
		for i = 1, #selectedUnitIds do
			-- selectedUnitsMap[selectedUnits[i]] = true
			local x, _, z = Spring.GetUnitPosition(selectedUnitIds[i])
			table.insert(xPositions, x)
			table.insert(zPositions, z)
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

		local commands = {}
		local nCommands = 0
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
					log('cmp dist', Distance(allImmobileBuilders[j].x, allImmobileBuilders[j].z, command.params[1], command.params[3]))
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

		-- preparing commands done

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
				table.insert(builders, { id = unitId, x = x, z = z, buildSpeed = 1 })
			end

			local clusters = kmeans(commands, #builders, 100)

			local snakeSortedClusters = {}
			for i, cluster in ipairs(clusters) do
				table.sort(cluster, SortbuildSpeedDistance)

				snakeSortedClusters[i] = snake_sort_with_lookahead(cluster, lookahead_steps)
			end

			-- for i, builder in ipairs(builders) do
			--   local builderCommands = deepcopy(snakeSortedClusters[i] or {})

			--   for j = 1, #snakeSortedClusters do
			--     if i ~= j then
			--       for k = 1, #snakeSortedClusters[j] do
			--         table.insert(builderCommands, snakeSortedClusters[j][k])
			--       end
			--     end
			--   end

			--   Spring.GiveOrderToUnit(builder.id, CMD.STOP, {}, {})
			--   Spring.GiveOrderArrayToUnit(builder.id, builderCommands)
			-- end

			-- Step 2: Assign builders to the closest cluster based on the distance to the first command in each cluster
			local builderAssignments = {} -- To store which cluster each builder is assigned to
			local assignedClusters = {} -- To mark clusters that are already assigned

			for i, builder in ipairs(builders) do
				local minDistance = math.huge
				local closestCluster = nil
				local closestClusterIndex = nil

				-- Find the closest cluster that hasn't been assigned yet
				for j, cluster in ipairs(snakeSortedClusters) do
					if not assignedClusters[j] then
						-- Get the first command of the cluster to calculate distance
						local firstCommand = cluster[1]
						-- log('firstCommand',firstCommand[2][1], firstCommand[2][2])
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

				-- Assign the builder to the closest cluster and mark it as assigned
				if closestCluster ~= nil and closestClusterIndex ~= nil then
					builderAssignments[i] = closestCluster
					assignedClusters[closestClusterIndex] = true
				end
			end

			-- Step 3: Add secondary tasks for each builder after their primary cluster
			for i, builder in ipairs(builders) do
				local builderCommands = deepcopy(builderAssignments[i] or {})

				-- Assign secondary tasks: other clusters not assigned to this builder
				for j, cluster in ipairs(snakeSortedClusters) do
					if builderAssignments[i] ~= cluster then
						for k = 1, #cluster do
							table.insert(builderCommands, cluster[k])
						end
					end
				end

				-- Stop existing commands and give new command set
				Spring.GiveOrderToUnit(builder.id, CMD.STOP, {}, {})
				Spring.GiveOrderArrayToUnit(builder.id, builderCommands)
			end

			-- for i, cluster in ipairs(clusters) do
			--   table.sort(cluster, SortbuildSpeedDistance)

			--   local clusterCommands = snake_sort_with_lookahead(cluster, lookahead_steps)
			--   Spring.GiveOrderToUnit(builderId, CMD.STOP, {}, {})
			--   Spring.GiveOrderArrayToUnit(builderId, clusterCommands)
			--   -- local builderId = builders[i].id

			--   -- Spring.GiveOrderToUnit(builderId, CMD.STOP, {}, {})
			--   -- Spring.GiveOrderArrayToUnit(builderId, clusterCommands)
			--   -- local nClusterCommands = #clusterCommands
			--   -- splitBuilderWatch[builderId] = {commands=commands, lastCommand=clusterCommands[nClusterCommands], nClusterCommands=nClusterCommands}
			-- end
		end
	end

	if key == KEYSYMS.E and mods['alt'] and not mods['shift'] and mods['ctrl'] then
		local reclaimers = {}
		local reclaimCommands = {}
		log('selectedUnitIds', #selectedUnitIds)
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
end

-- function widget:GameFrame(gameframe)

--   if gameframe % 7 == 0 then
--     for builderId, watch in pairs(splitBuilderWatch) do
--       local commandQueue = Spring.GetUnitCommands(builderId, watch.nClusterCommands)

--       if commandQueue == nil then
--         splitBuilderWatch[builderId] = nil
--       else
--         local nCommands = type(commandQueue) == "number" and 0 or #commandQueue
--         log('builderId', builderId, 'nCommands', nCommands)
--         if nCommands == 0 then
--           local backupCommands = deepcopy(watch.commands)
--           table.sort(backupCommands, SortbuildSpeedDistance)
--           backupCommands = snake_sort_with_lookahead(backupCommands, lookahead_steps)

--           log('issuing extra commands', builderId, #backupCommands, table.tostring(backupCommands))

--           Spring.GiveOrderArrayToUnit(builderId, backupCommands)
--           splitBuilderWatch[builderId] = nil
--         else
--           local lastCommand = commandQueue[nCommands]

--           if watch.lastCommand[1] ~= lastCommand.id
--             or watch.lastCommand[2][1] ~= lastCommand.params[1]
--             or watch.lastCommand[2][3] ~= lastCommand.params[3] then
--             splitBuilderWatch[builderId] = nil
--           end
--         end
--       end
--     end
--   end
-- end

-- function widget:Update(dt)
-- if Spring.DiffTimers(Spring.GetTimer(), selectCheckTimer, true) < 300 then
--   return
-- end

-- selectCheckTimer = Spring.GetTimer()

-- local selectedUnits = Spring.GetSelectedUnits()

-- local isSame = true
-- if #selectedUnits ~= #lastSelect then
--   isSame = false

--   for i = 1, #lastSelect do
--     if Spring.GetUnitHealth(lastSelect[i]) == nil then
--       table.remove(selectHistory, #selectHistory)
--       break
--     end
--   end

-- else
--   table.sort(selectedUnits)
--   for i = 1, #selectedUnits do
--     if selectedUnits[i] ~= lastSelect[i] then
--       isSame = false
--       break
--     end
--   end
-- end

-- if isSame then
--   return
-- end

-- lastSelect = selectedUnits
-- table.insert(selectHistory, lastSelect)

-- if #selectHistory > 40 then
--   table.remove(selectHistory, 1)
-- end
