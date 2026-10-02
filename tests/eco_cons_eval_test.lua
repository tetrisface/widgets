-- Run with: lua tests/eco_cons_eval_test.lua
-- luacheck: globals ECO_CONS_EVAL_TEST widget CMD Spring assert dofile error print

local function assertEqual(actual, expected, message)
  if actual ~= expected then
    error(string.format('%s: expected %s, got %s', message or 'assertEqual', tostring(expected), tostring(actual)))
  end
end

local function assertContains(text, fragment, message)
  if not text:find(fragment, 1, true) then
    error(string.format('%s: %q not in %q', message or 'assertContains', fragment, text))
  end
end

widget = {}
CMD = {FIGHT = 16, GUARD = 25, MOVE = 10, PATROL = 15, RECLAIM = 90, REPAIR = 40, WAIT = 5}
Spring = {}

ECO_CONS_EVAL_TEST = true
local api = assert(dofile('Widgets/eco_cons_eval.lua'))
ECO_CONS_EVAL_TEST = nil

local tests = {}

function tests.classifyActivity()
  assertEqual(api.classifyActivity({build = 0.4, ecoType = 'energy'}, CMD.REPAIR), 'energy', 'assisting eco')
  assertEqual(api.classifyActivity({build = 0.4}, -12), 'other', 'non-eco build')
  assertEqual(api.classifyActivity({build = 1, ecoType = 'energy'}, CMD.REPAIR), 'repair', 'finished target')
  assertEqual(api.classifyActivity(nil, nil), 'idle', 'empty queue')
  assertEqual(api.classifyActivity(nil, nil, true), 'idle_nano', 'nano turrets idle apart from mobile builders')
  assertEqual(api.classifyActivity(nil, CMD.FIGHT, true), 'patrol', 'fight order with nothing to do')
  assertEqual(api.classifyActivity(nil, -12), 'travel', 'walking to a build site')
  assertEqual(api.classifyActivity(nil, CMD.REPAIR), 'travel', 'walking to an assist')
  assertEqual(api.classifyActivity(nil, CMD.REPAIR, true), 'stuck', 'nano turret holding an order it does not work on')
  assertEqual(api.classifyActivity(nil, CMD.REPAIR, true, true), 'area', 'area repair with nothing to repair')
  assertEqual(api.classifyActivity(nil, CMD.RECLAIM), 'reclaim')
  assertEqual(api.classifyActivity(nil, CMD.GUARD), 'guard', 'guard with nothing to assist')
  assertEqual(api.classifyActivity(nil, CMD.MOVE), 'move')
  assertEqual(api.classifyActivity(nil, 31337), 'misc', 'custom command')
end

function tests.pollWatchReloadsOnlySettledCompilingChanges()
  local function compile(source)
    if source == 'broken' then return nil, 'syntax error' end
    return true
  end
  local watch = {loaded = 'v1'}
  assertEqual(api.pollWatch(watch, 'v1', compile), nil, 'unchanged file')
  assertEqual(api.pollWatch(watch, nil, compile), nil, 'unreadable file')
  assertEqual(api.pollWatch(watch, 'v2 half', compile), nil, 'first sight of a change waits')
  assertEqual(api.pollWatch(watch, 'v2', compile), nil, 'still being written')
  assertEqual(api.pollWatch(watch, 'v2', compile), 'reload', 'settled change reloads')
  assertEqual(api.pollWatch(watch, 'v2', compile), nil, 'reloaded once')

  api.pollWatch(watch, 'broken', compile)
  local action, compileError = api.pollWatch(watch, 'broken', compile)
  assertEqual(action, 'broken', 'syntax error is reported')
  assertEqual(compileError, 'syntax error', 'with its message')
  assertEqual(api.pollWatch(watch, 'broken', compile), nil, 'and reported once')
  api.pollWatch(watch, 'v3', compile)
  assertEqual(api.pollWatch(watch, 'v3', compile), 'reload', 'the fix reloads')
end

function tests.orderOutcome()
  assertEqual(api.orderOutcome(true, true, false, true), 'ord_took', 'builder works on the target')
  assertEqual(api.orderOutcome(false, false, false, false), 'ord_moot', 'target finished meanwhile')
  assertEqual(api.orderOutcome(false, true, true, true), 'ord_walking', 'order held by a builder that can get there')
  assertEqual(api.orderOutcome(false, true, true, false), 'ord_stuck', 'order held by a turret out of range')
  assertEqual(api.orderOutcome(false, true, false, true), 'ord_lost', 'order gone without being worked on')
end

function tests.stuckCause()
  assertEqual(api.stuckCause(false, false, false), 'gone', 'target died')
  assertEqual(api.stuckCause(true, false, false), 'done', 'stale order on a finished target')
  assertEqual(api.stuckCause(true, true, true), 'near', 'engine refuses a target in range')
  assertEqual(api.stuckCause(true, true, false), 'far', 'target out of range')
end

function tests.resourceOutcome()
  local stall = api.resourceOutcome(10, 1000, 50, 20, 30)
  assertEqual(stall.stalling, true, 'empty with unmet pull')
  assertEqual(stall.unmet, 20, 'unmet is pull - expense')
  assertEqual(api.resourceOutcome(25, 1000, 30, 20, 30).stalling, true, 'every request met but empty within the runway')
  assertEqual(api.resourceOutcome(500, 1000, 30, 20, 30).stalling, false, 'draining slowly from deep storage')
  assertEqual(api.resourceOutcome(1000, 1000, 500, 100, 40).stalling, false, 'full storage with pull left unspent by a stall in the other resource')
  local leak = api.resourceOutcome(1000, 1000, 5, 25, 5)
  assertEqual(leak.leaking, true, 'full and rising')
  assertEqual(leak.overflow, 20, 'overflow is income - expense')
  assertEqual(api.resourceOutcome(1000, 1000, 30, 25, 30).leaking, false, 'full but draining')
  assertEqual(api.resourceOutcome(0, 0, 0, 0, 0).level, 0, 'no storage')
end

local function sample(energyLeaking, shares, decisions, state)
  return {
    metal = api.resourceOutcome(500, 1000, 10, 10, 10),
    energy = energyLeaking and api.resourceOutcome(1000, 1000, 0, 100, 40, 15) or api.resourceOutcome(500, 1000, 40, 40, 40),
    shares = shares,
    buildSpeed = 300,
    builders = 3,
    directed = {energy = 0.25},
    retargets = 1,
    decisions = decisions,
    state = state
  }
end

function tests.summaryBucketsByCondition()
  local stats = api.newStats()
  local state = {powerNeed = 0.2, energyNeed = 0.8, mMMNeed = 0}
  api.accumulate(stats, sample(true, {energy = 0.5, idle = 0.5}, {assign_energy = 2}, state))
  api.accumulate(stats, sample(false, {power = 1}, {}, nil))

  local lines = api.summaryLines(stats, true)
  assertContains(lines[1], 'summary 0:02 eco_cons=on retargets/min=60.0', 'header')
  assertContains(lines[3], 'energy income 140 overflow 60 (43%) excess 15 unmet 0', 'energy overflow share of income')
  assertContains(lines[4], 'all 2s (100%) need p0.20 e0.80 m0.00 | ec energy 25% | all idle 25% power 50% energy 25% | /min assign_energy=60.0', 'all bucket')
  assertContains(lines[5], 'eLeak 1s (50%) need p0.20 e0.80 m0.00 | ec energy 25% | all idle 50% energy 50%', 'leak bucket')
  assertEqual(#lines, 5, 'empty buckets are omitted')
end

function tests.timelineShowsTruthNextToEcoConsView()
  local state = {powerNeed = 0.75, energyNeed = 0, mMMNeed = 1, isEnergyLeaking = true, anyBuildWillMStall = true}
  local line = api.timelineLine(125, sample(true, {mMM = 1}, {}, state), {level = 0.6, use = 300, capacity = 400}, {reclaim = 3, guard = 1}, {energy = 4, other = 1})
  assertEqual(line, '2:05 M 50% +10 -10 E 100% +100 -40 mm 60% 300/400 [eLeak] | ec p0.75 e0.00 m1.00 [eLeak,willMStall] | bp 300 x3 | mMM 100% | ec energy 25% | q energy=4 other=1 | guard=1 reclaim=3')
  assertContains(api.timelineLine(5, sample(false, {}, {}, nil), {level = 0, use = 0, capacity = 0}, {}, {}), 'eco_cons off', 'eco cons absent')
end

local names = {}
for name in pairs(tests) do
  names[#names + 1] = name
end
table.sort(names)
for _, name in ipairs(names) do
  tests[name]()
  print('  [PASS] ' .. name)
end
print(string.format('Passed %d eco_cons_eval tests.', #names))
