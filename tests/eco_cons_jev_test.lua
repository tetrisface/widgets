-- Run with: lua tests/eco_cons_jev_test.lua
-- luacheck: globals ECO_CONS_JEV_TEST widget VFS Spring WG assert dofile error print type

local function assertEqual(actual, expected, message)
  if actual ~= expected then
    error(string.format('%s: expected %s, got %s', message or 'assertEqual', tostring(expected), tostring(actual)))
  end
end

widget = {}
WG = {}
Spring = {}
VFS = {Include = function() return {} end}

ECO_CONS_JEV_TEST = true
local api = assert(dofile('Widgets/eco_cons_jev.lua'))
ECO_CONS_JEV_TEST = nil

local function snapshot(level, income, expenseActual, expenseWanted)
  return {level = level, income = income, expenseActual = expenseActual, expenseWanted = expenseWanted}
end

local function energyRound(families)
  return {ecoType = 'energy', openFrame = 100, shortfall = 120000, heuristicFamily = 'afust3', families = families}
end

local fusion = {family = 'afust3', unit = 'corafust3', owned = 6, cost = 90000, perBuilding = 45000, investment = 540000}
local wind = {family = 'wint2', unit = 'corwint2', owned = 20, cost = 300, perBuilding = 150, investment = 6000}

local context = {
  frame = 30960,
  metal = snapshot(0.44, 5776, 5921, 5921),
  energy = snapshot(0.04, 91373, 85378, 205378),
  conversion = {capacity = 64340, use = 0},
  buildSpeed = 214838,
  utilization = 0.71
}

local tests = {}

function tests.stateTurnsEveryFigureIntoAWord()
  local state = api.buildState(context, energyRound({fusion, wind}))
  assertEqual(state.shortage, 'energy')
  assertEqual(state.energy.storage, 'empty', '4% stored')
  assertEqual(state.energy.flow, 'more is wanted than comes in', '205378 wanted against 91373 income')
  assertEqual(state.metal.storage, 'about half', '44% stored')
  assertEqual(state.metal.flow, 'balanced', '5921 wanted against 5776 income')
  assertEqual(state.build_power, 'partly busy', '71% of build power building')
  assertEqual(state.options.afust3.paid_for, 'slowly', '90000 metal is 15.6 s of income')
  assertEqual(state.options.afust3.covers_the_shortage, 'a good part of it', '45000 of a 120000 shortfall')
  assertEqual(state.options.wint2.paid_for, 'at once', '300 metal')
  assertEqual(state.options.wint2.covers_the_shortage, 'a sliver of it', '150 of 120000')
  assertEqual(state.options.wint2.already_owned, 20)

  local metalRound = {ecoType = 'mMM', openFrame = 1, shortfall = 0, families = {{family = 'mmkrt3', unit = 'cormmkrt3', owned = 3, cost = 9000, perBuilding = 6000}}}
  local metalState = api.buildState(context, metalRound)
  assertEqual(metalState.shortage, 'metal', 'metal makers relieve a metal shortage')
  assertEqual(metalState.options.mmkrt3.paid_for, 'at once', '9000 metal is 1.6 s of income')
  assertEqual(metalState.options.mmkrt3.covers_the_shortage, nil, 'no shortfall known: no share claimed')
end

function tests.familyIsOnlyAskedWhenThereIsAChoice()
  local both = api.buildQuestions(energyRound({fusion, wind}))
  assertEqual(both.family.type, 'choice')
  assertEqual(type(both.family.criteria.afust3), 'string', 'one option per owned family')
  assertEqual(type(both.family.criteria.wint2), 'string')
  assertEqual(both.place_now.type, 'noul')

  local single = api.buildQuestions(energyRound({fusion}))
  assertEqual(single.family, nil, 'one family: nothing to choose')
  assertEqual(single.place_now.type, 'noul', 'the timing is still asked')
end

function tests.adviceIsGatedOnConfidenceAndAClearNo()
  local due = energyRound({fusion, wind})
  local confident = api.interpret({family = {choice = 'wint2', confidence = 0.8}, place_now = {noul = 0.9}}, due)
  assertEqual(confident.family, 'wint2', 'confident choice is passed on')
  assertEqual(confident.place, true)

  assertEqual(api.interpret({family = {choice = 'wint2', confidence = 0.3}}, due).family, nil, 'unsure: eco cons keeps its own')
  assertEqual(api.interpret({family = {choice = 'solar', confidence = 0.9}}, due).family, nil, 'a family the team does not own is ignored')
  assertEqual(api.interpret({place_now = {noul = 0.2}}, due).place, false, 'a clear no calls the round off')
  assertEqual(api.interpret({place_now = {noul = 0.45}}, due).place, true, 'an unsure no does not')
  assertEqual(api.interpret({}, due).place, true, 'no answers: no interference')
end

function tests.describeShowsJevNextToEcoCons()
  local due = energyRound({fusion, wind})
  local answers = {family = {choice = 'wint2', confidence = 0.8}, place_now = {noul = 0.9}, shortage_is_real = {noul = 0.97}}
  assertEqual(
    api.describe(answers, due, api.interpret(answers, due)),
    'energy: family wint2 0.80 (ec afust3) place_now 0.90 shortage_is_real 0.97 -> wint2'
  )
  assertEqual(api.describe({place_now = {noul = 0.1}}, due, {place = false}), 'energy: place_now 0.10 -> do not place')
end

function tests.parseResponseSplitsStatusAndBody()
  local status, body = api.parseResponse('HTTP/1.0 200 OK\r\nContent-Type: application/json\r\n\r\n{"answers":{}}')
  assertEqual(status, 200)
  assertEqual(body, '{"answers":{}}')
  assertEqual(api.parseResponse('garbage'), nil, 'not HTTP')
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
print(string.format('Passed %d eco_cons_jev tests.', #names))
