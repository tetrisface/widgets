local WIDGET_NAME = 'Boss Killer Planner'
local MODEL_NAME = 'boss_killer_planner'
local RML_PATH = 'luaui/rmlwidgets/boss_killer_planner/boss_killer_planner.rml'
local BOSS_INFO_FREQUENCY = 90
local QUEUE_SCAN_FREQUENCY = 300
local RML_UPDATE_FREQUENCY = 90
local DEFAULT_ENERGY_PER_METAL = 70
local SCORE_WINDOW_SECONDS = 30
local GAME_FRAMES_PER_SECOND = 30
local KNOWLEDGE_PATH = 'LuaUI/Config/boss_killer_planner_stats.lua'
local KNOWLEDGE_SCHEMA_VERSION = 2
local MAX_KNOWLEDGE_ROWS = 256
local RANKED_ROW_LIMIT = 90
local PANEL_DEFAULT_WIDTH = 820
local PANEL_DEFAULT_HEIGHT = 430
local PANEL_MIN_WIDTH = 620
local PANEL_MIN_HEIGHT = 180
local PANEL_VIEWPORT_MARGIN = 24
local TABLE_FONT_BASE_DP = 12
local TABLE_FONT_DEFAULT_SCALE = 1
local TABLE_FONT_MIN_SCALE = 0.75
local TABLE_FONT_MAX_SCALE = 1.35
local STATUS_NONE_COLOR = '#C86A5A'
local STATUS_BUILDING_COLOR = '#F4C96D'
local STATUS_DONE_COLOR = '#7ED47E'

--------------------------------------------------------------------------------
-- Pure helpers
--------------------------------------------------------------------------------

local function clamp(value, minValue, maxValue)
	if value < minValue then
		return minValue
	end
	if value > maxValue then
		return maxValue
	end
	return value
end

local function safeNumber(value, fallback)
	value = tonumber(value)
	if not value or value ~= value or value == math.huge or value == -math.huge then
		return fallback or 0
	end
	return value
end

local function safePercent(value, fallback)
	return clamp(safeNumber(value, fallback or 0), 0, 100)
end

local function safeDivide(numerator, denominator)
	denominator = safeNumber(denominator, 0)
	if denominator <= 0 then
		return 0
	end
	return safeNumber(numerator, 0) / denominator
end

local function round(value)
	return math.floor((value or 0) + 0.5)
end

local function formatSI(value)
	value = safeNumber(value, 0)
	local absValue = math.abs(value)
	if absValue >= 1000000000 then
		return string.format('%.1fG', value / 1000000000)
	end
	if absValue >= 1000000 then
		return string.format('%.1fM', value / 1000000)
	end
	if absValue >= 1000 then
		return string.format('%.1fk', value / 1000)
	end
	if absValue >= 10 then
		return string.format('%.0f', value)
	end
	if absValue > 0 then
		return string.format('%.2f', value)
	end
	return '0'
end

local function paginate(totalRows, requestedPage, pageSize, defaultPageSize)
	totalRows = math.max(0, safeNumber(totalRows, 0))
	pageSize = math.max(1, safeNumber(pageSize, defaultPageSize or 1))
	local pageCount = math.max(1, math.ceil(totalRows / pageSize))
	local page = clamp(math.floor(safeNumber(requestedPage, 1)), 1, pageCount)
	if totalRows <= 0 then
		return {
			startIndex = 1,
			endIndex = 0,
			page = 1,
			pageCount = pageCount,
			label = '0 rows',
			hasPrev = false,
			hasNext = false,
		}
	end

	local startIndex = (page - 1) * pageSize + 1
	local endIndex = math.min(totalRows, startIndex + pageSize - 1)
	return {
		startIndex = startIndex,
		endIndex = endIndex,
		page = page,
		pageCount = pageCount,
		label = string.format('%d-%d / %d', startIndex, endIndex, totalRows),
		hasPrev = page > 1,
		hasNext = page < pageCount,
	}
end

local function clampPanelRect(rect, viewport, minWidth, minHeight)
	rect = rect or {}
	viewport = viewport or {}
	local viewWidth = safeNumber(viewport.width, 0)
	local viewHeight = safeNumber(viewport.height, 0)
	local preferredMinWidth = math.max(1, safeNumber(minWidth, PANEL_MIN_WIDTH))
	local preferredMinHeight = math.max(1, safeNumber(minHeight, PANEL_MIN_HEIGHT))
	local widthMargin = viewWidth > 0 and math.min(PANEL_VIEWPORT_MARGIN, math.max(0, viewWidth - 1)) or 0
	local heightMargin = viewHeight > 0 and math.min(PANEL_VIEWPORT_MARGIN, math.max(0, viewHeight - 1)) or 0
	local maxWidth = viewWidth > 0 and math.max(1, viewWidth - widthMargin) or math.max(preferredMinWidth, safeNumber(rect.width, preferredMinWidth))
	local maxHeight = viewHeight > 0 and math.max(1, viewHeight - heightMargin) or math.max(preferredMinHeight, safeNumber(rect.height, preferredMinHeight))
	local effectiveMinWidth = viewWidth > 0 and math.min(preferredMinWidth, maxWidth) or preferredMinWidth
	local effectiveMinHeight = viewHeight > 0 and math.min(preferredMinHeight, maxHeight) or preferredMinHeight
	local fallbackWidth = math.min(PANEL_DEFAULT_WIDTH, maxWidth)
	local fallbackHeight = math.min(PANEL_DEFAULT_HEIGHT, maxHeight)
	local requestedWidth = safeNumber(rect.width, fallbackWidth)
	local requestedHeight = safeNumber(rect.height, fallbackHeight)
	local width = requestedWidth > maxWidth and fallbackWidth or clamp(requestedWidth, effectiveMinWidth, maxWidth)
	local height = requestedHeight > maxHeight and fallbackHeight or clamp(requestedHeight, effectiveMinHeight, maxHeight)
	local maxX = viewWidth > 0 and math.max(0, viewWidth - width - widthMargin) or safeNumber(rect.x, 0)
	local maxY = viewHeight > 0 and math.max(0, viewHeight - height - heightMargin) or safeNumber(rect.y, 0)

	return {
		x = math.floor(viewWidth > 0 and clamp(safeNumber(rect.x, 0), 0, maxX) or safeNumber(rect.x, 0)),
		y = math.floor(viewHeight > 0 and clamp(safeNumber(rect.y, 0), 0, maxY) or safeNumber(rect.y, 0)),
		width = math.floor(width),
		height = math.floor(height),
	}
end

local function tableSize(tbl)
	local count = 0
	for _ in pairs(tbl or {}) do
		count = count + 1
	end
	return count
end

local function shallowCopy(tbl)
	local copy = {}
	for key, value in pairs(tbl or {}) do
		copy[key] = value
	end
	return copy
end

local function sortedValues(map, compare)
	local values = {}
	for _, value in pairs(map or {}) do
		values[#values + 1] = value
	end
	table.sort(values, compare)
	return values
end

local function clampTableFontScale(value)
	return math.floor(clamp(safeNumber(value, TABLE_FONT_DEFAULT_SCALE), TABLE_FONT_MIN_SCALE, TABLE_FONT_MAX_SCALE) * 100 + 0.5) / 100
end

local function tableFontScaleLabel(scale)
	return string.format('T %.0f%%', clampTableFontScale(scale) * 100)
end

local function tableFontScaleDp(scale)
	return tostring(round(TABLE_FONT_BASE_DP * clampTableFontScale(scale))) .. 'dp'
end

local function presentTeamCell(counts)
	counts = counts or {}
	local alive = safeNumber(counts.alive, 0)
	local building = safeNumber(counts.building, 0)
	local queuedOwn = safeNumber(counts.queuedOwn, 0)
	local tooltip = {
		string.format('Allyteam total | alive %d | building %d | own queued %d', alive, building, queuedOwn),
	}

	if alive + building + queuedOwn <= 0 then
		return {
			label = '',
			color = STATUS_NONE_COLOR,
			tooltip = tooltip[1],
		}
	end

	local label = tostring(alive)
	if building > 0 then
		label = label .. '+' .. tostring(building)
	end
	if queuedOwn > 0 then
		label = label .. ' q' .. tostring(queuedOwn)
	end

	local teamCounts = sortedValues(counts.teams or {}, function(a, b)
		if (a.allyTeamID or 0) == (b.allyTeamID or 0) then
			return (a.teamID or 0) < (b.teamID or 0)
		end
		return (a.allyTeamID or 0) < (b.allyTeamID or 0)
	end)
	for _, row in ipairs(teamCounts) do
		local teamAlive = safeNumber(row.alive, 0)
		local teamBuilding = safeNumber(row.building, 0)
		local teamLabel = tostring(teamAlive)
		if teamBuilding > 0 then
			teamLabel = teamLabel .. '+' .. tostring(teamBuilding)
		end
		tooltip[#tooltip + 1] = (row.name or ('Team ' .. tostring(row.teamID or '?'))) .. ' | ' .. teamLabel
	end

	return {
		label = label,
		color = alive > 0 and STATUS_DONE_COLOR or STATUS_BUILDING_COLOR,
		tooltip = table.concat(tooltip, '\n'),
	}
end

local function getUnitDefField(unitDef, camelName, lowerName, fallback)
	if not unitDef then
		return fallback
	end
	local value = unitDef[camelName]
	if value == nil and lowerName then
		value = unitDef[lowerName]
	end
	return value == nil and fallback or value
end

local function unitDisplayName(unitDef)
	if not unitDef then
		return 'Unknown'
	end
	return unitDef.translatedHumanName or unitDef.humanName or unitDef.name or unitDef.unitname or 'Unknown'
end

--------------------------------------------------------------------------------
-- BossInfoAdapter
--------------------------------------------------------------------------------

local BossInfoAdapter = {}

function BossInfoAdapter.DecodePveBossInfo(raw, json)
	if type(raw) == 'table' then
		return raw
	end
	if not raw or raw == '' or not json or not json.decode then
		return {resistances = {}, statuses = {}, playerDamages = {}}
	end

	local ok, decoded = pcall(json.decode, raw)
	if not ok or type(decoded) ~= 'table' then
		return {resistances = {}, statuses = {}, playerDamages = {}}
	end

	decoded.resistances = decoded.resistances or {}
	decoded.statuses = decoded.statuses or {}
	decoded.playerDamages = decoded.playerDamages or {}
	return decoded
end

function BossInfoAdapter.Normalize(rawInfo, options)
	options = options or {}
	rawInfo = rawInfo or {}

	local mode = options.mode or 'unknown'
	local cap = 0.95
	if options.resistanceCap then
		cap = options.resistanceCap
	end

	local resistances = {}
	for defID, resistance in pairs(rawInfo.resistances or {}) do
		local numericDefID = tonumber(defID)
		if numericDefID then
			local percent = clamp(safeNumber(resistance.percent, 0), 0, cap)
			resistances[numericDefID] = {
				defID = numericDefID,
				percent = percent,
				damage = safeNumber(resistance.damage, 0),
			}
		end
	end

	local statuses = {}
	local totalHealth = 0
	local totalMaxHealth = 0
	local aliveMaxHealth = 0
	local aliveBossIDs = {}
	for unitID, status in pairs(rawInfo.statuses or {}) do
		local numericUnitID = tonumber(unitID)
		local health = safeNumber(status.health, 0)
		local maxHealth = safeNumber(status.maxHealth, 0)
		local isDead = status.isDead == true or health <= 0
		statuses[numericUnitID or unitID] = {
			unitID = numericUnitID or unitID,
			health = health,
			maxHealth = maxHealth,
			isDead = isDead,
		}
		totalHealth = totalHealth + health
		totalMaxHealth = totalMaxHealth + maxHealth
		if not isDead then
			aliveMaxHealth = aliveMaxHealth + maxHealth
			if numericUnitID then
				aliveBossIDs[#aliveBossIDs + 1] = numericUnitID
			end
		end
	end

	local playerDamages = {}
	for teamID, damage in pairs(rawInfo.playerDamages or {}) do
		playerDamages[tonumber(teamID) or teamID] = safeNumber(damage, 0)
	end

	return {
		mode = mode,
		difficulty = options.difficulty or 'unknown',
		resistanceCap = cap,
		resistances = resistances,
		statuses = statuses,
		playerDamages = playerDamages,
		bossCount = tableSize(statuses),
		aliveBossIDs = aliveBossIDs,
		aliveMaxHealth = aliveMaxHealth,
		totalHealth = totalHealth,
		totalMaxHealth = totalMaxHealth,
		healthPercent = totalMaxHealth > 0 and safePercent(totalHealth / totalMaxHealth * 100, 0) or safePercent(options.healthPercent, 0),
		anger = safePercent(options.anger, 0),
		staggerActive = options.staggerActive == true or options.staggerActive == 1,
		staggerPercent = safePercent(options.staggerPercent, 0),
	}
end

function BossInfoAdapter.ReadFromSpring(api)
	local spring = api.Spring
	local json = api.Json
	local isRaptors = api.isRaptors
	local isScavengers = api.isScavengers
	local modOptions = api.modOptions or {}

	local mode = 'unknown'
	if isRaptors then
		mode = 'raptor'
	elseif isScavengers then
		mode = 'scav'
	end

	local rawInfo = BossInfoAdapter.DecodePveBossInfo(spring.GetGameRulesParam('pveBossInfo'), json)
	local options = {
		mode = mode,
		difficulty = isRaptors and modOptions.raptor_difficulty or modOptions.scav_difficulty,
		anger = isRaptors and spring.GetGameRulesParam('raptorQueenAnger') or spring.GetGameRulesParam('scavBossAnger'),
		healthPercent = isRaptors and spring.GetGameRulesParam('raptorQueenHealth') or spring.GetGameRulesParam('scavBossHealth'),
		staggerActive = isRaptors and spring.GetGameRulesParam('raptorQueenStaggerActive') or spring.GetGameRulesParam('scavBossStaggerActive'),
		staggerPercent = isRaptors and spring.GetGameRulesParam('raptorQueenStaggerPercentage') or spring.GetGameRulesParam('scavBossStaggerPercentage'),
	}
	return BossInfoAdapter.Normalize(rawInfo, options)
end

--------------------------------------------------------------------------------
-- UnitCatalog
--------------------------------------------------------------------------------

local UnitCatalog = {}

local function normalizeBuildOption(buildOption, unitDefNames)
	if type(buildOption) == 'number' then
		return buildOption
	end
	if type(buildOption) == 'string' and unitDefNames and unitDefNames[buildOption] then
		return unitDefNames[buildOption].id
	end
	return nil
end

local function unitHasWeapon(unitDef)
	if not unitDef then
		return false
	end
	local weapons = unitDef.weapons
	return type(weapons) == 'table' and #weapons > 0
end

local function getWeaponRange(unitDef, weaponDefs)
	local maxRange = 0
	for _, weapon in ipairs(unitDef.weapons or {}) do
		local range = safeNumber(weapon.range, 0)
		if range <= 0 and weapon.weaponDef and weaponDefs and weaponDefs[weapon.weaponDef] then
			range = safeNumber(weaponDefs[weapon.weaponDef].range, 0)
		end
		if range > maxRange then
			maxRange = range
		end
	end

	return maxRange
end

-- Runtime WeaponDefs[id].damages is indexed by armor type ID (0 = default);
-- armorTypeIndex selects the boss armor class when known. Paralyzer damages
-- are stun values and bogus weapons are targeting dummies; neither hurts a boss
local function weaponDamageVsArmor(weaponDef, armorTypeIndex)
	if not weaponDef or weaponDef.paralyzer then
		return 0
	end
	local customParams = weaponDef.customParams or weaponDef.customparams
	if customParams and customParams.bogus then
		return 0
	end
	local damages = weaponDef.damages
	if type(damages) ~= 'table' then
		return safeNumber(damages, 0)
	end
	local damage
	if armorTypeIndex ~= nil then
		damage = damages[armorTypeIndex]
	end
	if damage == nil then
		damage = damages[0]
	end
	return safeNumber(damage, 0)
end

local function resolveWeaponDef(weapon, weaponDefs)
	if not weapon then
		return nil
	end
	if weapon.weaponDef and weaponDefs and weaponDefs[weapon.weaponDef] then
		return weaponDefs[weapon.weaponDef]
	end
	return weapon
end

local function weaponCycleSeconds(weaponDef)
	if not weaponDef then
		return 1
	end
	local customParams = weaponDef.customParams or weaponDef.customparams or {}
	local camelStockpileTime = safeNumber(weaponDef.stockpileTime, 0)
	local lowerStockpileTime = safeNumber(weaponDef.stockpiletime, 0)
	local hasStockpileLimit = safeNumber(weaponDef.stockpilelimit, 0) > 0 or safeNumber(customParams.stockpilelimit, 0) > 0
	local stockpile = weaponDef.stockpile == true
		or weaponDef.stockpile == 1
		or (camelStockpileTime > 0 and hasStockpileLimit)
		or (lowerStockpileTime > 0 and hasStockpileLimit)
	if stockpile then
		if camelStockpileTime > 0 then
			return math.max(0.1, camelStockpileTime / 30)
		end
		if lowerStockpileTime > 0 then
			return math.max(0.1, lowerStockpileTime)
		end
	end

	local reload = safeNumber(weaponDef.reload, 0)
	if reload <= 0 then
		reload = safeNumber(weaponDef.reloadTime, 0)
	end
	if reload <= 0 then
		reload = safeNumber(weaponDef.reloadtime, 1)
	end
	return math.max(0.1, reload)
end

local function weaponShotCost(weaponDef)
	if not weaponDef then
		return 0, 0
	end
	local customParams = weaponDef.customParams or weaponDef.customparams or {}
	local metal = safeNumber(weaponDef.metalCost, 0)
	if metal <= 0 then
		metal = safeNumber(weaponDef.metalcost, 0)
	end
	if metal <= 0 then
		metal = safeNumber(weaponDef.metalPerShot, 0)
	end
	if metal <= 0 then
		metal = safeNumber(weaponDef.metalpershot, 0)
	end
	metal = math.max(metal, safeNumber(customParams.stockpilemetal, 0), safeNumber(customParams.metalperstockpile, 0))

	local energy = safeNumber(weaponDef.energyCost, 0)
	if energy <= 0 then
		energy = safeNumber(weaponDef.energycost, 0)
	end
	if energy <= 0 then
		energy = safeNumber(weaponDef.energyPerShot, 0)
	end
	if energy <= 0 then
		energy = safeNumber(weaponDef.energypershot, 0)
	end
	energy = math.max(energy, safeNumber(customParams.stockpileenergy, 0), safeNumber(customParams.energyperstockpile, 0))

	return metal, energy
end

local function weaponShotsPerCycle(weaponDef)
	return math.max(1, safeNumber(weaponDef.salvoSize, 1)) * math.max(1, safeNumber(weaponDef.projectiles, 1))
end

-- Engine kamikaze units set canKamikaze; BAR crawling bombs instead mark
-- customparams.instantselfd and detonate via self-destruct through a gadget
local function isSuicideUnit(unitDef)
	if unitDef.canKamikaze then
		return true
	end
	local customParams = unitDef.customParams or unitDef.customparams or {}
	local instantSelfD = customParams.instantselfd
	return instantSelfD ~= nil and instantSelfD ~= false and instantSelfD ~= 'false' and instantSelfD ~= '0'
end

function UnitCatalog.EstimateDps(unitDef, weaponDefs, armorTypeIndex, weaponDefNames)
	if not unitDef then
		return 0
	end

	-- Suicide units deliver one blast and die: price the self-destruct
	-- explosion (or best real weapon) once per score window
	if isSuicideUnit(unitDef) then
		local blast = 0
		local blastDef = weaponDefNames and unitDef.selfDExplosion and weaponDefNames[unitDef.selfDExplosion]
		if blastDef then
			blast = weaponDamageVsArmor(blastDef, armorTypeIndex)
		end
		for _, weapon in ipairs(unitDef.weapons or {}) do
			local damage = weaponDamageVsArmor(resolveWeaponDef(weapon, weaponDefs), armorTypeIndex)
			if damage > blast then
				blast = damage
			end
		end
		return blast / SCORE_WINDOW_SECONDS
	end

	local total = 0
	for _, weapon in ipairs(unitDef.weapons or {}) do
		local weaponDef = resolveWeaponDef(weapon, weaponDefs)
		local reload = weaponCycleSeconds(weaponDef)
		total = total + (weaponDamageVsArmor(weaponDef, armorTypeIndex) * weaponShotsPerCycle(weaponDef) / math.max(0.1, reload))
	end

	return total
end

local function addWeaponOperatingCost(totals, weaponDef, armorTypeIndex)
	if not weaponDef or weaponDamageVsArmor(weaponDef, armorTypeIndex) <= 0 then
		return
	end
	local metal, energy = weaponShotCost(weaponDef)
	if metal <= 0 and energy <= 0 then
		return
	end
	-- Firing cost is charged once per salvo/stockpile cycle, not per projectile
	local cycleSeconds = weaponCycleSeconds(weaponDef)
	totals.fireMetalPerSecond = totals.fireMetalPerSecond + metal / cycleSeconds
	totals.fireEnergyPerSecond = totals.fireEnergyPerSecond + energy / cycleSeconds
end

function UnitCatalog.EstimateOperatingCost(unitDef, weaponDefs, armorTypeIndex)
	if not unitDef then
		return {
			fireMetalPerSecond = 0,
			fireEnergyPerSecond = 0,
			upkeepMetalPerSecond = 0,
			upkeepEnergyPerSecond = 0,
			metalPerSecond = 0,
			energyPerSecond = 0,
		}
	end

	local totals = {
		fireMetalPerSecond = 0,
		fireEnergyPerSecond = 0,
		upkeepMetalPerSecond = safeNumber(getUnitDefField(unitDef, 'metalUpkeep', 'metalupkeep', 0), 0),
		upkeepEnergyPerSecond = safeNumber(getUnitDefField(unitDef, 'energyUpkeep', 'energyupkeep', 0), 0),
	}
	totals.upkeepMetalPerSecond = totals.upkeepMetalPerSecond + safeNumber(getUnitDefField(unitDef, 'metalUse', 'metaluse', 0), 0)
	totals.upkeepEnergyPerSecond = totals.upkeepEnergyPerSecond + safeNumber(getUnitDefField(unitDef, 'energyUse', 'energyuse', 0), 0)

	-- Suicide units pay no per-shot costs; their cost is the unit itself
	if not isSuicideUnit(unitDef) then
		for _, weapon in ipairs(unitDef.weapons or {}) do
			addWeaponOperatingCost(totals, resolveWeaponDef(weapon, weaponDefs), armorTypeIndex)
		end
	end

	totals.metalPerSecond = totals.fireMetalPerSecond + totals.upkeepMetalPerSecond
	totals.energyPerSecond = totals.fireEnergyPerSecond + totals.upkeepEnergyPerSecond
	return totals
end

local function isSeaOnly(unitDef)
	if not unitDef then
		return false
	end
	if safeNumber(unitDef.minWaterDepth, 0) > 0 then
		return true
	end
	local cp = unitDef.customParams or unitDef.customparams or {}
	local unitGroup = tostring(cp.unitgroup or ''):lower()
	local name = tostring(unitDef.name or unitDef.unitname or ''):lower()
	if unitGroup:find('ship', 1, true) or unitGroup:find('naval', 1, true) or unitGroup:find('sub', 1, true) then
		return true
	end
	if name:find('ship', 1, true) or name:find('sub', 1, true) then
		return true
	end
	return false
end

local function isBuilderOrFactory(unitDef)
	if not unitDef then
		return false
	end
	local buildOptions = unitDef.buildOptions or unitDef.buildoptions
	return type(buildOptions) == 'table' and next(buildOptions) ~= nil
end

local function addBuildOptionClosure(rootDefID, ownedSourceDefIDs, env, visited)
	local unitDefs = env.unitDefs or {}
	local unitDefNames = env.unitDefNames or {}
	local unitDef = unitDefs[rootDefID]
	local buildOptions = unitDef and (unitDef.buildOptions or unitDef.buildoptions)
	if type(buildOptions) ~= 'table' then
		return
	end

	for _, buildOption in pairs(buildOptions) do
		local builtDefID = normalizeBuildOption(buildOption, unitDefNames)
		if builtDefID and not visited[builtDefID] then
			visited[builtDefID] = true
			ownedSourceDefIDs[builtDefID] = true
			addBuildOptionClosure(builtDefID, ownedSourceDefIDs, env, visited)
		end
	end
end

-- Preferred build path to a unit: array of def IDs from tech root to the
-- immediate builder (max 3 hops, factories preferred at each step)
local function buildSourceChain(defID, sourceByBuilt, unitDefs)
	local chain = {}
	local visited = {[defID] = true}
	local currentDefID = defID
	for _ = 1, 3 do
		local sources = sourceByBuilt[currentDefID]
		if not sources or #sources == 0 then
			break
		end
		table.sort(sources, function(a, b)
			local ad = unitDefs[a]
			local bd = unitDefs[b]
			if ad and bd and ad.isFactory ~= bd.isFactory then
				return ad.isFactory == true
			end
			return unitDisplayName(ad) < unitDisplayName(bd)
		end)
		local sourceDefID = sources[1]
		if visited[sourceDefID] then
			break
		end
		visited[sourceDefID] = true
		table.insert(chain, 1, sourceDefID)
		currentDefID = sourceDefID
	end
	return chain
end

local function sourceChainLabel(chain, unitDefs)
	local names = {}
	for i = 1, #chain do
		names[i] = unitDisplayName(unitDefs[chain[i]])
	end
	return table.concat(names, ' > ')
end

function UnitCatalog.Build(env)
	env = env or {}
	local unitDefs = env.unitDefs or {}
	local unitDefNames = env.unitDefNames or {}
	local weaponDefs = env.weaponDefs or {}
	local weaponDefNames = env.weaponDefNames or {}
	local resistanceMap = env.resistanceMap or {}
	local hasMeaningfulWater = env.hasMeaningfulWater ~= false
	local bossArmorTypeIndex = env.bossArmorTypeIndex

	local sourceByBuilt = {}
	for builderDefID, builderDef in pairs(unitDefs) do
		local buildOptions = builderDef.buildOptions or builderDef.buildoptions
		if type(buildOptions) == 'table' then
			for _, buildOption in pairs(buildOptions) do
				local builtDefID = normalizeBuildOption(buildOption, unitDefNames)
				if builtDefID then
					sourceByBuilt[builtDefID] = sourceByBuilt[builtDefID] or {}
					sourceByBuilt[builtDefID][#sourceByBuilt[builtDefID] + 1] = builderDefID
				end
			end
		end
	end

	local candidates = {}
	local ownedSourceDefIDs = env.ownedSourceDefIDs or {}
	for defID, unitDef in pairs(unitDefs) do
		local numericDefID = tonumber(defID) or defID
		local hasResistance = resistanceMap[numericDefID] ~= nil
		if hasResistance or unitHasWeapon(unitDef) then
			local metalCost = safeNumber(getUnitDefField(unitDef, 'metalCost', 'metalcost', 0), 0)
			local energyCost = safeNumber(getUnitDefField(unitDef, 'energyCost', 'energycost', 0), 0)
			local buildTime = safeNumber(getUnitDefField(unitDef, 'buildTime', 'buildtime', 0), 0)
			local reachable = sourceByBuilt[numericDefID] ~= nil
			local seaOnly = isSeaOnly(unitDef)
			local operatingCost = UnitCatalog.EstimateOperatingCost(unitDef, weaponDefs, bossArmorTypeIndex)
			local sourceChain = buildSourceChain(numericDefID, sourceByBuilt, unitDefs)
			candidates[numericDefID] = {
				defID = numericDefID,
				name = unitDef.name or unitDef.unitname or tostring(numericDefID),
				displayName = unitDisplayName(unitDef),
				icon = '#' .. tostring(numericDefID),
				metalCost = metalCost,
				energyCost = energyCost,
				buildTime = buildTime,
				maxWeaponRange = getWeaponRange(unitDef, weaponDefs),
				estimatedDps = UnitCatalog.EstimateDps(unitDef, weaponDefs, bossArmorTypeIndex, weaponDefNames),
				fireMetalPerSecond = operatingCost.fireMetalPerSecond,
				fireEnergyPerSecond = operatingCost.fireEnergyPerSecond,
				upkeepMetalPerSecond = operatingCost.upkeepMetalPerSecond,
				upkeepEnergyPerSecond = operatingCost.upkeepEnergyPerSecond,
				operatingMetalPerSecond = operatingCost.metalPerSecond,
				operatingEnergyPerSecond = operatingCost.energyPerSecond,
				hasResistance = hasResistance,
				reachable = reachable,
				mapViable = (not seaOnly) or hasMeaningfulWater,
				seaOnly = seaOnly,
				ownedSource = ownedSourceDefIDs[numericDefID] == true,
				sourceChain = sourceChain,
				sourceLabel = sourceChainLabel(sourceChain, unitDefs),
				isBuilder = isBuilderOrFactory(unitDef),
			}
		end
	end

	return {
		candidates = candidates,
		sourceByBuilt = sourceByBuilt,
	}
end

function UnitCatalog.ApplyAvailability(candidates, availabilityMode)
	local filtered = {}
	for defID, candidate in pairs(candidates or {}) do
		local keep = true
		if availabilityMode == 'owned' then
			keep = candidate.ownedSource == true
		elseif availabilityMode == 'map' then
			keep = candidate.reachable and candidate.mapViable
		elseif availabilityMode == 'match' then
			keep = candidate.reachable
		end

		if keep then
			filtered[defID] = candidate
		end
	end
	return filtered
end

--------------------------------------------------------------------------------
-- EngagementTracker
--------------------------------------------------------------------------------

local EngagementTracker = {}

function EngagementTracker.New()
	return {
		units = {},
		queuedOwn = {},
	}
end

function EngagementTracker.UpdateUnit(tracker, unitID, unitDefID, teamID, finished, buildProgress)
	if not unitID or not unitDefID then
		return
	end
	tracker.units[unitID] = {
		unitID = unitID,
		defID = unitDefID,
		teamID = teamID,
		finished = finished == true,
		buildProgress = safeNumber(buildProgress, finished and 1 or 0),
	}
end

function EngagementTracker.RemoveUnit(tracker, unitID)
	tracker.units[unitID] = nil
end

function EngagementTracker.OwnedSourceDefIDs(tracker, env)
	env = env or {}
	local unitDefs = env.unitDefs or {}
	local sourceTeamID = env.sourceTeamID
	local ownedSourceDefIDs = {}
	local rootDefIDs = {}

	for _, unit in pairs((tracker and tracker.units) or {}) do
		local inSourceTeam = sourceTeamID == nil or unit.teamID == sourceTeamID
		if inSourceTeam and unit.finished and unit.buildProgress >= 1 then
			local unitDef = unitDefs[unit.defID]
			if isBuilderOrFactory(unitDef) then
				rootDefIDs[unit.defID] = true
			end
		end
	end

	for rootDefID in pairs(rootDefIDs) do
		addBuildOptionClosure(rootDefID, ownedSourceDefIDs, env, {[rootDefID] = true})
	end

	return ownedSourceDefIDs
end

local function distanceSq(ax, az, bx, bz)
	local dx = ax - bx
	local dz = az - bz
	return dx * dx + dz * dz
end

function EngagementTracker.BuildCounts(tracker, env)
	env = env or {}
	local teamInfo = env.teamInfo or {}
	local candidateMap = env.candidateMap or {}
	local queuedOwn = tracker.queuedOwn or {}

	local countsByDef = {}
	local teamRowsByTeam = {}
	local ownedSourceDefIDs = EngagementTracker.OwnedSourceDefIDs(tracker, env)

	for _, unit in pairs(tracker.units) do
		if candidateMap[unit.defID] then
			local team = teamInfo[unit.teamID] or {teamID = unit.teamID, name = 'Team ' .. tostring(unit.teamID), allyTeamID = unit.teamID}
			local defCounts = countsByDef[unit.defID]
			if not defCounts then
				defCounts = {alive = 0, building = 0, queuedOwn = queuedOwn[unit.defID] or 0, teams = {}}
				countsByDef[unit.defID] = defCounts
			end

			local teamCounts = defCounts.teams[unit.teamID]
			if not teamCounts then
				teamCounts = {
					teamID = unit.teamID,
					allyTeamID = team.allyTeamID,
					name = team.name,
					color = team.color,
					alive = 0,
					building = 0,
					queuedOwn = 0,
				}
				defCounts.teams[unit.teamID] = teamCounts
			end

			local isFinished = unit.finished and unit.buildProgress >= 1
			if isFinished then
				defCounts.alive = defCounts.alive + 1
				teamCounts.alive = teamCounts.alive + 1
			else
				defCounts.building = defCounts.building + 1
				teamCounts.building = teamCounts.building + 1
			end

			teamRowsByTeam[unit.teamID] = teamRowsByTeam[unit.teamID] or {
				teamID = unit.teamID,
				name = team.name,
				color = team.color,
				damage = 0,
				units = {},
			}
		end
	end

	for defID, queuedCount in pairs(queuedOwn) do
		local defCounts = countsByDef[defID]
		if not defCounts then
			defCounts = {alive = 0, building = 0, queuedOwn = 0, teams = {}}
			countsByDef[defID] = defCounts
		end
		defCounts.queuedOwn = queuedCount
	end

	return countsByDef, teamRowsByTeam, ownedSourceDefIDs
end

--------------------------------------------------------------------------------
-- ResistanceSampler
--------------------------------------------------------------------------------

-- Tracks the pveBossInfo damage accumulator per unit def and reports damage
-- dealt over a sliding window, independent of the gadget's publish cadence
local ResistanceSampler = {}

function ResistanceSampler.New(windowSeconds)
	return {
		windowSeconds = math.max(1, safeNumber(windowSeconds, SCORE_WINDOW_SECONDS)),
		samplesByDef = {},
	}
end

function ResistanceSampler.Update(sampler, resistances, nowSeconds)
	nowSeconds = safeNumber(nowSeconds, 0)
	for defID, resistance in pairs(resistances or {}) do
		local samples = sampler.samplesByDef[defID]
		if not samples then
			samples = {}
			sampler.samplesByDef[defID] = samples
		end
		samples[#samples + 1] = {time = nowSeconds, damage = safeNumber(resistance.damage, 0)}
		-- Keep one sample at or before the window edge so the delta spans the full window
		while #samples > 1 and samples[2].time <= nowSeconds - sampler.windowSeconds do
			table.remove(samples, 1)
		end
	end
end

-- Damage normalized to one full window, keyed by unit def. Short histories are
-- extrapolated, clamped to 5x so a single early sample cannot spike the rate
function ResistanceSampler.WindowDamages(sampler)
	local result = {}
	for defID, samples in pairs(sampler.samplesByDef) do
		local first = samples[1]
		local last = samples[#samples]
		local elapsed = last.time - first.time
		local delta = last.damage - first.damage
		if elapsed > 0 and delta > 0 then
			result[defID] = delta * sampler.windowSeconds / math.max(elapsed, sampler.windowSeconds * 0.2)
		end
	end
	return result
end

--------------------------------------------------------------------------------
-- ScoringEngine
--------------------------------------------------------------------------------

local ScoringEngine = {}

function ScoringEngine.MetalEquivalent(unit, energyPerMetal)
	energyPerMetal = math.max(1, safeNumber(energyPerMetal, DEFAULT_ENERGY_PER_METAL))
	return safeNumber(unit.metalCost, 0) + safeNumber(unit.energyCost, 0) / energyPerMetal
end

function ScoringEngine.OperatingMetalEquivalentPerSecond(unit, energyPerMetal)
	energyPerMetal = math.max(1, safeNumber(energyPerMetal, DEFAULT_ENERGY_PER_METAL))
	return safeNumber(unit.operatingMetalPerSecond, 0) + safeNumber(unit.operatingEnergyPerSecond, 0) / energyPerMetal
end

function ScoringEngine.ScoreCost(unit, energyPerMetal, costMode, windowSeconds)
	local buildMetalEq = ScoringEngine.MetalEquivalent(unit, energyPerMetal)
	if costMode ~= 'full' then
		return buildMetalEq, 0
	end
	local operatingPerSecond = ScoringEngine.OperatingMetalEquivalentPerSecond(unit, energyPerMetal)
	local operatingWindowMetalEq = operatingPerSecond * math.max(0, safeNumber(windowSeconds, SCORE_WINDOW_SECONDS))
	return buildMetalEq + operatingWindowMetalEq, operatingWindowMetalEq
end

function ScoringEngine.EffectiveResistance(percent, staggerActive, mode)
	local resistance = clamp(safeNumber(percent, 0), 0, 0.99)
	if mode == 'scav' and resistance > 0.5 then
		if staggerActive then
			return 1 - ((1 - resistance) * (1 - resistance * 0.5))
		end
		return 1 - ((1 - resistance) * (1 - resistance))
	end
	if staggerActive then
		return resistance * 0.5
	end
	return resistance
end

function ScoringEngine.BossPhaseDamageMultiplier(healthPercent)
	healthPercent = safeNumber(healthPercent, 100)
	if healthPercent > 50 then
		return 2
	end
	if healthPercent > 25 then
		return 1
	end
	if healthPercent > 10 then
		return 0.75
	end
	if healthPercent > 5 then
		return 0.5
	end
	return 0.25
end

function ScoringEngine.ProjectResistance(resistance, expectedAccumulatorDelta, aliveMaxHealth, cap)
	local resistanceCap = safeNumber(cap, 0.95)
	local currentPercent = clamp(safeNumber(resistance and resistance.percent, 0), 0, resistanceCap)
	local currentDamage = safeNumber(resistance and resistance.damage, 0)
	aliveMaxHealth = safeNumber(aliveMaxHealth, 0)
	if aliveMaxHealth <= 0 then
		return currentPercent
	end
	return clamp((currentDamage + math.max(0, safeNumber(expectedAccumulatorDelta, 0))) / aliveMaxHealth, 0, resistanceCap)
end

local function confidenceFor(candidate, recentDelta, knowledge)
	if recentDelta and recentDelta > 0 then
		return 'high'
	end
	if knowledge and knowledge.samples and knowledge.samples > 0 then
		return 'med'
	end
	if candidate.estimatedDps > 0 then
		return 'low'
	end
	return ''
end

function ScoringEngine.BuildRows(input)
	input = input or {}
	local bossInfo = input.bossInfo or {}
	local countsByDef = input.countsByDef or {}
	local samplesByDef = input.samplesByDef or {}
	local knowledgeByDef = input.knowledgeByDef or {}
	local energyPerMetal = input.energyPerMetal or DEFAULT_ENERGY_PER_METAL
	local costMode = input.costMode or 'full'
	local sampleWindowSeconds = math.max(1 / GAME_FRAMES_PER_SECOND, safeNumber(input.sampleWindowSeconds, SCORE_WINDOW_SECONDS))
	-- The gadget grows the resistance accumulator by landed damage x 5 x difficulty
	-- resistance mult; callers pass 5 x that mult here
	local resistanceGainMult = math.max(0, safeNumber(input.resistanceGainMult, 5))
	local rows = {}

	for defID, candidate in pairs(input.candidates or {}) do
		local resistance = bossInfo.resistances and bossInfo.resistances[defID] or nil
		local resistancePercent = safeNumber(resistance and resistance.percent, 0)
		local resistanceDamage = safeNumber(resistance and resistance.damage, 0)
		local recentDelta = safeNumber(samplesByDef[defID], 0)
		local recentWindowDamage = recentDelta > 0 and recentDelta * SCORE_WINDOW_SECONDS / sampleWindowSeconds or 0
		local metalEq = math.max(1, ScoringEngine.MetalEquivalent(candidate, energyPerMetal))
		local scoreCostMetalEq, operatingWindowMetalEq = ScoringEngine.ScoreCost(
			candidate,
			energyPerMetal,
			costMode,
			SCORE_WINDOW_SECONDS
		)
		scoreCostMetalEq = math.max(1, scoreCostMetalEq)
		local operatingMetalEqPerSecond = ScoringEngine.OperatingMetalEquivalentPerSecond(candidate, energyPerMetal)
		local phaseMultiplier = ScoringEngine.BossPhaseDamageMultiplier(bossInfo.healthPercent)
		local estimatedBaseDamage = safeNumber(candidate.estimatedDps, 0) * SCORE_WINDOW_SECONDS * phaseMultiplier
		local estimatedWindowDamage = math.max(recentWindowDamage, estimatedBaseDamage)
		local currentResistance = ScoringEngine.EffectiveResistance(resistancePercent, bossInfo.staggerActive, bossInfo.mode)
		local expectedAccumulatorDelta = estimatedWindowDamage * math.max(0, 1 - currentResistance) * resistanceGainMult
		local projectedResistance = ScoringEngine.ProjectResistance(
			resistance,
			expectedAccumulatorDelta,
			bossInfo.aliveMaxHealth,
			bossInfo.resistanceCap
		)
		local marginalResistance = ScoringEngine.EffectiveResistance((resistancePercent + projectedResistance) * 0.5, bossInfo.staggerActive, bossInfo.mode)
		local currentDamage = estimatedBaseDamage * math.max(0, 1 - currentResistance)
		local marginalDamage = estimatedBaseDamage * math.max(0, 1 - marginalResistance)
		local counts = countsByDef[defID] or {alive = 0, building = 0, queuedOwn = 0, teams = {}}
		local knowledge = knowledgeByDef[defID]
		local historyAverage = safeNumber(knowledge and knowledge.averageScore, 0)
		local historySamples = safeNumber(knowledge and knowledge.samples, 0)
		local estimatedDamagePerCost = safeDivide(safeNumber(candidate.estimatedDps, 0), scoreCostMetalEq)
		local preBossSortScore = estimatedDamagePerCost
		local preBossSortSource = estimatedDamagePerCost > 0 and 'est' or ''
		if historySamples > 0 and historyAverage > 0 then
			preBossSortScore = historyAverage
			preBossSortSource = 'hist'
		end
		local teamSort = (counts.alive or 0) * 10000
			+ (counts.building or 0) * 100
			+ (counts.queuedOwn or 0)

		rows[#rows + 1] = {
			defID = defID,
			name = candidate.displayName,
			icon = candidate.icon,
			sourceLabel = candidate.sourceLabel ~= '' and candidate.sourceLabel or 'Unknown',
			sourceChain = candidate.sourceChain or {},
			resistancePercent = resistancePercent,
			resistanceDamage = resistanceDamage,
			projectedResistancePercent = projectedResistance,
			metalEq = metalEq,
			scoreCostMetalEq = scoreCostMetalEq,
			operatingWindowMetalEq = operatingWindowMetalEq,
			operatingMetalEqPerSecond = operatingMetalEqPerSecond,
			metalCost = candidate.metalCost,
			energyCost = candidate.energyCost,
			fireMetalPerSecond = candidate.fireMetalPerSecond,
			fireEnergyPerSecond = candidate.fireEnergyPerSecond,
			upkeepMetalPerSecond = candidate.upkeepMetalPerSecond,
			upkeepEnergyPerSecond = candidate.upkeepEnergyPerSecond,
			operatingMetalPerSecond = candidate.operatingMetalPerSecond,
			operatingEnergyPerSecond = candidate.operatingEnergyPerSecond,
			buildTime = candidate.buildTime,
			estimatedDps = candidate.estimatedDps,
			currentDamagePerMetalEq = currentDamage / scoreCostMetalEq,
			marginalDamagePerMetalEq = marginalDamage / scoreCostMetalEq,
			liveContributionPerMetalEq = recentWindowDamage > 0 and recentWindowDamage / scoreCostMetalEq or 0,
			confidence = confidenceFor(candidate, recentWindowDamage, knowledge),
			teamSort = teamSort,
			historyAverage = historyAverage,
			historySamples = historySamples,
			historyBest = safeNumber(knowledge and knowledge.bestScore, 0),
			historyLast = safeNumber(knowledge and knowledge.lastScore, 0),
			preBossSortScore = preBossSortScore,
			preBossSortSource = preBossSortSource,
			counts = counts,
			mapViable = candidate.mapViable,
			reachable = candidate.reachable,
			ownedSource = candidate.ownedSource,
			seaOnly = candidate.seaOnly,
		}
	end

	return rows
end

function ScoringEngine.SortRows(rows, sortKey, ascending)
	table.sort(rows, function(a, b)
		local av = a[sortKey] or 0
		local bv = b[sortKey] or 0
		if type(av) == 'string' then
			av = av:lower()
		end
		if type(bv) == 'string' then
			bv = bv:lower()
		end
		if type(av) ~= type(bv) then
			av = tostring(av)
			bv = tostring(bv)
		end
		if av == bv then
			if sortKey == 'preBossSortScore' then
				local adps = safeNumber(a.estimatedDps, 0)
				local bdps = safeNumber(b.estimatedDps, 0)
				if adps ~= bdps then
					return adps > bdps
				end
				local acost = safeNumber(a.scoreCostMetalEq, 0)
				local bcost = safeNumber(b.scoreCostMetalEq, 0)
				if acost ~= bcost then
					return acost < bcost
				end
			end
			return a.name < b.name
		end
		if ascending then
			return av < bv
		end
		return av > bv
	end)
end

--------------------------------------------------------------------------------
-- KnowledgeStore
--------------------------------------------------------------------------------

local KnowledgeStore = {}

function KnowledgeStore.New()
	return {
		schemaVersion = KNOWLEDGE_SCHEMA_VERSION,
		rows = {},
	}
end

function KnowledgeStore.Key(mode, difficulty, unitName)
	return tostring(mode or 'unknown') .. ':' .. tostring(difficulty or 'unknown') .. ':' .. tostring(unitName or 'unknown')
end

local function parseKnowledgeKey(key)
	local mode, difficulty, unitName = tostring(key or ''):match('^([^:]+):([^:]+):(.+)$')
	return mode or 'unknown', difficulty or 'unknown', unitName or tostring(key or 'unknown')
end

function KnowledgeStore.Merge(store, mode, difficulty, candidate, observation)
	local score = type(observation) == 'table' and observation.score or observation
	if not candidate or not candidate.name or safeNumber(score, 0) <= 0 then
		return
	end
	store.schemaVersion = KNOWLEDGE_SCHEMA_VERSION
	local key = KnowledgeStore.Key(mode, difficulty, candidate.name)
	local existing = store.rows[key] or {samples = 0, averageScore = 0, unitName = candidate.name}
	local samples = existing.samples + 1
	existing.averageScore = ((existing.averageScore * existing.samples) + score) / samples
	existing.samples = samples
	existing.lastSeen = os and os.time and os.time() or 0
	existing.lastScore = score
	existing.bestScore = math.max(safeNumber(existing.bestScore, 0), score)
	existing.schemaVersion = KNOWLEDGE_SCHEMA_VERSION
	existing.mode = mode
	existing.difficulty = difficulty
	existing.unitName = candidate.name
	if type(observation) == 'table' then
		existing.costMode = observation.costMode
		existing.energyPerMetal = observation.energyPerMetal
		existing.scoreWindowSeconds = observation.scoreWindowSeconds
		existing.resistancePercent = observation.resistancePercent
		existing.scoreCostMetalEq = observation.scoreCostMetalEq
		existing.operatingMetalEqPerSecond = observation.operatingMetalEqPerSecond
	end
	store.rows[key] = existing

	local count = tableSize(store.rows)
	if count <= MAX_KNOWLEDGE_ROWS then
		return
	end

	local oldestKey
	local oldestTime = math.huge
	for rowKey, row in pairs(store.rows) do
		local seen = safeNumber(row.lastSeen, 0)
		if seen < oldestTime then
			oldestKey = rowKey
			oldestTime = seen
		end
	end
	if oldestKey then
		store.rows[oldestKey] = nil
	end
end

function KnowledgeStore.Rows(store)
	local rows = {}
	for key, row in pairs((store and store.rows) or {}) do
		local keyMode, keyDifficulty, keyUnitName = parseKnowledgeKey(key)
		rows[#rows + 1] = {
			key = key,
			mode = row.mode or keyMode,
			difficulty = row.difficulty or keyDifficulty,
			unitName = row.unitName or keyUnitName,
			samples = safeNumber(row.samples, 0),
			averageScore = safeNumber(row.averageScore, 0),
			lastScore = safeNumber(row.lastScore, 0),
			bestScore = safeNumber(row.bestScore, row.averageScore or 0),
			lastSeen = safeNumber(row.lastSeen, 0),
			costMode = row.costMode or 'unknown',
			energyPerMetal = row.energyPerMetal,
			scoreWindowSeconds = row.scoreWindowSeconds,
			resistancePercent = row.resistancePercent,
			scoreCostMetalEq = row.scoreCostMetalEq,
			operatingMetalEqPerSecond = row.operatingMetalEqPerSecond,
		}
	end
	table.sort(rows, function(a, b)
		if a.mode == b.mode and a.difficulty == b.difficulty then
			if a.averageScore == b.averageScore then
				return a.unitName < b.unitName
			end
			return a.averageScore > b.averageScore
		end
		if a.mode == b.mode then
			return a.difficulty < b.difficulty
		end
		return a.mode < b.mode
	end)
	return rows
end

function KnowledgeStore.ByDefID(store, catalog, mode, difficulty)
	local byDefID = {}
	for defID, candidate in pairs(catalog.candidates or {}) do
		byDefID[defID] = store.rows[KnowledgeStore.Key(mode, difficulty, candidate.name)]
	end
	return byDefID
end

local Modules = {
	BossInfoAdapter = BossInfoAdapter,
	UnitCatalog = UnitCatalog,
	EngagementTracker = EngagementTracker,
	ResistanceSampler = ResistanceSampler,
	ScoringEngine = ScoringEngine,
	KnowledgeStore = KnowledgeStore,
	_helpers = {
		clamp = clamp,
		safeDivide = safeDivide,
		formatSI = formatSI,
		paginate = paginate,
		clampPanelRect = clampPanelRect,
		clampTableFontScale = clampTableFontScale,
		tableFontScaleLabel = tableFontScaleLabel,
		tableFontScaleDp = tableFontScaleDp,
		presentTeamCell = presentTeamCell,
	},
}

if type(_G) == 'table' and rawget(_G, 'BOSS_KILLER_PLANNER_TEST') then
	return Modules
end

--------------------------------------------------------------------------------
-- Widget lifecycle
--------------------------------------------------------------------------------

if not RmlUi then
	return
end

local Utilities = (BAR and BAR.Utilities) or Spring.Utilities

if not Utilities.Gametype.IsRaptors() and not Utilities.Gametype.IsScavengers() then
	return false
end

local widget = widget ---@type Widget

function widget:GetInfo()
	return {
		name = WIDGET_NAME,
		desc = 'Boss killer unit planner for PvE boss stages',
		author = 'tetrisface, Codex',
		date = '2026-06-15',
		license = 'GNU GPL, v2 or later',
		layer = 205,
		enabled = true,
		handler = true,
	}
end

local spGetGameRulesParam = Spring.GetGameRulesParam
local spGetGameFrame = Spring.GetGameFrame
local spGetModOptions = Spring.GetModOptions
local spGetConfigString = Spring.GetConfigString
local spSetConfigString = Spring.SetConfigString
local spGetViewGeometry = Spring.GetViewGeometry
local spGetAllUnits = Spring.GetAllUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitPosition = Spring.GetUnitPosition
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamColor = Spring.GetTeamColor
local spGetPlayerInfo = Spring.GetPlayerInfo
local spGetPlayerList = Spring.GetPlayerList
local spGetMyTeamID = Spring.GetMyTeamID
local spGetLocalTeamID = Spring.GetLocalTeamID
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetSpectatingState = Spring.GetSpectatingState
local spIsUnitAllied = Spring.IsUnitAllied
local spAreTeamsAllied = Spring.AreTeamsAllied
local spValidUnitID = Spring.ValidUnitID
local spGetUnitCommands = Spring.GetUnitCommands
local spIsGUIHidden = Spring.IsGUIHidden
local spGetCameraPosition = Spring.GetCameraPosition
local spSetCameraTarget = Spring.SetCameraTarget
local spGiveOrderToUnit = Spring.GiveOrderToUnit
local spClosestBuildPos = Spring.ClosestBuildPos

local isRaptors = Utilities.Gametype.IsRaptors()
local isScavengers = Utilities.Gametype.IsScavengers()
local modOptions = spGetModOptions()

local document
local dm_handle
local dataDirty = false
local forceRmlUpdate = false
local frameCounter = 0
local queueScanCounter = 0
local lastRmlUpdateFrame = -RML_UPDATE_FREQUENCY
local lastUIHiddenState = false
local widgetPosX = 1320
local widgetPosY = 300
local widgetWidth = PANEL_DEFAULT_WIDTH
local widgetHeight = PANEL_DEFAULT_HEIGHT
local activeTab = 'units'
local rowPage = 1
local currentPageCount = 1
local availabilityMode = 'match'
local sortKey = 'marginalDamagePerMetalEq'
local sortAscending = false
local energyPerMetal = DEFAULT_ENERGY_PER_METAL
local costMode = 'full'
local requireHistory = false
local tableFontScale = TABLE_FONT_DEFAULT_SCALE
local myTeamID
local sourceTeamID
local gaiaTeamID
local isSpectator = false
local fullView = false

local tracker = EngagementTracker.New()
local catalog = {candidates = {}, sourceByBuilt = {}}
local catalogBuilt = false
local catalogArmorTypeIndex
local cachedBossArmorTypeIndex
local cachedHasMeaningfulWater
local spawnDefsConfig
local bossInfo = BossInfoAdapter.Normalize(nil, {})
local resistanceSampler = ResistanceSampler.New(SCORE_WINDOW_SECONDS)
local resistanceSamples = {}
local knowledgeStore = KnowledgeStore.New()
local knowledgeLastSampleFrame = {}

local function configKey(suffix)
	return 'BossKillerPlanner_' .. suffix
end

local function refreshTeamState()
	myTeamID = spGetMyTeamID()
	local localTeamID = spGetLocalTeamID and spGetLocalTeamID()
	if localTeamID ~= nil and localTeamID >= 0 then
		sourceTeamID = localTeamID
	else
		sourceTeamID = myTeamID
	end
	local spec, full = spGetSpectatingState()
	isSpectator = spec
	fullView = full
end

local function currentViewport()
	if not spGetViewGeometry then
		return nil
	end
	local viewWidth, viewHeight = spGetViewGeometry()
	viewWidth = safeNumber(viewWidth, 0)
	viewHeight = safeNumber(viewHeight, 0)
	if viewWidth <= 0 or viewHeight <= 0 then
		return nil
	end
	return {width = viewWidth, height = viewHeight}
end

local function clampWindowStateToViewport(viewport)
	local rect = clampPanelRect({
		x = widgetPosX,
		y = widgetPosY,
		width = widgetWidth,
		height = widgetHeight,
	}, viewport or currentViewport(), PANEL_MIN_WIDTH, PANEL_MIN_HEIGHT)
	local changed = rect.x ~= widgetPosX
		or rect.y ~= widgetPosY
		or rect.width ~= widgetWidth
		or rect.height ~= widgetHeight
	widgetPosX = rect.x
	widgetPosY = rect.y
	widgetWidth = rect.width
	widgetHeight = rect.height
	return changed
end

local function markDataDirty(force)
	dataDirty = true
	if force then
		forceRmlUpdate = true
	end
end

local function resetRowPage()
	rowPage = 1
	currentPageCount = 1
end

local function parsePair(value)
	if type(value) ~= 'string' then
		return nil, nil
	end
	local a, b = value:match('^(%-?%d+),(%-?%d+)$')
	return tonumber(a), tonumber(b)
end

local function loadConfig()
	local x, y = parsePair(spGetConfigString(configKey('Position'), ''))
	if x and y then
		widgetPosX = x
		widgetPosY = y
	end
	local w, h = parsePair(spGetConfigString(configKey('Size'), ''))
	if w and h then
		widgetWidth = w
		widgetHeight = h
	end
	activeTab = spGetConfigString(configKey('Tab'), activeTab)
	if activeTab ~= 'units' and activeTab ~= 'teams' then
		activeTab = 'units'
	end
	availabilityMode = spGetConfigString(configKey('Availability'), availabilityMode)
	sortKey = spGetConfigString(configKey('SortKey'), sortKey)
	if sortKey == 'metalEq' then
		sortKey = 'scoreCostMetalEq'
	end
	sortAscending = spGetConfigString(configKey('SortAscending'), 'false') == 'true'
	energyPerMetal = math.max(1, tonumber(spGetConfigString(configKey('EnergyPerMetal'), tostring(DEFAULT_ENERGY_PER_METAL))) or DEFAULT_ENERGY_PER_METAL)
	costMode = spGetConfigString(configKey('CostMode'), costMode)
	if costMode ~= 'build' and costMode ~= 'full' then
		costMode = 'full'
	end
	requireHistory = spGetConfigString(configKey('RequireHistory'), 'false') == 'true'
	tableFontScale = clampTableFontScale(spGetConfigString(configKey('TableFontScale'), tostring(TABLE_FONT_DEFAULT_SCALE)))
	clampWindowStateToViewport()
end

local function saveConfig()
	spSetConfigString(configKey('Tab'), activeTab)
	spSetConfigString(configKey('Availability'), availabilityMode)
	spSetConfigString(configKey('SortKey'), sortKey)
	spSetConfigString(configKey('SortAscending'), tostring(sortAscending))
	spSetConfigString(configKey('EnergyPerMetal'), tostring(energyPerMetal))
	spSetConfigString(configKey('CostMode'), costMode)
	spSetConfigString(configKey('RequireHistory'), tostring(requireHistory))
	spSetConfigString(configKey('TableFontScale'), tostring(tableFontScale))
end

local updateDocumentPosition
local applyTableFontScale

local function savePositionAndSize()
	if not document then
		return
	end
	local panel = document:GetElementById('bkp-panel')
	if not panel then
		return
	end
	widgetPosX = math.floor(panel.absolute_left)
	widgetPosY = math.floor(panel.absolute_top)
	widgetWidth = math.floor(panel.offset_width)
	widgetHeight = math.floor(panel.offset_height)
	local wasClamped = clampWindowStateToViewport()
	if wasClamped then
		updateDocumentPosition()
	end
	spSetConfigString(configKey('Position'), widgetPosX .. ',' .. widgetPosY)
	spSetConfigString(configKey('Size'), widgetWidth .. ',' .. widgetHeight)
end

updateDocumentPosition = function()
	if not document then
		return
	end
	local panel = document:GetElementById('bkp-panel')
	if not panel then
		return
	end
	clampWindowStateToViewport()
	panel.style.left = widgetPosX .. 'px'
	panel.style.top = widgetPosY .. 'px'
	-- px throughout: offset_width/absolute_left report px, so writing dp here
	-- would rescale the panel by the dp ratio on every drag end
	panel.style.width = widgetWidth .. 'px'
	panel.style.height = widgetHeight .. 'px'
end

applyTableFontScale = function()
	if not document then
		return
	end
	local fontSize = tableFontScaleDp(tableFontScale)
	local unitsTable = document:GetElementById('bkp-units-table-area')
	if unitsTable then
		unitsTable.style['font-size'] = fontSize
	end
	local teamsTable = document:GetElementById('bkp-teams-table-area')
	if teamsTable then
		teamsTable.style['font-size'] = fontSize
	end
end

local function loadKnowledge()
	if not VFS or not VFS.FileExists or not VFS.FileExists(KNOWLEDGE_PATH) then
		return
	end
	local ok, loaded = pcall(VFS.Include, KNOWLEDGE_PATH)
	if ok and type(loaded) == 'table' and type(loaded.rows) == 'table' then
		loaded.schemaVersion = loaded.schemaVersion or 1
		knowledgeStore = loaded
	end
end

local function saveKnowledge()
	if table.save then
		table.save(knowledgeStore, KNOWLEDGE_PATH, '-- Boss Killer Planner knowledge')
	end
end

local function teamName(teamID)
	local _, leader, _, isAI = spGetTeamInfo(teamID, false)
	if isAI then
		return Spring.GetGameRulesParam('ainame_' .. teamID) or ('AI ' .. tostring(teamID))
	end
	if leader then
		return spGetPlayerInfo(leader, false) or ('Team ' .. tostring(teamID))
	end
	return 'Team ' .. tostring(teamID)
end

local function teamColorString(teamID)
	local r, g, b = spGetTeamColor(teamID)
	return string.format('rgb(%d,%d,%d)', round((r or 1) * 255), round((g or 1) * 255), round((b or 1) * 255))
end

local function collectTeamInfo()
	local result = {}
	local players = spGetPlayerList() or {}
	for _, playerID in ipairs(players) do
		local name, _, isSpec, teamID = spGetPlayerInfo(playerID, false)
		if teamID and not isSpec then
			local _, _, _, _, _, allyTeamID = spGetTeamInfo(teamID, false)
			result[teamID] = {
				teamID = teamID,
				allyTeamID = allyTeamID,
				name = name or teamName(teamID),
				color = teamColorString(teamID),
			}
		end
	end
	return result
end

local function shouldTrackUnit(unitID, teamID)
	if teamID == gaiaTeamID then
		return false
	end
	if unitID and spIsUnitAllied(unitID) then
		return true
	end
	return spAreTeamsAllied and spAreTeamsAllied(teamID, sourceTeamID or myTeamID)
end

local function refreshUnit(unitID, unitDefID, teamID, finishedOverride)
	if not unitID or not unitDefID or not teamID or not shouldTrackUnit(unitID, teamID) then
		return
	end
	local _, _, _, _, buildProgress = spGetUnitHealth(unitID)
	local finished = finishedOverride == true or safeNumber(buildProgress, 1) >= 1
	EngagementTracker.UpdateUnit(tracker, unitID, unitDefID, teamID, finished, finished and 1 or buildProgress)
end

local function rebuildTrackedUnits()
	tracker.units = {}
	for _, unitID in ipairs(spGetAllUnits() or {}) do
		local unitDefID = spGetUnitDefID(unitID)
		local teamID = spGetUnitTeam(unitID)
		refreshUnit(unitID, unitDefID, teamID)
	end
end

local function hasMeaningfulWater()
	if not Spring.GetGroundHeight or not Game then
		return true
	end
	local mapX = Game.mapSizeX or 0
	local mapZ = Game.mapSizeZ or 0
	if mapX <= 0 or mapZ <= 0 then
		return true
	end
	local waterSamples = 0
	local totalSamples = 0
	for xStep = 1, 5 do
		for zStep = 1, 5 do
			local x = mapX * xStep / 6
			local z = mapZ * zStep / 6
			totalSamples = totalSamples + 1
			if Spring.GetGroundHeight(x, z) < -8 then
				waterSamples = waterSamples + 1
			end
		end
	end
	return totalSamples > 0 and waterSamples / totalSamples >= 0.08
end

local function scanOwnQueues()
	tracker.queuedOwn = {}
	for unitID, unit in pairs(tracker.units) do
		if unit.teamID == myTeamID and spValidUnitID(unitID) then
			local unitDef = UnitDefs[unit.defID]
			if isBuilderOrFactory(unitDef) then
				for _, command in ipairs(spGetUnitCommands(unitID, 80) or {}) do
					if command.id and command.id < 0 then
						local defID = -command.id
						tracker.queuedOwn[defID] = (tracker.queuedOwn[defID] or 0) + 1
					end
				end
			end
		end
	end
end

-- Own-team status per unit def: 'done' (finished exists), 'building'
-- (under construction or queued), or nil for none
local function buildStatusByDef()
	local statusByDef = {}
	for _, unit in pairs(tracker.units) do
		if unit.teamID == sourceTeamID then
			if unit.finished and unit.buildProgress >= 1 then
				statusByDef[unit.defID] = 'done'
			elseif statusByDef[unit.defID] ~= 'done' then
				statusByDef[unit.defID] = 'building'
			end
		end
	end
	for defID, queuedCount in pairs(tracker.queuedOwn or {}) do
		if queuedCount > 0 and not statusByDef[defID] then
			statusByDef[defID] = 'building'
		end
	end
	return statusByDef
end

local statusColors = {
	done = STATUS_DONE_COLOR,
	building = STATUS_BUILDING_COLOR,
}

local function statusColor(status)
	return statusColors[status] or STATUS_NONE_COLOR
end

-- One independent knowledge observation per unit def per score window.
-- Runs on the data path so rendering stays free of persistence side effects
local function sampleKnowledge()
	if bossInfo.bossCount <= 0 then
		return
	end
	local frame = spGetGameFrame()
	local minGapFrames = SCORE_WINDOW_SECONDS * GAME_FRAMES_PER_SECOND
	for defID, windowDamage in pairs(resistanceSamples) do
		local candidate = catalog.candidates[defID]
		if candidate and windowDamage > 0 then
			local lastFrame = knowledgeLastSampleFrame[defID]
			if not lastFrame or frame - lastFrame >= minGapFrames then
				knowledgeLastSampleFrame[defID] = frame
				local scoreCostMetalEq = math.max(1, (ScoringEngine.ScoreCost(candidate, energyPerMetal, costMode, SCORE_WINDOW_SECONDS)))
				local resistance = bossInfo.resistances[defID]
				KnowledgeStore.Merge(knowledgeStore, bossInfo.mode, bossInfo.difficulty, candidate, {
					score = windowDamage / scoreCostMetalEq,
					costMode = costMode,
					energyPerMetal = energyPerMetal,
					scoreWindowSeconds = SCORE_WINDOW_SECONDS,
					resistancePercent = safeNumber(resistance and resistance.percent, 0),
					scoreCostMetalEq = scoreCostMetalEq,
					operatingMetalEqPerSecond = ScoringEngine.OperatingMetalEquivalentPerSecond(candidate, energyPerMetal),
				})
			end
		end
	end
end

-- Difficulty-selected config of the boss gadget (queenName/bossName, resistance mult)
local function loadSpawnDefsConfig()
	if spawnDefsConfig ~= nil then
		return spawnDefsConfig or nil
	end
	local path = isRaptors and 'LuaRules/Configs/raptor_spawn_defs.lua' or 'LuaRules/Configs/scav_spawn_defs.lua'
	local ok, config = pcall(VFS.Include, path)
	spawnDefsConfig = (ok and type(config) == 'table') and config or false
	return spawnDefsConfig or nil
end

-- 5x is the gadget's fixed accumulator factor. Endless-mode ramping
-- (+0.5 mult per difficulty cycle) is not tracked
local function resistanceGainMult()
	local config = loadSpawnDefsConfig()
	local difficultyMult = safeNumber(config and (config.queenResistanceMult or config.bossResistanceMult), 1)
	return 5 * math.max(0.1, difficultyMult)
end

-- Armor type of the boss unit def; damage estimates read this armor class.
-- Live bosses are the fallback when the config def name is missing.
local function resolveBossArmorTypeIndex()
	if cachedBossArmorTypeIndex ~= nil then
		return cachedBossArmorTypeIndex
	end

	local config = loadSpawnDefsConfig()
	local bossDefName = config and (config.queenName or config.bossName)
	if not bossDefName then
		bossDefName = isRaptors and ('raptor_queen_' .. tostring(modOptions.raptor_difficulty))
			or ('scavengerbossv4_' .. tostring(modOptions.scav_difficulty) .. '_scav')
	end
	local bossDef = UnitDefNames[bossDefName]
	if bossDef and bossDef.armorType then
		cachedBossArmorTypeIndex = bossDef.armorType
		return cachedBossArmorTypeIndex
	end

	for _, unitID in ipairs(bossInfo.aliveBossIDs or {}) do
		local defID = spGetUnitDefID(unitID)
		local unitDef = defID and UnitDefs[defID]
		if unitDef and unitDef.armorType then
			cachedBossArmorTypeIndex = unitDef.armorType
			return cachedBossArmorTypeIndex
		end
	end

	return nil
end

local function catalogNeedsRebuild(bossArmorType)
	if not catalogBuilt then
		return true
	end

	if catalogArmorTypeIndex ~= bossArmorType then
		return true
	end

	for defID in pairs(bossInfo.resistances or {}) do
		if UnitDefs[defID] and not catalog.candidates[defID] then
			return true
		end
	end

	return false
end

local function applyOwnedSourceFlags(ownedSourceDefIDs)
	for defID, candidate in pairs(catalog.candidates or {}) do
		candidate.ownedSource = ownedSourceDefIDs[defID] == true
	end
end

local function buildCatalogWithOwnedSources()
	local ownedSourceDefIDs = EngagementTracker.OwnedSourceDefIDs(tracker, {
		unitDefs = UnitDefs,
		unitDefNames = UnitDefNames,
		sourceTeamID = sourceTeamID,
	})
	local bossArmorType = resolveBossArmorTypeIndex()
	if catalogNeedsRebuild(bossArmorType) then
		if cachedHasMeaningfulWater == nil then
			cachedHasMeaningfulWater = hasMeaningfulWater()
		end
		catalog = UnitCatalog.Build({
			unitDefs = UnitDefs,
			unitDefNames = UnitDefNames,
			weaponDefs = WeaponDefs,
			weaponDefNames = WeaponDefNames,
			resistanceMap = bossInfo.resistances,
			hasMeaningfulWater = cachedHasMeaningfulWater,
			ownedSourceDefIDs = ownedSourceDefIDs,
			bossArmorTypeIndex = bossArmorType,
		})
		catalogArmorTypeIndex = bossArmorType
		catalogBuilt = true
		return
	end

	applyOwnedSourceFlags(ownedSourceDefIDs)
end

local confidenceLetters = {high = 'H', med = 'M', low = 'L'}

local function presentationRow(row, statusByDef)
	local history = ''
	if (row.historySamples or 0) > 0 then
		history = formatSI(row.historyAverage) .. '/' .. tostring(row.historySamples)
	end
	local preBoss = '-'
	if row.preBossSortSource and row.preBossSortSource ~= '' then
		preBoss = row.preBossSortSource .. ' ' .. formatSI(row.preBossSortScore)
	end
	local teamCell = presentTeamCell(row.counts or {})
	local sourceChain = {}
	for i = 1, #(row.sourceChain or {}) do
		local chainDefID = row.sourceChain[i]
		sourceChain[i] = {
			icon = '#' .. tostring(chainDefID),
			def_id = chainDefID,
			name = unitDisplayName(UnitDefs[chainDefID]),
			color = statusColor(statusByDef[chainDefID]),
		}
	end
	return {
		name = row.name,
		icon = row.icon,
		status_color = statusColor(statusByDef[row.defID]),
		source_chain = sourceChain,
		resistance = tostring(round(row.resistancePercent * 100)) .. '%',
		projected = tostring(round(row.projectedResistancePercent * 100)) .. '%',
		resistance_damage = formatSI(row.resistanceDamage),
		score = formatSI(row.marginalDamagePerMetalEq),
		live_score = row.liveContributionPerMetalEq > 0 and formatSI(row.liveContributionPerMetalEq) or '',
		conf = confidenceLetters[row.confidence] or '',
		cost = formatSI(row.scoreCostMetalEq),
		operating_cost = row.operatingMetalEqPerSecond > 0 and (formatSI(row.operatingMetalEqPerSecond) .. '/s') or '',
		history = history,
		history_tooltip = string.format(
			'Avg %s | Last %s | Best %s | Samples %d | Pre-boss %s | Confidence %s',
			formatSI(row.historyAverage),
			row.historyLast > 0 and formatSI(row.historyLast) or '-',
			row.historyBest > 0 and formatSI(row.historyBest) or '-',
			row.historySamples or 0,
			preBoss,
			row.confidence ~= '' and row.confidence or '-'
		),
		team_label = teamCell.label,
		team_color = teamCell.color,
		team_tooltip = teamCell.tooltip,
	}
end

local function currentPageInfo(totalRows, pageSize)
	local pageInfo = paginate(totalRows, rowPage, pageSize, RANKED_ROW_LIMIT)
	rowPage = pageInfo.page
	return pageInfo
end

local historyFallbackSortKeys = {
	currentDamagePerMetalEq = true,
	marginalDamagePerMetalEq = true,
	liveContributionPerMetalEq = true,
}

local function hasBossEvidence(rows)
	if bossInfo.bossCount > 0 then
		return true
	end
	for _, row in ipairs(rows or {}) do
		if (row.resistanceDamage or 0) > 0 or (row.liveContributionPerMetalEq or 0) > 0 then
			return true
		end
	end
	return false
end

local function resolveUnitSort(rows)
	if historyFallbackSortKeys[sortKey] and not hasBossEvidence(rows) then
		return {
			key = 'preBossSortScore',
			ascending = false,
			fallback = true,
		}
	end
	return {
		key = sortKey,
		ascending = sortAscending,
		fallback = false,
	}
end

local function buildRows()
	buildCatalogWithOwnedSources()
	local filteredCandidates = UnitCatalog.ApplyAvailability(catalog.candidates, availabilityMode)
	local teamInfo = collectTeamInfo()
	-- Counts run on the full catalog so the Teams tab reports allies' units
	-- even when the availability filter hides them from the Units tab
	local countsByDef, teamRows = EngagementTracker.BuildCounts(tracker, {
		unitDefs = UnitDefs,
		unitDefNames = UnitDefNames,
		candidateMap = catalog.candidates,
		teamInfo = teamInfo,
		sourceTeamID = sourceTeamID,
	})

	local rows = ScoringEngine.BuildRows({
		candidates = filteredCandidates,
		bossInfo = bossInfo,
		countsByDef = countsByDef,
		samplesByDef = resistanceSamples,
		knowledgeByDef = KnowledgeStore.ByDefID(knowledgeStore, catalog, bossInfo.mode, bossInfo.difficulty),
		energyPerMetal = energyPerMetal,
		costMode = costMode,
		sampleWindowSeconds = SCORE_WINDOW_SECONDS,
		resistanceGainMult = resistanceGainMult(),
	})

	if requireHistory then
		local backedRows = {}
		for i = 1, #rows do
			if (rows[i].historySamples or 0) > 0 then
				backedRows[#backedRows + 1] = rows[i]
			end
		end
		rows = backedRows
	end

	local pageInfo = currentPageInfo(#rows, RANKED_ROW_LIMIT)
	local unitRows = {}
	local sortInfo = resolveUnitSort(rows)
	if activeTab == 'units' then
		local statusByDef = buildStatusByDef()
		local sortedRows = shallowCopy(rows)
		ScoringEngine.SortRows(sortedRows, sortInfo.key, sortInfo.ascending)
		pageInfo = currentPageInfo(#sortedRows, RANKED_ROW_LIMIT)
		for i = pageInfo.startIndex, pageInfo.endIndex do
			unitRows[#unitRows + 1] = presentationRow(sortedRows[i], statusByDef)
		end
	end

	local teamList = {}
	if activeTab == 'teams' then
		for teamID, damage in pairs(bossInfo.playerDamages or {}) do
			if not teamRows[teamID] then
				local team = teamInfo[teamID] or {
					teamID = teamID,
					name = teamName(teamID),
					color = teamColorString(teamID),
				}
				teamRows[teamID] = {
					teamID = teamID,
					name = team.name,
					color = team.color,
					damage = safeNumber(damage, 0),
					units = {},
				}
			end
		end

		for teamID, team in pairs(teamRows) do
			team.damage = safeNumber(bossInfo.playerDamages[teamID], 0)
			team.damage_label = formatSI(team.damage)
			team.units = {}
			teamList[#teamList + 1] = team
		end
		table.sort(teamList, function(a, b)
			if a.damage == b.damage then
				return a.name < b.name
			end
			return a.damage > b.damage
		end)

		for defID, defCounts in pairs(countsByDef) do
			local candidate = catalog.candidates[defID]
			if candidate then
				for _, teamCounts in pairs(defCounts.teams or {}) do
					for _, team in ipairs(teamList) do
						if team.teamID == teamCounts.teamID then
							team.units[#team.units + 1] = {
								name = candidate.displayName,
								icon = candidate.icon,
								alive = tostring(teamCounts.alive),
								building = tostring(teamCounts.building),
							}
							break
						end
					end
				end
			end
		end
		for _, team in ipairs(teamList) do
			table.sort(team.units, function(a, b)
				return a.name < b.name
			end)
		end
		pageInfo = {
			label = #teamList == 1 and '1 team' or (tostring(#teamList) .. ' teams'),
			hasPrev = false,
			hasNext = false,
			pageCount = 1,
		}
	end

	return unitRows, teamList, #rows > 0, pageInfo, sortInfo
end

local availabilityLabels = {
	match = 'Buildable by lobby',
	map = 'Map Viable',
	owned = 'Buildable by player',
	all = 'All Known',
}

local sortLabels = {
	name = 'Unit',
	sourceLabel = 'Source',
	marginalDamagePerMetalEq = 'Marginal',
	currentDamagePerMetalEq = 'Current',
	liveContributionPerMetalEq = 'Live',
	resistancePercent = 'Resist',
	projectedResistancePercent = 'Proj',
	resistanceDamage = 'Damage',
	scoreCostMetalEq = 'Cost',
	operatingMetalEqPerSecond = 'Use/s',
	teamSort = 'Teams',
	historyAverage = 'History',
}

local defaultSortAscending = {
	name = true,
	sourceLabel = true,
	resistancePercent = true,
	projectedResistancePercent = true,
	scoreCostMetalEq = true,
	operatingMetalEqPerSecond = true,
}

local validSortKeys = {
	name = true,
	sourceLabel = true,
	resistancePercent = true,
	projectedResistancePercent = true,
	resistanceDamage = true,
	marginalDamagePerMetalEq = true,
	currentDamagePerMetalEq = true,
	liveContributionPerMetalEq = true,
	scoreCostMetalEq = true,
	operatingMetalEqPerSecond = true,
	teamSort = true,
	historyAverage = true,
}

local costModeLabels = {
	build = 'Cost Build',
	full = 'Cost Full',
}

local function updateRmlData()
	if not dm_handle then
		return
	end

	local unitRows, teamRows, hasCandidateRows, pageInfo, sortInfo = buildRows()
	local statusText
	if bossInfo.mode == 'unknown' then
		statusText = 'Waiting for boss data'
	elseif bossInfo.bossCount <= 0 and safeNumber(bossInfo.healthPercent, 0) <= 0 then
		statusText = string.format('%s %s - waiting for boss - %.0f%% anger', bossInfo.mode, bossInfo.difficulty or '', bossInfo.anger or 0)
	else
		statusText = string.format(
			'%s %s - %.0f%% HP - %.0f%% anger',
			bossInfo.mode,
			bossInfo.difficulty or '',
			bossInfo.healthPercent or 0,
			bossInfo.anger or 0
		)
	end

	dm_handle.active_tab = activeTab
	dm_handle.is_units = activeTab == 'units'
	dm_handle.is_teams = activeTab == 'teams'
	dm_handle.status_text = statusText
	dm_handle.availability_label = availabilityLabels[availabilityMode] or availabilityMode
	dm_handle.history_filter_label = requireHistory and 'Has Hist' or 'Any Hist'
	dm_handle.sort_label = sortInfo.fallback and 'Pre-boss estimate' or (sortLabels[sortKey] or sortKey)
	dm_handle.sort_direction = sortInfo.ascending and 'Asc' or 'Desc'
	dm_handle.energy_per_metal = tostring(energyPerMetal)
	dm_handle.cost_mode_label = costModeLabels[costMode] or costMode
	dm_handle.cost_header = costMode == 'full' and 'Full' or 'Build'
	dm_handle.table_font_label = tableFontScaleLabel(tableFontScale)
	dm_handle.stagger_label = bossInfo.staggerActive and ('Stagger ' .. tostring(round(bossInfo.staggerPercent)) .. '%') or ''
	dm_handle.page_label = pageInfo.label
	dm_handle.has_prev_page = pageInfo.hasPrev
	dm_handle.has_next_page = pageInfo.hasNext
	dm_handle.prev_page_style = pageInfo.hasPrev and 'color: #9EB7C8' or 'color: #46515A'
	dm_handle.next_page_style = pageInfo.hasNext and 'color: #9EB7C8' or 'color: #46515A'
	currentPageCount = pageInfo.pageCount or 1
	dm_handle.unit_rows = unitRows
	dm_handle.team_rows = teamRows
	dm_handle.has_rows = hasCandidateRows or #unitRows > 0
end

local function maybeUpdateRmlData(force)
	if not force and not dataDirty then
		return
	end

	local frame = spGetGameFrame and spGetGameFrame() or 0
	if not force and not forceRmlUpdate and frame - lastRmlUpdateFrame < RML_UPDATE_FREQUENCY then
		return
	end

	updateRmlData()
	applyTableFontScale()
	dataDirty = false
	forceRmlUpdate = false
	lastRmlUpdateFrame = frame
end

local function refreshBossInfo()
	local nextBossInfo = BossInfoAdapter.ReadFromSpring({
		Spring = {GetGameRulesParam = spGetGameRulesParam},
		Json = Json,
		isRaptors = isRaptors,
		isScavengers = isScavengers,
		modOptions = modOptions,
	})
	ResistanceSampler.Update(resistanceSampler, nextBossInfo.resistances, spGetGameFrame() / GAME_FRAMES_PER_SECOND)
	resistanceSamples = ResistanceSampler.WindowDamages(resistanceSampler)
	bossInfo = nextBossInfo
end

function widget:Initialize()
	loadConfig()
	if not validSortKeys[sortKey] then
		sortKey = 'marginalDamagePerMetalEq'
		sortAscending = false
	end
	loadKnowledge()
	gaiaTeamID = spGetGaiaTeamID()
	refreshTeamState()

	widget.rmlContext = RmlUi.GetContext('shared')
	if not widget.rmlContext then
		Spring.Echo(WIDGET_NAME .. ': ERROR - failed to get RML context')
		return false
	end

	local initialModel = {
		active_tab = activeTab,
		is_units = activeTab == 'units',
		is_teams = activeTab == 'teams',
		status_text = 'Starting...',
		availability_label = availabilityLabels[availabilityMode],
		history_filter_label = requireHistory and 'Has Hist' or 'Any Hist',
		sort_label = sortLabels[sortKey],
		sort_direction = 'Desc',
		energy_per_metal = tostring(energyPerMetal),
		cost_mode_label = costModeLabels[costMode],
		cost_header = costMode == 'full' and 'Full' or 'Build',
		table_font_label = tableFontScaleLabel(tableFontScale),
		stagger_label = '',
		page_label = '',
		has_prev_page = false,
		has_next_page = false,
		prev_page_style = 'color: #46515A',
		next_page_style = 'color: #46515A',
		unit_rows = {},
		team_rows = {},
		has_rows = false,
	}

	dm_handle = widget.rmlContext:OpenDataModel(MODEL_NAME, initialModel)
	if not dm_handle then
		Spring.Echo(WIDGET_NAME .. ': ERROR - failed to create data model')
		return false
	end

	document = widget.rmlContext:LoadDocument(RML_PATH, widget)
	if not document then
		Spring.Echo(WIDGET_NAME .. ': ERROR - failed to load document: ' .. RML_PATH)
		widget:Shutdown()
		return false
	end

	document:ReloadStyleSheet()
	updateDocumentPosition()
	applyTableFontScale()
	if not spIsGUIHidden() then
		document:Show()
	end

	refreshBossInfo()
	rebuildTrackedUnits()
	scanOwnQueues()
	markDataDirty(true)
	maybeUpdateRmlData(true)
	return true
end

function widget:Update()
	if not document then
		return
	end
	local isHidden = spIsGUIHidden()
	if isHidden ~= lastUIHiddenState then
		lastUIHiddenState = isHidden
		if isHidden then
			document:Hide()
		else
			document:Show()
			markDataDirty(true)
		end
	end
	if isHidden then
		return
	end
	maybeUpdateRmlData(false)
end

function widget:GameFrame()
	frameCounter = frameCounter + 1
	queueScanCounter = queueScanCounter + 1

	if queueScanCounter >= QUEUE_SCAN_FREQUENCY then
		queueScanCounter = 0
		scanOwnQueues()
		markDataDirty(false)
	end

	if frameCounter >= BOSS_INFO_FREQUENCY then
		frameCounter = 0
		refreshBossInfo()
		sampleKnowledge()
		markDataDirty(false)
	end
end

function widget:UnitCreated(unitID, unitDefID, teamID)
	refreshUnit(unitID, unitDefID, teamID, false)
	markDataDirty(false)
end

function widget:UnitFinished(unitID, unitDefID, teamID)
	refreshUnit(unitID, unitDefID, teamID, true)
	markDataDirty(false)
end

function widget:UnitDestroyed(unitID)
	EngagementTracker.RemoveUnit(tracker, unitID)
	markDataDirty(false)
end

function widget:UnitGiven(unitID, unitDefID, newTeamID)
	refreshUnit(unitID, unitDefID, newTeamID, true)
	markDataDirty(false)
end

function widget:UnitTaken(unitID)
	EngagementTracker.RemoveUnit(tracker, unitID)
	markDataDirty(false)
end

function widget:PlayerChanged()
	refreshTeamState()
	rebuildTrackedUnits()
	catalogBuilt = false
	markDataDirty(true)
end

function widget:ViewResize(viewSizeX, viewSizeY)
	local viewport = {
		width = safeNumber(viewSizeX, 0),
		height = safeNumber(viewSizeY, 0),
	}
	if viewport.width <= 0 or viewport.height <= 0 then
		viewport = currentViewport()
	end
	if clampWindowStateToViewport(viewport) then
		updateDocumentPosition()
		spSetConfigString(configKey('Position'), widgetPosX .. ',' .. widgetPosY)
		spSetConfigString(configKey('Size'), widgetWidth .. ',' .. widgetHeight)
	end
end

function widget:Shutdown()
	saveKnowledge()
	if widget.rmlContext and dm_handle then
		widget.rmlContext:RemoveDataModel(MODEL_NAME)
		dm_handle = nil
	end
	if document then
		document:Close()
		document = nil
	end
	widget.rmlContext = nil
end

--------------------------------------------------------------------------------
-- RML events
--------------------------------------------------------------------------------

function widget:CloseWidget()
	Spring.SendCommands('luaui disablewidget ' .. WIDGET_NAME)
end

function widget:OnDragEnd()
	savePositionAndSize()
end

function widget:SetTab(event)
	local element = event and event.current_element
	local tab = element and element:GetAttribute('data-tab')
	if tab == 'units' or tab == 'teams' then
		if activeTab ~= tab then
			resetRowPage()
		end
		activeTab = tab
		markDataDirty(true)
		saveConfig()
	end
end

function widget:SetSort(event)
	local element = event and event.current_element
	local key = element and element:GetAttribute('data-sort')
	if not validSortKeys[key] then
		return
	end
	if sortKey == key then
		sortAscending = not sortAscending
	else
		sortKey = key
		sortAscending = defaultSortAscending[key] == true
	end
	resetRowPage()
	markDataDirty(true)
	saveConfig()
end

function widget:PrevPage()
	if rowPage <= 1 then
		return
	end
	rowPage = rowPage - 1
	markDataDirty(true)
end

function widget:NextPage()
	if rowPage >= currentPageCount then
		return
	end
	rowPage = rowPage + 1
	markDataDirty(true)
end

function widget:CycleAvailability()
	if availabilityMode == 'match' then
		availabilityMode = 'map'
	elseif availabilityMode == 'map' then
		availabilityMode = 'owned'
	elseif availabilityMode == 'owned' then
		availabilityMode = 'all'
	else
		availabilityMode = 'match'
	end
	resetRowPage()
	markDataDirty(true)
	saveConfig()
end

function widget:ToggleCostMode()
	costMode = costMode == 'full' and 'build' or 'full'
	resetRowPage()
	markDataDirty(true)
	saveConfig()
end

function widget:ToggleHistoryFilter()
	requireHistory = not requireHistory
	resetRowPage()
	markDataDirty(true)
	saveConfig()
end

local function nearestOwnUnit(matchDefIDs)
	local camX, _, camZ = spGetCameraPosition()
	camX = camX or 0
	camZ = camZ or 0
	local bestUnitID, bestDistSq
	for unitID, unit in pairs(tracker.units) do
		if matchDefIDs[unit.defID] and unit.teamID == sourceTeamID and unit.finished and unit.buildProgress >= 1 then
			local x, _, z = spGetUnitPosition(unitID)
			if x and z then
				local dist = distanceSq(camX, camZ, x, z)
				if not bestDistSq or dist < bestDistSq then
					bestUnitID, bestDistSq = unitID, dist
				end
			end
		end
	end
	return bestUnitID
end

local function jumpToUnit(unitID)
	local x, y, z = spGetUnitPosition(unitID)
	if x then
		spSetCameraTarget(x, y or 0, z, 0.5)
	end
end

local function nearestOwnBuilderOf(defID)
	local builderDefIDs = {}
	for _, builderDefID in ipairs(catalog.sourceByBuilt[defID] or {}) do
		builderDefIDs[builderDefID] = true
	end
	return nearestOwnUnit(builderDefIDs)
end

-- CMD.INSERT at position 0 with the 'alt' order option puts the build order at
-- the queue front; OPT_INTERNAL keeps it out of the repeat cycle
local function queueBuildAtBuilder(builderID, defID)
	local targetDef = UnitDefs[defID]
	if targetDef and targetDef.isBuilding then
		local bx, by, bz = spGetUnitPosition(builderID)
		local px, py, pz = spClosestBuildPos(sourceTeamID, defID, bx, by, bz, 600, 8, 0)
		if px and px >= 0 then
			spGiveOrderToUnit(builderID, CMD.INSERT, {0, -defID, CMD.OPT_INTERNAL, px, py, pz, 0}, {'alt'})
		end
	else
		spGiveOrderToUnit(builderID, CMD.INSERT, {0, -defID, CMD.OPT_INTERNAL}, {'alt'})
	end
end

-- Click a source-chain icon: jump to the nearest owned instance. Otherwise walk
-- up the build graph until an owned builder exists and queue the missing step
-- there, e.g. clicking a T2 unit with only a commander queues the T2 lab
function widget:SourceStepClick(event)
	local element = event and event.current_element
	local defID = tonumber(element and element:GetAttribute('defid'))
	if not defID then
		return
	end

	local existingID = nearestOwnUnit({[defID] = true})
	if existingID then
		jumpToUnit(existingID)
		return
	end

	local buildDefID = defID
	local visited = {[defID] = true}
	for _ = 1, 6 do
		local builderID = nearestOwnBuilderOf(buildDefID)
		if builderID then
			jumpToUnit(builderID)
			if not isSpectator then
				queueBuildAtBuilder(builderID, buildDefID)
			end
			return
		end

		local nextDefID
		for _, sourceDefID in ipairs(catalog.sourceByBuilt[buildDefID] or {}) do
			if not visited[sourceDefID] then
				nextDefID = sourceDefID
				break
			end
		end
		if not nextDefID then
			return
		end
		visited[nextDefID] = true
		buildDefID = nextDefID
	end
end

function widget:AdjustEnergy(event)
	local element = event and event.current_element
	local delta = tonumber(element and element:GetAttribute('data-delta')) or 0
	energyPerMetal = clamp(energyPerMetal + delta, 1, 500)
	resetRowPage()
	markDataDirty(true)
	saveConfig()
end

function widget:AdjustTableFont(event)
	local element = event and event.current_element
	local delta = tonumber(element and element:GetAttribute('data-delta')) or 0
	local nextScale = clampTableFontScale(tableFontScale + delta)
	if nextScale == tableFontScale then
		return
	end
	tableFontScale = nextScale
	if dm_handle then
		dm_handle.table_font_label = tableFontScaleLabel(tableFontScale)
	end
	applyTableFontScale()
	saveConfig()
end

local function isAboveElement(el, x, y)
	if not el then
		return false
	end
	local _, vsy = spGetViewGeometry()
	local mouseY = vsy - y
	return x >= el.absolute_left and x <= el.absolute_left + el.offset_width
		and mouseY >= el.absolute_top and mouseY <= el.absolute_top + el.offset_height
end

function widget:IsAbove(x, y)
	if not document then
		return false
	end
	return isAboveElement(document:GetElementById('bkp-panel'), x, y)
end
