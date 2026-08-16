local ReplacementPolicy = {}

local factionPrefixes = {
	arm = true,
	cor = true,
	leg = true,
}

local protectedEvolvingFamilies = {
	evfus = true,
	evconv = true,
	evnano = false,
}

-- Units defined by external tweaks have no stable unitdef name, so they are
-- matched by display name (UnitDef.translatedHumanName) instead.
local protectedHumanNames = {
	['Base Builder'] = true,
}

local function evolvingUnitParts(unitName)
	if type(unitName) ~= 'string' then
		return nil, nil
	end

	local faction = unitName:sub(1, 3)
	if not factionPrefixes[faction] then
		return nil, nil
	end

	local family, level = unitName:sub(4):match('^(%a+)(%d+)$')
	level = tonumber(level)
	if not level or level < 1 then
		return nil, nil
	end

	return family, level
end

function ReplacementPolicy.isProtectedEvolvingUnitName(unitName)
	local family, level = evolvingUnitParts(unitName)
	return level ~= nil and protectedEvolvingFamilies[family] == true
end

function ReplacementPolicy.isProtectedHumanName(humanName)
	return humanName ~= nil and protectedHumanNames[humanName] == true
end

-- Returns nil when this is not an evnano-to-evnano replacement. Otherwise,
-- returns the directional decision shared by all faction combinations.
function ReplacementPolicy.getEvolvingNanoReplacementDecision(existingUnitName, placingUnitName)
	local existingFamily, existingLevel = evolvingUnitParts(existingUnitName)
	local placingFamily, placingLevel = evolvingUnitParts(placingUnitName)
	if existingFamily ~= 'evnano' or placingFamily ~= 'evnano' then
		return nil
	end

	return placingLevel > existingLevel
end

return ReplacementPolicy
