--t3 eco no explodeas
-- SCAV_HP_1_3X_START

local originalUnitDef_Post = UnitDef_Post
function UnitDef_Post(unitName, unitDef)
  originalUnitDef_Post(unitName, unitDef)
  if unitDef.health and unitName:match('_scav$') and not unitName:match('^scavengerbossv4') then
    unitDef.health = math.floor(unitDef.health * 1.3)
  end
  if unitName:match('_scav$') then
    if unitDef.metalcost and type(unitDef.metalcost) == 'number' then
      unitDef.metalcost = math.floor(unitDef.metalcost * 1.3)
    end
    unitDef.nochasecategory = 'OBJECT'
  end
end

-- SCAV_HP_1_3X_END

-- SCAV_HP_1_3X_START

local originalUnitDef_Post = UnitDef_Post
function UnitDef_Post(unitName, unitDef)
  originalUnitDef_Post(unitName, unitDef)
  if unitDef.health and unitName:match('^scavengerbossv4') then
    unitDef.health = math.floor(unitDef.health * 1.3)
  end
end

-- SCAV_HP_1_3X_END

-- T3_BUILDERS_START

do
  local a, b, c, d, e, f, g =
    UnitDefs or {},
    {'arm', 'cor', 'leg'},
    table.merge,
    {arm = 'Armada ', cor = 'Cortex ', leg = 'Legion '},
    '_taxed',
    1.5,
    table.contains
  local function h(i, j, k)
    if a[i] and not a[j] then
      a[j] = c(a[i], k)
    end
  end
  for l, m in pairs(b) do
    local n, o, p = m == 'arm', m == 'cor', m == 'leg'
    h(
      m .. 'nanotct2',
      m .. 'nanotct3',
      {
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
        objectname = p and 'Units/legnanotcbase.s3o' or o and 'Units/CORRESPAWN.s3o' or 'Units/ARMRESPAWN.s3o',
        customparams = {
          i18n_en_humanname = 'T3 Construction Turret',
          i18n_en_tooltip = 'More BUILDPOWER! For the connoisseur'
        }
      }
    )
    h(
      p and 'legamstor' or m .. 'uwadvms',
      p and 'legamstort3' or m .. 'uwadvmst3',
      {
        metalstorage = 30000,
        metalcost = 4200,
        energycost = 231150,
        buildtime = 142800,
        health = 53560,
        maxthisunit = 10,
        icontype = 'armuwadves',
        name = d[m] .. 'T3 Metal Storage',
        customparams = {
          i18n_en_humanname = 'T3 Hardened Metal Storage',
          i18n_en_tooltip = [[The big metal storage tank for your most precious resources.Chopped chicken!]]
        }
      }
    )
    h(
      p and 'legadvestore' or m .. 'uwadves',
      p and 'legadvestoret3' or m .. 'advestoret3',
      {
        energystorage = 272000,
        metalcost = 2100,
        energycost = 59000,
        buildtime = 93380,
        health = 49140,
        icontype = 'armuwadves',
        maxthisunit = 10,
        name = d[m] .. 'T3 Energy Storage',
        customparams = {
          i18n_en_humanname = 'T3 Hardened Energy Storage',
          i18n_en_tooltip = 'Power! Power! We need power!1!'
        }
      }
    )
    for l, q in pairs({m .. 'nanotc', m .. 'nanotct2'}) do
      if a[q] then
        a[q].canrepeat = true
      end
    end
    local r = n and 'armshltx' or o and 'corgant' or 'leggant'
    local s = a[r]
    h(
      r,
      r .. e,
      {
        energycost = s.energycost * f,
        icontype = r,
        metalcost = s.metalcost * f,
        name = d[m] .. 'Experimental Gantry Taxed',
        customparams = {
          i18n_en_humanname = d[m] .. 'Experimental Gantry Taxed',
          i18n_en_tooltip = 'Produces Experimental Units'
        }
      }
    )
    local t, u = {},
      {
        m .. 'nanotct2',
        m .. 'nanotct3',
        m .. 'alab',
        m .. 'avp',
        m .. 'aap',
        m .. 'gatet3',
        m .. 'flak',
        p and 'legdeflector' or m .. 'gate',
        p and 'legforti' or m .. 'fort',
        n and 'armshltx' or m .. 'gant'
      }
    for l, v in ipairs(u) do
      t[#t + 1] = v
    end
    local w = {arm = {'corgant', 'leggant'}, cor = {'armshltx', 'leggant'}, leg = {'armshltx', 'corgant'}}
    for l, x in ipairs(w[m] or {}) do
      t[#t + 1] = x .. e
    end
    local y = {
      arm = {'armamd', 'armmercury', 'armbrtha', 'armminivulc', 'armvulc', 'armannit3', 'armlwall', 'armannit4'},
      cor = {
        'corfmd',
        'corscreamer',
        'cordoomt3',
        'corbuzz',
        'corminibuzz',
        'corint',
        'corhllllt',
        'cormwall',
        'cordoomt4',
        'epic_calamity'
      },
      leg = {
        'legabm',
        'legstarfall',
        'legministarfall',
        'leglraa',
        'legbastion',
        'legrwall',
        'leglrpc',
        'legbastiont4',
        'legdtf'
      }
    }
    for l, v in ipairs(y[m] or {}) do
      t[#t + 1] = v
    end
    local j = m .. 't3aide'
    h(
      m .. 'decom',
      j,
      {
        blocking = true,
        builddistance = 350,
        buildtime = 140000,
        energycost = 200000,
        energyupkeep = 2000,
        health = 10000,
        idleautoheal = 5,
        idletime = 1800,
        maxthisunit = 9999,
        metalcost = 12600,
        speed = 85,
        terraformspeed = 3000,
        turninplaceanglelimit = 1.890,
        turnrate = 1240,
        workertime = 6000,
        reclaimable = true,
        candgun = false,
        name = d[m] .. 'Epic Aide',
        customparams = {
          subfolder = 'ArmBots/T3',
          techlevel = 3,
          unitgroup = 'buildert3',
          i18n_en_humanname = 'Epic Ground Construction Aide',
          i18n_en_tooltip = 'Your Aide that helps you construct buildings x9999 Max'
        },
        buildoptions = t
      }
    )
    a[j].weapondefs = {}
    a[j].weapons = {}
    j = m .. 't3airaide'
    h(
      'armfify',
      j,
      {
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
        maxthisunit = 9999,
        metalcost = 13400,
        speed = 25,
        category = 'OBJECT',
        terraformspeed = 3000,
        turninplaceanglelimit = 1.890,
        turnrate = 1240,
        workertime = 1600,
        buildpic = 'ARMFIFY.DDS',
        name = d[m] .. 'Epic Aide',
        customparams = {
          is_builder = true,
          subfolder = 'ArmBots/T3',
          techlevel = 3,
          unitgroup = 'buildert3',
          i18n_en_humanname = 'Epic Air Construction Aide',
          i18n_en_tooltip = 'Your Aide that helps you construct buildings x9999 Max'
        },
        buildoptions = t
      }
    )
    a[j].weapondefs = {}
    a[j].weapons = {}
    local z = n and 'armshltx' or o and 'corgant' or 'leggant'
    if a[z] and a[z].buildoptions then
      local A = m .. 't3aide'
      if not g(a[z].buildoptions, A) then
        table.insert(a[z].buildoptions, A)
      end
    end
    z = m .. 'apt3'
    if a[z] and a[z].buildoptions then
      local B = m .. 't3airaide'
      if not g(a[z].buildoptions, B) then
        table.insert(a[z].buildoptions, B)
      end
    end
  end
end

-- T3_BUILDERS_END

-- CROSS_FACTION_START

do
  local unitDefs, taxMultiplier, tierTwoFactories, taxedDefs, language, suffix, labelSuffix =
    UnitDefs or {},
    1.7,
    {},
    {},
    Json.decode(VFS.LoadFile('language/en/units.json')),
    '_taxed',
    ' (Taxed)'
  local function ensureBuildOption(builderName, optionName, optionSource)
    local builder = unitDefs[builderName]
    local optionDef = optionSource and optionSource[optionName] or unitDefs[optionName]
    if not builder or not optionDef or not optionName then
      return
    end
    builder.buildoptions = builder.buildoptions or {}
    for i = 1, #builder.buildoptions do
      if builder.buildoptions[i] == optionName then
        return
      end
    end
    builder.buildoptions[#builder.buildoptions + 1] = optionName
  end
  for unitName, def in pairs(unitDefs) do
    if
      def.customparams and def.customparams.subfolder and
        (def.customparams.subfolder:match 'Fact' or def.customparams.subfolder:match 'Lab') and
        def.customparams.techlevel == 2
     then
      local humanName = language and language.units.names[unitName] or unitName
      tierTwoFactories[unitName] = true
      taxedDefs[unitName .. suffix] =
        table.merge(
        def,
        {
          energycost = def.energycost * taxMultiplier,
          icontype = unitName,
          metalcost = def.metalcost * taxMultiplier,
          name = humanName .. labelSuffix,
          customparams = {
            i18n_en_humanname = humanName .. labelSuffix,
            i18n_en_tooltip = language and language.units.descriptions[unitName] or unitName
          }
        }
      )
    end
  end
  for builderName, builder in pairs(unitDefs) do
    if builder.buildoptions then
      for _, optionName in pairs(builder.buildoptions) do
        if tierTwoFactories[optionName] then
          for _, factionPrefix in pairs {'arm', 'cor', 'leg'} do
            local taxedName = factionPrefix .. optionName:sub(4) .. suffix
            if optionName:sub(1, 3) ~= factionPrefix and taxedDefs[taxedName] then
              ensureBuildOption(builderName, taxedName, taxedDefs)
            end
          end
        end
      end
    end
  end
  table.mergeInPlace(unitDefs, taxedDefs)
end

-- CROSS_FACTION_END

-- T3_ECO_START

do
  local a, b =
    UnitDefs or {},
    {'armack', 'armaca', 'armacv', 'corack', 'coraca', 'coracv', 'legack', 'legaca', 'legacv'}
  local function ensureBuildOption(builderName, optionName)
    local builder = a[builderName]
    local optionDef = optionName and a[optionName]
    if not builder or not optionDef then
      return
    end
    builder.buildoptions = builder.buildoptions or {}
    for i = 1, #builder.buildoptions do
      if builder.buildoptions[i] == optionName then
        return
      end
    end
    builder.buildoptions[#builder.buildoptions + 1] = optionName
  end
  for _, defName in pairs({'armmmkrt3', 'cormmkrt3', 'legadveconvt3'}) do
    table.mergeInPlace(
      a[defName],
      {footprintx = 6, footprintz = 6, explodeas = 'nanoboom', selfdestructas = 'nanoboom'}
    )
  end
  for _, defName in pairs({'armafust3', 'corafust3', 'legafust3'}) do
    if a[defName] then
      table.mergeInPlace(a[defName], {explodeas = 'nanoboom', selfdestructas = 'nanoboom'})
    end
  end
  for _, builderName in pairs(b) do
    local prefix = builderName:sub(1, 3)
    ensureBuildOption(builderName, prefix .. 'afust3')
    ensureBuildOption(builderName, prefix == 'leg' and 'legadveconvt3' or prefix .. 'mmkrt3')
  end
  for _, prefix in pairs({'arm', 'cor', 'leg'}) do
    local groundBuilder = prefix .. 't3aide'
    local airBuilder = prefix .. 't3airaide'
    local ecoOptions = {
      prefix .. 'afust3',
      prefix == 'leg' and 'legadveconvt3' or prefix .. 'mmkrt3',
      prefix == 'leg' and 'legamstort3' or prefix .. 'uwadvmst3',
      prefix == 'leg' and 'legadvestoret3' or prefix .. 'advestoret3'
    }
    for _, optionName in ipairs(ecoOptions) do
      ensureBuildOption(groundBuilder, optionName)
      ensureBuildOption(airBuilder, optionName)
    end
  end
  ensureBuildOption('legck', 'legdtf')
  for _, defName in pairs({'coruwadves', 'legadvestore'}) do
    table.mergeInPlace(a[defName], {footprintx = 4, footprintz = 4})
  end
end

-- T3_ECO_END
