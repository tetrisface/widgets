local ReplacementPolicy = {}

local factionPrefixes = {
	arm = true,
	cor = true,
	leg = true,
}

local protectedEvolvingFamilies = {
	evfus = true,
	evconv = true,
	evnano = true,
}

function ReplacementPolicy.isProtectedEvolvingUnitName(unitName)
	if type(unitName) ~= 'string' then
		return false
	end

	local faction = unitName:sub(1, 3)
	if not factionPrefixes[faction] then
		return false
	end

	local family, level = unitName:sub(4):match('^(%a+)(%d+)$')
	return protectedEvolvingFamilies[family] == true and tonumber(level) >= 1
end

return ReplacementPolicy
