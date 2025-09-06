function widget:GetInfo()
	return {
		name = 'Smart Constructor Positioning',
		desc = 'Automatically positions constructors to minimize movement during building',
		author = 'tetrisface',
		date = '2025-07-31',
		layer = 2,
		enabled = true,
		handler = true
	}
end

VFS.Include('LuaUI/Widgets/helpers.lua')

local echo = Spring.Echo
local i18n = Spring.I18N
local GetSelectedUnits = Spring.GetSelectedUnits
local GetUnitDefID = Spring.GetUnitDefID
local GetUnitCommands = Spring.GetUnitCommands
local GetUnitBasePosition = Spring.GetUnitBasePosition
local GetUnitEffectiveBuildRange = Spring.GetUnitEffectiveBuildRange
local GetUnitsInCylinder = Spring.GetUnitsInCylinder
local GiveOrderToUnit = Spring.GiveOrderToUnit
local UnitDefs = UnitDefs
local CMD_MOVE = CMD.MOVE
local CMD_INSERT = CMD.INSERT

-- Custom command for the toggle
local CMD_SMART_POSITIONING = 28341
local CMD_SMART_POSITIONING_DESCRIPTION = {
	id = CMD_SMART_POSITIONING,
	type = CMDTYPE.ICON_MODE,
	name = 'Smart Positioning',
	cursor = nil,
	action = 'smart_positioning',
	params = {1, 'smart_positioning_off', 'smart_positioning_on'}
}

-- Force positioning command (Ctrl+W)
local CMD_FORCE_POSITIONING = 28342
local CMD_FORCE_POSITIONING_DESCRIPTION = {
	id = CMD_FORCE_POSITIONING,
	type = CMDTYPE.ICON,
	name = 'Force Smart Positioning',
	cursor = 'cursorrepair',
	action = 'force_smart_positioning',
	tooltip = 'Force smart positioning for selected constructors (ignores blocking state)'
}

-- Localization
i18n.set('en.ui.orderMenu.' .. CMD_SMART_POSITIONING_DESCRIPTION.params[2], 'Smart Positioning Off')
i18n.set('en.ui.orderMenu.' .. CMD_SMART_POSITIONING_DESCRIPTION.params[3], 'Smart Positioning On')
i18n.set(
	'en.ui.orderMenu.' .. CMD_SMART_POSITIONING_DESCRIPTION.action .. '_tooltip',
	'Automatically position constructors for optimal building'
)

i18n.set('en.ui.orderMenu.' .. CMD_FORCE_POSITIONING_DESCRIPTION.action, 'Force Smart Positioning')
i18n.set(
	'en.ui.orderMenu.' .. CMD_FORCE_POSITIONING_DESCRIPTION.action .. '_tooltip',
	'Force smart positioning for selected constructors (ignores blocking state)'
)

-- Settings
local SMART_POSITIONING_OFF = 0
local SMART_POSITIONING_ON = 1

-- Global variables
local myTeamID = Spring.GetMyTeamID()
local constructorUnits = {}
local constructorDefs = {}
local debugMode = false
local objectSpotlightAvailable = false

-- Initialize constructor definitions
local function initializeConstructorDefs()
	constructorDefs = {}

	for unitDefID, unitDef in pairs(UnitDefs) do
		-- Check if it's a non-air constructor that can move
		if unitDef.isBuilder and unitDef.canMove and not unitDef.isAirUnit and not unitDef.isFactory then
			constructorDefs[unitDefID] = {
				buildDistance = unitDef.buildDistance or 0,
				buildSpeed = unitDef.buildSpeed or 0,
				-- Use the proper build distance calculation like the construction turrets gadget
				maxBuildDistance = (unitDef.buildDistance or 0) + (unitDef.radius or 0),
				buildRange3D = unitDef.buildRange3D,
				radius = unitDef.radius or 0
			}
		end
	end
end

-- Check if a unit is a valid constructor
local function isConstructor(unitDefID)
	return constructorDefs[unitDefID] ~= nil
end

-- Create or update a constructor unit entry
local function createConstructorUnit(unitID, unitDefID)
	if not isConstructor(unitDefID) or constructorUnits[unitID] then
		return nil
	end

	constructorUnits[unitID] = constructorUnits[unitID] or {}
	constructorUnits[unitID].mode = constructorUnits[unitID].mode or SMART_POSITIONING_ON
	constructorUnits[unitID].unlockBuildingHash = nil -- Hash of the building that should trigger unlocking

	if debugMode then
		echo('Added constructor ' .. unitID .. ' in SMART_POSITIONING_ON mode')
	end

	return constructorUnits[unitID]
end

-- Remove a constructor unit
local function removeConstructorUnit(unitID)
	constructorUnits[unitID] = nil
end

-- Initialize all existing constructors on the team
local function initializeExistingConstructors()
	local allUnits = Spring.GetTeamUnits(myTeamID)
	for _, unitID in ipairs(allUnits) do
		local unitDefID = GetUnitDefID(unitID)
		if unitDefID and isConstructor(unitDefID) then
			createConstructorUnit(unitID, unitDefID)
		end
	end
end

-- Validate and clean up constructor units
local function validateConstructorUnits()
	local toRemove = {}
	for constructorID, _ in pairs(constructorUnits) do
		local unitDefID = GetUnitDefID(constructorID)
		local unitTeam = Spring.GetUnitTeam(constructorID)

		if not unitDefID or not isConstructor(unitDefID) or unitTeam ~= myTeamID then
			table.insert(toRemove, constructorID)
		end
	end

	for _, constructorID in ipairs(toRemove) do
		removeConstructorUnit(constructorID)
	end
end

-- Check if unit has a move command in first or second position
local function hasEarlyMoveCommand(unitID)
	local commands = GetUnitCommands(unitID, 3)
	if not commands then
		return false
	end

	-- Check first two commands for move commands
	for i = 1, math.min(2, #commands) do
		if commands[i].id == CMD_MOVE then
			return true
		end
	end
	return false
end



-- Check if constructor is being assisted
local function isBeingAssisted(constructorID)
	local x, y, z = GetUnitBasePosition(constructorID)
	if not x then
		return false
	end

	-- Get current build target if any
	local _, currentBuildTarget = Spring.GetUnitWorkerTask(constructorID)
	if not currentBuildTarget then
		if debugMode then
			echo('Constructor ' .. constructorID .. ' has no current build target')
		end
		return false
	end

	local nearbyUnits = GetUnitsInCylinder(x, z, 5000, myTeamID)
	local assistCount = 0
	local assisters = {}

	for _, unitID in ipairs(nearbyUnits) do
		if unitID ~= constructorID then
			-- Check if this unit is a builder
			local unitDefID = GetUnitDefID(unitID)
			local unitDef = UnitDefs[unitDefID]

			if unitDef and unitDef.isBuilder then
				-- Use GetUnitWorkerTask to see what this builder is actually doing
				local workerCmdID, workerTargetID = Spring.GetUnitWorkerTask(unitID)

				if workerCmdID and workerTargetID then
					-- Check if the worker is building/repairing the same target as our constructor
					if workerTargetID == currentBuildTarget then
						assistCount = assistCount + 1
						table.insert(assisters, unitID)
					end
					-- Also check if the worker is directly assisting our constructor
					if workerTargetID == constructorID and workerCmdID == CMD.REPAIR then
						assistCount = assistCount + 1
						table.insert(assisters, unitID)
					end
				end
			end
		end
	end

	return assistCount > 0
end

-- Helper function to calculate building center position
local function getBuildingCenterPosition(buildX, buildZ, buildeeDefID, buildFacing)
	local buildDef = UnitDefs[buildeeDefID]
	if not buildDef then
		return buildX, buildZ
	end

	-- Get building footprint size (in footprint units, typically 16x16 game units each)
	local xSize = (buildDef.xsize or 1) * 8 -- Convert to game units (8 units per footprint square)
	local zSize = (buildDef.zsize or 1) * 8

	-- Calculate center offset based on building facing
	local centerX, centerZ = buildX, buildZ

	-- Buildings are placed from their so add half the footprint to get center
	-- Note: This assumes the command position is the bottom-left corner
	if buildFacing == 0 or buildFacing == 2 then
		-- North/South facing - use normal dimensions
		centerX = buildX + xSize / 2
		centerZ = buildZ + zSize / 2
	else
		-- East/West facing - dimensions are swapped
		centerX = buildX + zSize / 2
		centerZ = buildZ + xSize / 2
	end

	return centerX, centerZ
end

-- Check if constructor is standing in a building position
local function isStandingInBuilding(constructorID, buildCommand)
	if not buildCommand or not buildCommand.params then
		return false
	end

	local buildeeDefID = -buildCommand.id
	local buildX, buildY, buildZ = buildCommand.params[1], buildCommand.params[2], buildCommand.params[3]
	local buildFacing = buildCommand.params[4] or 0

	if not buildX or not buildZ then
		return false
	end

	-- local unitX, unitY, unitZ = Spring.GetUnitPosition(constructorID)
	local baseX, baseY, baseZ = Spring.GetUnitBasePosition(constructorID)
	if not baseX then
		return false
	end

	-- Get the actual center position of the building
	-- local buildCenterX, buildCenterZ = getBuildingCenterPosition(buildX, buildZ, buildeeDefID, buildFacing)

	-- Use TestBuildOrder to see if the build position is blocked (1 = allowed, 0 = blocked)
	local blockingTestBuildOrder = Spring.TestBuildOrder(buildeeDefID, buildX, buildY or 0, buildZ, buildFacing) == 1

	-- Calculate distance from constructor to building center
	-- local distanceToCenter = math.sqrt((baseX - buildX) ^ 2 + (baseZ - buildZ) ^ 2)

	-- Get building footprint for reference
	local buildDef = UnitDefs[buildeeDefID]
	local buildingFootprint = 64 -- Default footprint
	if buildDef then
		-- Calculate building footprint radius (convert footprint to world units)
		local xSize = (buildDef.xsize or 1) * 8 -- footprint is in 16x16 unit squares, 8 units per square
		local zSize = (buildDef.zsize or 1) * 8
		buildingFootprint = math.max(xSize, zSize) -- Use the larger dimension as diameter for safety
	end

	-- Use proper build distance calculation like the construction turrets gadget
	local constructorDefID = GetUnitDefID(constructorID)
	local constructorDef = constructorDefs[constructorDefID]
	if not constructorDef then
		return false
	end

	-- Calculate proper build distance (buildDistance + constructor radius)
	-- local maxBuildDistance = GetUnitEffectiveBuildRangePatched(constructorID, -buildCommand.id)

	-- Check if constructor is within build range of the build position
	-- local constructorCanReach = distanceToCenter <= maxBuildDistance

	-- Alternative check: Use GetUnitsInRectangle to see if constructor is in build area
	-- Use building center position for accurate rectangle check
	local buildArea = buildingFootprint / 2
	-- local unitsInBuildArea =
	-- 	Spring.GetUnitsInRectangle(
	-- 	buildX - buildArea,
	-- 	buildZ - buildArea,
	-- 	buildX + buildArea,
	-- 	buildZ + buildArea
	-- )
	local left, bottom, right, top = buildX - buildArea, buildZ - buildArea, buildX + buildArea, buildZ + buildArea
	local unitsInBuildArea = Spring.GetUnitsInRectangle(left, bottom, right, top, -2)
	local blockingRectangleSelect = false
	if unitsInBuildArea then
		for _, unitID in ipairs(unitsInBuildArea) do
			if unitID == constructorID then
				blockingRectangleSelect = true
				break
			end
		end
	end

	-- Constructor is standing in building if: build is blocked AND constructor can reach it OR constructor is directly in build area
	local isStandingInBuildingBool = blockingTestBuildOrder and blockingRectangleSelect

	if debugMode then
	-- 	echo('=== Standing in Building Check ===')
	-- 	echo('  Constructor ' .. constructorID)
	-- 	echo('  Building DefID: ' .. buildeeDefID .. ' (' .. (buildDef and buildDef.name or 'unknown') .. ')')
	-- 	echo(
	-- 		'  Build command params: [' ..
	-- 			(buildCommand.params[1] or 'nil') ..
	-- 				', ' ..
	-- 					(buildCommand.params[2] or 'nil') ..
	-- 						', ' .. (buildCommand.params[3] or 'nil') .. ', ' .. (buildCommand.params[4] or 'nil') .. ']'
	-- 	)
	-- 	echo('  build pos: (' .. buildX .. ', ' .. (buildY or 'nil') .. ', ' .. buildZ .. ')')
	-- 	echo('  Constructor pos: (' .. (baseX or 'nil') .. ', ' .. (baseY or 'nil') .. ', ' .. (baseZ or 'nil') .. ')')
	-- 	-- echo('  Distance to center: ' .. math.floor(distanceToCenter * 10) / 10)
	-- 	echo('  TestBuildOrder blocking: ' .. (blockingTestBuildOrder and 'yes' or 'no'))
	-- 	-- echo('  Constructor can reach (distance): ' .. (constructorCanReach and 'yes' or 'no'))
	-- 	-- echo(
	-- 	-- 	'  Rectangle bounds: [' ..
	-- 	-- 		(buildX - buildArea) ..
	-- 	-- 			', ' ..
	-- 	-- 				(buildZ - buildArea) .. '] to [' .. (buildX + buildArea) .. ', ' .. (buildZ + buildArea) .. ']'
	-- 	-- )
	-- 	echo(
	-- 		'  GetUnitsInRectangle blocking: ' ..
	-- 			(blockingRectangleSelect and 'yes' or 'no') .. ' with ' .. (#unitsInBuildArea or 0) .. ' units',
	-- 		'[' .. left .. ', ' .. bottom .. ', ' .. right .. ', ' .. top .. ']'
	-- 	)
	-- -- echo('  Standing in building (combined): ' .. (isStandingInBuildingBool and 'YES' or 'NO'))
	end

	return isStandingInBuildingBool
end

-- Calculate average position of build commands (using building centers)
local function calculateAveragePosition(commands, startIndex)
	local totalX, totalZ = 0, 0
	local count = 0

	for i = startIndex, #commands do
		local command = commands[i]
		if command.id < 0 and command.params then -- Build command
			local buildX, buildZ = command.params[1] or 0, command.params[3] or 0
			local buildFacing = command.params[4] or 0
			local buildeeDefID = -command.id

			-- Get the actual center position of this building
			local centerX, centerZ = getBuildingCenterPosition(buildX, buildZ, buildeeDefID, buildFacing)

			totalX = totalX + centerX
			totalZ = totalZ + centerZ
			count = count + 1
		end
	end

	if count == 0 then
		return nil
	end

	return totalX / count, totalZ / count
end

-- Calculate consecutive build streak from a position
local function calculateConsecutiveStreak(posX, posZ, buildCommands, maxBuildDistance)
	local streak = 0
	for i, buildCmd in ipairs(buildCommands) do
		local buildX, buildZ = buildCmd.command.params[1], buildCmd.command.params[3]
		local distToBuilding = math.sqrt((posX - buildX) ^ 2 + (posZ - buildZ) ^ 2)
		
		if distToBuilding <= maxBuildDistance then
			streak = streak + 1
		else
			-- Streak broken, stop counting
			break
		end
	end
	return streak
end

-- Check which buildings a position would block and return blocking score
local function calculateBlockingScore(constructorID, posX, posZ, buildCommands)
	local blockingBuildings = {}
	local blockingScore = 0 -- Lower is better
	
	for i, buildCmd in ipairs(buildCommands) do
		-- Simulate constructor at this position and check if it blocks this building
		local command = buildCmd.command
		local buildeeDefID = -command.id
		local buildX, buildY, buildZ = command.params[1], command.params[2], command.params[3]
		local buildFacing = command.params[4] or 0
		
		if buildX and buildZ then
			-- Get building footprint for blocking check
			local buildDef = UnitDefs[buildeeDefID]
			local buildingFootprint = 64 -- Default
			if buildDef then
				local xSize = (buildDef.xsize or 1) * 8
				local zSize = (buildDef.zsize or 1) * 8
				buildingFootprint = math.max(xSize, zSize)
			end
			
			-- Check if constructor position would be in building area
			local buildArea = buildingFootprint / 2
			local left, bottom, right, top = buildX - buildArea, buildZ - buildArea, buildX + buildArea, buildZ + buildArea
			
			if posX >= left and posX <= right and posZ >= bottom and posZ <= top then
				table.insert(blockingBuildings, i)
				-- Penalty increases for earlier buildings in queue (higher priority)
				blockingScore = blockingScore + (1000 / i) -- Earlier = higher penalty
			end
		end
	end
	
	return blockingScore, blockingBuildings
end

-- Score a position based on priority criteria
local function scorePosition(constructorID, posX, posZ, buildCommands, averageX, averageZ, maxBuildDistance, currentTargetX, currentTargetZ)
	-- Priority 1: Must reach current build target
	local distToCurrentTarget = math.sqrt((posX - currentTargetX) ^ 2 + (posZ - currentTargetZ) ^ 2)
	if distToCurrentTarget > maxBuildDistance then
		return nil -- Invalid position
	end
	
	-- Priority 2: Consecutive streak length (higher is better)
	local streakLength = calculateConsecutiveStreak(posX, posZ, buildCommands, maxBuildDistance)
	
	-- Priority 3: Blocking score (lower is better)
	local blockingScore, blockingBuildings = calculateBlockingScore(constructorID, posX, posZ, buildCommands)
	
	-- Priority 4: Distance to average (lower is better)
	local distToAverage = math.sqrt((posX - averageX) ^ 2 + (posZ - averageZ) ^ 2)
	
	return {
		streak = streakLength,
		blocking = blockingScore,
		distToAverage = distToAverage,
		blockingBuildings = blockingBuildings,
		valid = true
	}
end

-- Find optimal position using streak-based priority algorithm
local function findOptimalPosition(
	constructorID,
	currentBuildCommand,
	averageX,
	averageZ,
	commands,
	standingInBuildIndex)
		local unitX, _, unitZ = Spring.GetUnitBasePosition(constructorID)
	local buildX, buildZ = currentBuildCommand.params[1], currentBuildCommand.params[3]

	if not unitX or not buildX or not averageX then
		return nil
	end

	local maxBuildDistance = GetUnitEffectiveBuildRangePatched(constructorID, -currentBuildCommand.id)

	-- Get the actual current build target position (this might be different from where we're standing)
	local _, currentBuildTarget = Spring.GetUnitWorkerTask(constructorID)
	local currentTargetX, currentTargetZ
	if currentBuildTarget then
		local targetX, _, targetZ = Spring.GetUnitPosition(currentBuildTarget)
		if targetX then
			currentTargetX, currentTargetZ = targetX, targetZ
		end
	end
	
	-- If we don't have a current build target, fall back to the standing position
	if not currentTargetX then
		currentTargetX, currentTargetZ = buildX, buildZ
	end

	-- Get all build commands in order (for streak calculation)
	local allBuildCommands = {}
	for i, command in ipairs(commands) do
		if command.id < 0 and command.params then -- Build command
			table.insert(allBuildCommands, {command = command, index = i})
		end
	end
	
	if #allBuildCommands == 0 then
		return nil -- No build commands to optimize for
	end

	-- Generate candidate positions to test
	local candidatePositions = {}
	local safeRange = maxBuildDistance * 0.95
	
	-- Sample positions in multiple directions from the current target
	local directions = {
		{1, 0}, {-1, 0}, {0, 1}, {0, -1}, -- Cardinal directions
		{1, 1}, {1, -1}, {-1, 1}, {-1, -1}, -- Diagonal directions
	}
	
	-- Also include direction towards average
	local dirToAvgX = averageX - currentTargetX
	local dirToAvgZ = averageZ - currentTargetZ
	local dirToAvgLength = math.sqrt(dirToAvgX ^ 2 + dirToAvgZ ^ 2)
	if dirToAvgLength > 10 then
		table.insert(directions, {dirToAvgX / dirToAvgLength, dirToAvgZ / dirToAvgLength})
	end
	
	-- Generate candidate positions
	for _, dir in ipairs(directions) do
		local dirX, dirZ = dir[1], dir[2]
		
		-- Sample at multiple distances along this direction
		for distance = 32, safeRange, 32 do -- Every 32 units from 32 to max range
			local candX = currentTargetX + dirX * distance
			local candZ = currentTargetZ + dirZ * distance
			table.insert(candidatePositions, {x = candX, z = candZ})
		end
	end
	
	-- Score all candidate positions
	local scoredPositions = {}
	for _, pos in ipairs(candidatePositions) do
		local score = scorePosition(constructorID, pos.x, pos.z, allBuildCommands, averageX, averageZ, maxBuildDistance, currentTargetX, currentTargetZ)
		if score and score.valid then
			score.x = pos.x
			score.z = pos.z
			table.insert(scoredPositions, score)
		end
	end
	
	if #scoredPositions == 0 then
		return nil -- No valid positions found
	end
	
	-- Sort positions by priority criteria
	table.sort(scoredPositions, function(a, b)
		-- Priority 1: Longest consecutive streak (higher is better)
		if a.streak ~= b.streak then
			return a.streak > b.streak
		end
		
		-- Priority 2: Less blocking (lower is better)
		if a.blocking ~= b.blocking then
			return a.blocking < b.blocking
		end
		
		-- Priority 3: Closer to average (lower is better)
		return a.distToAverage < b.distToAverage
	end)
	
	local bestPosition = scoredPositions[1]
	
	-- Check if the move position is significantly different from current position
	local moveDistance = math.sqrt((bestPosition.x - unitX) ^ 2 + (bestPosition.z - unitZ) ^ 2)
	if moveDistance < 32 then
		return nil -- Not worth moving
	end

	-- Debug output
	if debugMode then
		echo('=== Streak-Based Optimization ===')
		echo('  Constructor position: (' .. unitX .. ', ' .. unitZ .. ')')
		echo('  Current build target: (' .. currentTargetX .. ', ' .. currentTargetZ .. ')')
		echo('  Average position: (' .. averageX .. ', ' .. averageZ .. ')')
		echo('  Total build commands: ' .. #allBuildCommands)
		echo('  Best position: (' .. bestPosition.x .. ', ' .. bestPosition.z .. ')')
		echo('  Consecutive streak: ' .. bestPosition.streak .. '/' .. #allBuildCommands)
		echo('  Blocking score: ' .. bestPosition.blocking)
		if #bestPosition.blockingBuildings > 0 then
			echo('  Blocking buildings at positions: ' .. table.concat(bestPosition.blockingBuildings, ', '))
		else
			echo('  No buildings blocked')
		end
		echo('  Distance to average: ' .. math.floor(bestPosition.distToAverage))
		echo('  Move distance: ' .. math.floor(moveDistance))
		echo('  Tested ' .. #candidatePositions .. ' positions, ' .. #scoredPositions .. ' were valid')
	end

	return bestPosition.x, bestPosition.z
end

-- Create a unique hash for a building command (unit def + position + facing)
local function createBuildingHash(buildCommand)
	if not buildCommand or not buildCommand.params or not buildCommand.params[1] or not buildCommand.params[3] then
		return nil
	end

	local buildeeDefID = -buildCommand.id
	local buildX, buildZ = buildCommand.params[1], buildCommand.params[3]
	local buildFacing = buildCommand.params[4] or 0

	-- Round positions to avoid floating point precision issues
	buildX = math.floor(buildX * 10) / 10
	buildZ = math.floor(buildZ * 10) / 10

	-- Create hash: unitDefID + position + facing
	return string.format("%d_%.1f_%.1f_%d", buildeeDefID, buildX, buildZ, buildFacing)
end


-- Force positioning function that trims non-build commands and processes positioning
local function forceProcessConstructorPositioning(constructorID)
	local constructorData = constructorUnits[constructorID]
	if not constructorData or constructorData.mode == SMART_POSITIONING_OFF then
		if debugMode then
			echo('Constructor ' .. constructorID .. ' skipped: mode is OFF')
		end
		return
	end

	local unitDefID = GetUnitDefID(constructorID)
	if not isConstructor(unitDefID) then
		if debugMode then
			echo('Constructor ' .. constructorID .. ' skipped: not a valid constructor')
		end
		return
	end

	-- Get command queue
	local commands = GetUnitCommands(constructorID, 500)
	if not commands or #commands <= 2 then
		if debugMode then
			echo('Constructor ' .. constructorID .. ' skipped: queue too small')
		end
		return
	end

	-- Skip if already has move command in first two positions
	if hasEarlyMoveCommand(constructorID) then
		if debugMode then
			echo('Constructor ' .. constructorID .. ' skipped: already has early move command')
		end
		return
	end

	-- Force positioning bypasses the assisting check since it's meant to be used proactively
	-- Only check if being assisted for regular positioning

	-- Find all build commands and trim non-build commands from the start
	local buildCommands = {}
	local firstBuildIndex = nil
	local trimmedCommands = {}

	for i, command in ipairs(commands) do
		if command.id > 0 and CMD.REPAIR ~= command.id then
			-- Stop at first non-build, non-repair command
			break
		end
		if command.id ~= CMD.REPAIR then
			-- This is a build command
			table.insert(buildCommands, {command = command, index = i})
			if not firstBuildIndex then
				firstBuildIndex = i
			end
		end
		-- Keep all commands up to this point
		table.insert(trimmedCommands, command)
	end

	if #buildCommands == 0 then
		if debugMode then
			echo('Constructor ' .. constructorID .. ' skipped: no build commands found')
		end
		return
	end

	-- Calculate average position of all build commands
	local averageX, averageZ = calculateAveragePosition(commands, firstBuildIndex)
	if not averageX then
		if debugMode then
			echo('Constructor ' .. constructorID .. ' skipped: could not calculate average position')
		end
		return
	end

	-- Use the first build command as reference for positioning
	local firstBuildCommand = buildCommands[1]
	
	-- Find optimal position relative to the first building
	local moveX, moveZ = findOptimalPosition(constructorID, firstBuildCommand.command, averageX, averageZ, commands, firstBuildIndex)
	if not moveX then
		if debugMode then
			echo('Constructor ' .. constructorID .. ' skipped: no optimal position found')
		end
		return
	end

	-- Get the correct ground height for the move position
	local moveY = Spring.GetGroundHeight(moveX, moveZ)

	-- Insert move command at front of queue with correct ground height
	GiveOrderToUnit(constructorID, CMD_INSERT, {0, CMD_MOVE, 0, moveX, moveY, moveZ}, {'alt'})

	-- Store which building should trigger unlocking (the one BEFORE the building we're moving TO)
	-- We need to find which building our new position will be blocking
	local unlockBuildingIndex = nil
	
	-- Check which building our new position will block
	for i, buildCmd in ipairs(buildCommands) do
		local command = buildCmd.command
		local buildeeDefID = -command.id
		local buildX, buildY, buildZ = command.params[1], command.params[2], command.params[3]
		local buildFacing = command.params[4] or 0
		
		if buildX and buildZ then
			-- Get building footprint for blocking check
			local buildDef = UnitDefs[buildeeDefID]
			local buildingFootprint = 64 -- Default
			if buildDef then
				local xSize = (buildDef.xsize or 1) * 8
				local zSize = (buildDef.zsize or 1) * 8
				buildingFootprint = math.max(xSize, zSize)
			end
			
			-- Check if our new position will block this building
			local buildArea = buildingFootprint / 2
			local left, bottom, right, top = buildX - buildArea, buildZ - buildArea, buildX + buildArea, buildZ + buildArea
			
			if moveX >= left and moveX <= right and moveZ >= bottom and moveZ <= top then
				-- This is the building we'll be blocking from our new position
				unlockBuildingIndex = math.max(1, i - 1) -- Building BEFORE the one we'll block
				break
			end
		end
	end
	
	-- If we found a building we'll block, store the unlock hash
	if unlockBuildingIndex and unlockBuildingIndex <= #commands then
		local unlockCommand = commands[unlockBuildingIndex]
		if unlockCommand and unlockCommand.id < 0 then -- Build command
			constructorData.unlockBuildingHash = createBuildingHash(unlockCommand)
			if debugMode then
				echo('Stored unlock hash for building #' .. unlockBuildingIndex .. ' (before building we will block): ' .. constructorData.unlockBuildingHash)
			end
		end
	end
	
	if debugMode then
		echo('Constructor ' .. constructorID .. ' FORCE positioned at (' .. moveX .. ', ' .. moveY .. ', ' .. moveZ .. ')')
		if constructorData.unlockBuildingHash and unlockBuildingIndex then
			echo('Will unlock when building #' .. unlockBuildingIndex .. ' (hash ' .. constructorData.unlockBuildingHash .. ') completes')
		else
			echo('No unlock building hash stored (not blocking any buildings from new position)')
		end

		-- Add debug spotlights when we actually make a move (with safety checks)
		if objectSpotlightAvailable then
			local success, err = pcall(function()
				local spotlightID = 'smart_pos_' .. constructorID
				local unitX, _, unitZ = Spring.GetUnitPosition(constructorID)
				
				if unitX and unitZ then
					-- Move destination (blue spotlight)
					WG['ObjectSpotlight'].addSpotlight(
						'ground',
						spotlightID .. '_destination',
						{moveX, moveY, moveZ},
						{0, 0, 1, 1}, -- Blue
						{duration = 30, radius = 16, heightCoefficient = 6}
					)

					-- Get proper build ranges using the construction turrets gadget approach
					local constructorDefID = GetUnitDefID(constructorID)
					local constructorDef = constructorDefs[constructorDefID]
					if constructorDef then
						local effectiveBuildRange = GetUnitEffectiveBuildRangePatched(constructorID, -firstBuildCommand.command.id)

						-- Effective build range (purple circle)
						if effectiveBuildRange then
							WG['ObjectSpotlight'].addSpotlight(
								'ground',
								spotlightID .. '_effective_range',
								{moveX, Spring.GetGroundHeight(moveX, moveZ), moveZ},
								{0.8, 0, 0.8, 0.8}, -- Purple, semi-transparent
								{duration = 30, radius = effectiveBuildRange, heightCoefficient = 1}
							)
						end
					end
				end
			end)
			
			if not success then
				echo('Warning: ObjectSpotlight failed: ' .. tostring(err))
			end
		end
	end
end

-- Process smart positioning for a constructor
local function processConstructorPositioning(constructorID)
	local constructorData = constructorUnits[constructorID]
	if not constructorData or constructorData.mode == SMART_POSITIONING_OFF then
		if debugMode then
			echo('Constructor ' .. constructorID .. ' skipped: mode is OFF')
		end
		return
	end

	local unitDefID = GetUnitDefID(constructorID)
	if not isConstructor(unitDefID) then
		if debugMode then
			echo('Constructor ' .. constructorID .. ' skipped: not a valid constructor')
		end
		return
	end

	-- Get command queue
	local commands = GetUnitCommands(constructorID, 500)
	if not commands or #commands <= 2 then
		-- Reset unlock building if queue becomes too small
		constructorData.unlockBuildingHash = nil
		return
	end -- Need queue larger than 2

	-- Skip if already has move command in first two positions
	if hasEarlyMoveCommand(constructorID) then
		if debugMode then
		-- echo('Constructor ' .. constructorID .. ' skipped: already has early move command')
		end
		return
	end

	-- Check if being assisted
	if not isBeingAssisted(constructorID) then
		if debugMode then
			echo('Constructor ' .. constructorID .. ' skipped: not being assisted')
		end
		return
	end

	if constructorData.unlockBuildingHash then
		-- Check if the lock building still exists anywhere in the command queue
		local lockBuildingStillExists = false
		local lockBuildingIndex = nil

		for i, command in ipairs(commands) do
			if command.id < 0 and command.params then -- Build command
				local commandHash = createBuildingHash(command)
				if commandHash == constructorData.unlockBuildingHash then
					lockBuildingStillExists = true
					lockBuildingIndex = i
					break
				end
			end
		end

		if not lockBuildingStillExists then
			-- Lock building was removed/modified from queue, invalidate hash
			if debugMode then
				echo('Constructor ' .. constructorID .. ' lock building no longer in queue, invalidating hash')
			end
			constructorData.unlockBuildingHash = nil
		elseif lockBuildingIndex == 1 then
			-- Lock building is now first in queue, unlock and process
			if debugMode then
				echo('Constructor ' .. constructorID .. ' lock building reached (now first), processing')
			end
			constructorData.unlockBuildingHash = nil
		else
			-- Still locked, skip processing
			if debugMode then
				echo('Constructor ' .. constructorID .. ' still locked, building #' .. lockBuildingIndex .. ' not yet reached')
			end
			return -- CRITICAL: Return early when still locked!
		end
	end

	-- Find all build commands and check if constructor is standing in any of them
	local buildCommands = {}
	local standingInBuildIndex = nil
	local standingInBuildCommand = nil

	for i, command in ipairs(commands) do
		if command.id > 0 and CMD.REPAIR ~= command.id then
			if debugMode then
				echo('Con ' .. constructorID .. ' stopped evaluating at command id ' .. command.id .. ' at index ' .. i)
			end
			break
		end
		if command.id ~= CMD.REPAIR then
			table.insert(buildCommands, {command = command, index = i})
			if debugMode then
				echo('build command ' .. command.id .. ' at index ' .. i)
			end
			-- Check if constructor is standing in this building position
			if not standingInBuildCommand and isStandingInBuilding(constructorID, command) then
				standingInBuildIndex = i
				standingInBuildCommand = command
				if debugMode then
					echo('Constructor ' .. constructorID .. ' is standing in build command at queue position ' .. i)
				end
			end
		end
	end

	if #buildCommands == 0 then
		if debugMode then
			echo('Constructor ' .. constructorID .. ' skipped: no build commands found')
		end
		return
	end

	-- Check if constructor is standing in any building position
	if not standingInBuildCommand then
		if debugMode then
			echo('Con ' .. constructorID .. ' skipped: not blocking build. ' .. #buildCommands .. ' commands')
		end
		return
	end
	
	-- First run optimization: if no unlock hash exists, only consider ourselves blocking if we're blocking the 2nd building
	-- This delays the first move until absolutely necessary
	if not constructorData.unlockBuildingHash and standingInBuildIndex ~= 2 then
		if debugMode then
			echo('Constructor ' .. constructorID .. ' first run: not blocking 2nd building, delaying move until necessary')
		end
		return
	end

	-- Calculate average position of remaining build commands (after the one we're standing in)
	local averageX, averageZ = calculateAveragePosition(commands, standingInBuildIndex + 1)
	if not averageX then
		if debugMode then
			echo(
				'Constructor ' .. constructorID .. ' skipped: no remaining build commands after position ' .. standingInBuildIndex
			)
		end
		return
	end

	-- Find optimal position relative to the building we're standing in
	local moveX, moveZ =
		findOptimalPosition(constructorID, standingInBuildCommand, averageX, averageZ, commands, standingInBuildIndex)
	if not moveX then
		if debugMode then
			echo('Constructor ' .. constructorID .. ' skipped: no optimal position found')
		end
		return
	end

	-- Get the correct ground height for the move position
	local moveY = Spring.GetGroundHeight(moveX, moveZ)

	-- Insert move command at front of queue with correct ground height
	GiveOrderToUnit(constructorID, CMD_INSERT, {0, CMD_MOVE, 0, moveX, moveY, moveZ}, {'alt'})

	-- Store which building should trigger unlocking (the one BEFORE the building we're moving TO)
	-- We need to find which building our new position will be blocking
	local unlockBuildingIndex = nil
	
	-- Check which building our new position will block
	for i, buildCmd in ipairs(buildCommands) do
		local command = buildCmd.command
		local buildeeDefID = -command.id
		local buildX, buildY, buildZ = command.params[1], command.params[2], command.params[3]
		local buildFacing = command.params[4] or 0
		
		if buildX and buildZ then
			-- Get building footprint for blocking check
			local buildDef = UnitDefs[buildeeDefID]
			local buildingFootprint = 64 -- Default
			if buildDef then
				local xSize = (buildDef.xsize or 1) * 8
				local zSize = (buildDef.zsize or 1) * 8
				buildingFootprint = math.max(xSize, zSize)
			end
			
			-- Check if our new position will block this building
			local buildArea = buildingFootprint / 2
			local left, bottom, right, top = buildX - buildArea, buildZ - buildArea, buildX + buildArea, buildZ + buildArea
			
			if moveX >= left and moveX <= right and moveZ >= bottom and moveZ <= top then
				-- This is the building we'll be blocking from our new position
				unlockBuildingIndex = math.max(1, i - 1) -- Building BEFORE the one we'll block
				break
			end
		end
	end
	
	-- If we found a building we'll block, store the unlock hash
	if unlockBuildingIndex and unlockBuildingIndex <= #commands then
		local unlockCommand = commands[unlockBuildingIndex]
		if unlockCommand and unlockCommand.id < 0 then -- Build command
			constructorData.unlockBuildingHash = createBuildingHash(unlockCommand)
			if debugMode then
				echo('Stored unlock hash for building #' .. unlockBuildingIndex .. ' (before building we will block): ' .. constructorData.unlockBuildingHash)
			end
		end
	end
	
	if debugMode then
		echo('Constructor ' .. constructorID .. ' positioned at (' .. moveX .. ', ' .. moveY .. ', ' .. moveZ .. ')')
		if constructorData.unlockBuildingHash and unlockBuildingIndex then
			echo('Will unlock when building #' .. unlockBuildingIndex .. ' (hash ' .. constructorData.unlockBuildingHash .. ') completes')
		else
			echo('No unlock building hash stored (not blocking any buildings from new position)')
		end

		-- Add debug spotlights when we actually make a move (with safety checks)
		if objectSpotlightAvailable then
			local success, err = pcall(function()
				local spotlightID = 'smart_pos_' .. constructorID
				local unitX, _, unitZ = Spring.GetUnitPosition(constructorID)
				
				if unitX and unitZ then
					-- -- Constructor current position (yellow spotlight)
					-- WG['ObjectSpotlight'].addSpotlight(
					-- 	'ground',
					-- 	spotlightID .. '_constructor',
					-- 	{unitX, Spring.GetGroundHeight(unitX, unitZ), unitZ},
					-- 	{1, 1, 0, 1}, -- Yellow
					-- 	{duration = 30, radius = 20, heightCoefficient = 8}
					-- )

					-- Move destination (blue spotlight)
					WG['ObjectSpotlight'].addSpotlight(
						'ground',
						spotlightID .. '_destination',
						{moveX, moveY, moveZ},
						{0, 0, 1, 1}, -- Blue
						{duration = 30, radius = 16, heightCoefficient = 6}
					)

					-- -- Current build target position (red spotlight) - use actual build target, not standing position
					-- local _, currentBuildTarget = Spring.GetUnitWorkerTask(constructorID)
					-- if currentBuildTarget then
					-- 	local buildTargetX, buildTargetY, buildTargetZ = Spring.GetUnitPosition(currentBuildTarget)
					-- 	if buildTargetX then
					-- 		WG['ObjectSpotlight'].addSpotlight(
					-- 			'ground',
					-- 			spotlightID .. '_build',
					-- 			{buildTargetX, buildTargetY or Spring.GetGroundHeight(buildTargetX, buildTargetZ), buildTargetZ},
					-- 			{1, 0, 0, 1}, -- Red
					-- 			{duration = 30, radius = 16, heightCoefficient = 6}
					-- 		)
					-- 	end
					-- else
					-- 	-- Fallback to standing position if no current build target
					-- 	local buildX, buildZ = standingInBuildCommand.params[1], standingInBuildCommand.params[3]
					-- 	WG['ObjectSpotlight'].addSpotlight(
					-- 		'ground',
					-- 		spotlightID .. '_build',
					-- 		{buildX, Spring.GetGroundHeight(buildX, buildZ), buildZ},
					-- 		{1, 0, 0, 1}, -- Red
					-- 		{duration = 30, radius = 16, heightCoefficient = 6}
					-- 	)
					-- end

					-- Average position (green spotlight)
					-- WG['ObjectSpotlight'].addSpotlight(
					-- 	'ground',
					-- 	spotlightID .. '_average',
					-- 	{averageX, Spring.GetGroundHeight(averageX, averageZ), averageZ},
					-- 	{0, 1, 0, 1}, -- Green
					-- 	{duration = 30, radius = 16, heightCoefficient = 6}
					-- )

					-- Get proper build ranges using the construction turrets gadget approach
					local constructorDefID = GetUnitDefID(constructorID)
					local constructorDef = constructorDefs[constructorDefID]
					if constructorDef then
						local maxBuildDistance = constructorDef.maxBuildDistance
						local baseBuildDistance = constructorDef.buildDistance
						local constructorRadius = constructorDef.radius
						local effectiveBuildRange = GetUnitEffectiveBuildRangePatched(constructorID, -standingInBuildCommand.id)

						-- Effective build range (purple circle)
						if effectiveBuildRange and effectiveBuildRange ~= maxBuildDistance then
							WG['ObjectSpotlight'].addSpotlight(
								'ground',
								spotlightID .. '_effective_range',
								{moveX, Spring.GetGroundHeight(moveX, moveZ), moveZ},
								{0.8, 0, 0.8, 0.8}, -- Purple, semi-transparent
								{duration = 30, radius = effectiveBuildRange, heightCoefficient = 1}
							)
						end

						-- echo('Debug ranges:')
						-- echo('  Base build distance: ' .. baseBuildDistance)
						-- echo('  Constructor radius: ' .. constructorRadius)
						-- echo('  Max build distance: ' .. maxBuildDistance .. ' (base + radius)')
						-- echo('  Effective build range: ' .. (effectiveBuildRange or 'nil'))
					end
				end
			end)
			
			if not success then
				echo('Warning: ObjectSpotlight failed: ' .. tostring(err))
			end
		end
	end
end

-- Check if selected units have constructors
local function checkSelectedUnits(updateMode)
	local selectedUnits = GetSelectedUnits()
	local hasConstructors = false
	local foundMode = SMART_POSITIONING_ON

	for _, unitID in ipairs(selectedUnits) do
		local unitDefID = GetUnitDefID(unitID)
		if isConstructor(unitDefID) then
			hasConstructors = true

			if updateMode then
				local mode = CMD_SMART_POSITIONING_DESCRIPTION.params[1]
				local constructorData = createConstructorUnit(unitID, unitDefID)
				if constructorData then
					constructorData.mode = mode
				end
			else
				createConstructorUnit(unitID, unitDefID)
				if constructorUnits[unitID] and constructorUnits[unitID].mode then
					foundMode = constructorUnits[unitID].mode
				end
			end
		end
	end

	if not updateMode then
		CMD_SMART_POSITIONING_DESCRIPTION.params[1] = foundMode
	end

	return hasConstructors
end

-- Widget event handlers
function widget:Initialize()

	-- Clean up if spectating
	if Spring.GetSpectatingState() or Spring.IsReplay() then
		widgetHandler:RemoveWidget()
		return
	end

	initializeConstructorDefs()

	-- Check if ObjectSpotlight is available and working
	if WG['ObjectSpotlight'] and WG['ObjectSpotlight'].addSpotlight then
		objectSpotlightAvailable = true
		echo('Smart Constructor Positioning: ObjectSpotlight available for debug visualization')
	else
		echo('Smart Constructor Positioning: ObjectSpotlight not available, debug visualization disabled')
	end

	myTeamID = Spring.GetMyTeamID()
	initializeExistingConstructors()
	
	-- Add key binding for Ctrl+W (force positioning)
	Spring.SendCommands('bind ctrl+w force_smart_positioning')
end

function widget:CommandsChanged()
	if checkSelectedUnits(false) then
		local cmds = widgetHandler.customCommands
		cmds[#cmds + 1] = CMD_SMART_POSITIONING_DESCRIPTION
		cmds[#cmds + 1] = CMD_FORCE_POSITIONING_DESCRIPTION
	end
end

function widget:CommandNotify(cmd_id, cmd_params, cmd_options)
	if cmd_id == CMD_SMART_POSITIONING then
		local mode = CMD_SMART_POSITIONING_DESCRIPTION.params[1]

		-- Check for right-click (cycle backwards)
		local nModes = #CMD_SMART_POSITIONING_DESCRIPTION.params - 1
		if cmd_options and cmd_options.shift then
			mode = (mode - 1 + nModes) % nModes
		else
			mode = (mode + 1) % nModes
		end

		CMD_SMART_POSITIONING_DESCRIPTION.params[1] = mode
		checkSelectedUnits(true)
		return true
	elseif cmd_id == CMD_FORCE_POSITIONING then
		-- Force positioning for all selected constructors
		local selectedUnits = GetSelectedUnits()
		local processedCount = 0
		
		for _, unitID in ipairs(selectedUnits) do
			local unitDefID = GetUnitDefID(unitID)
			if isConstructor(unitDefID) then
				-- Ensure constructor is tracked
				createConstructorUnit(unitID, unitDefID)
				-- Force process positioning
				forceProcessConstructorPositioning(unitID)
				processedCount = processedCount + 1
			end
		end
		
		if debugMode then
			echo('Force positioning processed ' .. processedCount .. ' selected constructors')
		end
		
		return true
	end
end

function widget:UnitDestroyed(unitID)
	removeConstructorUnit(unitID)
end

function widget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
	if oldTeam == myTeamID then
		removeConstructorUnit(unitID)
	elseif newTeam == myTeamID then
		createConstructorUnit(unitID, unitDefID)
	end
end

function widget:UnitCreated(unitID, unitDefID, teamID)
	if teamID == myTeamID then
		createConstructorUnit(unitID, unitDefID)
	end
end

function widget:UnitTaken(unitID, unitDefID, oldTeam, newTeam)
	if oldTeam == myTeamID then
		removeConstructorUnit(unitID)
	elseif newTeam == myTeamID then
		createConstructorUnit(unitID, unitDefID)
	end
end

function widget:Shutdown()
	-- Remove key binding when widget is disabled/removed
	Spring.SendCommands('unbind ctrl+w force_smart_positioning')
end

function widget:GameFrame(frameNum)
	-- Only process every 15 frames to reduce CPU usage
	if frameNum % 15 ~= 0 then
		return
	end

	validateConstructorUnits()

	-- Process smart positioning for all constructors
	for constructorID, constructorData in pairs(constructorUnits) do
		if constructorData.mode and constructorData.mode == SMART_POSITIONING_ON then
			processConstructorPositioning(constructorID)
		end
	end
end

-- Debug command
function widget:TextCommand(command)
	if command == 'dbg_conpos' then
		debugMode = not debugMode
		echo('Smart positioning debug mode: ' .. (debugMode and 'ON' or 'OFF'))
		return true
	elseif command == 'smartinfo' then
		echo('Smart Constructor Positioning Info:')
		echo('Tracked constructors: ' .. #table.keys(constructorUnits))
		for constructorID, data in pairs(constructorUnits) do
			echo('  Constructor ' .. constructorID .. ': mode=' .. data.mode)
		end
		return true
	elseif command == 'spotlight_test' then
		if objectSpotlightAvailable then
			echo('ObjectSpotlight is available and working')
		else
			echo('ObjectSpotlight is not available')
		end
		return true
	elseif command == 'unlock_info' then
		echo('Unlock Building Info:')
		for constructorID, data in pairs(constructorUnits) do
			if data.unlockBuildingHash then
				echo('  Constructor ' .. constructorID .. ': unlock hash = ' .. data.unlockBuildingHash)
			else
				echo('  Constructor ' .. constructorID .. ': no unlock hash (first run or unlocked)')
			end
		end
		return true
	elseif command == 'clear_locks' then
		echo('Clearing all constructor locks...')
		for constructorID, data in pairs(constructorUnits) do
			if data.unlockBuildingHash then
				echo('  Cleared lock for constructor ' .. constructorID)
				data.unlockBuildingHash = nil
			end
		end
		return true
	elseif command == 'force_pos' then
		echo('Force positioning all tracked constructors...')
		local processedCount = 0
		for constructorID, data in pairs(constructorUnits) do
			if data.mode == SMART_POSITIONING_ON then
				forceProcessConstructorPositioning(constructID)
				processedCount = processedCount + 1
			end
		end
		echo('Force positioning processed ' .. processedCount .. ' constructors')
		return true
	end
	return false
end

function widget:GetConfigData()
	return {
		constructorSettings = constructorUnits
	}
end

function widget:SetConfigData(data)
	if data.constructorSettings then
		constructorUnits = data.constructorSettings
	end
end

-- Helper function for table.keys (if not available)
if not table.keys then
	table.keys = function(t)
		local keys = {}
		for k, _ in pairs(t) do
			table.insert(keys, k)
		end
		return keys
	end
end

function widget:ActiveCommandChanged(id, cmdType)
	local cmd = Spring.GetActiveCommand()
	local selectedUnits = Spring.GetSelectedUnits()

	if cmd and cmd > 0 and #selectedUnits > 0 then
		local defID = Spring.GetUnitDefID(selectedUnits[1])
		local cmdDef = UnitDefs[cmd]
		local eff = GetUnitEffectiveBuildRange(selectedUnits[1])
		local effCmd = GetUnitEffectiveBuildRange(selectedUnits[1], cmd)
		if debugMode then
			Spring.Echo(
				'buildrange def ' .. UnitDefs[defID].buildDistance .. ', eff ' .. eff .. ', eff cmd ' .. (effCmd or 0),
				'radius cmd ' .. cmdDef.radius,
				'radius con ' .. UnitDefs[defID].radius
			)
		end
	end
end
