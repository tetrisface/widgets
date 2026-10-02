-- Run with: lua tests/scav_constructor_guard_test.lua
-- luacheck: globals SCAV_CONSTRUCTOR_GUARD_TEST widget CMD Game Engine Spring UnitDefs FeatureDefs UnitDefNames assert dofile error pcall print

local function assertEqual(actual, expected, message)
	if actual ~= expected then
		error(string.format('%s: expected %s, got %s', message or 'assertEqual', tostring(expected), tostring(actual)))
	end
end

widget = {}
CMD = {INSERT = 1, REMOVE = 2, FIGHT = 16, RECLAIM = 90}
Game = {maxUnits = 32000}
Engine = {FeatureSupport = {}}
Spring = {}
UnitDefs = {[1] = {isFactory = true}, [2] = {isFactory = false}}
FeatureDefs, UnitDefNames = {}, {}

SCAV_CONSTRUCTOR_GUARD_TEST = true
local api = assert(dofile('Widgets/cmd_scav_constructor_guard.lua'))
SCAV_CONSTRUCTOR_GUARD_TEST = nil

local function cmd(id, tag, params, options)
	return {id = id, tag = tag, params = params, options = options or {}}
end

local area = cmd(90, 7, {100, 0, 200, 300})
local picked = cmd(90, 8, {32005, 100, 0, 200, 300}, {internal = true})

local function neverSearched()
	error('substitute searched')
end

local function nothingLeft()
	return nil
end

local tests = {}

function tests.isScavConstructor()
	local function def(name, canMove, buildOptions)
		return {name = name, canMove = canMove, buildOptions = buildOptions}
	end
	assertEqual(api.isScavConstructor(def('armck_scav', true, {2, 1})), true, 'builds a factory')
	assertEqual(api.isScavConstructor(def('armmlv_scav', true, {2})), false, 'minelayer')
	assertEqual(api.isScavConstructor(def('armck', true, {1})), false, 'not scav')
	assertEqual(api.isScavConstructor(def('armlab_scav', false, {1})), false, 'factory itself')
end

function tests.explicitOrderIsDropped()
	local orders = api.ordersFor({cmd(90, 3, {32005}), area}, neverSearched)
	assertEqual(#orders, 1)
	assertEqual(orders[1][1], CMD.REMOVE)
	assertEqual(orders[1][2][1], 3)
end

function tests.areaPickIsSwapped()
	local orders = api.ordersFor({picked, area}, function(x, z, radius)
		assertEqual(x + z + radius, 600, 'searches the picked order circle')
		return 9
	end)
	assertEqual(#orders, 2)
	assertEqual(orders[1][2][1], 8)
	assertEqual(orders[2][1], CMD.INSERT)
	assertEqual(orders[2][2][2], CMD.RECLAIM)
	assertEqual(orders[2][2][4], 32009)
end

function tests.exhaustedAreaIsDropped()
	local orders = api.ordersFor({picked, area}, nothingLeft)
	assertEqual(#orders, 2)
	assertEqual(orders[2][1], CMD.REMOVE)
	assertEqual(orders[2][2][1], 7)
end

function tests.fightPickIsOnlyDropped()
	assertEqual(#api.ordersFor({picked, cmd(16, 9, {1, 2, 3})}, nothingLeft), 1)
end

function tests.unitReclaimAreaIsDroppedNotSwapped()
	local unitPick = cmd(90, 8, {5, 100, 0, 200, 300}, {internal = true, meta = true})
	local orders = api.ordersFor({unitPick, area}, neverSearched)
	assertEqual(#orders, 2)
	assertEqual(orders[2][2][1], 7)
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
