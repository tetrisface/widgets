--T2 Scav Veh Con Waves

local spring = Spring
local targetUnits = {
	'armacv_scav',
	'coracv_scav',
	'legacv_scav',
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
		[prefix .. 'squadminanger'] = 45,
		[prefix .. 'squadmaxanger'] = 1000,
		[prefix .. 'squadweight'] = 2,
		[prefix .. 'squadrarity'] = 'basic',
		[prefix .. 'squadbehavior'] = 'healer',
		[prefix .. 'squadbehaviordistance'] = 500,
		[prefix .. 'squadbehaviorchance'] = 1,
		[prefix .. 'squadsurface'] = 'land',
	}
end

local customParams = customSquadParams()

local function isTargetUnit(unitName)
	for _, targetUnitName in ipairs(targetUnits) do
		if unitName == targetUnitName then
			return true
		end
	end
	return false
end

local function applyConstructorWaveParams(unitDef)
	unitDef.maxthisunit = scaledCount(1)
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
