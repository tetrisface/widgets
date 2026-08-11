-- Run with: lua tests/exponential_evo_eco_nano_test.lua
-- luacheck: globals UnitDefs assert dofile error ipairs math pairs pcall print string table tostring type

local tweakPath = 'tweaks/--ExponentialEvoEcoConTurre.lua'
local maxLevel = 30
local growthPivotLevel = 15
local earlyGrowthFactor = 1.25
local lateGrowthFactor = 1.12
local efficiencyGainPerLevel = 0.03

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

local function assertRotationallySymmetric(grid, size, message)
	for row = 1, size do
		for column = 1, size do
			assertEqual(grid[row][column], grid[column][size - row + 1], message)
		end
	end
end

local function assertWallSafe(grid, size, message)
	for startRow = 1, size - 3 do
		for startColumn = 1, size - 3 do
			local guarded = false
			for row = startRow, startRow + 3 do
				for column = startColumn, startColumn + 3 do
					if grid[row][column] == 's' then
						guarded = true
					end
				end
			end
			assertTrue(guarded, message .. ' at ' .. startRow .. ',' .. startColumn)
		end
	end
end

local function assertDottedGuardBorder(grid, size, anchors, message)
	local anchorSet = {}
	for _, position in ipairs(anchors) do
		anchorSet[position] = true
	end
	for row = 1, size do
		for column = 1, size do
			if row == 1 or row == size or column == 1 or column == size then
				local expectedGuard = ((row == 1 or row == size) and anchorSet[column]) or ((column == 1 or column == size) and anchorSet[row]) or false
				assertEqual(grid[row][column] == 's', expectedGuard, message .. ' at ' .. row .. ',' .. column)
			end
		end
	end
end

local function hardMarkerKey(grid, size)
	local coordinates = {}
	for row = 1, size do
		for column = 1, size do
			if grid[row][column] == 'o' then
				coordinates[#coordinates + 1] = row .. ':' .. column
			end
		end
	end
	assertEqual(#coordinates, 4, 'one four-cell hard-marker orbit')
	return table.concat(coordinates, ',')
end

local function canStack(existingYardmap, incomingYardmap)
	local existing, existingSize = parseYardmap(existingYardmap)
	local incoming, incomingSize = parseYardmap(incomingYardmap)
	assertEqual(incomingSize, existingSize, 'stacked yardmap dimensions')
	for row = 1, existingSize do
		for column = 1, existingSize do
			local existingCell = existing[row][column]
			local incomingCell = incoming[row][column]
			if existingCell ~= 'b' and incomingCell ~= 's' then
				return false
			end
		end
	end
	return true
end

local function assertSourceDefinitionsUnchanged()
	for sourceName, snapshot in pairs(sourceSnapshots) do
		assertTrue(deepEqual(UnitDefs[sourceName], snapshot), sourceName .. ' source definition remains unchanged')
	end
end

print('Running exponential evolving economy and nano tests...')
assert(dofile(tweakPath) == nil)

local evolvedCount = 0
for _, faction in ipairs(factions) do
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
	assertEqual(nanoT3.customparams.family_sentinel, faction.prefix .. '_nano', faction.nanoT3Base .. ' inherited custom parameter')

	local fusionMarkers = {}
	local converterMarkers = {}
	local nanoMarkers = {}
	for level = 1, maxLevel do
		local fusionName = faction.prefix .. 'evfus' .. level
		local converterName = faction.prefix .. 'evconv' .. level
		local nanoName = faction.prefix .. 'evnano' .. level
		local fusion = UnitDefs[fusionName]
		local converter = UnitDefs[converterName]
		local nano = UnitDefs[nanoName]
		assertNotNil(fusion, fusionName)
		assertNotNil(converter, converterName)
		assertNotNil(nano, nanoName)
		evolvedCount = evolvedCount + 3

		assertEqual(fusion.footprintx, 12, fusionName .. ' footprint X')
		assertEqual(fusion.footprintz, 12, fusionName .. ' footprint Z')
		assertEqual(fusion.metalcost, expectedCost(90000, level), fusionName .. ' metal cost')
		assertEqual(fusion.energycost, expectedCost(550000, level), fusionName .. ' energy cost')
		assertEqual(fusion.buildtime, expectedCost(2500000, level), fusionName .. ' build time')
		assertEqual(fusion.energymake, expectedProduction(30000, level), fusionName .. ' energy production')
		assertEqual(fusion.energystorage, expectedProduction(90000, level), fusionName .. ' energy storage')
		assertEqual(fusion.health, 7900, fusionName .. ' fixed health')
		assertEqual(fusion.mass, 91000, fusionName .. ' fixed mass')
		assertEqual(fusion.sightdistance, 273, fusionName .. ' fixed sight range')
		assertEqual(fusion.objectname, faction.prefix .. '_fusion.s3o', fusionName .. ' inherited model')
		assertEqual(fusion.script, faction.prefix .. '_fusion.cob', fusionName .. ' inherited script')
		assertEqual(fusion.explodeas, 'fusionExplosion', fusionName .. ' inherited explosion')
		assertEqual(fusion.selfdestructas, 'fusionSelfDestruct', fusionName .. ' inherited self-destruct explosion')
		assertEqual(fusion.customparams.family_sentinel, faction.prefix .. '_fusion', fusionName .. ' inherited custom parameter')
		assertTrue(fusion.customparams.i18n_en_tooltip:find(tostring(fusion.energymake), 1, true) ~= nil, fusionName .. ' generated output tooltip')

		assertEqual(converter.footprintx, 6, converterName .. ' footprint X')
		assertEqual(converter.footprintz, 6, converterName .. ' footprint Z')
		assertEqual(converter.metalcost, expectedCost(9000, level), converterName .. ' metal cost')
		assertEqual(converter.energycost, expectedCost(550000, level), converterName .. ' energy cost')
		assertEqual(converter.buildtime, expectedCost(350000, level), converterName .. ' build time')
		assertEqual(converter.customparams.energyconv_capacity, expectedProduction(6000, level), converterName .. ' capacity')
		assertEqual(converter.customparams.energyconv_efficiency, 0.02, converterName .. ' fixed efficiency')
		assertEqual(converter.health, 1500, converterName .. ' fixed health')
		assertEqual(converter.mass, 9000, converterName .. ' fixed mass')
		assertEqual(converter.sightdistance, 273, converterName .. ' fixed sight range')
		assertEqual(converter.collisionvolumescales, '122 107 121', converterName .. ' inherited collision volume')
		assertEqual(converter.objectname, faction.prefix .. '_converter.s3o', converterName .. ' inherited model')
		assertEqual(converter.script, faction.prefix .. '_converter.cob', converterName .. ' inherited script')
		assertEqual(converter.explodeas, 'converterExplosion', converterName .. ' inherited explosion')
		assertEqual(converter.selfdestructas, 'converterSelfDestruct', converterName .. ' inherited self-destruct explosion')
		assertEqual(converter.customparams.family_sentinel, faction.prefix .. '_converter', converterName .. ' inherited custom parameter')
		assertTrue(converter.customparams.i18n_en_tooltip:find(tostring(converter.customparams.energyconv_capacity), 1, true) ~= nil, converterName .. ' generated capacity tooltip')

		assertEqual(nano.footprintx, 6, nanoName .. ' footprint X')
		assertEqual(nano.footprintz, 6, nanoName .. ' footprint Z')
		assertEqual(nano.metalcost, expectedCost(3700, level), nanoName .. ' metal cost')
		assertEqual(nano.energycost, expectedCost(62000, level), nanoName .. ' energy cost')
		assertEqual(nano.buildtime, expectedCost(108000, level), nanoName .. ' build time')
		assertEqual(nano.workertime, expectedProduction(1900, level), nanoName .. ' build power')
		assertEqual(nano.health, 8800, nanoName .. ' fixed health')
		assertEqual(nano.mass, 37200, nanoName .. ' fixed mass')
		assertEqual(nano.sightdistance, 575, nanoName .. ' fixed sight range')
		assertEqual(nano.builddistance, 550, nanoName .. ' fixed build distance')
		assertEqual(nano.collisionvolumescales, '61 128 61', nanoName .. ' fixed collision volume')
		assertEqual(nano.objectname, faction.nanoObject, nanoName .. ' inherited T3 model')
		assertEqual(nano.script, faction.prefix .. '_nano.cob', nanoName .. ' inherited script')
		assertEqual(nano.explodeas, 'nanoExplosion', nanoName .. ' inherited explosion')
		assertEqual(nano.selfdestructas, 'nanoSelfDestruct', nanoName .. ' inherited self-destruct explosion')
		assertEqual(nano.customparams.family_sentinel, faction.prefix .. '_nano', nanoName .. ' inherited custom parameter')
		assertTrue(nano.customparams.i18n_en_tooltip:find(tostring(nano.workertime), 1, true) ~= nil, nanoName .. ' generated buildpower tooltip')

		for _, definition in ipairs({ fusion, converter, nano }) do
			local grid, size, body = parseYardmap(definition.yardmap)
			local expectedSize = definition == fusion and 24 or 12
			local expectedGuardCells = definition == fusion and 64 or 16
			assertEqual(size, expectedSize, definition.name .. ' yardmap size')
			assertTrue(body:match('^[sbo]+$') ~= nil, definition.name .. ' yardmap characters')
			assertRotationallySymmetric(grid, size, definition.name .. ' four-way symmetry')
			assertEqual(countCharacter(body, 's'), expectedGuardCells + (level - 1) * 4, definition.name .. ' stackable cells')
			assertEqual(countCharacter(body, 'o'), 4, definition.name .. ' hard-marker cells')
			if definition ~= fusion then
				assertEqual(countCharacter(body, 'b'), size * size - expectedGuardCells - level * 4, definition.name .. ' build-only cells')
			end
		end

		local fusionGrid, fusionSize = parseYardmap(fusion.yardmap)
		local converterGrid, converterSize = parseYardmap(converter.yardmap)
		local nanoGrid, nanoSize = parseYardmap(nano.yardmap)
		fusionMarkers[hardMarkerKey(fusionGrid, fusionSize)] = true
		converterMarkers[hardMarkerKey(converterGrid, converterSize)] = true
		nanoMarkers[hardMarkerKey(nanoGrid, nanoSize)] = true
	end

	assertEqual(countEntries(fusionMarkers), maxLevel, faction.prefix .. ' unique fusion markers')
	assertEqual(countEntries(converterMarkers), maxLevel, faction.prefix .. ' unique converter markers')
	assertEqual(countEntries(nanoMarkers), maxLevel, faction.prefix .. ' unique nano markers')

	local fusionGrid, fusionSize = parseYardmap(UnitDefs[faction.prefix .. 'evfus1'].yardmap)
	local converterGrid, converterSize = parseYardmap(UnitDefs[faction.prefix .. 'evconv1'].yardmap)
	local nanoGrid, nanoSize = parseYardmap(UnitDefs[faction.prefix .. 'evnano1'].yardmap)
	assertWallSafe(fusionGrid, fusionSize, faction.prefix .. ' fusion wall-safe guard lattice')
	assertWallSafe(converterGrid, converterSize, faction.prefix .. ' converter wall-safe guard lattice')
	assertWallSafe(nanoGrid, nanoSize, faction.prefix .. ' nano wall-safe guard lattice')
	assertDottedGuardBorder(fusionGrid, fusionSize, { 1, 5, 9, 12, 13, 16, 20, 24 }, faction.prefix .. ' fusion dotted guard border')
	assertDottedGuardBorder(converterGrid, converterSize, { 1, 5, 8, 12 }, faction.prefix .. ' converter dotted guard border')
	assertDottedGuardBorder(nanoGrid, nanoSize, { 1, 5, 8, 12 }, faction.prefix .. ' nano dotted guard border')

	local topConverter = UnitDefs[faction.prefix .. 'evconv30']
	local _, topConverterSize, topConverterBody = parseYardmap(topConverter.yardmap)
	assertEqual(topConverterSize, 12, faction.prefix .. ' top converter size')
	assertEqual(countCharacter(topConverterBody, 'b'), 8, faction.prefix .. ' two spare converter orbits')
end

assertEqual(evolvedCount, 270, 'total evolved definitions')
assertSourceDefinitionsUnchanged()

assertEqual(UnitDefs.armevfus15.energymake, 682122, 'level 15 uses the final 25% growth step')
assertEqual(UnitDefs.armevfus16.energymake, 763976, 'level 16 starts the 12% growth phase')
assertEqual(UnitDefs.armevfus30.energymake, 3733635, 'level 30 capped production curve')
assertEqual(UnitDefs.armevfus30.metalcost, 5989788, 'level 30 applies the 87% linear efficiency gain')
assertEqual(UnitDefs.armevconv30.customparams.energyconv_capacity, 746727, 'converter output follows the production curve')
assertEqual(UnitDefs.armevnano30.workertime, 236464, 'nano buildpower follows the production curve')

for level = 1, maxLevel do
	assertEqual(UnitDefs['armevfus' .. level].yardmap, UnitDefs['corevfus' .. level].yardmap, 'fusion factions share yardmaps at level ' .. level)
	assertEqual(UnitDefs['armevfus' .. level].yardmap, UnitDefs['legevfus' .. level].yardmap, 'all fusion factions share yardmaps at level ' .. level)
	assertEqual(UnitDefs['armevconv' .. level].yardmap, UnitDefs['corevconv' .. level].yardmap, 'converter factions share yardmaps at level ' .. level)
	assertEqual(UnitDefs['armevconv' .. level].yardmap, UnitDefs['legevconv' .. level].yardmap, 'all converter factions share yardmaps at level ' .. level)
	assertEqual(UnitDefs['armevnano' .. level].yardmap, UnitDefs['corevnano' .. level].yardmap, 'nano factions share yardmaps at level ' .. level)
	assertEqual(UnitDefs['armevnano' .. level].yardmap, UnitDefs['legevnano' .. level].yardmap, 'all nano factions share yardmaps at level ' .. level)
end

local factionPrefixes = { 'arm', 'cor', 'leg' }
for _, familySuffix in ipairs({ 'evfus', 'evconv', 'evnano' }) do
	for _, lowerPrefix in ipairs(factionPrefixes) do
		for _, higherPrefix in ipairs(factionPrefixes) do
			for lowerLevel = 1, maxLevel do
				local lower = UnitDefs[lowerPrefix .. familySuffix .. lowerLevel].yardmap
				local duplicate = UnitDefs[higherPrefix .. familySuffix .. lowerLevel].yardmap
				assertFalse(canStack(lower, duplicate), familySuffix .. ' rejects cross-faction duplicate level ' .. lowerLevel)
				for higherLevel = lowerLevel + 1, maxLevel do
					local higher = UnitDefs[higherPrefix .. familySuffix .. higherLevel].yardmap
					assertTrue(canStack(lower, higher), familySuffix .. ' permits cross-faction ascending ' .. lowerLevel .. ' -> ' .. higherLevel)
					assertFalse(canStack(higher, lower), familySuffix .. ' rejects descending ' .. higherLevel .. ' -> ' .. lowerLevel)
				end
			end
		end
	end
end

for converterLevel = 1, maxLevel do
	local converter = UnitDefs['armevconv' .. converterLevel].yardmap
	for nanoLevel = 1, maxLevel do
		local nano = UnitDefs['corevnano' .. nanoLevel].yardmap
		assertFalse(canStack(converter, nano), 'nano cannot stack over converter at levels ' .. converterLevel .. '/' .. nanoLevel)
		assertFalse(canStack(nano, converter), 'converter cannot stack over nano at levels ' .. nanoLevel .. '/' .. converterLevel)
	end
end

local expectedOptions = {}
for _, faction in ipairs(factions) do
	for level = 1, maxLevel do
		expectedOptions[#expectedOptions + 1] = faction.prefix .. 'evfus' .. level
		expectedOptions[#expectedOptions + 1] = faction.prefix .. 'evconv' .. level
		expectedOptions[#expectedOptions + 1] = faction.prefix .. 'evnano' .. level
	end
	for _, builderName in ipairs(faction.builders) do
		local counts = {}
		for _, optionName in ipairs(UnitDefs[builderName].buildoptions) do
			counts[optionName] = (counts[optionName] or 0) + 1
		end
		assertEqual(counts.existingoption, 1, builderName .. ' preserves existing build option')
		for level = 1, maxLevel do
			assertEqual(counts[faction.prefix .. 'evfus' .. level], 1, builderName .. ' fusion option ' .. level)
			assertEqual(counts[faction.prefix .. 'evconv' .. level], 1, builderName .. ' converter option ' .. level)
			assertEqual(counts[faction.prefix .. 'evnano' .. level], 1, builderName .. ' nano option ' .. level)
		end
		assertEqual(#UnitDefs[builderName].buildoptions, 91, builderName .. ' option count')
	end
end
assertEqual(#expectedOptions, 270, 'expected generated option count')

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
assertSourceDefinitionsUnchanged()

local completeUnitDefs = UnitDefs
UnitDefs = { armaca = { buildoptions = {} } }
local missingSourcesOk, missingSourcesError = pcall(dofile, tweakPath)
assertTrue(missingSourcesOk, 'missing source definitions are skipped: ' .. tostring(missingSourcesError))
assertEqual(countEntries(UnitDefs), 1, 'missing source run adds no partial definitions')
UnitDefs = completeUnitDefs

print('  [PASS] generated 30 exponential levels for all three factions and families')
print('  [PASS] validated two-phase growth, linear efficiency, cloning, build options, and idempotency')
print('  [PASS] validated high-resolution yardmap geometry and placement compatibility')
print('Passed exponential evolving economy and nano tests.')
