--40lim-T3ConsTaxed-T3Def-MiniBosses-LRPC.Rebalance
-- Source: ["lua/builders-t3.lua","lua/defences-t3.lua","lua/mini-bosses.lua","lua/lrpc-rebalance.lua"]
do
	local a, b, c, d, e, f, g = UnitDefs or {}, { 'arm', 'cor', 'leg' }, table.merge, { arm = 'Armada ', cor = 'Cortex ', leg = 'Legion ' }, '_taxed', 1.5, table.contains
	local function h(b, d, e)
		if a[b] and not a[d] then
			a[d] = c(a[b], e)
		end
	end
	for b, b in pairs(b) do
		local c, i, j = b == 'arm', b == 'cor', b == 'leg'
		h(b .. 'nanotct2', b .. 'nanotct3', {
			metalcost = 3700,
			energycost = 62000,
			builddistance = 550,
			buildtime = 108000,
			collisionvolumescales = '61 128 61',
			footprintx = 6,
			footprintz = 6,
			health = 8800,
			mass = 37200,
			sightdistance = 575,
			workertime = 1900,
			icontype = 'armnanotct2',
			canrepeat = true,
			objectname = j and 'Units/legnanotcbase.s3o' or i and 'Units/CORRESPAWN.s3o' or 'Units/ARMRESPAWN.s3o',
			customparams = { i18n_en_humanname = 'T3 Construction Turret', i18n_en_tooltip = 'More BUILDPOWER! For the connoisseur' },
		})
		h(j and 'legamstor' or b .. 'uwadvms', j and 'legamstort3' or b .. 'uwadvmst3', {
			metalstorage = 30000,
			metalcost = 4200,
			energycost = 231150,
			buildtime = 142800,
			health = 53560,
			icontype = 'armuwadves',
			name = d[b] .. 'T3 Metal Storage',
			customparams = {
				i18n_en_humanname = 'T3 Hardened Metal Storage',
				i18n_en_tooltip = 'The big metal storage tank for your most precious resources. Chopped chicken!',
			},
		})
		h(j and 'legadvestore' or b .. 'uwadves', j and 'legadvestoret3' or b .. 'advestoret3', {
			energystorage = 272000,
			metalcost = 2100,
			energycost = 59000,
			buildtime = 93380,
			health = 49140,
			icontype = 'armuwadves',
			name = d[b] .. 'T3 Energy Storage',
			customparams = { i18n_en_humanname = 'T3 Hardened Energy Storage', i18n_en_tooltip = 'Power! Power! We need power!1!' },
		})
		for b, b in pairs({ b .. 'nanotc', b .. 'nanotct2' }) do
			if a[b] then
				a[b].canrepeat = true
			end
		end
		local i = c and 'armshltx' or i and 'corgant' or 'leggant'
		local k = a[i]
		h(i, i .. e, {
			energycost = k.energycost * f,
			icontype = i,
			metalcost = k.metalcost * f,
			name = d[b] .. 'Experimental Gantry Taxed',
			customparams = { i18n_en_humanname = d[b] .. 'Experimental Gantry Taxed', i18n_en_tooltip = 'Produces Experimental Units' },
		})
		local c = {
			b .. 'afust3',
			b .. 'nanotct2',
			b .. 'nanotct3',
			b .. 'alab',
			b .. 'avp',
			b .. 'aap',
			b .. 'gatet3',
			b .. 'flak',
			j and 'legadveconvt3' or b .. 'mmkrt3',
			j and 'legamstort3' or b .. 'uwadvmst3',
			j and 'legadvestoret3' or b .. 'advestoret3',
			j and 'legdeflector' or b .. 'gate',
			j and 'legforti' or b .. 'fort',
			c and 'armshltx' or b .. 'gant',
		}
		local f = { arm = { 'corgant', 'leggant' }, cor = { 'armshltx', 'leggant' }, leg = { 'armshltx', 'corgant' } }
		for a, a in ipairs(f[b] or {}) do
			c[#c + 1] = a .. e
		end
		local e = {
			arm = { 'armamd', 'armmercury', 'armbrtha', 'armminivulc', 'armvulc', 'armanni', 'armannit3', 'armlwall', 'armannit4' },
			cor = { 'corfmd', 'corscreamer', 'cordoomt3', 'corbuzz', 'corminibuzz', 'corint', 'cordoom', 'corhllllt', 'cormwall', 'cordoomt4' },
			leg = { 'legabm', 'legstarfall', 'legministarfall', 'leglraa', 'legbastion', 'legrwall', 'leglrpc', 'legbastiont4', 'legapopupdef', 'legdtf' },
		}
		for a, a in ipairs(e[b] or {}) do
			c[#c + 1] = a
		end
		local e = b .. 't3aide'
		h(b .. 'decom', e, {
			blocking = true,
			builddistance = 350,
			buildtime = 140000,
			energycost = 200000,
			energyupkeep = 2000,
			health = 10000,
			idleautoheal = 5,
			idletime = 1800,
			maxthisunit = 40,
			metalcost = 12600,
			speed = 85,
			terraformspeed = 3000,
			turninplaceanglelimit = 1.890,
			turnrate = 1240,
			workertime = 6000,
			reclaimable = true,
			candgun = false,
			name = d[b] .. 'T3 Aide',
			customparams = {
				subfolder = 'ArmBots/T3',
				techlevel = 3,
				unitgroup = 'buildert3',
				i18n_en_humanname = 'T3 Ground Construction Aide',
				i18n_en_tooltip = 'Your Aide that helps you construct buildings',
			},
			buildoptions = c,
		})
		a[e].weapondefs = {}
		a[e].weapons = {}
		e = b .. 't3airaide'
		h('armfify', e, {
			blocking = false,
			canassist = true,
			cruisealtitude = 3000,
			builddistance = 1750,
			buildtime = 140000,
			energycost = 200000,
			energyupkeep = 2000,
			health = 1100,
			idleautoheal = 5,
			idletime = 1800,
			icontype = 'armnanotct2',
			maxthisunit = 40,
			metalcost = 13400,
			speed = 25,
			category = 'OBJECT',
			terraformspeed = 3000,
			turninplaceanglelimit = 1.890,
			turnrate = 1240,
			workertime = 1600,
			buildpic = 'ARMFIFY.DDS',
			name = d[b] .. 'T3 Aide',
			customparams = {
				is_builder = true,
				subfolder = 'ArmBots/T3',
				techlevel = 3,
				unitgroup = 'buildert3',
				i18n_en_humanname = 'T3 Air Construction Aide',
				i18n_en_tooltip = 'Your Aide that helps you construct buildings',
			},
			buildoptions = c,
		})
		a[e].weapondefs = {}
		a[e].weapons = {}
		local c = i
		a[c].maxthisunit = 40
		a[b .. 'apt3'].maxthisunit = 40
		if a[c] and a[c].buildoptions then
			local b = b .. 't3aide'
			if not g(a[c].buildoptions, b) then
				table.insert(a[c].buildoptions, b)
			end
		end
		c = b .. 'apt3'
		if a[c] and a[c].buildoptions then
			local b = b .. 't3airaide'
			if not g(a[c].buildoptions, b) then
				table.insert(a[c].buildoptions, b)
			end
		end
	end
end
do
	local a = UnitDefs or {}
	local b = { armannit3 = 'T3 Pulsar', cordoomt3 = 'T3 Bulwark', legbastion = 'T3 Bastion' }
	for b, c in pairs(b) do
		local a = a[b]
		if a then
			a.name = c
			a.customparams = a.customparams or {}
			a.customparams.i18n_en_humanname = c
		end
	end
end
do
	local a, b, c, d, e, f = UnitDefs or {}, table.merge, table.copy, 'raptor_matriarch_basic', 'customfusionexplo', Spring
	local g = a[d].health / 60000
	local h = a['raptor_queen_epic'].health / 1250000
	local i = 1
	local j = f.Utilities.Gametype.IsRaptors()
	if j or f.Utilities.Gametype.IsScavengers() then
		i = (#f.GetTeamList() - 2) / 12
	end
	local k = f.GetModOptions().raptor_spawncountmult or 3
	local i = i * (k / 3)
	local function k(a)
		return math.max(1, math.ceil(a * i))
	end
	local i = { 70, 85, 90, 105, 110, 125 }
	local l = math.max(1, f.GetModOptions().raptor_queentimemult or 1.3)
	local m, n = i[1], i[#i]
	local o = l * i[#i] / 1.3
	local n = (o - m) / (n - m)
	for a = 2, #i do
		i[a] = math.floor(m + (i[a] - m) * n)
	end
	local f = f.GetModOptions().raptor_queen_count or 1
	local h = math.min(10, h / 1.3 * 0.9)
	local m = 40
	local n = 20
	local o = 10 * (1.06 ^ math.max(0, math.min(f, n) - 8))
	local n = math.max(0, f - n)
	local n = (n <= 80) and (0.6 * n - n * n / 270) or (24.3 + (n - 80) * 0.15)
	local n = o + n
	local h = math.ceil(h * n)
	local h = l * 100 + h + m
	local f = math.max(3, k(math.floor((21 * f + 36) / 19)))
	local function l(c, d, e)
		if a[c] and not a[d] then
			a[d] = b(a[c], e or {})
		end
	end
	local d = a[d].health
	l('raptor_queen_veryeasy', 'raptor_miniq_a', {
		name = 'Queenling Prima',
		icontype = 'raptor_queen_veryeasy',
		health = d * 5,
		customparams = { i18n_en_humanname = 'Queenling Prima', i18n_en_tooltip = 'Majestic and bold, ruler of the hunt.' },
	})
	l('raptor_queen_easy', 'raptor_miniq_b', {
		name = 'Queenling Secunda',
		icontype = 'raptor_queen_easy',
		health = d * 6,
		customparams = { i18n_en_humanname = 'Queenling Secunda', i18n_en_tooltip = 'Swift and sharp, a noble among raptors.' },
	})
	l('raptor_queen_normal', 'raptor_miniq_c', {
		name = 'Queenling Tertia',
		icontype = 'raptor_queen_normal',
		health = d * 7,
		customparams = { i18n_en_humanname = 'Queenling Tertia', i18n_en_tooltip = 'Refined tastes. Likes her prey rare.' },
	})
	a.raptor_miniq_b.weapondefs.acidgoo = c(a['raptor_matriarch_acid'].weapondefs.acidgoo)
	a.raptor_miniq_c.weapondefs.empgoo = c(a['raptor_matriarch_electric'].weapondefs.goo)
	for a, a in ipairs {
		{ 'raptor_matriarch_basic', 'raptor_mama_ba', 'Matrona', 'Claws charged with vengeance.' },
		{ 'raptor_matriarch_fire', 'raptor_mama_fi', 'Pyro Matrona', 'A firestorm of maternal wrath.' },
		{ 'raptor_matriarch_electric', 'raptor_mama_el', 'Paralyzing Matrona', 'Crackling with rage, ready to strike.' },
		{ 'raptor_matriarch_acid', 'raptor_mama_ac', 'Acid Matrona', 'Acid-fueled, melting everything in sight.' },
	} do
		l(a[1], a[2], { name = a[3], icontype = a[1], health = d * 1.5, customparams = { i18n_en_humanname = a[3], i18n_en_tooltip = a[4] } })
	end
	l('critter_penguinking', 'raptor_consort', {
		name = 'Raptor Consort',
		icontype = 'corkorg',
		health = d * 4,
		mass = 100000,
		nochasecategory = 'MOBILE VTOL OBJECT',
		sonarstealth = false,
		stealth = false,
		speed = 67.5,
		customparams = { i18n_en_humanname = 'Raptor Consort', i18n_en_tooltip = 'Sneaky powerful little terror.' },
	})
	a.raptor_consort.weapondefs.goo = c(a['raptor_queen_epic'].weapondefs.goo)
	l('raptor_consort', 'raptor_doombringer', {
		name = 'Doombringer',
		icontype = 'armafust3',
		health = d * 12,
		speed = 50,
		customparams = { i18n_en_humanname = 'Doombringer', i18n_en_tooltip = 'Your time is up. The Queens called for backup.' },
	})
	local function c(a, b, c, d, e, f)
		local g = j and 'raptor' or 'scav'
		return {
			[g .. 'customsquad'] = true,
			[g .. 'squadunitsamount'] = e or 1,
			[g .. 'squadminanger'] = a,
			[g .. 'squadmaxanger'] = b,
			[g .. 'squadweight'] = f or 5,
			[g .. 'squadrarity'] = d or 'basic',
			[g .. 'squadbehavior'] = c,
			[g .. 'squadbehaviordistance'] = 500,
			[g .. 'squadbehaviorchance'] = 0.75,
		}
	end
	local d = { selfdestructas = e, explodeas = e, weapondefs = { yellow_missile = { damage = { default = 1, vtol = 1000 } } } }
	for b, c in pairs {
		raptor_miniq_a = b(
			d,
			{ maxthisunit = k(2), customparams = c(i[1], i[2], 'berserk'), weapondefs = { goo = { damage = { default = 750 } }, melee = { damage = { default = 4000 } } } }
		),
		raptor_miniq_b = b(d, {
			maxthisunit = k(3),
			customparams = c(i[3], i[4], 'berserk'),
			weapondefs = { acidgoo = { burst = 8, reloadtime = 10, sprayangle = 4096, damage = { default = 1500, shields = 1500 } }, melee = { damage = { default = 5000 } } },
			weapons = {
				[1] = { def = 'MELEE', maindir = '0 0 1', maxangledif = 155 },
				[2] = { onlytargetcategory = 'VTOL', def = 'yellow_missile' },
				[3] = { onlytargetcategory = 'VTOL', def = 'yellow_missile' },
				[4] = { onlytargetcategory = 'VTOL', def = 'yellow_missile' },
				[5] = { def = 'acidgoo', maindir = '0 0 1', maxangledif = 180 },
			},
		}),
		raptor_miniq_c = b(d, {
			maxthisunit = k(4),
			customparams = c(i[5], i[6], 'berserk'),
			weapondefs = { empgoo = { burst = 10, reloadtime = 10, sprayangle = 4096, damage = { default = 2000, shields = 2000 } }, melee = { damage = { default = 6000 } } },
			weapons = {
				[1] = { def = 'MELEE', maindir = '0 0 1', maxangledif = 155 },
				[2] = { onlytargetcategory = 'VTOL', def = 'yellow_missile' },
				[3] = { onlytargetcategory = 'VTOL', def = 'yellow_missile' },
				[4] = { onlytargetcategory = 'VTOL', def = 'yellow_missile' },
				[5] = { def = 'empgoo', maindir = '0 0 1', maxangledif = 180 },
			},
		}),
		raptor_consort = {
			explodeas = 'raptor_empdeath_big',
			maxthisunit = k(6),
			customparams = c(i[2], 1000, 'berserk'),
			weapondefs = {
				eyelaser = { name = 'Angry Eyes', reloadtime = 3, rgbcolor = '1 0 0.3', range = 500, damage = { default = 6000, commanders = 6000 } },
				goo = {
					name = 'Snowball Barrage',
					soundstart = 'penbray2',
					soundStartVolume = 2,
					cegtag = 'blob_trail_blue',
					burst = 8,
					sprayangle = 2048,
					weaponvelocity = 600,
					reloadtime = 4,
					range = 1000,
					hightrajectory = 1,
					rgbcolor = '0.7 0.85 1.0',
					damage = { default = 1000 },
				},
			},
			weapons = {
				[1] = { def = 'eyelaser', badtargetcategory = 'VTOL OBJECT' },
				[2] = { def = 'goo', maindir = '0 0 1', maxangledif = 180, badtargetcategory = 'VTOL OBJECT' },
			},
		},
		raptor_doombringer = {
			explodeas = 'ScavComBossExplo',
			maxthisunit = f,
			customparams = c(h, 1000, 'berserk', nil, 1, 99),
			weapondefs = {
				eyelaser = { name = 'Eyes of Doom', reloadtime = 3, rgbcolor = '0.3 1 0', range = 500, damage = { default = 48000, commanders = 24000 } },
				goo = {
					name = 'Amber Hailstorm',
					soundstart = 'penbray1',
					soundStartVolume = 2,
					cegtag = 'blob_trail_red',
					burst = 15,
					sprayangle = 3072,
					weaponvelocity = 600,
					reloadtime = 5,
					rgbcolor = '0.7 0.85 1.0',
					hightrajectory = 1,
					damage = { default = 5000 },
				},
			},
			weapons = {
				[1] = { def = 'eyelaser', badtargetcategory = 'VTOL OBJECT' },
				[2] = { def = 'goo', maindir = '0 0 1', maxangledif = 180, badtargetcategory = 'VTOL OBJECT' },
			},
		},
		raptor_mama_ba = {
			maxthisunit = k(4),
			customparams = c(55, i[3] - 1, 'berserk'),
			weapondefs = { goo = { damage = { default = 750 } }, melee = {
				damage = { default = 750 },
			} },
		},
		raptor_mama_fi = {
			explodeas = 'raptor_empdeath_big',
			maxthisunit = k(4),
			customparams = c(55, i[3] - 1, 'berserk'),
			weapondefs = { flamethrowerspike = { damage = { default = 80 } }, flamethrowermain = { damage = { default = 160 } } },
		},
		raptor_mama_el = { maxthisunit = k(4), customparams = c(65, 1000, 'berserk') },
		raptor_mama_ac = { maxthisunit = k(4), customparams = c(60, 1000, 'berserk'), weapondefs = { melee = { damage = { default = 750 } } } },
		raptor_land_assault_basic_t4_v2 = { maxthisunit = k(8), customparams = c(33, 50, 'raider') },
		raptor_land_assault_basic_t4_v1 = { maxthisunit = k(12), customparams = c(51, 64, 'raider', 'basic', 2) },
	} do
		a[b] = a[b] or {}
		table.mergeInPlace(a[b], c, true)
	end
	local a = { raptor_mama_ba = 36000, raptor_mama_fi = 36000, raptor_mama_el = 36000, raptor_mama_ac = 36000, raptor_consort = 45000, raptor_doombringer = 90000 }
	local b = UnitDef_Post
	function UnitDef_Post(c, d)
		if b then
			b(c, d)
		end
		local b = 1
		if g > 1.3 then
			b = g / 1.3
		end
		for a, c in pairs(a) do
			if UnitDefs[a] then
				local b = math.floor(c * b)
				UnitDefs[a].metalcost = b
			end
		end
	end
end
do
	local a = UnitDefs or {}
	if a.armbrtha then
		table.mergeInPlace(a.armbrtha, {
			health = 13000,
			weapondefs = {
				ARMBRTHA_MAIN = { damage = { commanders = 480, default = 33000 }, areaofeffect = 60, energypershot = 8000, range = 2400, reloadtime = 9, turnrate = 20000 },
			},
		})
	end
	if a.corint then
		table.mergeInPlace(a.corint, {
			health = 13000,
			weapondefs = {
				CORINT_MAIN = {
					damage = { commanders = 480, default = 85000 },
					areaofeffect = 230,
					edgeeffectiveness = 0.6,
					energypershot = 15000,
					range = 2700,
					reloadtime = 18,
				},
			},
		})
	end
	if a.leglrpc then
		table.mergeInPlace(a.leglrpc, {
			health = 13000,
			weapondefs = { LEGLRPC_MAIN = { damage = { commanders = 480, default = 4500 }, energypershot = 2000, range = 2000, reloadtime = 2, turnrate = 30000 } },
		})
	end
end
