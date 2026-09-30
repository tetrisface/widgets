-- Run with: lua tests/area_reclaim_spread_test.lua
-- luacheck: globals AREA_RECLAIM_SPREAD_TEST widget CMD Game Engine Spring UnitDefs FeatureDefs UnitDefNames assert dofile error pcall print

local function assertEqual(actual, expected, message)
	if actual ~= expected then
		error(string.format('%s: expected %s, got %s', message or 'assertEqual', tostring(expected), tostring(actual)))
	end
end

local function assertNear(actual, expected, message)
	if math.abs(actual - expected) > 1e-6 then
		error(string.format('%s: expected %.6f, got %.6f', message or 'assertNear', expected, actual))
	end
end

widget = {}
CMD = {INSERT = 1, RECLAIM = 90, RESURRECT = 125, WAIT = 5}
Game = {maxUnits = 32000}
Engine = {FeatureSupport = {}}
Spring = {}
UnitDefs, FeatureDefs, UnitDefNames = {}, {}, {}

AREA_RECLAIM_SPREAD_TEST = true
local api = assert(dofile('Widgets/cmd_area_reclaim_spread.lua'))
AREA_RECLAIM_SPREAD_TEST = nil

local function unit(id, x, overrides)
	local result = {id = id, kind = 'reclaim', x = x, z = 0, speed = 100, range = 0, immobile = false, tortuosity = 1, workSpeed = 10}
	for key, value in pairs(overrides or {}) do result[key] = value end
	return result
end

local function feature(id, x, work, metal, energy)
	return {id = id, x = x, z = 0, radius = 0, work = work, metal = metal or 0, energy = energy or 0}
end

local function count(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

local tests = {}

function tests.finishSeconds()
	local f = feature(1, 0, 50)
	assertEqual(api.finishSeconds(f, {}), math.huge, 'nobody coming')
	assertNear(api.finishSeconds(f, {{id = 1, arrival = 2, speed = 10}}), 7, 'one assignee')
	local two = {{id = 2, arrival = 4, speed = 10}, {id = 1, arrival = 2, speed = 10}}
	assertNear(api.finishSeconds(f, two), 5.5, 'second assignee joins mid-way')
	assertNear(api.finishSeconds(f, two, 2), 7, 'excluded assignee')
	assertEqual(api.finishSeconds(feature(2, 0, 0), {}), 0, 'no work left')
end

function tests.isDoomed()
	local slow = unit(9, 1000)
	local ahead = {{id = 1, arrival = 1, speed = 10}}
	assertEqual(api.isDoomed(slow, feature(1, 0, 50), ahead), true, 'small feature gone before arrival')
	assertEqual(api.isDoomed(slow, feature(1, 0, 500), ahead), false, 'big wreck still there')
	assertEqual(api.isDoomed(unit(9, 1000, {immobile = true}), feature(1, 0, 500), {}), true, 'unreachable')
end

function tests.throughputFansOut()
	local units = {unit(1, 0), unit(2, 0), unit(3, 0)}
	local small = {feature(1, 100, 1, 10), feature(2, 200, 1, 10), feature(3, 300, 1, 10)}
	local result = api.assign(units, {[1] = small, [2] = small, [3] = small}, {}, 'throughput')
	assertEqual(result[1], 1)
	assertEqual(result[2], 2)
	assertEqual(result[3], 3)
end

function tests.throughputStacksOnBigWreck()
	local units = {unit(1, 0), unit(2, 0)}
	local field = {feature(1, 100, 1000, 1000), feature(2, 200, 1, 10)}
	local result = api.assign(units, {[1] = field, [2] = field}, {}, 'throughput')
	assertEqual(result[1], 1)
	assertEqual(result[2], 1, 'halving a big wreck beats a small far feature')
end

function tests.immediateTakesNearestMetal()
	local units = {unit(1, 0), unit(2, 0)}
	local field = {feature(1, 100, 1, 0, 50), feature(2, 200, 1000, 1000)}
	local result = api.assign(units, {[1] = field, [2] = field}, {}, 'immediate')
	assertEqual(result[1], 2, 'energy-only feature is skipped')
	assertEqual(result[2], 2, 'nearest metal, not doomed, everyone stacks')
end

function tests.immediateSkipsDoomed()
	local fast, slow = unit(1, 0), unit(2, 500)
	local field = {feature(1, 100, 1, 10), feature(2, 700, 1, 10)}
	local result = api.assign({fast, slow}, {[1] = field, [2] = field}, {}, 'immediate')
	assertEqual(result[1], 1)
	assertEqual(result[2], 2, 'slow unit would arrive after the fast one finishes feature 1')
end

function tests.leakIgnoresMetal()
	local field = {feature(1, 100, 1, 10), feature(2, 200, 1, 0, 40)}
	local result = api.assign({unit(1, 0)}, {[1] = field}, {}, 'leak')
	assertEqual(result[1], 2)
	assertEqual(count(api.assign({unit(1, 0)}, {[1] = {field[1]}}, {}, 'leak')), 0, 'metal-only field: do nothing')
end

function tests.kindsNeverMix()
	local load = {[1] = {kind = 'resurrect', assignees = {{id = 7, arrival = 1, speed = 10}}}}
	local result = api.assign({unit(1, 0)}, {[1] = {feature(1, 100, 1000, 1000)}}, load, 'throughput')
	assertEqual(count(result), 0, 'reclaimer stays off a wreck being resurrected')
	assertEqual(#load[1].assignees, 1, 'load untouched')
end

function tests.unknownModeAssignsNothing()
	assertEqual(count(api.assign({unit(1, 0)}, {[1] = {feature(1, 100, 1, 10)}}, {}, 'off')), 0)
end

function tests.blockOf()
	local area = {id = 90, params = {10, 0, 20, 300}, options = {}}
	local engineNative = api.blockOf({{id = 90, params = {32001}, options = {internal = true}}, area})
	assertEqual(engineNative.kind, 'reclaim')
	assertEqual(engineNative.target, 1)
	assertEqual(engineNative.area, area.params)

	local smart = api.blockOf({{id = 90, params = {32005}, options = {}}, {id = 90, params = {32006}, options = {}}})
	assertEqual(smart.target, 5)
	assertEqual(#smart.queued, 2)
	assertEqual(smart.area, nil)

	assertEqual(api.blockOf({{id = 90, params = {32005}, options = {}}}), nil, 'lone manual target')
	assertEqual(api.blockOf({{id = 90, params = {1, 2, 3, 4}, options = {meta = true}}}), nil, 'unit reclaim area')
	assertEqual(api.blockOf({{id = 10, params = {1, 2, 3}, options = {}}, area}), nil, 'move at the front')
	assertEqual(api.blockOf({{id = 125, params = {1, 2, 3, 4}, options = {}}}).kind, 'resurrect')
	assertEqual(api.blockOf({}), nil)
end

local failed = 0
for name, test in pairs(tests) do
	local ok, err = pcall(test)
	if ok then
		print('ok   ' .. name)
	else
		failed = failed + 1
		print('FAIL ' .. name .. ': ' .. tostring(err))
	end
end
if failed > 0 then
	error(failed .. ' test(s) failed')
end
print('all tests passed')
