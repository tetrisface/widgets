-- Run with: lua tests/eco_cons_test.lua
-- luacheck: globals ECO_CONS_TEST IsInBuildRange _G assert dofile error pcall print type

local function assertEqual(actual, expected, message)
  if actual ~= expected then
    error(string.format('%s: expected %s, got %s', message or 'assertEqual', tostring(expected), tostring(actual)))
  end
end

local function assertNear(actual, expected, epsilon, message)
  if math.abs(actual - expected) > epsilon then
    error(string.format('%s: expected %.6f, got %.6f', message or 'assertNear', expected, actual))
  end
end

local function assertTrue(value, message)
  assertEqual(value, true, message)
end

local function assertFalse(value, message)
  assertEqual(value, false, message)
end

local function newSetList()
  local setList = {hash = {}, list = {}, count = 0}

  function setList:Add(key)
    if self.hash[key] ~= nil then return end
    self.count = self.count + 1
    self.hash[key] = self.count
    self.list[self.count] = key
  end

  function setList:Remove(key)
    local index = self.hash[key]
    if not index then return end
    if index ~= self.count then
      local lastKey = self.list[self.count]
      self.list[index] = lastKey
      self.hash[lastKey] = index
    end
    self.list[self.count] = nil
    self.hash[key] = nil
    self.count = self.count - 1
  end

  return setList
end

local function unitDef(overrides)
  local result = {
    buildDistance = 100,
    buildOptions = {},
    buildSpeed = 0,
    canAssist = false,
    cost = 100,
    customParams = {},
    energyMake = 0,
    energyUpkeep = 0,
    extractsMetal = 0,
    isBuilder = false,
    isBuilding = false,
    isFactory = false,
    makesMetal = 0,
    metalMake = 0,
    metalCost = 100,
    onOffable = false,
    speed = 50,
    tidalGenerator = 0,
    translatedHumanName = 'test unit',
    windGenerator = 0
  }
  for key, value in pairs(overrides or {}) do
    result[key] = value
  end
  return result
end

local state = {
  commands = {},
  defIDs = {},
  echoes = {},
  featureResources = {},
  health = {},
  positions = {},
  radii = {},
  resources = {},
  selectedUnits = {},
  teamResources = {},
  teamUnits = {},
  teamUnitsByDefs = {}
}

local function resetCounters()
  state.commandCalls = 0
  state.positionCalls = 0
  state.radiusCalls = 0
  state.removeOrderBatches = 0
  state.rulesMessages = 0
  state.spotlights = 0
  state.teamUnitCalls = 0
  state.unitResourceCalls = 0
end

widget = {}
WG = {}
KEYSYMS = {L = 76, T = 84}
CMD = {
  FIGHT = 16,
  GUARD = 25,
  INSERT = 1,
  MOVE = 10,
  OPT_CTRL = 64,
  OPT_SHIFT = 32,
  RECLAIM = 90,
  REMOVE = 2,
  REPAIR = 40,
  WAIT = 5
}
Game = {maxUnits = 32000, tidal = 10, windMax = 20, windMin = 5}
UnitDefs = {
  [1] = unitDef({
    buildOptions = {4},
    buildSpeed = 100,
    canAssist = true,
    isBuilder = true,
    metalMake = 1,
    energyMake = 2,
    translatedHumanName = 'constructor'
  }),
  [2] = unitDef({
    energyUpkeep = 60,
    isBuilding = true,
    makesMetal = 2,
    onOffable = true,
    translatedHumanName = 'metal maker'
  }),
  [3] = unitDef({energyUpkeep = 20, translatedHumanName = 'radar'}),
  [4] = unitDef({
    buildSpeed = 50,
    energyMake = 20,
    extractsMetal = 1,
    isBuilding = true,
    translatedHumanName = 'eco target'
  })
}

IsInBuildRange = function(builderID, targetID)
  state.lastBuildRangeBuilderID = builderID
  state.lastBuildRangeTargetID = targetID
  return true
end

VFS = {
  Include = function(path)
    if path == 'common/SetList.lua' then
      return {NewSetList = newSetList}
    end
    return nil
  end
}

widgetHandler = {
  RemoveWidget = function()
    state.widgetRemovals = (state.widgetRemovals or 0) + 1
  end
}

Spring = {
  Echo = function(...)
    state.echoes[#state.echoes + 1] = table.concat({...}, ' ')
  end,
  GetFeatureHealth = function() return 100 end,
  GetFeatureResources = function(featureID)
    local resources = state.featureResources[featureID]
    if not resources then return nil end
    return resources[1], resources[2], resources[3]
  end,
  GetFeatureResurrect = function() return nil end,
  GetFeaturesInCylinder = function() return {} end,
  GetGameFrame = function() return state.gameFrame or 100 end,
  GetMyTeamID = function() return 1 end,
  GetSelectedUnits = function() return state.selectedUnits end,
  GetSpectatingState = function() return state.spectating == true end,
  GetTeamResources = function(_, resourceType)
    local values = state.teamResources[resourceType] or {100, 1000, 0, 10, 0, 0, 0, 0}
    return table.unpack(values)
  end,
  GetTeamRulesParam = function() return state.mmLevel end,
  GetTeamUnits = function()
    state.teamUnitCalls = state.teamUnitCalls + 1
    return state.teamUnits
  end,
  GetTeamUnitsByDefs = function() return state.teamUnitsByDefs end,
  GetUnitBasePosition = function(unitID)
    state.positionCalls = state.positionCalls + 1
    local position = state.positions[unitID]
    if not position then return nil end
    return position[1], position[2] or 0, position[3]
  end,
  GetUnitCommands = function(unitID)
    state.commandCalls = state.commandCalls + 1
    return state.commands[unitID] or {}
  end,
  GetUnitDefID = function(unitID) return state.defIDs[unitID] end,
  GetUnitHealth = function(unitID)
    local health = state.health[unitID]
    if not health then return nil end
    return health.health, health.maxHealth, nil, nil, health.build
  end,
  GetUnitIsBuilding = function(unitID) return state.buildTargets and state.buildTargets[unitID] end,
  GetUnitRadius = function(unitID)
    state.radiusCalls = state.radiusCalls + 1
    return state.radii[unitID] or 0
  end,
  GetUnitResources = function(unitID)
    state.unitResourceCalls = state.unitResourceCalls + 1
    local resources = state.resources[unitID] or {0, 0, 0, 0}
    return table.unpack(resources)
  end,
  GetUnitsInCylinder = function() return state.unitsInCylinder or {} end,
  GiveOrderArrayToUnit = function()
    state.removeOrderBatches = state.removeOrderBatches + 1
  end,
  GiveOrderToUnit = function() end,
  GiveOrderToUnitArray = function() end,
  IsReplay = function() return false end,
  SendLuaRulesMsg = function()
    state.rulesMessages = state.rulesMessages + 1
  end
}

table.tostring = function(value) return tostring(value) end

ECO_CONS_TEST = true
local api = assert(dofile('Widgets/eco_cons.lua'))
ECO_CONS_TEST = nil

local function initialize(teamUnits, defIDs)
  state.teamUnits = teamUnits or {}
  state.defIDs = defIDs or {}
  state.spectating = false
  resetCounters()
  widget:Initialize()
  resetCounters()
end

local tests = {}

local function test(name, callback)
  tests[#tests + 1] = {name = name, callback = callback}
end

test('builder registry survives swap-removal, duplicates, stale entries, and rescans', function()
  initialize({101, 102, 103}, {[101] = 1, [102] = 1, [103] = 1, [104] = 1})

  widget:UnitDestroyed(102, 1, 1)
  local snapshot = api.getBuilderRegistrySnapshot()
  assertEqual(snapshot.count, 2, 'middle removal count')
  assertTrue(snapshot.records[101] ~= nil, 'first builder remains')
  assertTrue(snapshot.records[103] ~= nil, 'swap-moved builder remains')

  widget:UnitFinished(103, 1, 1)
  assertEqual(api.getBuilderRegistrySnapshot().count, 2, 'duplicate finish is idempotent')

  state.teamUnits = {101, 103, 104}
  api.rescanBuilders()
  api.rescanBuilders()
  snapshot = api.getBuilderRegistrySnapshot()
  assertEqual(snapshot.count, 3, 'rescan adds exactly one missing builder')
  assertTrue(snapshot.records[104] ~= nil, 'rescan records by unit ID')

  api.dropBuilderRecordForTest(101)
  assertEqual(api.builderById(101), nil, 'stale record returns nil')
  snapshot = api.getBuilderRegistrySnapshot()
  assertEqual(snapshot.count, 2, 'self-heal removes only the stale ID')
  assertTrue(snapshot.records[103] ~= nil and snapshot.records[104] ~= nil, 'self-heal preserves live builders')
end)

test('small rosters never produce a zero game-frame modulo', function()
  initialize({101}, {[101] = 1})
  api.setResponsivenessSpeed(3)
  assertEqual(api.gameFrameModulo(), 1, '3x responsiveness')
  api.setResponsivenessSpeed(4)
  assertEqual(api.gameFrameModulo(), 1, '4x responsiveness')
  api.setResponsivenessSpeed(1)
end)

test('selection and debug logging remain independently observable', function()
  initialize({101}, {[101] = 1})
  state.selectedUnits = {101}
  api.refreshSelectedUnits()
  assertTrue(api.isSelected(101), 'selection is always captured')
  assertFalse(api.isUnitSelectedLog(101), 'selected logging defaults off')

  api.setUnitLogActive(true)
  assertTrue(api.isUnitSelectedLog(101), 'debug mode logs selected builder')
  assertTrue(state.echoes[#state.echoes]:find('enabled', 1, true) ~= nil, 'enable feedback')
  api.setUnitLogActive(false)
  assertFalse(api.isUnitSelectedLog(101), 'debug mode turns off')
  assertTrue(state.echoes[#state.echoes]:find('disabled', 1, true) ~= nil, 'disable feedback')
end)

test('metal-maker totals use registered values and ignore unrelated deaths', function()
  initialize()
  widget:UnitFinished(201, 2, 1)
  widget:UnitFinished(201, 2, 1)
  local upkeep, production = api.getMetalMakerTotals()
  assertEqual(upkeep, 60, 'duplicate maker upkeep')
  assertEqual(production, 2, 'duplicate maker production')

  widget:UnitDestroyed(301, 3, 1)
  upkeep, production = api.getMetalMakerTotals()
  assertEqual(upkeep, 60, 'unrelated destruction upkeep')
  assertEqual(production, 2, 'unrelated destruction production')

  widget:UnitDestroyed(201, nil, 1)
  upkeep, production = api.getMetalMakerTotals()
  assertEqual(upkeep, 0, 'maker upkeep unregisters without def')
  assertEqual(production, 0, 'maker production unregisters without def')
end)

test('reclaim decoding accepts only encoded single-feature commands', function()
  assertEqual(
    api.getSingleReclaimFeatureId({id = CMD.RECLAIM, params = {Game.maxUnits + 77}}),
    77,
    'encoded feature ID'
  )
  assertEqual(api.getSingleReclaimFeatureId({id = CMD.RECLAIM, params = {77}}), nil, 'unit reclaim')
  assertEqual(api.getSingleReclaimFeatureId({id = CMD.RECLAIM, params = {1, 2, 3, 4}}), nil, 'area reclaim')
  assertFalse(api.hasMultiSlotBuildQueue({{id = 0}, {id = -4}}), 'STOP is not a build order')
  assertTrue(api.hasMultiSlotBuildQueue({{id = -3}, {id = -4}}), 'two build orders are detected')
end)

test('optional spotlight and conversion rules parameters are nil-safe', function()
  initialize()
  WG.ObjectSpotlight = nil
  api.addObjectSpotlight('unit', 'me', 101)

  WG.ObjectSpotlight = {addSpotlight = function() state.spotlights = state.spotlights + 1 end}
  api.addObjectSpotlight('unit', 'me', 101)
  assertEqual(state.spotlights, 1, 'available spotlight is called')

  state.mmLevel = nil
  assertFalse(api.sendMetalMakerLevelIfNeeded(1), 'missing mmLevel skips send')
  assertEqual(state.rulesMessages, 0, 'no rules message without mmLevel')
  state.mmLevel = 0.4
  assertTrue(api.sendMetalMakerLevelIfNeeded(1), 'available mmLevel sends')
  assertEqual(state.rulesMessages, 1, 'one rules message with mmLevel')
end)

test('purged command queues are filtered, cached, and invalidatable', function()
  initialize({101}, {[101] = 1})
  state.health[501] = {health = 100, maxHealth = 100, build = 1}
  state.commands[101] = {
    {id = CMD.REPAIR, params = {501}, tag = 1},
    {id = CMD.MOVE, params = {10, 0, 10}, tag = 2}
  }
  api.beginFrame()

  local queue, count = api.getPurgedUnitCommands(101)
  assertEqual(count, 1, 'invalid repair removed from logical queue')
  assertEqual(queue[1].id, CMD.MOVE, 'valid command remains')
  assertEqual(state.commandCalls, 1, 'first fetch reaches engine')
  assertEqual(state.removeOrderBatches, 1, 'invalid command removal issued')

  local _, cachedCount = api.getPurgedUnitCommands(101)
  assertEqual(cachedCount, 1, 'cached filtered queue count')
  assertEqual(state.commandCalls, 1, 'cached fetch avoids engine')

  state.commands[101] = {{id = CMD.WAIT, params = {}, tag = 3}}
  api.invalidatePurgedUnitCommands(101)
  queue, count = api.getPurgedUnitCommands(101)
  assertEqual(count, 1, 'invalidated queue refetch count')
  assertEqual(queue[1].id, CMD.WAIT, 'invalidated queue refetch content')
  assertEqual(state.commandCalls, 2, 'invalidation reaches engine')
end)

test('resource and upkeep scans avoid redundant full-team engine calls', function()
  initialize({301, 302}, {[301] = 3, [302] = 3})
  state.teamResources.metal = {100, 1000, 10, 20, 0, 0, 0, 5}
  state.teamResources.energy = {200, 2000, 15, 30, 0, 0, 0, 7}
  state.resources[301] = {10, 3, 20, 5}
  state.resources[302] = {4, 1, 6, 2}
  api.beginFrame()

  local metalTotal, _, _, metalExpense = api.getResourceStatus('metal')
  local energyTotal, _, _, energyExpense = api.getResourceStatus('energy')
  assertEqual(metalTotal, 15, 'metal total')
  assertEqual(metalExpense, 4, 'metal expense')
  assertEqual(energyTotal, 26, 'energy total')
  assertEqual(energyExpense, 7, 'energy expense')
  assertEqual(state.teamUnitCalls, 1, 'both resources share one team scan')
  assertEqual(state.unitResourceCalls, 2, 'both resources share one unit-resource call per unit')

  api.getResourceStatus('metal')
  api.getResourceStatus('energy')
  assertEqual(state.teamUnitCalls, 1, 'resource results remain cached')
  assertEqual(state.unitResourceCalls, 2, 'cached resources avoid unit calls')

  initialize({101, 102, 301}, {[101] = 1, [102] = 1, [301] = 3})
  state.resources[101] = {2, 4, 3, 8}
  state.resources[102] = {1, 5, 2, 7}
  api.beginFrame()
  api.getUnitsUpkeep()
  assertEqual(state.teamUnitCalls, 0, 'upkeep iterates the builder registry')
  assertEqual(state.unitResourceCalls, 2, 'upkeep reads builders only')
end)

test('candidate scoring and radius-aware squared range preserve behavior', function()
  initialize()
  api.setNeeds(0.2, 0.3, 0.5)
  local candidate = {defId = 4}
  api.scoreEcoCandidates({candidate})
  assertNear(candidate.score, 0.44, 0.000001, 'precomputed combined candidate score')
  assertNear(api.scoreEcoCandidate(candidate), candidate.score, 0.000001, 'score equivalence')

  local builderSnapshot = {builder = {def = {buildDistance = 100}}, x = 0, z = 0, radius = 10}
  assertTrue(api.isWithinBuildRange(builderSnapshot, {x = 117, z = 0, radius = 20}), 'inside surface range')
  assertFalse(api.isWithinBuildRange(builderSnapshot, {x = 118, z = 0, radius = 20}), 'strict range boundary')
end)

test('nearby build-range checks receive target unit IDs, not definition IDs', function()
  initialize({101}, {[101] = 1, [401] = 4})
  state.positions[101] = {0, 0, 0}
  state.unitsInCylinder = {101, 401}
  state.health[401] = {health = 50, maxHealth = 100, build = 0.5}

  local builder = assert(api.builderById(101))
  local _, _, unfinished, unfinishedCount = api.scanNearbyBuildables(builder)
  assertEqual(unfinishedCount, 1, 'unfinished candidate is found')
  assertEqual(unfinished[1].id, 401, 'candidate unit ID')
  assertEqual(state.lastBuildRangeBuilderID, 101, 'range builder ID')
  assertEqual(state.lastBuildRangeTargetID, 401, 'range target uses unit ID')
  state.unitsInCylinder = nil
end)

test('batch snapshots fetch builder commands, positions, and radii once', function()
  initialize({101, 102, 103}, {[101] = 1, [102] = 1, [103] = 1})
  state.positions = {[101] = {0, 0, 0}, [102] = {10, 0, 0}, [103] = {20, 0, 0}}
  state.radii = {[101] = 10, [102] = 10, [103] = 10}
  state.selectedUnits = {}
  api.refreshSelectedUnits()
  resetCounters()

  local snapshots = api.buildBatchBuilderSnapshots(100)
  assertEqual(#snapshots, 3, 'snapshot count')
  assertEqual(state.commandCalls, 3, 'one command fetch per builder')
  assertEqual(state.positionCalls, 3, 'one position fetch per candidate builder')
  assertEqual(state.radiusCalls, 3, 'one radius fetch per candidate builder')

  state.teamUnitsByDefs = {401, 402}
  state.health[401] = {health = 50, maxHealth = 100, build = 0.5}
  state.health[402] = {health = 60, maxHealth = 100, build = 0.6}
  state.positions[401] = {100, 0, 100}
  state.positions[402] = {200, 0, 200}
  state.radii[401] = 15
  state.radii[402] = 20
  resetCounters()
  local candidates = api.getCandidateAlternatives({4})
  assertEqual(#candidates, 2, 'candidate count')
  assertEqual(state.positionCalls, 2, 'one position fetch per candidate')
  assertEqual(state.radiusCalls, 2, 'one radius fetch per candidate')
end)

test('spectator initialization returns immediately after removing the widget', function()
  WG.eco_cons = nil
  state.spectating = true
  state.widgetRemovals = 0
  widget:Initialize()
  assertEqual(state.widgetRemovals, 1, 'spectator removes widget')
  assertEqual(WG.eco_cons, nil, 'spectator does not register WG API')
  state.spectating = false
end)

test('widget loads when BAR omits the _G binding', function()
  local savedGlobalBinding = _G
  ECO_CONS_TEST = true
  _G = nil
  local ok, exports = pcall(dofile, 'Widgets/eco_cons.lua')
  _G = savedGlobalBinding
  ECO_CONS_TEST = nil
  assertTrue(ok, '_G-less widget load')
  assertTrue(type(exports) == 'table', 'test exports remain available without _G')
end)

print('Running eco_cons tests...')
for i = 1, #tests do
  local current = tests[i]
  current.callback()
  print('  [PASS] ' .. current.name)
end
print(string.format('Passed %d eco_cons tests.', #tests))
