-- Run with: lua tests/exponential_evo_eco_nano_test.lua
-- luacheck: globals UnitDefs assert dofile error ipairs math pairs pcall print string table tostring type

local tweakPath = 'tweaks/--ExponentialEvoEcoConTurre.lua'
local growthPivotLevel = 15
local earlyGrowthFactor = 1.25
local lateGrowthFactor = 1.12
local efficiencyGainPerLevel = 0.03
local nanoRangeGainPerLevel = 0.03
local factionPrefixes = { 'arm', 'cor', 'leg' }
local familyOrder = { 'fusion', 'converter', 'nano' }
local familyConfigs = {
	fusion = { suffix = 'evfus', levelCount = 30, yardmapSize = 24 },
	converter = { suffix = 'evconv', levelCount = 24, yardmapSize = 12 },
	nano = { suffix = 'evnano', levelCount = 30 },
}

local function fail(message)
	error(message, 2)
end

local function assertEqual(actual, expected, message)
	if actual ~= expected then
		fail(string.format('%s: expected %s, got %s', message or 'assertEqual', tostring(expected), tostring(actual)))
	end
end

local function assertTrue(value, message)
	assertEqual(value, true, message)
end

local function assertFalse(value, message)
	assertEqual(value, false, message)
end

local function assertNil(value, message)
	if value ~= nil then
		fail((message or 'assertNil') .. ': expected nil, got ' .. tostring(value))
	end
end

local function assertNotNil(value, message)
	if value == nil then
		fail((message or 'assertNotNil') .. ': expected a value')
	end
end

local function countEntries(values)
	local count = 0
	for _ in pairs(values) do
		count = count + 1
	end
	return count
end

local function deepEqual(left, right)
	if type(left) ~= type(right) then
		return false
	end
	if type(left) ~= 'table' then
		return left == right
	end
	for key, value in pairs(left) do
		if not deepEqual(value, right[key]) then
			return false
		end
	end
	for key in pairs(right) do
		if left[key] == nil then
			return false
		end
	end
	return true
end

table.copy = function(source)
	local result = {}
	for key, value in pairs(source) do
		if type(value) == 'table' then
			result[key] = table.copy(value)
		else
			result[key] = value
		end
	end
	return result
end

table.merge = function(base, overrides)
	local result = table.copy(base)
	for key, value in pairs(overrides) do
		if type(value) == 'table' and type(result[key]) == 'table' then
			result[key] = table.merge(result[key], value)
		elseif type(value) == 'table' then
			result[key] = table.copy(value)
		else
			result[key] = value
		end
	end
	return result
end

local factions = {
	{
		prefix = 'arm',
		fusionBase = 'armafust3',
		converterBase = 'armmmkrt3',
		nanoT2Base = 'armnanotct2',
		nanoT3Base = 'armnanotct3',
		nanoObject = 'Units/ARMRESPAWN.s3o',
		builders = { 'armaca', 'armack', 'armacsub', 'armacv', 'armt3aide', 'armt3airaide' },
	},
	{
		prefix = 'cor',
		fusionBase = 'corafust3',
		converterBase = 'cormmkrt3',
		nanoT2Base = 'cornanotct2',
		nanoT3Base = 'cornanotct3',
		nanoObject = 'Units/CORRESPAWN.s3o',
		builders = { 'coraca', 'corack', 'coracsub', 'coracv', 'cort3aide', 'cort3airaide' },
	},
	{
		prefix = 'leg',
		fusionBase = 'legafust3',
		converterBase = 'legadveconvt3',
		nanoT2Base = 'legnanotct2',
		nanoT3Base = 'legnanotct3',
		nanoObject = 'Units/legnanotcbase.s3o',
		builders = { 'legaca', 'legack', 'legacv', 'legcomt2com', 'legt3aide', 'legt3airaide' },
	},
}

local function fusionDef(prefix)
	return {
		name = prefix .. ' fusion source',
		metalcost = 90000,
		energycost = 550000,
		buildtime = 2500000,
		energymake = 30000,
		energystorage = 90000,
		footprintx = 12,
		footprintz = 12,
		health = 7900,
		mass = 91000,
		sightdistance = 273,
		collisionvolumescales = '192 192 192',
		objectname = prefix .. '_fusion.s3o',
		script = prefix .. '_fusion.cob',
		explodeas = 'fusionExplosion',
		selfdestructas = 'fusionSelfDestruct',
		customparams = {
			family_sentinel = prefix .. '_fusion',
			energygroup = 'energy',
		},
	}
end

local function converterDef(prefix)
	return {
		name = prefix .. ' converter source',
		metalcost = 9000,
		energycost = 550000,
		buildtime = 350000,
		footprintx = 8,
		footprintz = 8,
		health = 1500,
		mass = 9000,
		sightdistance = 273,
		collisionvolumescales = '122 107 121',
		objectname = prefix .. '_converter.s3o',
		script = prefix .. '_converter.cob',
		explodeas = 'converterExplosion',
		selfdestructas = 'converterSelfDestruct',
		customparams = {
			family_sentinel = prefix .. '_converter',
			energyconv_capacity = 6000,
			energyconv_efficiency = 0.02,
		},
	}
end

local function nanoT2Def(prefix)
	return {
		name = prefix .. ' nano source',
		metalcost = 840,
		energycost = 12800,
		buildtime = 21000,
		workertime = 600,
		builddistance = 500,
		builder = true,
		canassist = true,
		canfight = true,
		canguard = true,
		canpatrol = true,
		canreclaim = true,
		canstop = true,
		canmove = false,
		movementclass = 'NANO',
		terraformspeed = 3000,
		upright = true,
		footprintx = 4,
		footprintz = 4,
		health = 2200,
		mass = 5100,
		sightdistance = 500,
		collisionvolumescales = '46 80 46',
		objectname = prefix .. '_nano.s3o',
		script = prefix .. '_nano.cob',
		explodeas = 'nanoExplosion',
		selfdestructas = 'nanoSelfDestruct',
		-- Deliberately present to prove generated static builders explicitly
		-- clear inherited yardmaps instead of relying on a nil merge override.
		yardmap = string.rep('o', 16),
		customparams = {
			family_sentinel = prefix .. '_nano',
			unitgroup = 'builder',
		},
	}
end

UnitDefs = {}
for _, faction in ipairs(factions) do
	UnitDefs[faction.fusionBase] = fusionDef(faction.prefix)
	UnitDefs[faction.converterBase] = converterDef(faction.prefix)
	UnitDefs[faction.nanoT2Base] = nanoT2Def(faction.prefix)
	for _, builderName in ipairs(faction.builders) do
		UnitDefs[builderName] = { buildoptions = { 'existingoption' } }
	end
end
UnitDefs.armaca.buildoptions[#UnitDefs.armaca.buildoptions + 1] = 'armevfus1'

local sourceSnapshots = {}
for _, faction in ipairs(factions) do
	for _, sourceName in ipairs({ faction.fusionBase, faction.converterBase, faction.nanoT2Base }) do
		sourceSnapshots[sourceName] = table.copy(UnitDefs[sourceName])
	end
end

local function expectedProductionMultiplier(level)
	local earlySteps = math.min(level - 1, growthPivotLevel - 1)
	local lateSteps = math.max(level - growthPivotLevel, 0)
	return (earlyGrowthFactor ^ earlySteps) * (lateGrowthFactor ^ lateSteps)
end

local function expectedProduction(value, level)
	return math.ceil(value * expectedProductionMultiplier(level))
end

local function expectedCost(value, level)
	local efficiency = 1 + efficiencyGainPerLevel * (level - 1)
	return math.ceil(value * expectedProductionMultiplier(level) / efficiency)
end

local function expectedLinear(value, level, gainPerLevel)
	return math.ceil(value * (1 + gainPerLevel * (level - 1)))
end

local function parseYardmap(yardmap)
	assertNotNil(yardmap, 'yardmap')
	local compact = yardmap:gsub('%s+', '')
	assertEqual(compact:sub(1, 1), 'h', 'high-resolution prefix')
	local body = compact:sub(2)
	local size = math.floor(math.sqrt(#body) + 0.5)
	assertEqual(size * size, #body, 'square yardmap')
	local grid = {}
	for row = 1, size do
		grid[row] = {}
		for column = 1, size do
			grid[row][column] = body:sub((row - 1) * size + column, (row - 1) * size + column)
		end
	end
	return grid, size, body
end

local function countCharacter(body, wanted)
	local count = 0
	for index = 1, #body do
		if body:sub(index, index) == wanted then
			count = count + 1
		end
	end
	return count
end

local function rotateGrid(grid)
	local size = #grid
	local result = {}
	for row = 1, size do
		result[row] = {}
		for column = 1, size do
			result[row][column] = grid[size - column + 1][row]
		end
	end
	return result
end

local function gridsEqual(left, right)
	if #left ~= #right then
		return false
	end
	for row = 1, #left do
		for column = 1, #left do
			if left[row][column] ~= right[row][column] then
				return false
			end
		end
	end
	return true
end

local function assertFourWaySymmetry(grid, message)
	local rotated = grid
	for facing = 1, 3 do
		rotated = rotateGrid(rotated)
		assertTrue(gridsEqual(grid, rotated), message .. ' facing ' .. facing)
	end
end

local function hardMarkerKey(grid)
	local coordinates = {}
	for row = 1, #grid do
		for column = 1, #grid do
			if grid[row][column] == 'o' then
				coordinates[#coordinates + 1] = row .. ':' .. column
			end
		end
	end
	assertEqual(#coordinates, 4, 'one four-cell hard-marker orbit')
	return table.concat(coordinates, ',')
end

local function solidGrid(size)
	local grid = {}
	for row = 1, size do
		grid[row] = {}
		for column = 1, size do
			grid[row][column] = 'o'
		end
	end
	return grid
end

-- Mirrors Recoil placement: b cells are always open, while BAR's geothermal
-- gadget opens c cells only after UnitFinished. Incoming s cells may stack.
local function canPlace(existing, incoming, rowOffset, columnOffset, existingFinished)
	if existingFinished == nil then
		existingFinished = true
	end
	local overlaps = false
	for incomingRow = 1, #incoming do
		local existingRow = rowOffset + incomingRow
		if existingRow >= 1 and existingRow <= #existing then
			for incomingColumn = 1, #incoming do
				local existingColumn = columnOffset + incomingColumn
				if existingColumn >= 1 and existingColumn <= #existing then
					overlaps = true
					local existingCell = existing[existingRow][existingColumn]
					local existingOpen = existingCell == 'b' or (existingFinished and existingCell == 'c')
					if not existingOpen and incoming[incomingRow][incomingColumn] ~= 's' then
						return false
					end
				end
			end
		end
	end
	return overlaps
end

local function eachOverlappingOffset(existingSize, incomingSize, callback)
	for rowOffset = -(incomingSize - 2), existingSize - 2, 2 do
		for columnOffset = -(incomingSize - 2), existingSize - 2, 2 do
			callback(rowOffset, columnOffset)
		end
	end
end

local function assertAllOverlapsRejected(existing, incoming, message)
	eachOverlappingOffset(#existing, #incoming, function(rowOffset, columnOffset)
		if canPlace(existing, incoming, rowOffset, columnOffset) then
			fail(string.format('%s at offset %d,%d', message, rowOffset, columnOffset))
		end
	end)
end

local function assertQuadrant(grid, expectedRows, message)
	for row, expected in ipairs(expectedRows) do
		assertEqual(table.concat(grid[row], '', 1, #expected), expected, message .. ' row ' .. row)
	end
end

local function isRecoilFactory(definition)
	local isBuilder = definition.builder == true and definition.workertime > 0 and definition.builddistance > 0
	local isBuilding = definition.yardmap ~= nil and definition.yardmap ~= ''
	return isBuilder and isBuilding
end

local function assertSourceDefinitionsUnchanged()
	for sourceName, snapshot in pairs(sourceSnapshots) do
		assertTrue(deepEqual(UnitDefs[sourceName], snapshot), sourceName .. ' source definition remains unchanged')
	end
end

print('Running exponential evolving economy and nano tests...')
assert(dofile(tweakPath) == nil)

local evolvedCount = 0
local yardmapGrids = { fusion = {}, converter = {} }
for _, faction in ipairs(factions) do
	yardmapGrids.fusion[faction.prefix] = {}
	yardmapGrids.converter[faction.prefix] = {}

	local nanoT3 = UnitDefs[faction.nanoT3Base]
	assertNotNil(nanoT3, faction.nanoT3Base .. ' baseline')
	assertEqual(nanoT3.metalcost, 3700, faction.nanoT3Base .. ' metal cost')
	assertEqual(nanoT3.energycost, 62000, faction.nanoT3Base .. ' energy cost')
	assertEqual(nanoT3.buildtime, 108000, faction.nanoT3Base .. ' build time')
	assertEqual(nanoT3.workertime, 1900, faction.nanoT3Base .. ' build power')
	assertEqual(nanoT3.builddistance, 550, faction.nanoT3Base .. ' build distance')
	assertEqual(nanoT3.footprintx, 6, faction.nanoT3Base .. ' footprint X')
	assertEqual(nanoT3.footprintz, 6, faction.nanoT3Base .. ' footprint Z')
	assertEqual(nanoT3.health, 8800, faction.nanoT3Base .. ' health')
	assertEqual(nanoT3.mass, 37200, faction.nanoT3Base .. ' mass')
	assertEqual(nanoT3.sightdistance, 575, faction.nanoT3Base .. ' sight distance')
	assertEqual(nanoT3.collisionvolumescales, '61 128 61', faction.nanoT3Base .. ' collision volume')
	assertEqual(nanoT3.objectname, faction.nanoObject, faction.nanoT3Base .. ' model')
	assertEqual(nanoT3.builder, true, faction.nanoT3Base .. ' remains a builder')
	assertNil(nanoT3.yardmap, faction.nanoT3Base .. ' has no factory-triggering yardmap')
	assertFalse(isRecoilFactory(nanoT3), faction.nanoT3Base .. ' is not classified as a factory')
	assertEqual(nanoT3.customparams.family_sentinel, faction.prefix .. '_nano', faction.nanoT3Base .. ' inherited custom parameter')

	local fusionMarkers = {}
	for level = 1, familyConfigs.fusion.levelCount do
		local unitName = faction.prefix .. familyConfigs.fusion.suffix .. level
		local fusion = UnitDefs[unitName]
		assertNotNil(fusion, unitName)
		evolvedCount = evolvedCount + 1
		assertEqual(fusion.footprintx, 12, unitName .. ' footprint X')
		assertEqual(fusion.footprintz, 12, unitName .. ' footprint Z')
		assertEqual(fusion.metalcost, expectedCost(90000, level), unitName .. ' metal cost')
		assertEqual(fusion.energycost, expectedCost(550000, level), unitName .. ' energy cost')
		assertEqual(fusion.buildtime, expectedCost(2500000, level), unitName .. ' build time')
		assertEqual(fusion.energymake, expectedProduction(30000, level), unitName .. ' energy production')
		assertEqual(fusion.energystorage, expectedProduction(90000, level), unitName .. ' energy storage')
		assertEqual(fusion.health, 7900, unitName .. ' fixed health')
		assertEqual(fusion.mass, 91000, unitName .. ' fixed mass')
		assertEqual(fusion.sightdistance, 273, unitName .. ' fixed sight range')
		assertEqual(fusion.objectname, faction.prefix .. '_fusion.s3o', unitName .. ' inherited model')
		assertEqual(fusion.script, faction.prefix .. '_fusion.cob', unitName .. ' inherited script')
		assertEqual(fusion.explodeas, 'fusionExplosion', unitName .. ' inherited explosion')
		assertEqual(fusion.selfdestructas, 'fusionSelfDestruct', unitName .. ' inherited self-destruct explosion')
		assertEqual(fusion.customparams.family_sentinel, faction.prefix .. '_fusion', unitName .. ' inherited custom parameter')
		assertEqual(fusion.customparams.geothermal, 1, unitName .. ' uses BAR geothermal replacement')
		assertTrue(fusion.customparams.i18n_en_tooltip:find(tostring(fusion.energymake), 1, true) ~= nil, unitName .. ' generated output tooltip')

		local grid, size, body = parseYardmap(fusion.yardmap)
		assertEqual(size, familyConfigs.fusion.yardmapSize, unitName .. ' yardmap size')
		assertTrue(body:match('^[sboc]+$') ~= nil, unitName .. ' yardmap characters')
		assertFourWaySymmetry(grid, unitName .. ' four-way symmetry')
		assertEqual(countCharacter(body, 's'), (27 + level - 1) * 4, unitName .. ' stackable cells')
		assertEqual(countCharacter(body, 'o'), 4, unitName .. ' hard-marker cells')
		assertEqual(countCharacter(body, 'c'), 4, unitName .. ' completion-gate cells')
		for _, corner in ipairs({ { 1, 1 }, { 1, size }, { size, 1 }, { size, size } }) do
			assertTrue(grid[corner[1]][corner[2]] ~= 'b', unitName .. ' filled corner')
		end
		fusionMarkers[hardMarkerKey(grid)] = true
		yardmapGrids.fusion[faction.prefix][level] = grid
	end
	assertEqual(countEntries(fusionMarkers), familyConfigs.fusion.levelCount, faction.prefix .. ' unique fusion markers')

	local converterMarkers = {}
	for level = 1, familyConfigs.converter.levelCount do
		local unitName = faction.prefix .. familyConfigs.converter.suffix .. level
		local converter = UnitDefs[unitName]
		assertNotNil(converter, unitName)
		evolvedCount = evolvedCount + 1
		assertEqual(converter.footprintx, 6, unitName .. ' footprint X')
		assertEqual(converter.footprintz, 6, unitName .. ' footprint Z')
		assertEqual(converter.metalcost, expectedCost(9000, level), unitName .. ' metal cost')
		assertEqual(converter.energycost, expectedCost(550000, level), unitName .. ' energy cost')
		assertEqual(converter.buildtime, expectedCost(350000, level), unitName .. ' build time')
		assertEqual(converter.customparams.energyconv_capacity, expectedProduction(6000, level), unitName .. ' capacity')
		assertEqual(converter.customparams.energyconv_efficiency, 0.02, unitName .. ' fixed efficiency')
		assertEqual(converter.health, 1500, unitName .. ' fixed health')
		assertEqual(converter.mass, 9000, unitName .. ' fixed mass')
		assertEqual(converter.sightdistance, 273, unitName .. ' fixed sight range')
		assertEqual(converter.collisionvolumescales, '122 107 121', unitName .. ' inherited collision volume')
		assertEqual(converter.objectname, faction.prefix .. '_converter.s3o', unitName .. ' inherited model')
		assertEqual(converter.script, faction.prefix .. '_converter.cob', unitName .. ' inherited script')
		assertEqual(converter.explodeas, 'converterExplosion', unitName .. ' inherited explosion')
		assertEqual(converter.selfdestructas, 'converterSelfDestruct', unitName .. ' inherited self-destruct explosion')
		assertEqual(converter.customparams.family_sentinel, faction.prefix .. '_converter', unitName .. ' inherited custom parameter')
		assertEqual(converter.customparams.geothermal, 1, unitName .. ' uses BAR geothermal replacement')
		assertTrue(converter.customparams.i18n_en_tooltip:find(tostring(converter.customparams.energyconv_capacity), 1, true) ~= nil, unitName .. ' generated capacity tooltip')

		local grid, size, body = parseYardmap(converter.yardmap)
		assertEqual(size, familyConfigs.converter.yardmapSize, unitName .. ' yardmap size')
		assertTrue(body:match('^[sboc]+$') ~= nil, unitName .. ' yardmap characters')
		assertFourWaySymmetry(grid, unitName .. ' four-way symmetry')
		assertEqual(countCharacter(body, 's'), (6 + level - 1) * 4, unitName .. ' stackable cells')
		assertEqual(countCharacter(body, 'o'), 4, unitName .. ' hard-marker cells')
		assertEqual(countCharacter(body, 'c'), 4, unitName .. ' completion-gate cells')
		for _, corner in ipairs({ { 1, 1 }, { 1, size }, { size, 1 }, { size, size } }) do
			assertTrue(grid[corner[1]][corner[2]] ~= 'b', unitName .. ' filled corner')
		end
		converterMarkers[hardMarkerKey(grid)] = true
		yardmapGrids.converter[faction.prefix][level] = grid
	end
	assertEqual(countEntries(converterMarkers), familyConfigs.converter.levelCount, faction.prefix .. ' unique converter markers')
	for level = familyConfigs.converter.levelCount + 1, 30 do
		assertNil(UnitDefs[faction.prefix .. familyConfigs.converter.suffix .. level], faction.prefix .. ' converter level ' .. level .. ' omitted')
	end

	for level = 1, familyConfigs.nano.levelCount do
		local unitName = faction.prefix .. familyConfigs.nano.suffix .. level
		local nano = UnitDefs[unitName]
		assertNotNil(nano, unitName)
		evolvedCount = evolvedCount + 1
		assertEqual(nano.footprintx, 6, unitName .. ' footprint X')
		assertEqual(nano.footprintz, 6, unitName .. ' footprint Z')
		assertEqual(nano.metalcost, expectedCost(3700, level), unitName .. ' metal cost')
		assertEqual(nano.energycost, expectedCost(62000, level), unitName .. ' energy cost')
		assertEqual(nano.buildtime, expectedCost(108000, level), unitName .. ' build time')
		assertEqual(nano.workertime, expectedProduction(1900, level), unitName .. ' build power')
		assertEqual(nano.health, 8800, unitName .. ' fixed health')
		assertEqual(nano.mass, 37200, unitName .. ' fixed mass')
		assertEqual(nano.sightdistance, 575, unitName .. ' fixed sight range')
		assertEqual(nano.builddistance, expectedLinear(550, level, nanoRangeGainPerLevel), unitName .. ' linear build distance')
		assertEqual(nano.collisionvolumescales, '61 128 61', unitName .. ' fixed collision volume')
		assertEqual(nano.objectname, faction.nanoObject, unitName .. ' inherited T3 model')
		assertEqual(nano.script, faction.prefix .. '_nano.cob', unitName .. ' inherited script')
		assertEqual(nano.explodeas, 'nanoExplosion', unitName .. ' inherited explosion')
		assertEqual(nano.selfdestructas, 'nanoSelfDestruct', unitName .. ' inherited self-destruct explosion')
		assertEqual(nano.builder, true, unitName .. ' remains a builder')
		for _, fieldName in ipairs({ 'canassist', 'canfight', 'canguard', 'canpatrol', 'canreclaim', 'canstop' }) do
			assertEqual(nano[fieldName], true, unitName .. ' preserves ' .. fieldName)
		end
		assertEqual(nano.movementclass, 'NANO', unitName .. ' inherited movement class')
		assertEqual(nano.terraformspeed, 3000, unitName .. ' inherited terraform speed')
		assertNil(nano.yardmap, unitName .. ' has no factory-triggering yardmap')
		assertFalse(isRecoilFactory(nano), unitName .. ' is a functional static builder, not a factory')
		assertEqual(nano.customparams.family_sentinel, faction.prefix .. '_nano', unitName .. ' inherited custom parameter')
		assertNil(nano.customparams.geothermal, unitName .. ' does not use geothermal replacement')
		assertTrue(nano.customparams.i18n_en_tooltip:find(tostring(nano.workertime), 1, true) ~= nil, unitName .. ' generated buildpower tooltip')
		assertTrue(nano.customparams.i18n_en_tooltip:find(tostring(nano.builddistance), 1, true) ~= nil, unitName .. ' generated range tooltip')
	end
end

assertEqual(evolvedCount, 252, 'total evolved definitions')
assertSourceDefinitionsUnchanged()

assertEqual(UnitDefs.armevfus15.energymake, 682122, 'level 15 uses the final 25% growth step')
assertEqual(UnitDefs.armevfus16.energymake, 763976, 'level 16 starts the 12% growth phase')
assertEqual(UnitDefs.armevfus30.energymake, 3733635, 'fusion level 30 keeps the approved production curve')
assertEqual(UnitDefs.armevfus30.metalcost, 5989788, 'fusion level 30 keeps the approved linear efficiency gain')
assertEqual(UnitDefs.armevconv24.customparams.energyconv_capacity, expectedProduction(6000, 24), 'converter level 24 follows the production curve')
assertEqual(UnitDefs.armevnano30.workertime, 236464, 'nano level 30 keeps the approved production curve')
assertEqual(UnitDefs.armevnano30.builddistance, 1029, 'nano level 30 has 87% more linear build range')

assertQuadrant(yardmapGrids.converter.arm[1], {
	'ocsbsb',
	'bbbbbb',
	'bbbbbb',
	'bbsbbb',
	'bbbbbs',
	'sbsbbb',
}, 'converter level 1 quadrant')
assertQuadrant(yardmapGrids.converter.arm[12], {
	'scsssb',
	'sbssbb',
	'ssssss',
	'obsbbb',
	'bbbbbs',
	'sbsbbb',
}, 'converter level 12 quadrant')
assertQuadrant(yardmapGrids.converter.arm[24], {
	'scsssb',
	'sbssbb',
	'ssssss',
	'sbssss',
	'ssssss',
	'ssssos',
}, 'converter level 24 quadrant')

local _, _, topFusionBody = parseYardmap(UnitDefs.armevfus30.yardmap)
local _, _, topConverterBody = parseYardmap(UnitDefs.armevconv24.yardmap)
assertEqual(countCharacter(topFusionBody, 'b') / 4 - 26, 60, 'fusion retains 60 spare build-only orbits')
assertEqual(countCharacter(topConverterBody, 'b'), 20, 'converter retains five build-only guard orbits plus one completion gate')

for familyName, config in pairs({ fusion = familyConfigs.fusion, converter = familyConfigs.converter }) do
	for level = 1, config.levelCount do
		local armYardmap = UnitDefs['arm' .. config.suffix .. level].yardmap
		assertEqual(armYardmap, UnitDefs['cor' .. config.suffix .. level].yardmap, familyName .. ' Armada/Cortex yardmap level ' .. level)
		assertEqual(armYardmap, UnitDefs['leg' .. config.suffix .. level].yardmap, familyName .. ' Armada/Legion yardmap level ' .. level)
	end
end

local function assertStrictCrossFactionLadder(familyName)
	local config = familyConfigs[familyName]
	for _, existingPrefix in ipairs(factionPrefixes) do
		for _, incomingPrefix in ipairs(factionPrefixes) do
			for existingLevel = 1, config.levelCount do
				local existing = yardmapGrids[familyName][existingPrefix][existingLevel]
				for incomingLevel = 1, config.levelCount do
					local incoming = yardmapGrids[familyName][incomingPrefix][incomingLevel]
					for facing = 0, 3 do
						if facing > 0 then
							incoming = rotateGrid(incoming)
						end
						local expected = existingLevel < incomingLevel
						local actual = canPlace(existing, incoming, 0, 0)
						if actual ~= expected then
							fail(string.format('%s placement %s%d -> %s%d facing %d', familyName, existingPrefix, existingLevel, incomingPrefix, incomingLevel, facing))
						end
						if canPlace(existing, incoming, 0, 0, false) then
							fail(string.format('%s unfinished placement %s%d -> %s%d facing %d', familyName, existingPrefix, existingLevel, incomingPrefix, incomingLevel, facing))
						end
					end
				end
			end
		end
	end
end

local function assertShiftedFamilyPlacementsRejected(familyName)
	local config = familyConfigs[familyName]
	local grids = yardmapGrids[familyName].arm
	for existingLevel = 1, config.levelCount do
		for incomingLevel = 1, config.levelCount do
			local existing = grids[existingLevel]
			local incoming = grids[incomingLevel]
			for facing = 0, 3 do
				if facing > 0 then
					incoming = rotateGrid(incoming)
				end
				eachOverlappingOffset(#existing, #incoming, function(rowOffset, columnOffset)
					if rowOffset ~= 0 or columnOffset ~= 0 then
						if canPlace(existing, incoming, rowOffset, columnOffset) then
							fail(string.format('%s shifted overlap L%d/L%d facing %d at %d,%d', familyName, existingLevel, incomingLevel, facing, rowOffset, columnOffset))
						end
						if canPlace(existing, incoming, rowOffset, columnOffset, false) then
							fail(string.format('%s unfinished shifted overlap L%d/L%d facing %d at %d,%d', familyName, existingLevel, incomingLevel, facing, rowOffset, columnOffset))
						end
					end
				end)
			end
		end
	end
end

assertStrictCrossFactionLadder('fusion')
assertStrictCrossFactionLadder('converter')
assertShiftedFamilyPlacementsRejected('fusion')
assertShiftedFamilyPlacementsRejected('converter')

local wall = solidGrid(4)
for familyName, config in pairs({ fusion = familyConfigs.fusion, converter = familyConfigs.converter }) do
	for level = 1, config.levelCount do
		local evolved = yardmapGrids[familyName].arm[level]
		assertAllOverlapsRejected(evolved, wall, familyName .. ' L' .. level .. ' rejects walls over every full/partial overlap')
		assertAllOverlapsRejected(wall, evolved, familyName .. ' L' .. level .. ' rejects placement over every full/partial wall overlap')
		local solidPeer = solidGrid(#evolved)
		assertAllOverlapsRejected(evolved, solidPeer, familyName .. ' L' .. level .. ' rejects ordinary peer buildings')
		assertAllOverlapsRejected(solidPeer, evolved, familyName .. ' L' .. level .. ' rejects placement over ordinary peer buildings')
	end
end

for converterLevel = 1, familyConfigs.converter.levelCount do
	local converter = yardmapGrids.converter.arm[converterLevel]
	for fusionLevel = 1, familyConfigs.fusion.levelCount do
		local fusion = yardmapGrids.fusion.cor[fusionLevel]
		assertAllOverlapsRejected(converter, fusion, 'fusion cannot cross-stack over converter')
		assertAllOverlapsRejected(fusion, converter, 'converter cannot cross-stack over fusion')
	end
end

local nanoBlockingGrid = solidGrid(12)
assertFalse(canPlace(nanoBlockingGrid, nanoBlockingGrid, 0, 0), 'functional nanos cannot stack over each other')
for converterLevel = 1, familyConfigs.converter.levelCount do
	local converter = yardmapGrids.converter.arm[converterLevel]
	assertAllOverlapsRejected(converter, nanoBlockingGrid, 'nano cannot stack over converter')
	assertAllOverlapsRejected(nanoBlockingGrid, converter, 'converter cannot stack over nano')
end

for _, faction in ipairs(factions) do
	for _, builderName in ipairs(faction.builders) do
		local counts = {}
		for _, optionName in ipairs(UnitDefs[builderName].buildoptions) do
			counts[optionName] = (counts[optionName] or 0) + 1
		end
		assertEqual(counts.existingoption, 1, builderName .. ' preserves existing build option')
		for familyName, config in pairs(familyConfigs) do
			for level = 1, config.levelCount do
				assertEqual(counts[faction.prefix .. config.suffix .. level], 1, builderName .. ' ' .. familyName .. ' option ' .. level)
			end
		end
		assertEqual(#UnitDefs[builderName].buildoptions, 85, builderName .. ' option count')
		local optionIndex = 2
		for level = 1, 30 do
			for _, familyName in ipairs(familyOrder) do
				local config = familyConfigs[familyName]
				if level <= config.levelCount then
					assertEqual(
						UnitDefs[builderName].buildoptions[optionIndex],
						faction.prefix .. config.suffix .. level,
						builderName .. ' level-major menu order at position ' .. optionIndex
					)
					optionIndex = optionIndex + 1
				end
			end
		end
	end
end

local definitionCountBeforeReload = countEntries(UnitDefs)
local builderLengthsBeforeReload = {}
for _, faction in ipairs(factions) do
	for _, builderName in ipairs(faction.builders) do
		builderLengthsBeforeReload[builderName] = #UnitDefs[builderName].buildoptions
	end
end
assert(dofile(tweakPath) == nil)
assertEqual(countEntries(UnitDefs), definitionCountBeforeReload, 'reload does not add definitions')
for builderName, length in pairs(builderLengthsBeforeReload) do
	assertEqual(#UnitDefs[builderName].buildoptions, length, builderName .. ' reload does not duplicate options')
end
for _, faction in ipairs(factions) do
	for level = 1, familyConfigs.nano.levelCount do
		assertNil(UnitDefs[faction.prefix .. familyConfigs.nano.suffix .. level].yardmap, faction.prefix .. ' nano reload remains yardmap-free')
	end
end
assertSourceDefinitionsUnchanged()

local completeUnitDefs = UnitDefs
UnitDefs = { armaca = { buildoptions = {} } }
local missingSourcesOk, missingSourcesError = pcall(dofile, tweakPath)
assertTrue(missingSourcesOk, 'missing source definitions are skipped: ' .. tostring(missingSourcesError))
assertEqual(countEntries(UnitDefs), 1, 'missing source run adds no partial definitions')
UnitDefs = completeUnitDefs

print('  [PASS] generated 30 fusion, 24 converter, and 30 functional nano levels for all factions')
print('  [PASS] validated two-phase growth, linear efficiency, cloning, build options, and idempotency')
print('  [PASS] exhaustively validated completion gates, rotations, offsets, walls, unrelated buildings, and strict upgrade ladders')
print('Passed exponential evolving economy and nano tests.')
