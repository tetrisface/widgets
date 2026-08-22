-- Run with: lua tests/pseudo_geo_snap_fix_test.lua
-- luacheck: globals UnitDefs WG widget widgetHandler assert dofile error ipairs pairs print select tostring type

local widgetPath = 'Widgets/pseudo_geo_snap_fix.lua'

local function fail(message)
	error(message, 2)
end

local function assertEqual(actual, expected, message)
	if actual ~= expected then
		fail(string.format('%s: expected %s, got %s', message or 'assertEqual', tostring(expected), tostring(actual)))
	end
end

local ARMGEO, ARMEVFUS, ARMMEX, ARMEVCONV = 101, 102, 103, 104

local function realDefs()
	return {
		[ARMGEO] = { customParams = { geothermal = '1' }, needGeo = true },
		[ARMEVFUS] = { customParams = { geothermal = '1' }, needGeo = false },
		[ARMMEX] = { customParams = {}, needGeo = false },
		[ARMEVCONV] = { customParams = { geothermal = '1' }, needGeo = false },
	}
end

local sentinelSpot = { x = 1, z = 2 }
local capturedFindArgs

local function freshApi()
	return {
		FindNearestValidSpotForExtractor = function(...)
			capturedFindArgs = { ... }
			return sentinelSpot
		end,
		GetBestExtractorFromBuilders = function()
			fail('original GetBestExtractorFromBuilders must be replaced')
		end,
	}
end

local removedWidget = false

local function loadWidget(defs, api)
	UnitDefs = defs
	WG = { resource_spot_builder = api }
	widget = {}
	widgetHandler = {
		RemoveWidget = function()
			removedWidget = true
		end,
	}
	removedWidget = false
	assert(dofile(widgetPath) == nil)
	widget:Initialize()
end

print('Running pseudo geo snap fix tests...')

local api = freshApi()
loadWidget(realDefs(), api)
assertEqual(removedWidget, false, 'widget stays loaded when pseudo-geos exist')

-- snap disarmed for pseudo-geos only
assertEqual(api.FindNearestValidSpotForExtractor(10, 20, {}, ARMEVFUS, true), nil, 'pseudo-geo fusion never snaps')
assertEqual(api.FindNearestValidSpotForExtractor(10, 20, {}, ARMEVCONV, true), nil, 'pseudo-geo converter never snaps')
assertEqual(api.FindNearestValidSpotForExtractor(10, 20, {}, ARMGEO, true), sentinelSpot, 'real geo still snaps')
assertEqual(api.FindNearestValidSpotForExtractor(10, 20, {}, ARMMEX, true), sentinelSpot, 'mex still snaps')
assertEqual(#capturedFindArgs, 5, 'pass-through forwards every argument')
assertEqual(capturedFindArgs[5], true, 'pass-through preserves trailing arguments')

-- quick build picks the real geo even when a pseudo-geo is listed first
local constructorIds = {
	[11] = { buildings = 3, building = { -ARMEVFUS, -ARMGEO, -ARMEVCONV } },
	[12] = { buildings = 1, building = { -ARMEVCONV } },
	[13] = { buildings = 1, building = { -ARMMEX } },
}
local extractors = { [ARMGEO] = 600, [ARMEVFUS] = 1e9, [ARMEVCONV] = 1e9, [ARMMEX] = 0.001 }
assertEqual(
	api.GetBestExtractorFromBuilders({ 11, 12, 13 }, constructorIds, extractors),
	ARMGEO,
	'best extractor skips pseudo-geos and pseudo-only builders'
)
assertEqual(api.GetBestExtractorFromBuilders({ 12 }, constructorIds, extractors), nil, 'pseudo-only builder yields none')
assertEqual(api.GetBestExtractorFromBuilders({ 13 }, constructorIds, extractors), ARMMEX, 'mex lists keep original behavior')
assertEqual(api.GetBestExtractorFromBuilders({ 99 }, constructorIds, extractors), nil, 'unknown builder yields none')

-- api reload: a fresh WG table gets re-patched, patching is idempotent per table
local reloadedApi = freshApi()
WG.resource_spot_builder = reloadedApi
widget:Update()
widget:Update()
assertEqual(reloadedApi.FindNearestValidSpotForExtractor(0, 0, {}, ARMEVFUS), nil, 'reloaded api is re-patched')
assertEqual(reloadedApi.FindNearestValidSpotForExtractor(0, 0, {}, ARMGEO), sentinelSpot, 'reloaded api still passes real geos through')
assertEqual(api.FindNearestValidSpotForExtractor(0, 0, {}, ARMEVFUS), nil, 'previous api table remains patched')

-- widget removes itself when the tweak is not active
loadWidget({ [ARMGEO] = { customParams = { geothermal = '1' }, needGeo = true } }, freshApi())
assertEqual(removedWidget, true, 'widget removes itself without pseudo-geos')

print('  [PASS] snap disarmed for pseudo-geos, untouched for real geos and mexes')
print('  [PASS] quick build best-extractor skips pseudo-geos without crashing')
print('  [PASS] re-patches rebuilt api tables and self-removes when unused')
print('Passed pseudo geo snap fix tests.')
