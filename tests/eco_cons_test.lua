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
    name = 'testunit',
    xsize = 4,
    zsize = 4,
    buildSpeed = 0,
    buildTime = 1000,
    canAssist = false,
    canMove = true,
    cost = 100,
    customParams = {},
    energyCost = 1000,
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
  rulesParams = {},
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
  state.teamResourceCalls = 0
  state.teamUnitCalls = 0
  state.unitResourceCalls = 0
  state.lastRulesMessage = nil
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
  return not (state.outOfRange and state.outOfRange[targetID])
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
    state.teamResourceCalls = state.teamResourceCalls + 1
    local values = state.teamResources[resourceType] or {100, 1000, 0, 10, 0, 0, 0, 0}
    return table.unpack(values)
  end,
  GetTeamRulesParam = function(_, name) return state.rulesParams[name] end,
  GetTeamUnits = function()
    state.teamUnitCalls = state.teamUnitCalls + 1
    return state.teamUnits
  end,
  GetTeamUnitDefCount = function(_, unitDefID)
    local count = 0
    for _, unitID in ipairs(state.teamUnitsByDefs) do
      if state.defIDs[unitID] == unitDefID then count = count + 1 end
    end
    return count
  end,
  GetTeamUnitsByDefs = function(_, unitDefIDs)
    local wanted = {}
    for _, unitDefID in ipairs(unitDefIDs) do wanted[unitDefID] = true end
    local units = {}
    for _, unitID in ipairs(state.teamUnitsByDefs) do
      local defID = state.defIDs[unitID]
      if defID == nil or wanted[defID] then units[#units + 1] = unitID end
    end
    return units
  end,
  GetGroundHeight = function() return 0 end,
  GetUnitBuildFacing = function() return 0 end,
  -- as the engine: 2 for an open spot, 2 plus a feature id when a reclaimable feature is in the way
  TestBuildOrder = function(_, x, _, z)
    local spot = x .. ',' .. z
    if state.featureSpots and state.featureSpots[spot] then return 2, 9000 end
    return state.openSpots and state.openSpots[spot] and 2 or 0
  end,
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
  GetUnitBuildeeRadius = function(unitID)
    state.radiusCalls = state.radiusCalls + 1
    return state.radii[unitID] or 0
  end,
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
  GiveOrderArrayToUnitArray = function(unitIDs, orders)
    state.lastArrayOrders = {unitIDs = unitIDs, orders = orders}
  end,
  GiveOrderToUnit = function(unitID, cmdID, params, options)
    state.lastOrder = {unitID = unitID, cmdID = cmdID, params = params, options = options}
    if state.orders then state.orders[#state.orders + 1] = state.lastOrder end
  end,
  GiveOrderToUnitArray = function() end,
  IsReplay = function() return false end,
  SendLuaRulesMsg = function(message)
    state.rulesMessages = state.rulesMessages + 1
    state.lastRulesMessage = message
  end
}

table.tostring = function(value) return tostring(value) end

ECO_CONS_TEST = true
local api = assert(dofile('Widgets/eco_cons.lua'))
ECO_CONS_TEST = nil

local function initialize(teamUnits, defIDs)
  state.teamUnits = teamUnits or {}
  state.defIDs = defIDs or {}
  state.rulesParams = {}
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

  state.rulesParams = {}
  state.teamResources.metal = {970, 1000, 0, 100, 50, 0, 0, 0}
  api.updateResourceNeeds()
  assertFalse(api.sendNudgedMetalMakerLevel(), 'missing mmLevel skips send')
  assertEqual(state.rulesMessages, 0, 'no rules message without mmLevel')
  state.teamResources.metal = nil
end)

test('already-in-stall means the storage runs out at the current pull, not pull above stock', function()
  initialize()
  state.teamResources.metal = {800, 10000, 1000, 1200, 1000, 0, 0, 0}
  state.teamResources.energy = {100, 10000, 1000, 900, 900, 0, 0, 0}
  api.beginFrame()
  local _, _, _, _, metalStall = api.getResourceStatus('metal')
  local _, _, _, _, energyStall = api.getResourceStatus('energy')
  assertFalse(metalStall, 'pull above stock is not a stall while income covers it')
  assertTrue(energyStall, 'one second of runway is a stall')

  state.teamResources.metal = {5000, 10000, 12000, 15000, 12000, 0, 0, 0}
  api.beginFrame()
  local _, _, _, _, bigEconomyStall = api.getResourceStatus('metal')
  assertFalse(bigEconomyStall, 'rising storage in a big economy is not a stall')
  state.teamResources.metal = nil
  state.teamResources.energy = nil
end)

test('resource trend is the windowed mean with a dead band', function()
  assertEqual(api.trendSign({50, 50, -10, 50, 50}, 10), 1, 'one dip does not reset a rising trend')
  assertEqual(api.trendSign({5, -5, 5, -5, 5}, 10), 0, 'noise inside the dead band is flat')
  assertEqual(api.trendSign({-50, -50, -50}, 10), -1, 'falling trend')
  assertEqual(api.trendSign({}, 10), 0, 'empty window is flat')

  initialize()
  state.teamResources.metal = {5000, 10000, 6000, 8000, 6000, 0, 0, 0}
  state.teamResources.energy = {5000, 10000, 900, 1000, 900, 0, 0, 0}
  api.updateResourceNeeds()
  local metalRising, metalFalling, energyRising, energyFalling = api.getTrend()
  assertTrue(metalRising, 'first sample after initialize lands in the window')
  assertFalse(metalFalling, 'rising metal is not falling')
  assertTrue(energyRising, 'rising energy')
  assertFalse(energyFalling, 'rising energy is not falling')
  state.teamResources.metal = nil
  state.teamResources.energy = nil
end)

test('build power need follows team runway instead of single-target stall predictions', function()
  initialize()
  state.teamResources.metal = {5000, 10000, 12000, 15000, 12000, 0, 0, 0}
  state.teamResources.energy = {5000, 10000, 900, 1000, 900, 0, 0, 0}
  api.updateResourceNeeds()
  local powerNeed = api.getNeeds()
  assertTrue(powerNeed >= 0.75, 'rising metal with pull above stock still wants build power')

  initialize()
  state.teamResources.energy = {500, 10000, 1000, 900, 1000, 0, 0, 0}
  api.updateResourceNeeds()
  powerNeed = api.getNeeds()
  assertEqual(powerNeed, 0, 'energy emptying within the runway horizon blocks build power')

  initialize()
  state.teamResources.metal = {50, 10000, 200, 100, 200, 0, 0, 0}
  state.teamResources.energy = {5000, 10000, 900, 1000, 900, 0, 0, 0}
  api.updateResourceNeeds()
  powerNeed = api.getNeeds()
  assertEqual(powerNeed, 0, 'metal stall blocks build power')
  state.teamResources.metal = nil
  state.teamResources.energy = nil
end)

test('build power need and rounds stop at break-even', function()
  UnitDefs[7] = unitDef({name = 'corfus', canMove = false, metalCost = 1000, energyCost = 10000})
  UnitDefs[11] = unitDef({name = 'armnanotc', buildSpeed = 200, canAssist = true, canMove = false, isBuilder = true})
  initialize({}, {[701] = 7})
  -- 400 build points per second on a fusion costing 1 metal and 10 energy per build point
  api.setAssignedTargetBuildSpeed({[701] = 400})
  api.setTotalBuildSpeed(500)
  -- {current, storage, pull, income, expense, share, sent, received}
  state.teamResources.metal = {9000, 10000, 400, 700, 400, 0, 0, 0}
  state.teamResources.energy = {8000, 10000, 4000, 20000, 4000, 0, 0, 0}
  assertNear(api.buildPowerShortfall(), 200, 1e-9, 'metal feeds 300 more, 100 of which is idle already; energy would feed 1600')
  assertEqual(api.batchSize('power', UnitDefs[11]), 1, '200 short at 200 a turret: one')
  api.updateResourceNeeds()
  assertTrue(api.getNeeds() >= 0.75, 'short of break-even: build power wanted')

  state.teamResources.metal = {9000, 10000, 400, 400, 400, 0, 0, 300}
  assertNear(api.buildPowerShortfall(), 200, 1e-9, 'metal allies hand over is supply too')

  state.teamResources.metal = {9000, 10000, 400, 650, 400, 0, 0, 0}
  assertNear(api.buildPowerShortfall(), 150, 1e-9, '150 short')
  assertEqual(api.batchSize('power', UnitDefs[11]), 0, 'a whole turret would overshoot: none')

  state.teamResources.metal = {9000, 10000, 400, 500, 400, 0, 0, 0}
  assertNear(api.buildPowerShortfall(), 0, 1e-9, 'the idle build power alone uses up the surplus')
  api.updateResourceNeeds()
  assertEqual(api.getNeeds(), 0, 'at break-even: no more build power, assisted or placed')

  api.setAssignedTargetBuildSpeed({})
  assertEqual(api.buildPowerShortfall(), nil, 'nothing under construction: cannot be told')
  api.updateResourceNeeds()
  assertTrue(api.getNeeds() >= 0.75, 'and so does not block')

  api.setTotalBuildSpeed(0)
  state.teamResources.metal = nil
  state.teamResources.energy = nil
  UnitDefs[7], UnitDefs[11] = nil, nil
end)

test('conversion snapshot reads the game rules params and clamps the surplus floor', function()
  initialize()
  state.rulesParams = {mmLevel = 0.88, mmUse = 950, mmCapacity = 1000}
  local snapshot = api.readConversionSnapshot()
  assertTrue(snapshot.available, 'mmLevel present')
  assertTrue(snapshot.saturated, '95% use is saturated')
  assertNear(snapshot.floor, 0.99, 0.000001, 'floor never reaches full storage')

  state.rulesParams = {mmLevel = 0.5, mmUse = 500, mmCapacity = 1000}
  snapshot = api.readConversionSnapshot()
  assertFalse(snapshot.saturated, 'half use is not saturated')
  assertNear(snapshot.floor, 0.62, 0.000001, 'floor is level plus bias')

  state.rulesParams = {mmLevel = 0.5}
  assertTrue(api.readConversionSnapshot().saturated, 'no converters counts as saturated')

  state.rulesParams = {}
  assertFalse(api.readConversionSnapshot().available, 'missing mmLevel is unavailable')
end)

test('conversion level nudges are symmetric, bounded, and rounded', function()
  local throttled = {level = 0.5, capacity = 1000, saturated = false}
  assertNear(api.nudgeMetalMakerLevel(throttled, 0.97, false), 0.52, 0.000001, 'full metal raises the floor')
  assertEqual(api.nudgeMetalMakerLevel({level = 0.75, capacity = 1000, saturated = false}, 0.97, false), nil, 'raise stops at the cap')
  assertEqual(api.nudgeMetalMakerLevel({level = 0.88, capacity = 1000, saturated = false}, 0.97, false), nil, 'manual levels above the cap are left alone')
  assertNear(api.nudgeMetalMakerLevel({level = 0.2, capacity = 1000, saturated = false}, 0.5, true), 0.18, 0.000001, 'leaking energy lowers a throttling floor')
  assertEqual(api.nudgeMetalMakerLevel({level = 0.12, capacity = 1000, saturated = false}, 0.5, true), nil, 'lower stops at the UI floor')
  assertEqual(api.nudgeMetalMakerLevel({level = 0.5, capacity = 1000, saturated = true}, 0.5, true), nil, 'saturated converters are not the floor problem')
  assertEqual(api.nudgeMetalMakerLevel({level = 0.5, capacity = 0, saturated = true}, 0.5, true), nil, 'no converters, nothing to nudge')
  assertEqual(api.nudgeMetalMakerLevel({level = 0.14, capacity = 0, saturated = true}, 0.97, false), nil, 'no converters leaves a manual level alone even with full metal')
  assertEqual(api.nudgeMetalMakerLevel({level = 0.5, capacity = 1000, saturated = false}, 0.97, true), nil, 'both overflowing leaves the floor alone')
  assertEqual(api.nudgeMetalMakerLevel({level = 0.5, capacity = 1000, saturated = false}, 0.5, false), nil, 'balanced eco leaves the floor alone')

  initialize()
  state.rulesParams = {mmLevel = 0.57, mmUse = 0, mmCapacity = 1000}
  state.teamResources.metal = {970, 1000, 0, 100, 50, 0, 0, 0}
  state.teamResources.energy = {500, 1000, 0, 100, 50, 0, 0, 0}
  api.updateResourceNeeds()
  assertTrue(api.sendNudgedMetalMakerLevel(), 'full metal sends a raise')
  assertEqual(state.lastRulesMessage, string.char(137) .. '59', 'raise is rounded, not floored')

  initialize()
  state.rulesParams = {mmLevel = 0.2, mmUse = 500, mmCapacity = 1000}
  state.teamResources.metal = {500, 1000, 0, 100, 50, 0, 0, 0}
  state.teamResources.energy = {1000, 1000, 0, 500, 100, 0, 0, 0}
  api.updateResourceNeeds()
  assertTrue(api.sendNudgedMetalMakerLevel(), 'leaking energy sends a lower')
  assertEqual(state.lastRulesMessage, string.char(137) .. '18', 'lower steps by two percent')

  state.rulesParams.mmUse = 960
  api.updateResourceNeeds()
  assertFalse(api.sendNudgedMetalMakerLevel(), 'saturated converters send nothing')
  state.teamResources.metal = nil
  state.teamResources.energy = nil
end)

test('evaluator seam reports decisions, needs, and eco classification', function()
  initialize()
  local emitted = {}
  WG.eco_cons.setDecisionSink(function(kind) emitted[#emitted + 1] = kind end)
  state.rulesParams = {mmLevel = 0.57, mmUse = 0, mmCapacity = 1000}
  state.teamResources.metal = {970, 1000, 0, 100, 50, 0, 0, 0}
  state.teamResources.energy = {500, 1000, 0, 100, 50, 0, 0, 0}
  api.updateResourceNeeds()
  api.sendNudgedMetalMakerLevel()
  assertEqual(emitted[1], 'mm_up', 'nudge is reported with its direction')

  api.setNeeds(0.1, 0.2, 0.3)
  local decisionState = WG.eco_cons.getDecisionState()
  assertEqual(decisionState.energyNeed, 0.2, 'needs are exposed')
  decisionState.energyNeed = 9
  assertEqual(WG.eco_cons.getDecisionState().energyNeed, 0.2, 'state is a copy')
  assertEqual(WG.eco_cons.ecoTypeOf(1), 'power', 'builders count as build power')
  assertEqual(WG.eco_cons.ecoTypeOf(3), nil, 'non-eco defs have no type')

  WG.eco_cons.setDecisionSink(nil)
  state.teamResources.metal = nil
  state.teamResources.energy = nil
end)

test('a small need is not inflated to every builder while the dominant need has nothing to assist', function()
  UnitDefs[5] = unitDef({extractsMetal = 1, isBuilding = true, translatedHumanName = 'mex'})
  initialize()
  state.defIDs = {[40] = 4, [50] = 5}
  local candidateByDef = {[4] = 40}
  local savedGetTeamUnitsByDefs = Spring.GetTeamUnitsByDefs
  Spring.GetTeamUnitsByDefs = function(_, defIDs)
    local units = {}
    for _, defID in ipairs(defIDs) do
      units[#units + 1] = candidateByDef[defID]
    end
    return units
  end
  state.health = {[40] = {health = 50, maxHealth = 100, build = 0.5}, [50] = {health = 50, maxHealth = 100, build = 0.5}}

  api.setNeeds(0.19, 0, 0.98)
  local needs = api.normalizedPositiveNeeds()
  assertEqual(#needs, 1, 'the need without unfinished buildings is dropped')
  assertNear(needs[1].value, 0.19, 0.000001, 'the remaining need keeps its own share')

  candidateByDef[5] = 50
  api.setNeeds(0.75, 0, 0.99)
  needs = api.normalizedPositiveNeeds()
  assertEqual(needs[1].name, 'mMM', 'largest need first')
  assertNear(needs[1].value + needs[2].value, 1, 0.000001, 'oversubscribed needs split every builder')

  Spring.GetTeamUnitsByDefs = savedGetTeamUnitsByDefs
  state.health = {}
  UnitDefs[5] = nil
end)

test('a target about to be finished by its current builders is not a candidate', function()
  initialize({101}, {[101] = 1, [401] = 4, [402] = 4})
  state.teamUnitsByDefs = {401, 402}
  state.health = {[401] = {health = 90, maxHealth = 100, build = 0.9}, [402] = {health = 90, maxHealth = 100, build = 0.9}}
  state.positions = {[401] = {50, 0, 0}, [402] = {60, 0, 0}}
  api.setAssignedTargetBuildSpeed({[401] = 500, [402] = 50})

  local candidates = api.getCandidateAlternatives({4})
  assertEqual(#candidates, 1, 'the target finishing within a second is skipped')
  assertEqual(candidates[1].id, 402, 'the one that takes longer remains')

  api.setAssignedTargetBuildSpeed({})
  assertEqual(#api.getCandidateAlternatives({4}), 2, 'nobody on it: both remain')

  state.teamUnitsByDefs = {}
  state.health = {}
  state.positions = {}
end)

test('family keys join faction and scav versions, adjacent spots touch the anchor', function()
  assertEqual(api.familyKey('armfus'), 'fus', 'arm prefix')
  assertEqual(api.familyKey('corfus_scav'), 'fus', 'cor prefix and scav suffix')
  assertEqual(api.familyKey('legmmkr'), 'mmkr', 'leg prefix')
  local spots = api.adjacentPositions(1000, 2000, 24, 16, 8, 8)
  assertEqual(spots[1][1] .. ',' .. spots[1][2], '1032,2000', 'east: anchor half + own half')
  assertEqual(spots[4][1] .. ',' .. spots[4][2], '1000,1976', 'north likewise with z extents')
end)

test('the family the player invested most in is extended, not the most numerous', function()
  UnitDefs[7] = unitDef({name = 'corfus', energyMake = 1000, canMove = false, cost = 4000, xsize = 6, zsize = 6})
  UnitDefs[8] = unitDef({name = 'armfus', energyMake = 1000, canMove = false, cost = 4000, xsize = 6, zsize = 6})
  UnitDefs[12] = unitDef({name = 'armwin', energyMake = 10, canMove = false, cost = 40})
  UnitDefs[10] = unitDef({buildOptions = {8, 12}, buildSpeed = 100, canAssist = true, isBuilder = true, name = 'armck'})
  initialize({110}, {[110] = 10, [701] = 7, [721] = 12, [722] = 12, [723] = 12})
  state.teamUnitsByDefs = {701, 721, 722, 723}
  state.health = {}
  for _, unitID in ipairs(state.teamUnitsByDefs) do
    state.health[unitID] = {health = 100, maxHealth = 100, build = 1}
  end
  state.positions = {[110] = {0, 0, 0}, [701] = {1000, 0, 1000}, [721] = {100, 0, 0}, [722] = {200, 0, 0}, [723] = {300, 0, 0}}
  state.openSpots = {['1048,1000'] = true, ['332,0'] = true}
  state.selectedUnits = {}
  api.refreshSelectedUnits()
  state.lastOrder = nil

  api.setNeeds(0, 0.95, 0)
  api.placeForNeeds(100)
  assertEqual(state.lastOrder and state.lastOrder.params[2], -8, 'one fusion outweighs three wind turbines')

  state.lastOrder = nil
  state.openSpots = nil
  state.teamUnitsByDefs = {}
  state.health = {}
  state.positions = {}
  UnitDefs[7], UnitDefs[8], UnitDefs[10], UnitDefs[12] = nil, nil, nil, nil
end)

test('a round places as many buildings as the shortfall calls for, each on its own spot', function()
  UnitDefs[7] = unitDef({name = 'corfus', energyMake = 100, canMove = false, xsize = 6, zsize = 6})
  UnitDefs[10] = unitDef({buildOptions = {7}, buildSpeed = 100, canAssist = true, isBuilder = true, name = 'corck'})
  initialize({110}, {[110] = 10, [701] = 7})
  state.teamUnitsByDefs = {701}
  state.health = {[701] = {health = 100, maxHealth = 100, build = 1}}
  state.positions = {[110] = {0, 0, 0}, [701] = {1000, 0, 1000}}
  -- open: east of the anchor, and the two spots continuing that row; nothing else
  state.openSpots = {['1048,1000'] = true, ['1096,1000'] = true, ['1144,1000'] = true}
  state.selectedUnits = {}
  api.refreshSelectedUnits()

  state.teamResources.metal = {100000, 100000, 0, 100, 0, 0, 0, 0}
  state.teamResources.energy = {10, 1000, 350, 100, 100, 0, 0, 0}
  assertEqual(api.batchSize('energy', UnitDefs[7]), 3, '250 short at 100 each: three')
  state.teamResources.energy = {10, 1000, 5000, 100, 100, 0, 0, 0}
  assertEqual(api.batchSize('energy', UnitDefs[7]), 6, 'capped')
  assertEqual(api.batchSize('power', UnitDefs[7]), 0, 'build power: none while nothing is under construction')
  state.teamResources.metal = {1000, 10000, 0, 100, 0, 0, 0, 0}
  UnitDefs[7].cost = 1400
  assertEqual(api.batchSize('energy', UnitDefs[7]), 2, 'capped by stored metal plus 20 s of income: 3000 pays for two')
  UnitDefs[7].cost = 5000
  assertEqual(api.batchSize('energy', UnitDefs[7]), 1, 'never less than one')
  UnitDefs[7].cost = 100
  state.teamResources.metal = {100000, 100000, 0, 100, 0, 0, 0, 0}

  state.orders = {}
  api.setNeeds(0, 0.95, 0)
  api.placeForNeeds(100)
  assertEqual(#state.orders, 3, 'only three spots are open, each ordered once')
  assertEqual(state.orders[1].params[1] .. '@' .. state.orders[1].params[4], '0@1048', 'first touches the anchor')
  assertEqual(state.orders[2].params[1] .. '@' .. state.orders[2].params[4], '1@1096', 'second continues from the first')
  assertEqual(state.orders[3].params[1] .. '@' .. state.orders[3].params[4], '2@1144', 'third continues the row')

  state.orders = nil
  state.lastOrder = nil
  state.teamResources.energy = nil
  state.teamResources.metal = nil
  state.openSpots = nil
  state.teamUnitsByDefs = {}
  state.health = {}
  state.positions = {}
  UnitDefs[7], UnitDefs[10] = nil, nil
end)

test('a busy builder is borrowed only when no idle one can place, never off a frame it builds alone', function()
  UnitDefs[7] = unitDef({name = 'corfus', energyMake = 100, canMove = false, xsize = 6, zsize = 6})
  UnitDefs[10] = unitDef({buildOptions = {7}, buildSpeed = 100, canAssist = true, isBuilder = true, name = 'corck'})
  local function setUp(teamUnits)
    local defIDs = {[701] = 7}
    for _, unitID in ipairs(teamUnits) do defIDs[unitID] = 10 end
    initialize(teamUnits, defIDs)
    state.teamUnitsByDefs = {701}
    state.health = {[701] = {health = 100, maxHealth = 100, build = 1}}
    state.positions = {[110] = {900, 0, 1000}, [112] = {0, 0, 0}, [113] = {950, 0, 1000}, [701] = {1000, 0, 1000}}
    state.openSpots = {['1048,1000'] = true}
    state.selectedUnits = {}
    api.refreshSelectedUnits()
    state.lastOrder = nil
    api.setNeeds(0, 0.95, 0)
  end
  local ownBuildQueue = {{id = -7, params = {3000, 0, 3000, 0}, tag = 1}}

  setUp({110})
  state.commands[110] = ownBuildQueue
  api.builderById(110).targetId = 950
  api.setAssignedTargetBuildSpeed({[950] = 100})
  api.placeForNeeds(100)
  assertEqual(state.lastOrder, nil, 'it is the only one on its frame: left alone')

  api.setAssignedTargetBuildSpeed({[950] = 500})
  api.placeForNeeds(100)
  assertEqual(state.lastOrder and state.lastOrder.unitID, 110, 'others are on its frame too: borrowed')

  setUp({110, 112, 113})
  state.commands[110] = ownBuildQueue
  state.commands[113] = {{id = CMD.MOVE, params = {0, 0, 0}, tag = 1}}
  api.builderById(110).targetId = 950
  api.setAssignedTargetBuildSpeed({[950] = 500})
  api.placeForNeeds(100)
  assertEqual(state.lastOrder and state.lastOrder.unitID, 112, 'an idle builder goes first though it is further away; a moving one never')

  state.commands[110], state.commands[113] = nil, nil
  api.setAssignedTargetBuildSpeed({})
  state.lastOrder = nil
  state.openSpots = nil
  state.teamUnitsByDefs = {}
  state.health = {}
  state.positions = {}
  UnitDefs[7], UnitDefs[10] = nil, nil
end)

test('an acting advisor is waited for briefly, can change the family or call a round off, and never stalls it', function()
  UnitDefs[7] = unitDef({name = 'corfus', energyMake = 1000, canMove = false, cost = 4000, xsize = 6, zsize = 6})
  UnitDefs[12] = unitDef({name = 'corwin', energyMake = 10, canMove = false, cost = 40})
  UnitDefs[10] = unitDef({buildOptions = {7, 12}, buildSpeed = 100, canAssist = true, isBuilder = true, name = 'corck'})
  local function setUp()
    initialize({110}, {[110] = 10, [701] = 7, [721] = 12})
    state.teamUnitsByDefs = {701, 721}
    state.health = {[701] = {health = 100, maxHealth = 100, build = 1}, [721] = {health = 100, maxHealth = 100, build = 1}}
    state.positions = {[110] = {0, 0, 0}, [701] = {1000, 0, 1000}, [721] = {100, 0, 0}}
    state.openSpots = {['1048,1000'] = true, ['132,0'] = true}
    state.selectedUnits = {}
    api.refreshSelectedUnits()
    state.lastOrder = nil
    api.setNeeds(0, 0.95, 0)
  end

  setUp()
  api.placeForNeeds(100)
  assertEqual(state.lastOrder.params[2], -7, 'no advisor: the heuristic family, at once')
  local context = WG.eco_cons.getAdvisorContext()
  assertEqual(#context.rounds, 1, 'the round is still visible to an advisor that only watches')
  assertEqual(context.rounds[1].ecoType .. ':' .. context.rounds[1].heuristicFamily, 'energy:fus', 'with what the heuristics chose')
  assertEqual(#context.rounds[1].families, 2, 'and every family owned, to choose from')

  setUp()
  WG.eco_cons.setAdvisorMode('act')
  api.placeForNeeds(100)
  assertEqual(state.lastOrder, nil, 'acting advisor: the due round waits')
  WG.eco_cons.setAdvice('energy', {frame = 110, family = 'win', place = true})
  api.placeForNeeds(130)
  assertEqual(state.lastOrder.params[2], -12, 'and follows the advised family')

  setUp()
  WG.eco_cons.setAdvisorMode('act')
  api.placeForNeeds(100)
  api.placeForNeeds(130)
  api.placeForNeeds(160)
  assertEqual(state.lastOrder, nil, 'still inside the wait')
  api.placeForNeeds(190)
  assertEqual(state.lastOrder.params[2], -7, 'no advice in time: the heuristics go ahead')

  setUp()
  WG.eco_cons.setAdvisorMode('act')
  api.placeForNeeds(100)
  WG.eco_cons.setAdvice('energy', {frame = 110, place = false})
  api.placeForNeeds(130)
  api.placeForNeeds(160)
  assertEqual(state.lastOrder, nil, 'advised against: nothing placed, and not retried at once')

  setUp()
  WG.eco_cons.setAdvisorMode('act')
  WG.eco_cons.setAdvice('energy', {frame = 100, family = 'win', place = true})
  api.placeForNeeds(400)
  assertEqual(state.lastOrder, nil, 'stale advice does not count as advice: the round waits for fresh one')

  state.lastOrder = nil
  state.openSpots = nil
  state.teamUnitsByDefs = {}
  state.health = {}
  state.positions = {}
  UnitDefs[7], UnitDefs[10], UnitDefs[12] = nil, nil, nil
end)

test('queued buildings are part of the cluster: a round goes beyond them and never onto them', function()
  UnitDefs[7] = unitDef({name = 'corfus', energyMake = 100, canMove = false, xsize = 6, zsize = 6})
  UnitDefs[10] = unitDef({buildOptions = {7}, buildSpeed = 100, canAssist = true, isBuilder = true, name = 'corck'})
  local function setUp(standing, queuedXs, openSpots)
    local defIDs = {[110] = 10, [112] = 10}
    state.teamUnitsByDefs, state.health, state.positions = {}, {}, {[110] = {900, 0, 1000}, [112] = {0, 0, 0}}
    for index, x in ipairs(standing) do
      local unitID = 700 + index
      defIDs[unitID] = 7
      state.teamUnitsByDefs[index] = unitID
      state.health[unitID] = {health = 100, maxHealth = 100, build = 1}
      state.positions[unitID] = {x, 0, 1000}
    end
    initialize({110, 112}, defIDs)
    state.commands[112] = {}
    for index, x in ipairs(queuedXs) do
      state.commands[112][index] = {id = -7, params = {x, 0, 1000, 0}, tag = index}
    end
    state.openSpots = openSpots
    state.selectedUnits = {}
    api.refreshSelectedUnits()
    state.lastOrder = nil
    api.setNeeds(0, 0.95, 0)
  end

  -- another builder has the next two spots of the row queued; to the engine they are open ground
  setUp({1000}, {1048, 1096}, {['1048,1000'] = true, ['1096,1000'] = true, ['1144,1000'] = true})
  api.placeForNeeds(100)
  assertEqual(state.lastOrder.unitID, 110, 'the idle builder places, not the one whose queue it is')
  assertEqual(state.lastOrder.params[4], 1144, 'beyond the end of the queued row')

  -- a queued gap between two standing buildings is the only spot the engine calls open on that row
  local emitted = {}
  setUp({1000, 1096}, {1048}, {['1048,1000'] = true, ['1000,1048'] = true})
  WG.eco_cons.setDecisionSink(function(kind) emitted[kind] = true end)
  api.placeForNeeds(100)
  assertEqual(state.lastOrder.params[4] .. ',' .. state.lastOrder.params[6], '1000,1048', 'the queued gap is left to its owner')
  assertTrue(emitted.avoided_queued_spot == true, 'and the log says a queued spot was avoided')

  WG.eco_cons.setDecisionSink(nil)
  state.commands[112] = nil
  state.lastOrder = nil
  state.openSpots = nil
  state.teamUnitsByDefs = {}
  state.health = {}
  state.positions = {}
  UnitDefs[7], UnitDefs[10] = nil, nil
end)

test('a starved need with nothing to assist places the scav version next to the nearest cluster', function()
  UnitDefs[7] = unitDef({name = 'corfus', energyMake = 100, canMove = false, xsize = 6, zsize = 6})
  UnitDefs[8] = unitDef({name = 'armfus', energyMake = 100, canMove = false, xsize = 6, zsize = 6})
  UnitDefs[9] = unitDef({name = 'armfus_scav', energyMake = 100, canMove = false, xsize = 6, zsize = 6})
  UnitDefs[10] = unitDef({buildOptions = {8, 9}, buildSpeed = 100, canAssist = true, isBuilder = true, name = 'armck'})
  initialize({110, 111, 701, 702}, {[110] = 10, [111] = 10, [701] = 7, [702] = 7})
  state.teamUnitsByDefs = {701, 702}
  state.health = {[701] = {health = 100, maxHealth = 100, build = 1}, [702] = {health = 100, maxHealth = 100, build = 1}}
  state.positions = {[110] = {0, 0, 0}, [701] = {1000, 0, 1000}, [702] = {1048, 0, 1000}}
  state.openSpots = {['1096,1000'] = true}
  state.featureSpots = {['952,1000'] = true}
  state.selectedUnits = {}
  api.refreshSelectedUnits()
  state.lastOrder = nil

  api.setNeeds(0, 0.95, 0)
  api.placeForNeeds(100)
  local order = state.lastOrder
  assertEqual(order.unitID, 110, 'the free mobile builder gets the order; 111 died and has no position')
  assertEqual(order.cmdID, CMD.INSERT, 'inserted ahead of its queue')
  assertEqual(order.params[2], -9, 'scav version preferred over armfus')
  assertEqual(order.params[4] .. ',' .. order.params[6], '1096,1000', 'the open spot, not the one with a wreck on it')

  state.lastOrder = nil
  state.commands[110] = {{id = -9, params = {1096, 0, 1000, 0}, tag = 5}}
  api.placeForNeeds(500)
  assertEqual(state.lastOrder, nil, 'nothing more while the builder still holds the build order')
  state.commands[110] = nil
  api.placeForNeeds(600)
  assertEqual(state.lastOrder, nil, 'nor right after: the cooldown runs from when the round was last under way')

  state.teamUnitsByDefs = {701, 702, 703}
  state.defIDs[703] = 7
  state.health[703] = {health = 10, maxHealth = 100, build = 0.1}
  state.positions[703] = {1096, 0, 1000}
  api.setAssignedTargetBuildSpeed({[703] = 1000000})
  assertEqual(#api.getCandidateAlternatives({7}), 0, 'about to finish: no longer an assist candidate')
  api.placeForNeeds(1000)
  assertEqual(state.lastOrder, nil, 'yet an unfinished building of the type still blocks placement')
  api.setAssignedTargetBuildSpeed({})

  api.setNeeds(0, 0.5, 0)
  state.teamUnitsByDefs = {701, 702}
  api.placeForNeeds(2000)
  assertEqual(state.lastOrder, nil, 'a moderate need does not place')

  -- a row of 45: the builder stands at the west end, the only open side is at the east end
  state.teamUnitsByDefs = {}
  for i = 1, 45 do
    local unitID = 800 + i
    state.teamUnitsByDefs[i] = unitID
    state.defIDs[unitID] = 7
    state.health[unitID] = {health = 100, maxHealth = 100, build = 1}
    state.positions[unitID] = {1000 + 48 * i, 0, 1000}
  end
  state.positions[110] = {1000, 0, 1000}
  state.openSpots = {['3208,1000'] = true}
  api.setNeeds(0, 0.95, 0)
  api.placeForNeeds(2500)
  assertEqual(state.lastOrder and state.lastOrder.params[4], 3208, 'the open side at the far edge of a long cluster is found')
  state.lastOrder = nil

  -- build power: a nano turret next to the existing one, but only while the builders there are busy
  -- and the resources feed more build power than the team has
  UnitDefs[11] = unitDef({name = 'armnanotc', buildSpeed = 200, canAssist = true, canMove = false, isBuilder = true})
  UnitDefs[10].buildOptions = {8, 9, 11}
  initialize({110}, {[110] = 10, [901] = 11, [902] = 8})
  state.teamUnitsByDefs = {901}
  state.health = {[901] = {health = 100, maxHealth = 100, build = 1}}
  state.positions = {[110] = {5000, 0, 5100}, [901] = {5000, 0, 5000}}
  state.openSpots = {['5032,5000'] = true}
  -- 400 build points per second on a fusion costing 0.1 metal and 1 energy per build point
  api.setAssignedTargetBuildSpeed({[902] = 400})
  api.setTotalBuildSpeed(400)
  state.teamResources.metal = {5000, 10000, 40, 70, 40, 0, 0, 0}
  state.teamResources.energy = {5000, 10000, 400, 2000, 400, 0, 0, 0}
  api.setNeeds(1, 0, 0)
  api.setBuildPowerUtilization(0.3)
  api.placeForNeeds(100)
  assertEqual(state.lastOrder, nil, 'no turret while most build power is idle')
  api.setBuildPowerUtilization(0.9)
  state.teamResources.metal = {5000, 10000, 40, 40, 40, 0, 0, 0}
  api.placeForNeeds(100)
  assertEqual(state.lastOrder, nil, 'no turret while the metal is spoken for')
  state.teamResources.metal = {5000, 10000, 40, 70, 40, 0, 0, 0}
  api.placeForNeeds(400)
  assertEqual(state.lastOrder and state.lastOrder.params[2], -11, 'a turret once the existing build power is busy and fed')
  state.lastOrder = nil
  state.teamResources.metal = nil
  state.teamResources.energy = nil
  api.setAssignedTargetBuildSpeed({})
  api.setTotalBuildSpeed(0)
  UnitDefs[11] = nil

  api.setNeeds(0, 0.95, 0)
  local savedGetTeamUnitDefCount = Spring.GetTeamUnitDefCount
  Spring.GetTeamUnitDefCount = function() error('boom') end
  state.echoes = {}
  api.runPlacement(3000)
  assertEqual(#state.echoes, 1, 'a fault inside placement is reported, not raised')
  Spring.GetTeamUnitDefCount = savedGetTeamUnitDefCount
  api.runPlacement(4000)
  assertEqual(state.lastOrder, nil, 'and placement stays off for the rest of the game')

  state.openSpots = nil
  state.featureSpots = nil
  state.teamUnitsByDefs = {}
  state.health = {}
  state.positions = {}
  UnitDefs[7], UnitDefs[8], UnitDefs[9], UnitDefs[10] = nil, nil, nil, nil
end)

test('resources are sampled on a fixed frame cadence independent of the builder roster', function()
  initialize()
  widget:GameFrame(30)
  assertEqual(state.teamResourceCalls, 2, 'sample frame reads both resources once')
  widget:GameFrame(31)
  assertEqual(state.teamResourceCalls, 2, 'builder frames do not sample resources')
  widget:GameFrame(60)
  assertEqual(state.teamResourceCalls, 4, 'next sample frame reads again')
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

test('a stale command is removed once while its REMOVE is on the way, and again if it outlives that', function()
  initialize({101}, {[101] = 1})
  state.health[501] = {health = 100, maxHealth = 100, build = 1}
  state.commands[101] = {{id = CMD.REPAIR, params = {501}, tag = 1}}
  state.gameFrame = 200
  api.beginFrame()
  local _, count = api.getPurgedUnitCommands(101)
  assertEqual(count, 0, 'stale repair leaves the logical queue')
  assertEqual(state.removeOrderBatches, 1, 'removal issued')

  state.gameFrame = 201
  api.beginFrame()
  _, count = api.getPurgedUnitCommands(101)
  assertEqual(count, 0, 'still out of the logical queue while the removal travels')
  assertEqual(state.removeOrderBatches, 1, 'no second removal a frame later')

  state.gameFrame = 215
  api.beginFrame()
  api.getPurgedUnitCommands(101)
  assertEqual(state.removeOrderBatches, 2, 'removal resent when the command is still there')

  state.gameFrame = nil
  state.health[501] = nil
end)

test('a nano turret keeps the FIGHT order that a mobile builder loses over a finished building', function()
  UnitDefs[6] = unitDef({buildSpeed = 100, canAssist = true, canMove = false, isBuilder = true, translatedHumanName = 'nano turret'})
  initialize({101, 102}, {[101] = 1, [102] = 6, [601] = 4})
  state.health[601] = {health = 100, maxHealth = 100, build = 1}
  state.unitsInCylinder = {601}
  local fight = {{id = CMD.FIGHT, params = {50, 0, 50}, tag = 1}}
  state.commands[101] = fight
  state.commands[102] = fight
  api.beginFrame()

  local _, mobileCount = api.getPurgedUnitCommands(101)
  assertEqual(mobileCount, 0, 'mobile builder FIGHT over a finished building is purged')
  assertEqual(state.removeOrderBatches, 1, 'one removal issued')
  local _, turretCount = api.getPurgedUnitCommands(102)
  assertEqual(turretCount, 1, 'nano turret FIGHT stays')
  assertEqual(state.removeOrderBatches, 1, 'no removal issued for the turret')

  state.health[602] = {health = 40, maxHealth = 100, build = 1}
  state.outOfRange = {[602] = true}
  local walkedOff = {{id = CMD.REPAIR, params = {602}, tag = 2}}
  state.commands[101] = walkedOff
  state.commands[102] = walkedOff
  api.beginFrame()
  _, mobileCount = api.getPurgedUnitCommands(101)
  assertEqual(mobileCount, 1, 'a mobile builder keeps a repair order beyond its range: it can walk')
  _, turretCount = api.getPurgedUnitCommands(102)
  assertEqual(turretCount, 0, 'a turret loses a repair order it can never reach')
  assertEqual(state.removeOrderBatches, 2, 'one more removal, for the turret')
  state.outOfRange = nil
  state.health[602] = nil

  state.unitsInCylinder = nil
  state.health[601] = nil
  UnitDefs[6] = nil
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

  local builderSnapshot = {builder = {def = {buildDistance = 100, canMove = true}}, x = 0, z = 0, radius = 10}
  assertTrue(api.isWithinBuildRange(builderSnapshot, {x = 117, z = 0, radius = 20}), 'inside surface range')
  assertFalse(api.isWithinBuildRange(builderSnapshot, {x = 118, z = 0, radius = 20}), 'strict range boundary')

  local turretSnapshot = {builder = {def = {buildDistance = 100, canMove = false}}, x = 0, z = 0, radius = 30}
  assertTrue(api.isWithinBuildRange(turretSnapshot, {x = 119, z = 0, radius = 20}), 'turret reaches buildDistance + target radius')
  assertFalse(api.isWithinBuildRange(turretSnapshot, {x = 121, z = 0, radius = 20}), 'turret own radius adds no reach')
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
  state.defIDs[401] = 4
  state.defIDs[402] = 4
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
