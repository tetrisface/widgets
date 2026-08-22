function widget:GetInfo()
	return {
		name = 'Pseudo Geo Snap Fix',
		desc = 'Stops extractor snap and quick build from treating gadget-only geothermal buildings (customparams.geothermal without vent yardmap cells) as real geos',
		author = 'tetrisface',
		date = 'aug, 2026',
		license = 'GNU GPL, v2 or later',
		layer = 0,
		enabled = true,
	}
end

-- customparams.geothermal enrolls a building in the geo upgrade-refund gadget
-- (unit_geo_upgrade_reclaimer), but api_resource_spot_builder also reads it as
-- "snaps to geo vents", hijacking placement clicks map-wide on geothermal maps.
-- Real vent buildings all carry g yardmap cells (needGeo); evolving eco
-- buildings from tweaks do not, which separates the two.
local isPseudoGeo = {}
for unitDefID, unitDef in pairs(UnitDefs) do
	if unitDef.customParams.geothermal and not unitDef.needGeo then
		isPseudoGeo[unitDefID] = true
	end
end

local patchedApi

local function PatchApi()
	local api = WG.resource_spot_builder
	if not api or api == patchedApi then
		return
	end

	local originalFindNearest = api.FindNearestValidSpotForExtractor
	api.FindNearestValidSpotForExtractor = function(x, z, spots, extractorDefID, ...)
		if isPseudoGeo[extractorDefID] then
			return nil
		end
		return originalFindNearest(x, z, spots, extractorDefID, ...)
	end

	-- The original blindly takes each builder's first geo build option; skipping
	-- pseudo-geos keeps quick build (right click a spot) offering the real geo
	-- instead of an evolved eco building.
	api.GetBestExtractorFromBuilders = function(units, constructorIds, extractors)
		local bestExtraction = 0
		local bestExtractor
		for i = 1, #units do
			local constructor = constructorIds[units[i]]
			if constructor then
				for j = 1, #constructor.building do
					local buildingID = -constructor.building[j]
					if not isPseudoGeo[buildingID] then
						local extractionAmount = extractors[buildingID]
						if extractionAmount and extractionAmount > bestExtraction then
							bestExtraction = extractionAmount
							bestExtractor = buildingID
						end
						break
					end
				end
			end
		end
		return bestExtractor
	end

	patchedApi = api
end

function widget:Initialize()
	if next(isPseudoGeo) == nil then
		widgetHandler:RemoveWidget(self)
		return
	end
	PatchApi()
end

-- api_resource_spot_builder rebuilds WG.resource_spot_builder when it reloads;
-- re-apply whenever a fresh table appears.
function widget:Update()
	PatchApi()
end
