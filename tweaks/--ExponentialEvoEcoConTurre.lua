--ExponentialEvoEcoConTurre
-- Exponential evolving economy and construction turrets
-- Author: tetrisface
-- https://github.com/tetrisface/Widgets/blob/main/tweaks/--ExponentialEvoEcoConTurre.lua

do
	local unitDefs = UnitDefs or {}
	local maxLevel = 30
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
			sourceKey = 'fusionBase',
			unitSuffix = 'evfus',
			displayName = 'Evolving Fusion Reactor',
			footprint = 12,
			costFields = { 'metalcost', 'energycost', 'buildtime' },
			productionFields = { 'energymake', 'energystorage' },
		},
		converter = {
			sourceKey = 'converterBase',
			unitSuffix = 'evconv',
			displayName = 'Evolving Energy Converter',
			footprint = 6,
			costFields = { 'metalcost', 'energycost', 'buildtime' },
			productionCustomFields = { 'energyconv_capacity' },
		},
		nano = {
			sourceKey = 'nanoT3Base',
			unitSuffix = 'evnano',
			displayName = 'Evolving Construction Turret',
			footprint = 6,
			costFields = { 'metalcost', 'energycost', 'buildtime' },
			productionFields = { 'workertime' },
		},
	}

	local smallGuardCoordinates = {
		{ 1, 1 },
		{ 1, 5 },
		{ 5, 1 },
		{ 5, 5 },
	}
	local fusionGuardCoordinates = {}
	local fusionGuardAxes = { 1, 5, 9, 12 }
	for _, row in ipairs(fusionGuardAxes) do
		for _, column in ipairs(fusionGuardAxes) do
			fusionGuardCoordinates[#fusionGuardCoordinates + 1] = { row, column }
		end
	end

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

	local function createYardmapLadder(quadrantSize, guardCoordinates, reverseMarkers)
		local fullSize = quadrantSize * 2
		local guardSet = {}
		for _, coordinate in ipairs(guardCoordinates) do
			guardSet[coordinateKey(coordinate[1], coordinate[2])] = true
		end

		local markerCoordinates = {}
		-- One quadrant cell expands into a four-cell rotational orbit. A 6x6
		-- quadrant therefore gives 36 independent states in a 12x12 h yardmap.
		for row = 1, quadrantSize do
			for column = 1, quadrantSize do
				if not guardSet[coordinateKey(row, column)] then
					markerCoordinates[#markerCoordinates + 1] = { row, column }
				end
			end
		end

		if #markerCoordinates < maxLevel then
			return nil
		end

		local selectedMarkers = {}
		for index = 1, maxLevel do
			selectedMarkers[index] = markerCoordinates[index]
		end
		if reverseMarkers then
			local reversedMarkers = {}
			for index = 1, maxLevel do
				reversedMarkers[index] = selectedMarkers[maxLevel - index + 1]
			end
			selectedMarkers = reversedMarkers
		end

		local yardmaps = {}
		for level = 1, maxLevel do
			local grid = {}
			for row = 1, fullSize do
				grid[row] = {}
				for column = 1, fullSize do
					grid[row][column] = 'b'
				end
			end

			for _, coordinate in ipairs(guardCoordinates) do
				for _, rotated in ipairs(orbitCoordinates(quadrantSize, coordinate[1], coordinate[2])) do
					grid[rotated[1]][rotated[2]] = 's'
				end
			end

			for markerLevel, coordinate in ipairs(selectedMarkers) do
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

			local rows = {}
			for row = 1, fullSize do
				rows[row] = table.concat(grid[row])
			end
			yardmaps[level] = 'h ' .. table.concat(rows, ' ')
		end

		return yardmaps
	end

	families.fusion.yardmaps = createYardmapLadder(12, fusionGuardCoordinates, false)
	families.converter.yardmaps = createYardmapLadder(6, smallGuardCoordinates, false)
	families.nano.yardmaps = createYardmapLadder(6, smallGuardCoordinates, true)

	local function nanoT3Overrides(faction)
		local config = families.nano
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

		for level = 1, maxLevel do
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
		for level = 1, maxLevel do
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
		cloneIfMissing(faction.nanoT2Base, faction.nanoT3Base, nanoT3Overrides(faction))
		local config = families.nano
		local baseName = faction[config.sourceKey]
		local base = unitDefs[baseName]
		if not base or not config.yardmaps then
			return
		end

		for level = 1, maxLevel do
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
				},
			}
			applyScaledFields(overrides, base, config.costFields, costScale)
			applyScaledFields(overrides, base, config.productionFields, productionScale)
			overrides.customparams.i18n_en_tooltip = 'Provides ' .. formatNumber(overrides.workertime) .. ' buildpower'
			cloneIfMissing(baseName, unitName, overrides)
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
			for level = 1, maxLevel do
				for _, familyName in ipairs(familyOrder) do
					ensureBuildOption(builderName, faction.prefix .. families[familyName].unitSuffix .. level)
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
