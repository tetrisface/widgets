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

-- Localization
i18n.set('en.ui.orderMenu.' .. CMD_SMART_POSITIONING_DESCRIPTION.params[2], 'Smart Positioning Off')
i18n.set('en.ui.orderMenu.' .. CMD_SMART_POSITIONING_DESCRIPTION.params[3], 'Smart Positioning On')
i18n.set(
	'en.ui.orderMenu.' .. CMD_SMART_POSITIONING_DESCRIPTION.action .. '_tooltip',
	'Automatically position constructors for optimal building'
)

-- Settings
local SMART_POSITIONING_OFF = 0
local SMART_POSITIONING_ON = 1

-- Global variables
local myTeamID = Spring.GetMyTeamID()
local constructorUnits = {}
local constructorDefs = {}
local debugMode = false

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

						if debugMode then
							echo('  Assister found: Unit ' .. unitID .. ' working on target ' .. workerTargetID)
						end
					end
					-- Also check if the worker is directly assisting our constructor
					if workerTargetID == constructorID and workerCmdID == CMD.REPAIR then
						assistCount = assistCount + 1
						table.insert(assisters, unitID)

						if debugMode then
							echo('  Direct assister found: Unit ' .. unitID .. ' repairing constructor ' .. constructorID)
						end
					end
				end
			end
		end
	end

	if debugMode then
		if assistCount > 0 then
			echo(
				'Constructor ' .. constructorID .. ' has ' .. assistCount .. ' assisters working on target ' .. currentBuildTarget
			)
			for i, assisterID in ipairs(assisters) do
				local assisterDefID = GetUnitDefID(assisterID)
				local assisterDef = UnitDefs[assisterDefID]
				echo('  - Assister ' .. i .. ': ' .. assisterID .. ' (' .. (assisterDef and assisterDef.name or 'unknown') .. ')')
			end
		else
			echo('Constructor ' .. constructorID .. ' has no assisters for target ' .. currentBuildTarget)
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

	local unitX, unitY, unitZ = Spring.GetUnitPosition(constructorID)
	local baseX, baseY, baseZ = Spring.GetUnitBasePosition(constructorID)
	if not unitX then
		return false
	end

	-- Get the actual center position of the building
	local buildCenterX, buildCenterZ = getBuildingCenterPosition(buildX, buildZ, buildeeDefID, buildFacing)

	-- Use TestBuildOrder to see if the build position is blocked (1 = allowed, 0 = blocked)
	local testBuildResult = Spring.TestBuildOrder(buildeeDefID, buildX, buildY or 0, buildZ, buildFacing)
	local isBlocking = testBuildResult == 0

	-- Calculate distance from constructor to building center
	local distanceToCenter = math.sqrt((unitX - buildX) ^ 2 + (unitZ - buildZ) ^ 2)

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
	local maxBuildDistance = constructorDef.maxBuildDistance

	-- Check if constructor is within build range of the build position
	local constructorCanReach = distanceToCenter <= maxBuildDistance

	-- Alternative check: Use GetUnitsInRectangle to see if constructor is in build area
	-- Use building center position for accurate rectangle check
	local buildArea = buildingFootprint / 2
	local unitsInBuildArea =
		Spring.GetUnitsInRectangle(
		buildCenterX - buildArea,
		buildCenterZ - buildArea,
		buildCenterX + buildArea,
		buildCenterZ + buildArea
	)
	local constructorInBuildArea = false
	if unitsInBuildArea then
		for _, unitID in ipairs(unitsInBuildArea) do
			if unitID == constructorID then
				constructorInBuildArea = true
				break
			end
		end
	end

	-- Constructor is standing in building if: build is blocked AND constructor can reach it OR constructor is directly in build area
	local isStandingInBuildingBool = isBlocking and constructorInBuildArea

	if debugMode then
		echo('=== Standing in Building Check ===')
		echo('  Constructor ' .. constructorID)
		echo('  Building DefID: ' .. buildeeDefID .. ' (' .. (buildDef and buildDef.name or 'unknown') .. ')')
		echo(
			'  Build command params: [' ..
				(buildCommand.params[1] or 'nil') ..
					', ' ..
						(buildCommand.params[2] or 'nil') ..
							', ' .. (buildCommand.params[3] or 'nil') .. ', ' .. (buildCommand.params[4] or 'nil') .. ']'
		)
		echo('  Extracted build pos: (' .. buildX .. ', ' .. (buildY or 'nil') .. ', ' .. buildZ .. ') [corner]')
		echo('  Building center pos: (' .. buildCenterX .. ', ' .. buildCenterZ .. ') [calculated]')
		echo('  Constructor GetUnitPosition: (' .. unitX .. ', ' .. unitY .. ', ' .. unitZ .. ')')
		echo(
			'  Constructor GetUnitBasePosition: (' ..
				(baseX or 'nil') .. ', ' .. (baseY or 'nil') .. ', ' .. (baseZ or 'nil') .. ')'
		)
		echo('  Distance calculation: sqrt((' .. unitX .. '-' .. buildX .. ')^2 + (' .. unitZ .. '-' .. buildZ .. ')^2)')
		echo('  Distance components: deltaX=' .. (unitX - buildX) .. ', deltaZ=' .. (unitZ - buildZ))
		echo('  Distance to center: ' .. math.floor(distanceToCenter * 10) / 10)
		echo('  Building footprint: ' .. buildingFootprint)
		echo('  Constructor build distance: ' .. constructorDef.buildDistance)
		echo('  Constructor radius: ' .. constructorDef.radius)
		echo('  Max build distance: ' .. maxBuildDistance .. ' (buildDistance + radius)')
		echo(
			'  TestBuildOrder(' ..
				buildeeDefID ..
					', ' ..
						buildX .. ', ' .. (buildY or 0) .. ', ' .. buildZ .. ', ' .. buildFacing .. ') = ' .. (testBuildResult or 'nil')
		)
		echo('  Is blocked (TestBuildOrder == 0): ' .. (isBlocking and 'yes' or 'no'))
		echo('  Constructor can reach (distance): ' .. (constructorCanReach and 'yes' or 'no'))
		echo(
			'  Rectangle bounds: [' ..
				(buildCenterX - buildArea) ..
					', ' ..
						(buildCenterZ - buildArea) .. '] to [' .. (buildCenterX + buildArea) .. ', ' .. (buildCenterZ + buildArea) .. ']'
		)
		echo('  Constructor in build area (rectangle): ' .. (constructorInBuildArea and 'yes' or 'no'))
		echo('  GetUnitsInRectangle found: ' .. (#unitsInBuildArea or 0) .. ' units')
		echo('  Standing in building (combined): ' .. (isStandingInBuildingBool and 'YES' or 'NO'))
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

-- Find optimal position towards average that can reach as many queued buildings as possible
local function findOptimalPosition(
	constructorID,
	currentBuildCommand,
	averageX,
	averageZ,
	commands,
	standingInBuildIndex)
	local unitX, _, unitZ = Spring.GetUnitBasePosition(constructorID)
	local buildX, buildZ = currentBuildCommand.params[1], currentBuildCommand.params[3]
	local buildFacing = currentBuildCommand.params[4] or 0
	local buildeeDefID = -currentBuildCommand.id

	if not unitX or not buildX or not averageX then
		return nil
	end

	-- Get the actual center position of the building we're currently building
	local buildCenterX, buildCenterZ = getBuildingCenterPosition(buildX, buildZ, buildeeDefID, buildFacing)

	-- Use proper build distance calculation like the construction turrets gadget
	local constructorDefID = GetUnitDefID(constructorID)
	local constructorDef = constructorDefs[constructorDefID]
	if not constructorDef then
		return nil
	end

	-- Use maxBuildDistance (buildDistance + radius) for accurate range calculation
	local maxBuildDistance = constructorDef.maxBuildDistance

	-- Get all future build positions (after the current one we're standing in)
	local futureBuildPositions = {}
	for i = standingInBuildIndex + 1, #commands do
		local command = commands[i]
		if command.id < 0 and command.params then -- Build command
			local futureX, futureZ = command.params[1], command.params[3]
			local futureFacing = command.params[4] or 0
			local futureDefID = -command.id

			-- Get center position of future building
			local centerX, centerZ = getBuildingCenterPosition(futureX, futureZ, futureDefID, futureFacing)
			table.insert(futureBuildPositions, {centerX, centerZ})
		end
	end

	if #futureBuildPositions == 0 then
		-- No future builds, use simple positioning
		local dirX = averageX - buildCenterX
		local dirZ = averageZ - buildCenterZ
		local dirLength = math.sqrt(dirX ^ 2 + dirZ ^ 2)

		if dirLength < 10 then
			return nil
		end

		dirX = dirX / dirLength
		dirZ = dirZ / dirLength

		local safeRange = maxBuildDistance * 0.99
		local moveX = buildCenterX + dirX * safeRange
		local moveZ = buildCenterZ + dirZ * safeRange

		local moveDistance = math.sqrt((moveX - unitX) ^ 2 + (moveZ - unitZ) ^ 2)
		if moveDistance < 32 then
			return nil
		end

		return moveX, moveZ
	end

	-- Calculate direction from build center towards average position
	local dirX = averageX - buildCenterX
	local dirZ = averageZ - buildCenterZ
	local dirLength = math.sqrt(dirX ^ 2 + dirZ ^ 2)

	if dirLength < 10 then
		return nil
	end -- Too close, no need to move

	-- Normalize direction
	dirX = dirX / dirLength
	dirZ = dirZ / dirLength

	-- First, determine which future buildings are reachable from the current build center
	local initiallyReachableBuildings = {}
	for i, buildPos in ipairs(futureBuildPositions) do
		local distToBuilding = math.sqrt((buildCenterX - buildPos[1]) ^ 2 + (buildCenterZ - buildPos[2]) ^ 2)
		if distToBuilding <= maxBuildDistance then
			table.insert(initiallyReachableBuildings, i)
		end
	end

	-- Sample positions along the line from current building center towards average
	-- Only accept positions that can still reach ALL initially reachable buildings
	local bestPosition = nil
	local safeRange = maxBuildDistance * 0.99

	-- Sample at many distances along the direction to find optimal position
	local sampleCount = 10
	for i = 1, sampleCount do
		local progress = i / sampleCount -- 0.1, 0.2, ... 1.0
		local distance = safeRange * progress
		local sampleX = buildCenterX + dirX * distance
		local sampleZ = buildCenterZ + dirZ * distance

		-- Check if this position can still reach ALL initially reachable buildings
		local canReachAll = true
		for _, buildingIndex in ipairs(initiallyReachableBuildings) do
			local buildPos = futureBuildPositions[buildingIndex]
			local distToBuilding = math.sqrt((sampleX - buildPos[1]) ^ 2 + (sampleZ - buildPos[2]) ^ 2)
			if distToBuilding > maxBuildDistance then
				canReachAll = false
				break
			end
		end

		-- If we can reach all initially reachable buildings, this is a valid position
		-- Prefer the furthest position toward average (highest progress)
		if canReachAll then
			bestPosition = {x = sampleX, z = sampleZ, distance = distance, progress = progress}
		else
			-- Stop sampling once we can't reach all buildings
			break
		end
	end

	if not bestPosition then
		return nil
	end

	-- Check if the move position is significantly different from current position
	local moveDistance = math.sqrt((bestPosition.x - unitX) ^ 2 + (bestPosition.z - unitZ) ^ 2)
	if moveDistance < 32 then
		return nil
	end -- Not worth moving

	-- Debug output
	if debugMode then
		echo('=== Multi-Building Optimization (Conservative) ===')
		echo('  Constructor position: (' .. unitX .. ', ' .. unitZ .. ')')
		echo('  Current build center: (' .. buildCenterX .. ', ' .. buildCenterZ .. ')')
		echo('  Average position: (' .. averageX .. ', ' .. averageZ .. ')')
		echo('  Future buildings total: ' .. #futureBuildPositions)
		echo('  Initially reachable buildings: ' .. #initiallyReachableBuildings .. '/' .. #futureBuildPositions)
		echo('  Best position: (' .. bestPosition.x .. ', ' .. bestPosition.z .. ')')
		echo('  Progress toward average: ' .. math.floor(bestPosition.progress * 100) .. '%')
		echo('  Move distance: ' .. math.floor(moveDistance))
		echo('  Guarantees access to all ' .. #initiallyReachableBuildings .. ' initially reachable buildings')
	end

	return bestPosition.x, bestPosition.z
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
		-- if debugMode then
		--   echo('Constructor ' .. constructorID .. ' skipped: queue too small (' .. (#commands or 0) .. ' commands)')
		-- end
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

	-- Find all build commands and check if constructor is standing in any of them
	local buildCommands = {}
	local standingInBuildIndex = nil
	local standingInBuildCommand = nil

	for i, command in ipairs(commands) do
		if command.id < 0 then -- Build command
			table.insert(buildCommands, {command = command, index = i})

			-- Check if constructor is standing in this building position
			if not standingInBuildCommand and isStandingInBuilding(constructorID, command) then
				standingInBuildIndex = i
				standingInBuildCommand = command
				if debugMode then
					echo('Constructor ' .. constructorID .. ' is standing in build command at queue position ' .. i)
				end
			end
		end
		if i > 2 then
			break
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
			echo('Constructor ' .. constructorID .. ' skipped: not standing in any building position')
			echo('  Found ' .. #buildCommands .. ' build commands in queue')
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

	if debugMode then
		echo('*** SMART POSITIONING ACTIVATED ***')
		echo('Moving constructor ' .. constructorID .. ' to (' .. moveX .. ', ' .. moveY .. ', ' .. moveZ .. ')')

		-- Add debug spotlights when we actually make a move
		if WG['ObjectSpotlight'] then
			local spotlightID = 'smart_pos_' .. constructorID
			local unitX, _, unitZ = Spring.GetUnitPosition(constructorID)

			-- Constructor current position (yellow spotlight)
			WG['ObjectSpotlight'].addSpotlight(
				'ground',
				spotlightID .. '_constructor',
				{unitX, Spring.GetGroundHeight(unitX, unitZ), unitZ},
				{1, 1, 0, 1}, -- Yellow
				{duration = 30, radius = 20, heightCoefficient = 8}
			)

			-- Move destination (blue spotlight)
			WG['ObjectSpotlight'].addSpotlight(
				'ground',
				spotlightID .. '_destination',
				{moveX, moveY, moveZ},
				{0, 0, 1, 1}, -- Blue
				{duration = 30, radius = 16, heightCoefficient = 6}
			)

			-- Build position (red spotlight)
			local buildX, buildZ = standingInBuildCommand.params[1], standingInBuildCommand.params[3]
			WG['ObjectSpotlight'].addSpotlight(
				'ground',
				spotlightID .. '_build',
				{buildX, Spring.GetGroundHeight(buildX, buildZ), buildZ},
				{1, 0, 0, 1}, -- Red
				{duration = 30, radius = 16, heightCoefficient = 6}
			)

			-- Average position (green spotlight)
			WG['ObjectSpotlight'].addSpotlight(
				'ground',
				spotlightID .. '_average',
				{averageX, Spring.GetGroundHeight(averageX, averageZ), averageZ},
				{0, 1, 0, 1}, -- Green
				{duration = 30, radius = 16, heightCoefficient = 6}
			)

			-- Get proper build ranges using the construction turrets gadget approach
			local constructorDefID = GetUnitDefID(constructorID)
			local constructorDef = constructorDefs[constructorDefID]
			local maxBuildDistance = constructorDef.maxBuildDistance
			local baseBuildDistance = constructorDef.buildDistance
			local constructorRadius = constructorDef.radius
			local effectiveBuildRange = GetUnitEffectiveBuildRange(constructorID, -standingInBuildCommand.id)

			-- Most important: Max build range circle (bright blue spotlight)
			WG['ObjectSpotlight'].addSpotlight(
				'ground',
				spotlightID .. '_max_build_range',
				{buildX, Spring.GetGroundHeight(buildX, buildZ), buildZ},
				{0, 0.8, 1, 0.4}, -- Bright blue, semi-transparent
				{duration = 30, radius = maxBuildDistance, heightCoefficient = 1}
			)

			-- Base build range for comparison (cyan circle)
			if baseBuildDistance ~= maxBuildDistance then
				WG['ObjectSpotlight'].addSpotlight(
					'ground',
					spotlightID .. '_base_range',
					{buildX, Spring.GetGroundHeight(buildX, buildZ), buildZ},
					{0, 1, 1, 0.2}, -- Cyan, more transparent
					{duration = 30, radius = baseBuildDistance, heightCoefficient = 1}
				)
			end

			-- Effective build range if different from max (purple circle)
			if effectiveBuildRange and effectiveBuildRange ~= maxBuildDistance then
				WG['ObjectSpotlight'].addSpotlight(
					'ground',
					spotlightID .. '_effective_range',
					{buildX, Spring.GetGroundHeight(buildX, buildZ), buildZ},
					{0.8, 0, 0.8, 0.3}, -- Purple, semi-transparent
					{duration = 30, radius = effectiveBuildRange, heightCoefficient = 1}
				)
			end

			echo('Debug ranges:')
			echo('  Base build distance: ' .. baseBuildDistance)
			echo('  Constructor radius: ' .. constructorRadius)
			echo('  Max build distance: ' .. maxBuildDistance .. ' (base + radius)')
			echo('  Effective build range: ' .. (effectiveBuildRange or 'nil'))
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
	initializeConstructorDefs()

	-- Clean up if spectating
	if Spring.GetSpectatingState() or Spring.IsReplay() then
		widgetHandler:RemoveWidget()
		return
	end

	myTeamID = Spring.GetMyTeamID()
	initializeExistingConstructors()

	echo('Smart Constructor Positioning widget initialized with debug mode ON')
	echo('All constructors default to SMART_POSITIONING_ON')
	echo('Use "/luaui smartdebug" to toggle debug mode')
	echo('Use "/luaui smartinfo" to see constructor status')
end

function widget:CommandsChanged()
	if checkSelectedUnits(false) then
		local cmds = widgetHandler.customCommands
		cmds[#cmds + 1] = CMD_SMART_POSITIONING_DESCRIPTION
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
	if command == 'smartdebug' then
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
