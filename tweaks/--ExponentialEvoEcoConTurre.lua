--ExponentialEvoEcoConTurre
-- Exponential evolving economy and construction turrets
-- Author: tetrisface

do
	local unitDefs = UnitDefs or {}
	local growthPivotLevel = 15
	local earlyGrowthFactor = 1.25
	local lateGrowthFactor = 1.12
	local efficiencyGainPerLevel = 0.03

	local factions = {
		{
			prefix = 'arm',
			displayName = 'Armada',
			fusionBase = 'armafust3',
			converterBase = 'armmmkrt3',
			nanoT2Base = 'armnanotct2',
			nanoT3Base = 'armnanotct3',
			nanoObject = 'Units/ARMRESPAWN.s3o',
			builders = { 'armaca', 'armack', 'armacsub', 'armacv' },
		},
		{
			prefix = 'cor',
			displayName = 'Cortex',
			fusionBase = 'corafust3',
			converterBase = 'cormmkrt3',
			nanoT2Base = 'cornanotct2',
			nanoT3Base = 'cornanotct3',
			nanoObject = 'Units/CORRESPAWN.s3o',
			builders = { 'coraca', 'corack', 'coracsub', 'coracv' },
		},
		{
			prefix = 'leg',
			displayName = 'Legion',
			fusionBase = 'legafust3',
			converterBase = 'legadveconvt3',
			nanoT2Base = 'legnanotct2',
			nanoT3Base = 'legnanotct3',
			nanoObject = 'Units/legnanotcbase.s3o',
			builders = { 'legaca', 'legack', 'legacv', 'legcomt2com' },
		},
	}
	local familyOrder = { 'fusion', 'converter', 'nano' }
	local families = {
		fusion = {
			levelCount = 30,
			sourceKey = 'fusionBase',
			unitSuffix = 'evfus',
			displayName = 'Evo Fusion',
			footprint = 12,
			usesGeothermalUpgrade = true,
			costFields = { 'metalcost', 'energycost', 'buildtime' },
			productionFields = { 'energymake', 'energystorage' },
		},
		converter = {
			levelCount = 24,
			sourceKey = 'converterBase',
			unitSuffix = 'evconv',
			displayName = 'Evo Energy Conv',
			footprint = 6,
			usesGeothermalUpgrade = true,
			costFields = { 'metalcost', 'energycost', 'buildtime' },
			productionCustomFields = { 'energyconv_capacity' },
		},
		nano = {
			levelCount = 30,
			sourceKey = 'nanoT3Base',
			unitSuffix = 'evnano',
			displayName = 'Construction Turret',
			footprint = 6,
			costFields = { 'metalcost', 'energycost', 'buildtime' },
			productionFields = { 'workertime' },
			linearFields = { 'builddistance' },
			linearGainPerLevel = 0.03,
		},
	}
	local maxFamilyLevel = 0
	for _, familyName in ipairs(familyOrder) do
		maxFamilyLevel = math.max(maxFamilyLevel, families[familyName].levelCount)
	end

	-- These two disjoint covers prevent ordinary buildings from being placed
	-- over an evolved unit and prevent evolved units from being placed over
	-- ordinary buildings. Marker 1 reuses the first stackable guard; the final
	-- marker reuses the final build-only guard.
	local smallStackableGuards = {
		{ 1, 1 },
		{ 1, 3 },
		{ 1, 5 },
		{ 4, 3 },
		{ 5, 6 },
		{ 6, 1 },
		{ 6, 3 },
	}
	local smallBuildOnlyGuards = {
		{ 1, 2 },
		{ 1, 6 },
		{ 2, 2 },
		{ 2, 5 },
		{ 2, 6 },
		{ 4, 2 },
		{ 6, 5 },
	}

	local function scaled(value, multiplier)
		if type(value) ~= 'number' then
			return nil
		end
		return math.ceil(value * multiplier)
	end

	local function productionMultiplier(level)
		local earlySteps = math.min(level - 1, growthPivotLevel - 1)
		local lateSteps = math.max(level - growthPivotLevel, 0)
		return (earlyGrowthFactor ^ earlySteps) * (lateGrowthFactor ^ lateSteps)
	end

	local function costMultiplier(level, productionScale)
		local efficiency = 1 + efficiencyGainPerLevel * (level - 1)
		return productionScale / efficiency
	end

	local function linearMultiplier(level, gainPerLevel)
		return 1 + gainPerLevel * (level - 1)
	end

	local function formatNumber(value)
		if not value then
			return '0'
		end
		if value == math.floor(value) then
			return string.format('%.0f', value)
		end
		return string.format('%.2f', value)
	end

	local function applyScaledFields(target, source, fieldNames, multiplier)
		for _, fieldName in ipairs(fieldNames) do
			local value = scaled(source[fieldName], multiplier)
			if value ~= nil then
				target[fieldName] = value
			end
		end
	end

	local function cloneIfMissing(baseName, newName, overrides)
		local base = unitDefs[baseName]
		if not base or unitDefs[newName] then
			return unitDefs[newName]
		end
		unitDefs[newName] = table.merge(base, overrides)
		return unitDefs[newName]
	end

	local function orbitCoordinates(quadrantSize, row, column)
		local fullSize = quadrantSize * 2
		return {
			{ row, column },
			{ column, fullSize - row + 1 },
			{ fullSize - row + 1, fullSize - column + 1 },
			{ fullSize - column + 1, row },
		}
	end

	local function coordinateKey(row, column)
		return row .. ':' .. column
	end

	local function tiledCoordinates(source, tileSize, tilesPerAxis, reflectFinalTile)
		local result = {}
		for tileRow = 0, tilesPerAxis - 1 do
			for tileColumn = 0, tilesPerAxis - 1 do
				for _, coordinate in ipairs(source) do
					local row = coordinate[1]
					local column = coordinate[2]
					if reflectFinalTile and tileRow == tilesPerAxis - 1 and tileColumn == tilesPerAxis - 1 then
						-- Reflect the final tile across its anti-diagonal. This retains
						-- both guard covers while preventing the 24x24 fusion map from
						-- aligning with the 12x12 converter family at partial offsets.
						row, column = tileSize - column + 1, tileSize - row + 1
					end
					result[#result + 1] = {
						row + tileRow * tileSize,
						column + tileColumn * tileSize,
					}
				end
			end
		end
		return result
	end

	local function createYardmapLadder(quadrantSize, levelCount, stackableGuards, buildOnlyGuards, completionGate)
		local fullSize = quadrantSize * 2
		local reservedSet = {}
		for _, coordinates in ipairs({ stackableGuards, buildOnlyGuards }) do
			for _, coordinate in ipairs(coordinates) do
				reservedSet[coordinateKey(coordinate[1], coordinate[2])] = true
			end
		end

		local markerCoordinates = { stackableGuards[1] }
		-- One quadrant cell expands into a four-cell rotational orbit. A 6x6
		-- quadrant therefore gives 36 independent states in a 12x12 h yardmap.
		for row = 1, quadrantSize do
			for column = 1, quadrantSize do
				if #markerCoordinates < levelCount - 1 and not reservedSet[coordinateKey(row, column)] then
					markerCoordinates[#markerCoordinates + 1] = { row, column }
				end
			end
		end
		markerCoordinates[#markerCoordinates + 1] = buildOnlyGuards[#buildOnlyGuards]

		if #markerCoordinates ~= levelCount then
			return nil
		end

		local yardmaps = {}
		for level = 1, levelCount do
			local grid = {}
			for row = 1, fullSize do
				grid[row] = {}
				for column = 1, fullSize do
					grid[row][column] = 'b'
				end
			end

			for _, coordinate in ipairs(stackableGuards) do
				for _, rotated in ipairs(orbitCoordinates(quadrantSize, coordinate[1], coordinate[2])) do
					grid[rotated[1]][rotated[2]] = 's'
				end
			end

			for markerLevel, coordinate in ipairs(markerCoordinates) do
				-- Recoil permits overlap when the existing cell is b or the incoming
				-- cell is s. This progression allows only a strictly higher level.
				local marker = 'b'
				if markerLevel < level then
					marker = 's'
				elseif markerLevel == level then
					marker = 'o'
				end
				for _, rotated in ipairs(orbitCoordinates(quadrantSize, coordinate[1], coordinate[2])) do
					grid[rotated[1]][rotated[2]] = marker
				end
			end

			-- BAR's geothermal upgrade gadget opens c cells only when this unit is
			-- finished. Reuse a permanent b guard orbit so unfinished foundations
			-- reject every next level without reducing the marker capacity.
			for _, rotated in ipairs(orbitCoordinates(quadrantSize, completionGate[1], completionGate[2])) do
				grid[rotated[1]][rotated[2]] = 'c'
			end

			local rows = {}
			for row = 1, fullSize do
				rows[row] = table.concat(grid[row])
			end
			yardmaps[level] = 'h ' .. table.concat(rows, ' ')
		end

		return yardmaps
	end

	local fusionStackableGuards = tiledCoordinates(smallStackableGuards, 6, 2, true)
	local fusionBuildOnlyGuards = tiledCoordinates(smallBuildOnlyGuards, 6, 2, true)
	families.fusion.yardmaps = createYardmapLadder(
		12,
		families.fusion.levelCount,
		fusionStackableGuards,
		fusionBuildOnlyGuards,
		fusionBuildOnlyGuards[1]
	)
	families.converter.yardmaps = createYardmapLadder(
		6,
		families.converter.levelCount,
		smallStackableGuards,
		smallBuildOnlyGuards,
		smallBuildOnlyGuards[1]
	)

	local function nanoT3Overrides(faction)
		return {
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
			objectname = faction.nanoObject,
		}
	end

	local function createFusionLevels(faction)
		local config = families.fusion
		local baseName = faction[config.sourceKey]
		local base = unitDefs[baseName]
		if not base or not config.yardmaps then
			return
		end

		for level = 1, config.levelCount do
			local productionScale = productionMultiplier(level)
			local costScale = costMultiplier(level, productionScale)
			local unitName = faction.prefix .. config.unitSuffix .. level
			local overrides = {
				name = faction.displayName .. ' ' .. config.displayName .. ' ' .. level,
				description = config.displayName .. ' Level ' .. level,
				footprintx = config.footprint,
				footprintz = config.footprint,
				yardmap = config.yardmaps[level],
				customparams = {
					i18n_en_humanname = config.displayName .. ' ' .. level,
					geothermal = config.usesGeothermalUpgrade and 1 or nil,
				},
			}
			applyScaledFields(overrides, base, config.costFields, costScale)
			applyScaledFields(overrides, base, config.productionFields, productionScale)
			overrides.customparams.i18n_en_tooltip = 'Produces ' .. formatNumber(overrides.energymake) .. ' energy/sec'
			cloneIfMissing(baseName, unitName, overrides)
		end
	end

	local function createConverterLevels(faction)
		local config = families.converter
		local baseName = faction[config.sourceKey]
		local base = unitDefs[baseName]
		if not base or not config.yardmaps then
			return
		end

		local baseCustomParams = base.customparams or {}
		for level = 1, config.levelCount do
			local productionScale = productionMultiplier(level)
			local costScale = costMultiplier(level, productionScale)
			local unitName = faction.prefix .. config.unitSuffix .. level
			local overrides = {
				name = faction.displayName .. ' ' .. config.displayName .. ' ' .. level,
				description = config.displayName .. ' Level ' .. level,
				footprintx = config.footprint,
				footprintz = config.footprint,
				yardmap = config.yardmaps[level],
				customparams = {
					i18n_en_humanname = config.displayName .. ' ' .. level,
					geothermal = config.usesGeothermalUpgrade and 1 or nil,
				},
			}
			applyScaledFields(overrides, base, config.costFields, costScale)
			applyScaledFields(overrides.customparams, baseCustomParams, config.productionCustomFields, productionScale)
			local capacity = overrides.customparams.energyconv_capacity
			local efficiency = baseCustomParams.energyconv_efficiency or 0
			local metalMake = capacity and capacity * efficiency or nil
			overrides.customparams.i18n_en_tooltip = 'Converts up to ' .. formatNumber(capacity) .. ' energy into ' .. formatNumber(metalMake) .. ' metal/sec (Hazardous)'
			cloneIfMissing(baseName, unitName, overrides)
		end
	end

	local function createNanoLevels(faction)
		local nanoT3WasMissing = unitDefs[faction.nanoT3Base] == nil
		local nanoT3 = cloneIfMissing(faction.nanoT2Base, faction.nanoT3Base, nanoT3Overrides(faction))
		if nanoT3WasMissing and nanoT3 then
			-- An immobile builder with a yardmap is classified as a factory by
			-- Recoil. Explicitly clear any yardmap inherited from the T2 source.
			nanoT3.yardmap = nil
		end
		local config = families.nano
		local baseName = faction[config.sourceKey]
		local base = unitDefs[baseName]
		if not base then
			return
		end

		for level = 1, config.levelCount do
			local productionScale = productionMultiplier(level)
			local costScale = costMultiplier(level, productionScale)
			local unitName = faction.prefix .. config.unitSuffix .. level
			local overrides = {
				name = faction.displayName .. ' ' .. config.displayName .. ' ' .. level,
				description = config.displayName .. ' Level ' .. level,
				footprintx = config.footprint,
				footprintz = config.footprint,
				customparams = {
					i18n_en_humanname = config.displayName .. ' ' .. level,
				},
			}
			applyScaledFields(overrides, base, config.costFields, costScale)
			applyScaledFields(overrides, base, config.productionFields, productionScale)
			applyScaledFields(overrides, base, config.linearFields, linearMultiplier(level, config.linearGainPerLevel))
			overrides.customparams.i18n_en_tooltip =
				'Provides ' .. formatNumber(overrides.workertime) .. ' buildpower at ' .. formatNumber(overrides.builddistance) .. ' range'
			local generated = cloneIfMissing(baseName, unitName, overrides)
			if generated then
				-- table.merge cannot remove an inherited key with a nil override.
				generated.yardmap = nil
			end
		end
	end

	local function ensureBuildOption(builderName, optionName)
		local builder = unitDefs[builderName]
		if not builder or not unitDefs[optionName] then
			return
		end
		builder.buildoptions = builder.buildoptions or {}
		for _, existing in ipairs(builder.buildoptions) do
			if existing == optionName then
				return
			end
		end
		builder.buildoptions[#builder.buildoptions + 1] = optionName
	end

	local function addEvolvingBuildOptions(faction)
		local builderNames = {}
		for _, builderName in ipairs(faction.builders) do
			builderNames[#builderNames + 1] = builderName
		end
		builderNames[#builderNames + 1] = faction.prefix .. 't3aide'
		builderNames[#builderNames + 1] = faction.prefix .. 't3airaide'

		for _, builderName in ipairs(builderNames) do
			for level = 1, maxFamilyLevel do
				for _, familyName in ipairs(familyOrder) do
					local family = families[familyName]
					if level <= family.levelCount then
						ensureBuildOption(builderName, faction.prefix .. family.unitSuffix .. level)
					end
				end
			end
		end
	end

	for _, faction in ipairs(factions) do
		createFusionLevels(faction)
		createConverterLevels(faction)
		createNanoLevels(faction)
		addEvolvingBuildOptions(faction)
	end
end
