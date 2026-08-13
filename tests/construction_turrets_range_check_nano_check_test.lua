-- Run with: lua tests/construction_turrets_range_check_nano_check_test.lua
-- luacheck: globals CMD LRUCache Spring UnitDefNames UnitDefs widget

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error(string.format('%s: expected %s, got %s', message, tostring(expected), tostring(actual)))
    end
end

local function load_widget(target_def_id, dimensions)
    local tower_id = 10
    local target_id = 20
    local state = {
        dimension_calls = 0,
        stop_orders = 0
    }

    widget = {}
    CMD = {
        ATTACK = 20,
        GUARD = 25,
        RECLAIM = 90,
        REPAIR = 40,
        STOP = 0
    }
    UnitDefs = {
        [1] = {name = 'armnanotc'}
    }
    UnitDefNames = {}
    Spring = {
        GetUnitCommands = function(unit_id)
            if unit_id == tower_id then
                return {{id = CMD.REPAIR, params = {target_id}, options = {}}}
            end
            return {}
        end,
        GetUnitDefDimensions = function()
            state.dimension_calls = state.dimension_calls + 1
            return dimensions
        end,
        GetUnitDefID = function(unit_id)
            if unit_id == tower_id then
                return 1
            end
            return target_def_id
        end,
        GetUnitEffectiveBuildRange = function()
            return 100
        end,
        GetUnitPosition = function(unit_id)
            if unit_id == tower_id then
                return 0, 0, 0
            end
            return 150, 0, 0
        end,
        GiveOrderArrayToUnit = function() end,
        GiveOrderToUnitArray = function()
            state.stop_orders = state.stop_orders + 1
        end
    }

    dofile('Widgets/construction_turrets_range_check_nano_check.lua')
    widget:SelectionChanged({tower_id})
    widget:UnitCommand(tower_id)

    return widget, state
end

local function run_frames(loaded_widget, count)
    for _ = 1, count do
        loaded_widget:GameFrame()
    end
end

do
    local loaded_widget, state = load_widget(nil, nil)
    run_frames(loaded_widget, 16)
    assert_equal(state.dimension_calls, 0, 'missing target definition must not be passed to GetUnitDefDimensions')
    assert_equal(state.stop_orders, 0, 'an unreadable target must preserve the existing queue')
end

do
    local loaded_widget, state = load_widget(2, nil)
    run_frames(loaded_widget, 16)
    assert_equal(state.dimension_calls, 1, 'available target definition should query its dimensions')
    assert_equal(state.stop_orders, 0, 'missing dimensions must preserve the existing queue')
end

do
    local loaded_widget, state = load_widget(2, {radius = 10})
    run_frames(loaded_widget, 16)
    assert_equal(state.dimension_calls, 1, 'target radius should be queried once')
    assert_equal(state.stop_orders, 1, 'an out-of-range command should still be removed')
end

print('Construction Turrets Range Check tests passed')
