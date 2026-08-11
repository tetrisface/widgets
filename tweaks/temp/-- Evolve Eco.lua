-- Evolve Eco
local UnitDefs = UnitDefs or {}
local baseFusions = { arm = 'armafust3', cor = 'corafust3', leg = 'legafust3' }
local baseConverters = { arm = 'armmmkrt3', cor = 'cormmkrt3', leg = 'legadveconvt3' }
local function rep(c, n)
	return string.rep(c, n)
end
local function block(seq, times)
	local str = ''
	for _, v in ipairs(seq) do
		str = str .. rep(v[1], v[2])
	end
	return string.rep(str, times or 1)
end
local s = string.rep
local fusionyardmaps = {
	[1] = 'h cbsbossosoboobosossobsbc' .. s('bssobobbssbsbossbbbsossb', 142) .. 'cbsbossosoboobosossobsbc',
	[2] = 'h cbsbssssssbssossssssbsbc' .. s('bsssbsbbssbsosssobbssssb', 142) .. 'cbsbssssssbssossssssbsbc',
	[3] = 'h cbsbssssssosssssssssbsbc' .. s('bsssbsoossbssssssobssssb', 142) .. 'cbsbssssssosssssssssbsbc',
	[4] = 'h cosbssssssssssssssssbsbc' .. s('bsssosssssbsssssssbssssb', 142) .. 'cosbssssssssssssssssbsbc',
	[5] = 'h cssossssssssssssssssbsbc' .. s('bsssssssssosssssssbssssb', 142) .. 'cssossssssssssssssssbsbc',
	[6] = 'h csssssssssssssssssssosbc' .. s('bsssssssssssssssssossssb', 142) .. 'csssssssssssssssssssosbc',
}
local mmkrtyardmaps = {
	[1] = 'h cobobbsbobbc' .. s('bbbssbobsbbb', 270) .. 'cobobbsbobbc',
	[2] = 'h csbsobsosbbc' .. s('obbssbsbsbbb', 270) .. 'csbsobsosbbc',
	[3] = 'h csbssbsssboc' .. s('sbbssosbsbbb', 270) .. 'csbssbsssboc',
	[4] = 'h csossbsssbsc' .. s('sbbssssbsbob', 270) .. 'csossbsssbsc',
	[5] = 'h cssssosssbsc' .. s('sbossssbsosb', 270) .. 'cssssosssbsc',
	[6] = 'h cssssssssosc' .. s('sosssssossso', 270) .. 'cssssssssosc',
}
local NewFusions = {}
local NewConverters = {}
for faction, baseFusion in pairs(baseFusions) do
	for i = 1, 6 do
		local unitName = faction .. 'evfus' .. i
		NewFusions[unitName] = {
			name = faction:upper() .. ' Evolve Fusion Reactor ' .. i,
			description = 'Upgradeable Fusion Reactor ' .. i,
			footprintx = 24,
			footprintz = 36,
			collisionvolumescales = '384 192 576',
			yardmap = fusionyardmaps[i],
			customparams = { i18n_en_humanname = 'Evolve Fusion Reactor ' .. i, i18n_en_tooltip = 'Fusion Level ' .. i .. ' Produce ' .. (i * 30000) .. ' Energy', geothermal = 1 },
		}
	end
end
for faction, baseConverter in pairs(baseConverters) do
	for i = 1, 6 do
		local unitName = faction .. 'mmkrt3' .. i
		NewConverters[unitName] = {
			name = faction:upper() .. ' Evolve Energy Converter ' .. i,
			description = 'Upgradeable Energy Converter ' .. i,
			footprintx = 12,
			footprintz = 18,
			collisionvolumescales = '213 60 320',
			collisionvolumetype = 'CylY',
			yardmap = mmkrtyardmaps[i],
			customparams = {
				i18n_en_humanname = 'Evolve Energy Converter ' .. i,
				i18n_en_tooltip = 'Converts ' .. (i * 6000) .. ' energy into ' .. (i * 120) .. ' metal per sec(Hazardous)',
				geothermal = 1,
			},
		}
	end
end
for faction, baseFusion in pairs(baseFusions) do
	if UnitDefs[baseFusion] then
		local basefus = UnitDefs[baseFusion]
		for i = 1, 6 do
			local f = NewFusions[faction .. 'evfus' .. i]
			if f then
				f.metalcost = basefus.metalcost * i
				f.energycost = basefus.energycost * i
				f.energymake = basefus.energymake * i
				f.energystorage = basefus.energystorage * i
				f.buildtime = basefus.buildtime * i
				if not UnitDefs[faction .. 'evfus' .. i] then
					UnitDefs[faction .. 'evfus' .. i] = table.merge(basefus, f)
					UnitDefs[faction .. 'evfus' .. i].customparams = UnitDefs[faction .. 'evfus' .. i].customparams or {}
				end
			end
		end
	end
end
for faction, baseConverter in pairs(baseConverters) do
	if UnitDefs[baseConverter] then
		local basemmkrt3 = UnitDefs[baseConverter]
		for i = 1, 6 do
			local c = NewConverters[faction .. 'mmkrt3' .. i]
			if c then
				c.metalcost = basemmkrt3.metalcost * i
				c.energycost = basemmkrt3.energycost * i
				c.buildtime = basemmkrt3.buildtime * i
				c.customparams.energyconv_capacity = basemmkrt3.customparams.energyconv_capacity * i
				if not UnitDefs[faction .. 'mmkrt3' .. i] then
					UnitDefs[faction .. 'mmkrt3' .. i] = table.merge(basemmkrt3, c)
					UnitDefs[faction .. 'mmkrt3' .. i].customparams = UnitDefs[faction .. 'mmkrt3' .. i].customparams or {}
				end
			end
		end
	end
end
local builders =
	{ arm = { 'armaca', 'armack', 'armacsub', 'armacv' }, cor = { 'coraca', 'corack', 'coracsub', 'coracv' }, leg = { 'legaca', 'legack', 'legacv', 'legcomt2com' } }
local function addBuildOption(unitDef, option)
	for _, existing in ipairs(unitDef.buildoptions) do
		if existing == option then
			return
		end
	end
	table.insert(unitDef.buildoptions, option)
end
for faction, blds in pairs(builders) do
	for _, builder in ipairs(blds) do
		local unitDef = UnitDefs[builder]
		if unitDef and unitDef.buildoptions then
			for i = 1, 6 do
				addBuildOption(unitDef, faction .. 'evfus' .. i)
				addBuildOption(unitDef, faction .. 'mmkrt3' .. i)
			end
		end
	end
end
