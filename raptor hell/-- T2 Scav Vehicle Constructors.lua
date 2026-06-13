--T2 Scav Veh Con Waves

local spring = Spring
local unitSets = {
	{
		source = 'armacv',
		raptorClone = 'raptor_armacv_builder',
		scav = 'armacv_scav',
		humanName = 'Raptor Scav Advanced Vehicle Constructor',
	},
	{
		source = 'coracv',
		raptorClone = 'raptor_coracv_builder',
		scav = 'coracv_scav',
		humanName = 'Raptor Scav Advanced Vehicle Constructor',
	},
	{
		source = 'legacv',
		raptorClone = 'raptor_legacv_builder',
		scav = 'legacv_scav',
		humanName = 'Raptor Scav Advanced Vehicle Constructor',
	},
}

local spawnScale = 1
local isRaptors = spring.Utilities.Gametype.IsRaptors()
local isScavengers = spring.Utilities.Gametype.IsScavengers()

if isRaptors or isScavengers then
	spawnScale = (#spring.GetTeamList() - 2) / 12
end

local spawnCountMult = spring.GetModOptions().raptor_spawncountmult or 3
spawnScale = spawnScale * (spawnCountMult / 3)

local function scaledCount(count)
	return math.max(1, math.ceil(count * spawnScale))
end

local function customSquadParams()
	local prefix = isRaptors and 'raptor' or 'scav'

	return {
		[prefix .. 'customsquad'] = '1',
		[prefix .. 'squadunitsamount'] = 1,
		[prefix .. 'squadminanger'] = 4, -- really low while testing
		[prefix .. 'squadmaxanger'] = 1000,
		[prefix .. 'squadweight'] = 999,
		[prefix .. 'squadrarity'] = 'basic',
		[prefix .. 'squadbehavior'] = 'raider',
		[prefix .. 'squadbehaviordistance'] = 500,
		[prefix .. 'squadbehaviorchance'] = 1,
		[prefix .. 'squadsurface'] = 'land',
	}
end

local customParams = customSquadParams()

local function hasScavengerCategory(unitDef)
	return unitDef.category and string.find(unitDef.category, 'SCAVENGER')
end

local function applyScavengerTraits(unitDef, sourceName)
	unitDef.category = unitDef.category or ''
	if not hasScavengerCategory(unitDef) then
		unitDef.category = unitDef.category .. ' SCAVENGER'
	end
	unitDef.capturable = false
	unitDef.decloakonfire = true
	unitDef.hidedamage = true
	unitDef.customparams = unitDef.customparams or {}
	unitDef.customparams.fromunit = unitDef.customparams.fromunit or sourceName
	unitDef.customparams.isscavenger = true
	unitDef.customparams.healthlookmod = 0.40
end

local ensureScavengerBuildTree

local function convertBuildOptionsToScav(unitDef)
	if not unitDef.buildoptions then
		return
	end

	for index, buildOptionName in pairs(unitDef.buildoptions) do
		local scavBuildOptionName = ensureScavengerBuildTree(buildOptionName)
		if scavBuildOptionName then
			unitDef.buildoptions[index] = scavBuildOptionName
		end
	end
end

local pendingScavengerClones = {}

ensureScavengerBuildTree = function(sourceName)
	if not sourceName or string.find(sourceName, '_scav') then
		return sourceName
	end

	if string.find(sourceName, 'raptor') or string.find(sourceName, 'critter') then
		return sourceName
	end

	local sourceDef = UnitDefs[sourceName]
	if not sourceDef then
		return nil
	end

	local cloneName = sourceName .. '_scav'
	if UnitDefs[cloneName] then
		return cloneName
	end

	UnitDefs[cloneName] = table.copy(sourceDef)
	local cloneDef = UnitDefs[cloneName]
	applyScavengerTraits(cloneDef, sourceName)

	if not pendingScavengerClones[sourceName] then
		pendingScavengerClones[sourceName] = true
		convertBuildOptionsToScav(cloneDef)
		pendingScavengerClones[sourceName] = nil
	end

	return cloneName
end

local function appendUnitName(unitNames, unitName)
	unitNames[#unitNames + 1] = unitName
end

local targetUnits = {}
for _, unitSet in ipairs(unitSets) do
	if isRaptors then
		appendUnitName(targetUnits, unitSet.raptorClone)
	else
		appendUnitName(targetUnits, unitSet.scav)
	end
end

local function cloneUnitDef(sourceName, cloneName, humanName)
	local sourceDef = UnitDefs[sourceName]
	if not sourceDef or UnitDefs[cloneName] then
		return
	end

	UnitDefs[cloneName] = table.copy(sourceDef)
	local cloneDef = UnitDefs[cloneName]
	cloneDef.name = humanName
	cloneDef.description = sourceDef.description
	cloneDef.icontype = sourceDef.icontype
	cloneDef.customparams = cloneDef.customparams or {}
	cloneDef.customparams.fromunit = sourceName
	convertBuildOptionsToScav(cloneDef)
end

if isRaptors then
	for _, unitSet in ipairs(unitSets) do
		cloneUnitDef(unitSet.source, unitSet.raptorClone, unitSet.humanName)
	end
end

local function isTargetUnit(unitName)
	for _, targetUnitName in ipairs(targetUnits) do
		if unitName == targetUnitName then
			return true
		end
	end
	return false
end

local function applyConstructorWaveParams(unitDef)
	if not isRaptors then
		applyScavengerTraits(unitDef)
	end
	unitDef.maxthisunit = scaledCount(10)
	unitDef.customparams = unitDef.customparams or {}

	for key, value in pairs(customParams) do
		unitDef.customparams[key] = value
	end
end

local oldUnitDef_Post = UnitDef_Post

function UnitDef_Post(unitName, unitDef)
	if oldUnitDef_Post and oldUnitDef_Post ~= UnitDef_Post then
		oldUnitDef_Post(unitName, unitDef)
	end

	if unitDef and isTargetUnit(unitName) then
		applyConstructorWaveParams(unitDef)
	end
end
