-- Run with: lua tests/boss_killer_planner_test.lua

BOSS_KILLER_PLANNER_TEST = true
local modules = dofile('rmlwidgets/boss_killer_planner/boss_killer_planner.lua')
BOSS_KILLER_PLANNER_TEST = nil

local BossInfoAdapter = modules.BossInfoAdapter
local UnitCatalog = modules.UnitCatalog
local EngagementTracker = modules.EngagementTracker
local ScoringEngine = modules.ScoringEngine
local KnowledgeStore = modules.KnowledgeStore
local helpers = modules._helpers

local function assertEq(actual, expected, message)
	if actual ~= expected then
		error(string.format('%s expected %s got %s', message or 'assertEq', tostring(expected), tostring(actual)))
	end
end

local function assertNear(actual, expected, epsilon, message)
	if math.abs(actual - expected) > epsilon then
		error(string.format('%s expected %.4f got %.4f', message or 'assertNear', expected, actual))
	end
end

local function assertTrue(value, message)
	if value ~= true then
		error(message or 'expected true')
	end
end

local function assertFalse(value, message)
	if value ~= false then
		error(message or 'expected false')
	end
end

print('Running Boss Killer Planner tests...')

do
	local savedG = _G
	local dofileFn = dofile
	_G = nil
	local ok, err = pcall(dofileFn, 'rmlwidgets/boss_killer_planner/boss_killer_planner.lua')
	_G = savedG
	assertTrue(ok, 'nil _G widget load guard: ' .. tostring(err))
	print('  [PASS] nil _G widget load guard')
end

do
	local info = BossInfoAdapter.Normalize(nil, {mode = 'raptor'})
	assertEq(info.mode, 'raptor', 'mode default')
	assertEq(info.bossCount, 0, 'empty boss count')
	assertEq(info.healthPercent, 0, 'empty health percent')

	local decoded = BossInfoAdapter.DecodePveBossInfo('', {decode = function() error('should not decode') end})
	assertEq(type(decoded.resistances), 'table', 'nil-safe resistances')
	local sentinel = BossInfoAdapter.Normalize(nil, {mode = 'scav', healthPercent = -2147483648, anger = 26})
	assertEq(sentinel.healthPercent, 0, 'pre-boss health sentinel clamps to zero')
	assertEq(sentinel.anger, 26, 'valid anger percent remains visible')
	print('  [PASS] pveBossInfo nil-safe defaults')
end

do
	local raw = {
		resistances = {
			['11'] = {percent = 1.2, damage = 1200},
			['12'] = {percent = 0.25, damage = 250},
		},
		statuses = {
			['90'] = {health = 500, maxHealth = 1000},
			['91'] = {health = 0, maxHealth = 1000, isDead = true},
		},
		playerDamages = {['2'] = 333},
	}
	local info = BossInfoAdapter.Normalize(raw, {mode = 'scav'})
	assertNear(info.resistances[11].percent, 0.95, 0.0001, 'resistance cap')
	assertNear(info.resistances[12].percent, 0.25, 0.0001, 'resistance percent')
	assertEq(info.bossCount, 2, 'boss status count')
	assertEq(info.aliveMaxHealth, 1000, 'alive max health')
	assertEq(info.playerDamages[2], 333, 'team damage')
	print('  [PASS] boss info decode and resistance cap')
end

do
	assertNear(ScoringEngine.EffectiveResistance(0.8, true), 0.4, 0.0001, 'stagger halves resistance')
	assertNear(ScoringEngine.EffectiveResistance(0.8, false), 0.8, 0.0001, 'normal resistance')
	assertNear(ScoringEngine.EffectiveResistance(0.8, false, 'scav'), 0.96, 0.0001, 'scav double resistance')
	assertNear(ScoringEngine.EffectiveResistance(0.8, true, 'scav'), 0.88, 0.0001, 'scav staggered double resistance')
	assertNear(ScoringEngine.BossPhaseDamageMultiplier(55), 2, 0.0001, 'high-health phase multiplier')
	assertNear(ScoringEngine.BossPhaseDamageMultiplier(7), 0.5, 0.0001, 'low-health phase multiplier')
	local projected = ScoringEngine.ProjectResistance({percent = 0.2, damage = 200}, 300, 1000, 0.95)
	assertNear(projected, 0.5, 0.0001, 'project resistance')
	print('  [PASS] resistance and stagger math')
end

do
	local rows = {
		{name = 'High Resist', resistancePercent = 0.6},
		{name = 'Low Resist', resistancePercent = 0.1},
	}
	ScoringEngine.SortRows(rows, 'resistancePercent', true)
	assertEq(rows[1].name, 'Low Resist', 'resistance ascending first row')
	assertEq(rows[2].name, 'High Resist', 'resistance ascending second row')

	local namedRows = {
		{name = 'Zeus', sourceLabel = 'Bot Lab'},
		{name = 'Arbiter', sourceLabel = 'Vehicle Lab'},
	}
	ScoringEngine.SortRows(namedRows, 'name', true)
	assertEq(namedRows[1].name, 'Arbiter', 'string sort ascending')
	print('  [PASS] resistance sorting ascending')
end

do
	local first = helpers.paginate(241, 1, 90, 90)
	assertEq(first.startIndex, 1, 'first page start')
	assertEq(first.endIndex, 90, 'first page end')
	assertEq(first.pageCount, 3, 'page count rounds up')
	assertTrue(first.hasNext, 'first page has next')
	assertFalse(first.hasPrev, 'first page has no prev')

	local last = helpers.paginate(241, 99, 90, 90)
	assertEq(last.page, 3, 'page clamps high')
	assertEq(last.startIndex, 181, 'last page start')
	assertEq(last.endIndex, 241, 'last page end')
	assertFalse(last.hasNext, 'last page has no next')

	local empty = helpers.paginate(0, 3, 90, 90)
	assertEq(empty.label, '0 rows', 'empty page label')
	assertEq(empty.startIndex, 1, 'empty start index')
	assertEq(empty.endIndex, 0, 'empty end index')
	print('  [PASS] pagination bounds')
end

do
	local oversized = helpers.clampPanelRect(
		{x = 120, y = 80, width = 2000, height = 1000},
		{width = 800, height = 600},
		620,
		180
	)
	assertEq(oversized.x, 0, 'oversized panel snaps to viewport left')
	assertEq(oversized.y, 80, 'oversized panel keeps reachable y position')
	assertEq(oversized.width, 776, 'oversized panel width falls back below viewport')
	assertEq(oversized.height, 430, 'oversized panel height falls back to default')

	local tinyViewport = helpers.clampPanelRect(
		{x = -40, y = -20, width = 120, height = 90},
		{width = 500, height = 140},
		620,
		180
	)
	assertEq(tinyViewport.x, 0, 'negative panel x clamps into viewport')
	assertEq(tinyViewport.y, 0, 'negative panel y clamps into viewport')
	assertEq(tinyViewport.width, 476, 'viewport width beats preferred minimum')
	assertEq(tinyViewport.height, 116, 'viewport height beats preferred minimum')
	print('  [PASS] panel viewport bounds')
end

do
	assertNear(helpers.clampTableFontScale('not-a-number'), 1, 0.0001, 'invalid table font scale defaults')
	assertNear(helpers.clampTableFontScale(0.2), 0.75, 0.0001, 'table font scale clamps low')
	assertNear(helpers.clampTableFontScale(2), 1.35, 0.0001, 'table font scale clamps high')
	assertEq(helpers.tableFontScaleLabel(0.75), 'T 75%', 'table font label minimum')
	assertEq(helpers.tableFontScaleLabel(1), 'T 100%', 'table font label default')
	assertEq(helpers.tableFontScaleLabel(1.35), 'T 135%', 'table font label maximum')
	assertEq(helpers.tableFontScaleDp(1), '12dp', 'table font dp default')
	print('  [PASS] table font scale helpers')
end

do
	local empty = helpers.presentTeamCell({})
	assertEq(empty.label, '-', 'empty team cell label')
	assertEq(empty.color, '#708698', 'empty team cell color')
	assertTrue(empty.tooltip:find('ready 0', 1, true) ~= nil, 'empty team tooltip includes ready count')

	local active = helpers.presentTeamCell({
		ready = 2,
		alive = 5,
		far = 4,
		building = 1,
		queuedOwn = 3,
		teams = {
			[9] = {teamID = 9, allyTeamID = 1, name = 'Blue', ready = 1, alive = 2, building = 1, far = 1},
		},
	})
	assertEq(active.label, '2/5+1 q3', 'active team cell compact label')
	assertEq(active.color, '#E8F2F8', 'active team cell color')
	assertTrue(active.tooltip:find('own queued 3', 1, true) ~= nil, 'active team tooltip includes queued count')
	assertTrue(active.tooltip:find('Blue | 1/2+1 | far 1', 1, true) ~= nil, 'active team tooltip includes team breakdown')
	print('  [PASS] team cell presentation')
end

do
	local rows = ScoringEngine.BuildRows({
		candidates = {
			[10] = {
				defID = 10,
				displayName = 'History Champ',
				sourceLabel = 'Lab',
				metalCost = 100,
				energyCost = 0,
				estimatedDps = 1,
				mapViable = true,
				reachable = true,
			},
			[11] = {
				defID = 11,
				displayName = 'Alpha Low Estimate',
				sourceLabel = 'Lab',
				metalCost = 100,
				energyCost = 0,
				estimatedDps = 100,
				mapViable = true,
				reachable = true,
			},
			[12] = {
				defID = 12,
				displayName = 'Zulu High Estimate',
				sourceLabel = 'Lab',
				metalCost = 100,
				energyCost = 0,
				estimatedDps = 300,
				mapViable = true,
				reachable = true,
			},
			[13] = {
				defID = 13,
				displayName = 'Aardvark No Damage',
				sourceLabel = 'Lab',
				metalCost = 100,
				energyCost = 0,
				estimatedDps = 0,
				mapViable = true,
				reachable = true,
			},
		},
		bossInfo = {resistances = {}, healthPercent = 100, resistanceCap = 0.95, mode = 'scav'},
		countsByDef = {},
		samplesByDef = {},
		knowledgeByDef = {[10] = {averageScore = 10, samples = 3}},
		energyPerMetal = 70,
		costMode = 'build',
	})
	ScoringEngine.SortRows(rows, 'preBossSortScore', false)
	assertEq(rows[1].name, 'History Champ', 'history score beats static estimate')
	assertEq(rows[1].preBossSortSource, 'hist', 'history pre-boss source')
	assertEq(rows[2].name, 'Zulu High Estimate', 'estimated dps per cost beats alphabetic order')
	assertNear(rows[2].preBossSortScore, 3, 0.0001, 'estimated pre-boss score')
	assertEq(rows[2].preBossSortSource, 'est', 'estimated pre-boss source')
	assertEq(rows[#rows].name, 'Aardvark No Damage', 'no dps estimate falls to bottom')
	assertEq(rows[#rows].preBossSortSource, '', 'empty pre-boss source for no evidence')
	local zeroRows = {
		{name = 'Alpha Expensive', preBossSortScore = 0, estimatedDps = 0, scoreCostMetalEq = 5000},
		{name = 'Zulu Cheap', preBossSortScore = 0, estimatedDps = 0, scoreCostMetalEq = 100},
	}
	ScoringEngine.SortRows(zeroRows, 'preBossSortScore', false)
	assertEq(zeroRows[1].name, 'Zulu Cheap', 'zero pre-boss scores prefer cheaper rows over alphabetic order')
	print('  [PASS] pre-boss sort score fallback')
end

do
	local unitDefs = {
		[1] = {
			id = 1,
			name = 'armcom',
			translatedHumanName = 'Commander',
			buildOptions = {2, 3},
			isBuilder = true,
			metalCost = 1000,
			energyCost = 1000,
		},
		[2] = {
			id = 2,
			name = 'bioprinter',
			translatedHumanName = 'BioPrinter',
			buildoptions = {[21] = 'grenadier'},
			isBuilder = true,
			metalCost = 12000,
			energyCost = 170000,
			weapons = {},
		},
		[3] = {
			id = 3,
			name = 'shipyard',
			translatedHumanName = 'Shipyard',
			buildOptions = {5},
			isBuilder = true,
			metalCost = 800,
			energyCost = 2000,
		},
		[4] = {
			id = 4,
			name = 'grenadier',
			translatedHumanName = 'Grenadier Beetle',
			metalCost = 1800,
			energyCost = 33500,
			buildTime = 19000,
			weapons = {{damage = {default = 700}, reloadtime = 2, range = 1200}},
		},
		[5] = {
			id = 5,
			name = 'subkiller',
			translatedHumanName = 'Sub Killer',
			minWaterDepth = 20,
			metalCost = 500,
			energyCost = 5000,
			weapons = {{damage = {default = 100}, reloadtime = 1, range = 500}},
		},
		[6] = {
			id = 6,
			name = 'unbuilt',
			translatedHumanName = 'Unbuilt Gun',
			metalCost = 500,
			energyCost = 1000,
			weapons = {{damage = {default = 100}, reloadtime = 1}},
		},
		[7] = {
			id = 7,
			name = 'raptor_healer',
			translatedHumanName = 'Healer',
			buildOptions = {8},
			isBuilder = true,
			metalCost = 400,
			energyCost = 1000,
		},
		[8] = {
			id = 8,
			name = 'acid_tentacle',
			translatedHumanName = 'Acid Tentacle',
			metalCost = 500,
			energyCost = 1000,
			weapons = {{damage = {default = 100}, reloadtime = 1}},
		},
	}
	local catalog = UnitCatalog.Build({
		unitDefs = unitDefs,
		unitDefNames = {grenadier = {id = 4}},
		resistanceMap = {[4] = {percent = 0.1}},
		hasMeaningfulWater = false,
		ownedSourceDefIDs = {[4] = true},
	})

	assertTrue(catalog.candidates[4].reachable, 'grenadier reachable')
	assertEq(catalog.candidates[4].sourceLabel, 'Commander > BioPrinter', 'source chain')
	assertFalse(catalog.candidates[5].mapViable, 'sea unit hidden on dry map')
	assertEq(UnitCatalog.ApplyAvailability(catalog.candidates, 'owned')[4].name, 'grenadier', 'owned filter keeps owned source')
	assertEq(UnitCatalog.ApplyAvailability(catalog.candidates, 'match')[6], nil, 'match filter drops unreachable')
	assertEq(UnitCatalog.ApplyAvailability(catalog.candidates, 'all')[6].name, 'unbuilt', 'all filter keeps unreachable')
	local tracker = EngagementTracker.New()
	EngagementTracker.UpdateUnit(tracker, 100, 1, 1, true, 1)
	EngagementTracker.UpdateUnit(tracker, 101, 7, 2, true, 1)
	EngagementTracker.UpdateUnit(tracker, 102, 2, 1, false, 0.5)
	local ownedSourceDefIDs = EngagementTracker.OwnedSourceDefIDs(tracker, {
		unitDefs = unitDefs,
		unitDefNames = {grenadier = {id = 4}},
		sourceTeamID = 1,
	})
	assertTrue(ownedSourceDefIDs[2], 'owned source includes direct build option')
	assertTrue(ownedSourceDefIDs[4], 'owned source helper traverses sparse string buildoptions')
	assertEq(ownedSourceDefIDs[8], nil, 'owned source excludes other team build trees')
	local enemySourceDefIDs = EngagementTracker.OwnedSourceDefIDs(tracker, {
		unitDefs = unitDefs,
		unitDefNames = {grenadier = {id = 4}},
		sourceTeamID = 2,
	})
	assertTrue(enemySourceDefIDs[8], 'owned source can traverse selected raptor team when selected')
	local _, _, ownedSources = EngagementTracker.BuildCounts(tracker, {
		unitDefs = unitDefs,
		unitDefNames = {grenadier = {id = 4}},
		candidateMap = {},
		sourceTeamID = 1,
	})
	assertTrue(ownedSources[4], 'build counts owned source uses transitive selected-team closure')
	assertEq(ownedSources[8], nil, 'build counts owned source excludes non-selected team closure')
	local selectedCatalog = UnitCatalog.Build({
		unitDefs = unitDefs,
		unitDefNames = {grenadier = {id = 4}},
		resistanceMap = {[4] = {percent = 0.1}, [8] = {percent = 0.1}},
		hasMeaningfulWater = true,
		ownedSourceDefIDs = ownedSourceDefIDs,
	})
	local buildable = UnitCatalog.ApplyAvailability(selectedCatalog.candidates, 'owned')
	assertEq(buildable[4].name, 'grenadier', 'buildable filter keeps selected team closure')
	assertEq(buildable[8], nil, 'buildable filter drops other team raptor closure')
	print('  [PASS] build-source graph and availability filters')
end

do
	local runtimeWeaponUnit = {
		weapons = {{weaponDef = 12}},
	}
	local runtimeWeaponDefs = {
		[12] = {
			reloadtime = 2,
			damages = {default = 600},
			energypershot = 1200,
		},
	}
	assertNear(UnitCatalog.EstimateDps(runtimeWeaponUnit, runtimeWeaponDefs), 300, 0.0001, 'runtime WeaponDefs.damages DPS estimate')
	assertNear(UnitCatalog.EstimateOperatingCost(runtimeWeaponUnit, runtimeWeaponDefs).fireEnergyPerSecond, 600, 0.0001, 'runtime WeaponDefs.damages operating cost')

	local disintegrator = {
		weapondefs = {
			disintegratorxl = {
				reloadtime = 1.5,
				energypershot = 150000,
				damage = {default = 12000},
			},
		},
		weapons = {{def = 'disintegratorxl'}},
	}
	local operating = UnitCatalog.EstimateOperatingCost(disintegrator, {})
	assertNear(operating.fireEnergyPerSecond, 100000, 0.0001, 'energy per shot operating cost')
	assertNear(operating.energyPerSecond, 100000, 0.0001, 'total energy operating cost')

	local launcher = {
		weapondefs = {
			launcher = {
				stockpiletime = 8,
				stockpilelimit = 50,
				burst = 2,
				metalpershot = 13000,
				energypershot = 180000,
				damage = {default = 30000},
			},
		},
	}
	local stockpileOperating = UnitCatalog.EstimateOperatingCost(launcher, {})
	assertNear(stockpileOperating.fireMetalPerSecond, 3250, 0.0001, 'stockpile metal per second')
	assertNear(stockpileOperating.fireEnergyPerSecond, 45000, 0.0001, 'stockpile energy per second')
	print('  [PASS] weapon operating cost estimation')
end

do
	local candidate = {
		defID = 4,
		name = 'grenadier',
		displayName = 'Grenadier Beetle',
		icon = '#4',
		sourceLabel = 'BioPrinter',
		metalCost = 1800,
		energyCost = 35000,
		buildTime = 20000,
		estimatedDps = 350,
		operatingMetalPerSecond = 0,
		operatingEnergyPerSecond = 70000,
		mapViable = true,
		reachable = true,
	}
	local rows = ScoringEngine.BuildRows({
		candidates = {[4] = candidate},
		bossInfo = {
			resistances = {[4] = {percent = 0.25, damage = 250}},
			aliveMaxHealth = 1000,
			healthPercent = 40,
			resistanceCap = 0.95,
			staggerActive = false,
			mode = 'raptor',
		},
		countsByDef = {[4] = {alive = 2, ready = 1, far = 1, building = 1, queuedOwn = 3, teams = {}}},
		samplesByDef = {[4] = 500},
		energyPerMetal = 70,
		costMode = 'build',
	})
	local fullRows = ScoringEngine.BuildRows({
		candidates = {[4] = candidate},
		bossInfo = {
			resistances = {[4] = {percent = 0.25, damage = 250}},
			aliveMaxHealth = 1000,
			healthPercent = 40,
			resistanceCap = 0.95,
			staggerActive = false,
			mode = 'raptor',
		},
		countsByDef = {[4] = {alive = 2, ready = 1, far = 1, building = 1, queuedOwn = 3, teams = {}}},
		samplesByDef = {[4] = 500},
		energyPerMetal = 70,
		costMode = 'full',
	})
	local normalizedRows = ScoringEngine.BuildRows({
		candidates = {[4] = candidate},
		bossInfo = {
			resistances = {[4] = {percent = 0.25, damage = 250}},
			aliveMaxHealth = 1000,
			healthPercent = 40,
			resistanceCap = 0.95,
			staggerActive = false,
			mode = 'raptor',
		},
		countsByDef = {[4] = {alive = 2, ready = 1, far = 1, building = 1, queuedOwn = 3, teams = {}}},
		samplesByDef = {[4] = 300},
		energyPerMetal = 70,
		costMode = 'build',
		sampleWindowSeconds = 3,
	})
	assertEq(#rows, 1, 'one score row')
	assertNear(rows[1].metalEq, 2300, 0.0001, 'metal equivalent')
	assertNear(fullRows[1].operatingMetalEqPerSecond, 1000, 0.0001, 'operating metal-equivalent per second')
	assertNear(fullRows[1].scoreCostMetalEq, 32300, 0.0001, 'full score cost includes operating window')
	assertNear(normalizedRows[1].liveContributionPerMetalEq, 3000 / 2300, 0.0001, 'live sample normalizes to score window')
	assertTrue(fullRows[1].marginalDamagePerMetalEq < rows[1].marginalDamagePerMetalEq, 'full cost deflates expensive weapon score')
	assertTrue(rows[1].marginalDamagePerMetalEq > 0, 'positive marginal score')
	assertEq(rows[1].confidence, 'high', 'live sample confidence')
	print('  [PASS] metal-equivalent scoring')
end

do
	local store = KnowledgeStore.New()
	KnowledgeStore.Merge(store, 'raptor', 'epic', {name = 'grenadier'}, {
		score = 10,
		costMode = 'build',
		energyPerMetal = 70,
		scoreWindowSeconds = 30,
	})
	KnowledgeStore.Merge(store, 'raptor', 'epic', {name = 'grenadier'}, {
		score = 20,
		costMode = 'full',
		energyPerMetal = 60,
		scoreWindowSeconds = 30,
	})
	KnowledgeStore.Merge(store, 'scav', 'epic', {name = 'grenadier'}, {
		score = 99,
		costMode = 'full',
		energyPerMetal = 70,
		scoreWindowSeconds = 30,
	})
	local row = store.rows[KnowledgeStore.Key('raptor', 'epic', 'grenadier')]
	local scavRow = store.rows[KnowledgeStore.Key('scav', 'epic', 'grenadier')]
	assertEq(row.samples, 2, 'knowledge samples')
	assertNear(row.averageScore, 15, 0.0001, 'knowledge average')
	assertEq(scavRow.samples, 1, 'scav knowledge separate samples')
	assertNear(scavRow.averageScore, 99, 0.0001, 'scav knowledge separate average')
	assertEq(row.schemaVersion, 2, 'knowledge schema version')
	assertEq(row.costMode, 'full', 'knowledge stores latest cost mode')
	local rows = KnowledgeStore.Rows(store)
	assertEq(#rows, 2, 'knowledge rows export count')
	assertEq(rows[1].unitName, 'grenadier', 'knowledge rows unit name')
	print('  [PASS] knowledge store merge')
end

print('\n=== All Boss Killer Planner tests passed! ===')
