-- luacheck: globals ECO_CONS_JEV_TEST socket Json pcall type
-- luacheck: no self

function widget:GetInfo()
  return {
    name = 'eco cons jev',
    desc = 'Asks TypeSafe Jev, through the local scripts/jev_bridge.py, which building eco cons should place. In shadow mode it only logs the answers as [eco_jev] lines',
    author = 'tetrisface',
    date = '2026-10-05',
    license = 'Public Domain',
    layer = 0,
    enabled = true
  }
end

-- The non-blocking HTTP client lives with the PvE stats widget; without it this widget stands down.
local hasHttpClient, HttpClient = pcall(VFS.Include, 'LuaUI/Widgets/gui_pve_stats/include/pve_stats_http_client.lua')
local Json = Json or VFS.Include('common/luaUtilities/json.lua')

local MODE = 'shadow'          -- 'shadow': log what Jev answers; 'act': hand its advice to eco cons
local BRIDGE = {host = '127.0.0.1', port = 8377, path = '/systemone'}
local POLL_SECONDS = 0.5       -- how often eco cons is asked whether a round is due
local REQUEST_TIMEOUT_SECONDS = 2
local RETRY_AFTER_FAILURE_SECONDS = 30
local FAMILY_CONFIDENCE = 0.5  -- Jev's family choice is passed on at or above this
local PLACE_NO = 0.35          -- a place_now answer below this calls the round off

local SHORTAGE = {energy = 'energy', mMM = 'metal', power = 'build_power'}

-- Upper bounds and the word for everything below them; the last word covers the rest.
local STORAGE = {{0.05, 'empty'}, {0.25, 'low'}, {0.75, 'about half'}, {0.95, 'high'}, 'full'}
local PAID_FOR_SECONDS = {{2, 'at once'}, {10, 'quickly'}, {30, 'slowly'}, 'very slowly'}
local COVERS_SHORTAGE = {{0.05, 'a sliver of it'}, {0.3, 'a small part of it'}, {0.7, 'a good part of it'}, {1, 'most of it'}, 'all of it'}
local BUILD_POWER_BUSY = {{0.4, 'mostly idle'}, {0.75, 'partly busy'}, 'busy'}

--------------------------------------------------------------------------------
-- Pure core. No Spring calls.
--------------------------------------------------------------------------------

local function bucket(value, steps)
  for i = 1, #steps - 1 do
    if value < steps[i][1] then
      return steps[i][2]
    end
  end
  return steps[#steps]
end

local function resourceFacts(snapshot)
  local demand = math.max(snapshot.expenseWanted, snapshot.expenseActual)
  local flow = 'balanced'
  if demand > snapshot.income * 1.05 then
    flow = 'more is wanted than comes in'
  elseif snapshot.income > demand * 1.05 then
    flow = 'more comes in than is used'
  end
  return {storage = bucket(snapshot.level, STORAGE), flow = flow}
end

-- All arithmetic happens here and every figure leaves as a word. Models of this kind are "not a
-- calculator" and cannot reliably tell whether two numbers are close (TypeSafe's limitations page
-- for Jev), and a short state of only what the questions need is judged best.
-- context and due are what WG.eco_cons.getAdvisorContext() returns and one of its rounds.
local function buildState(context, due)
  local metalIncome = math.max(context.metal.income, 1)
  local options = {}
  for _, family in ipairs(due.families) do
    local facts = {
      unit = family.unit,
      already_owned = family.owned,
      paid_for = bucket(family.cost / metalIncome, PAID_FOR_SECONDS)
    }
    if due.shortfall > 0 and family.perBuilding > 0 then
      facts.covers_the_shortage = bucket(family.perBuilding / due.shortfall, COVERS_SHORTAGE)
    end
    options[family.family] = facts
  end
  return {
    shortage = SHORTAGE[due.ecoType],
    metal = resourceFacts(context.metal),
    energy = resourceFacts(context.energy),
    build_power = bucket(context.utilization, BUILD_POWER_BUSY),
    options = options
  }
end

-- Narrow questions, each about one judgement. A choice needs at least two options.
local function buildQuestions(due)
  local questions = {
    place_now = {
      type = 'noul',
      instructions = {
        question = 'Is starting one of the buildings in `options` now a good use of resources?',
        compare = {'`metal`', '`energy`', '`options`'},
        focus = 'No if `metal.storage` is empty and every option is `paid_for` slowly or very slowly.'
      }
    },
    shortage_is_real = {
      type = 'noul',
      instructions = 'Is the resource named in `shortage` really running short right now, judging by its figures?'
    }
  }
  if #due.families >= 2 then
    local criteria = {}
    for _, family in ipairs(due.families) do
      criteria[family.family] = 'Build another `options.' .. family.family .. '` (' .. family.unit .. ').'
    end
    questions.family = {
      type = 'choice',
      instructions = {
        question = 'Which building in `options` should be built now to relieve the `shortage`?',
        focus = 'The one that relieves it soonest. One that is `paid_for` very slowly relieves nothing soon; one whose `covers_the_shortage` is a sliver hardly helps.'
      },
      criteria = criteria
    }
  end
  return questions
end

-- Advice for eco cons, gated: a family only when Jev is confident and names one the team owns,
-- a veto only on a clear no. Everything else leaves eco cons to its own choice.
local function interpret(answers, due)
  local advice = {place = true}
  local family = answers.family
  if family and (family.confidence or 0) >= FAMILY_CONFIDENCE then
    for _, owned in ipairs(due.families) do
      if owned.family == family.choice then
        advice.family = family.choice
      end
    end
  end
  local placeNow = answers.place_now
  if placeNow and placeNow.noul and placeNow.noul < PLACE_NO then
    advice.place = false
  end
  return advice
end

local function describe(answers, due, advice)
  local parts = {due.ecoType .. ':'}
  if answers.family then
    parts[#parts + 1] = string.format(
      'family %s %.2f (ec %s)', tostring(answers.family.choice), answers.family.confidence or 0, tostring(due.heuristicFamily)
    )
  end
  for _, name in ipairs({'place_now', 'shortage_is_real'}) do
    if answers[name] and answers[name].noul then
      parts[#parts + 1] = string.format('%s %.2f', name, answers[name].noul)
    end
  end
  parts[#parts + 1] = '-> ' .. (advice.place and (advice.family or 'ec choice') or 'do not place')
  return table.concat(parts, ' ')
end

local function parseResponse(raw)
  return tonumber(raw:match('^HTTP/%d%.%d (%d%d%d)')), raw:match('\r\n\r\n(.*)$')
end

--------------------------------------------------------------------------------
-- Spring glue
--------------------------------------------------------------------------------

local clockSeconds = 0
local sincePollSeconds = 0
local silentUntilSeconds = 0
local inFlight -- {operation, due, startedSeconds} of the one request under way
local askedOpenFrame = {} -- eco type -> openFrame of the round Jev was already asked about
local modeOwner -- the WG.eco_cons table our mode is set on
local totals = {answered = 0, failed = 0, inputTokens = 0, outputTokens = 0}

local function log(line)
  Spring.Echo('[eco_jev] ' .. line)
end

-- WG.eco_cons is a new table each time eco cons initializes; follow it.
local function ecoConsApi()
  local api = WG.eco_cons
  if not (api and api.getAdvisorContext) then
    return
  end
  if api ~= modeOwner then
    api.setAdvisorMode(MODE == 'act' and 'act' or nil)
    modeOwner = api
  end
  return api
end

local function fail(reason)
  totals.failed = totals.failed + 1
  silentUntilSeconds = clockSeconds + RETRY_AFTER_FAILURE_SECONDS
  log(string.format('no answer: %s (asking again in %d s)', tostring(reason), RETRY_AFTER_FAILURE_SECONDS))
end

local function startRequest(context, due)
  askedOpenFrame[due.ecoType] = due.openFrame
  local body = Json.encode({model = 'jev-latest', state = buildState(context, due), questions = buildQuestions(due)})
  local operation, startError = HttpClient.Start(
    socket, BRIDGE, body, {started_seconds = clockSeconds, timeout_seconds = REQUEST_TIMEOUT_SECONDS}
  )
  if not operation then
    return fail(startError)
  end
  inFlight = {operation = operation, due = due, startedSeconds = clockSeconds}
end

local function finishRequest(request, raw)
  local status, body = parseResponse(raw)
  local isDecoded, response = pcall(Json.decode, body or '')
  if status ~= 200 or not isDecoded or type(response) ~= 'table' or type(response.answers) ~= 'table' then
    return fail('status ' .. tostring(status) .. ' ' .. tostring(body):sub(1, 120))
  end

  local due = request.due
  local advice = interpret(response.answers, due)
  local usage = response.usage or {}
  totals.answered = totals.answered + 1
  totals.inputTokens = totals.inputTokens + (usage.input_tokens or 0)
  totals.outputTokens = totals.outputTokens + (usage.output_tokens or 0)
  log(string.format(
    '%s | %s | %s | %.0f ms | tokens %d+%d',
    describe(response.answers, due, advice), MODE, tostring(response.model),
    (clockSeconds - request.startedSeconds) * 1000, usage.input_tokens or 0, usage.output_tokens or 0
  ))

  local api = ecoConsApi()
  if MODE == 'act' and api then
    api.setAdvice(due.ecoType, {frame = Spring.GetGameFrame(), family = advice.family, place = advice.place})
  end
end

local function maybeRemoveSelf()
  if Spring.GetSpectatingState() or Spring.IsReplay() then
    widgetHandler:RemoveWidget()
  end
end

function widget:Initialize()
  if not (hasHttpClient and HttpClient and socket) then
    log('needs LuaSocket and the gui_pve_stats HTTP client; standing down')
    widgetHandler:RemoveWidget()
    return
  end
  maybeRemoveSelf()
end

function widget:PlayerChanged()
  maybeRemoveSelf()
end

function widget:Update(deltaSeconds)
  clockSeconds = clockSeconds + deltaSeconds
  if inFlight then
    local raw, requestError, isFinished = HttpClient.Poll(inFlight.operation, clockSeconds)
    if isFinished then
      local request = inFlight
      inFlight = nil
      if raw then
        finishRequest(request, raw)
      else
        fail(requestError)
      end
    end
    return
  end

  sincePollSeconds = sincePollSeconds + deltaSeconds
  if sincePollSeconds < POLL_SECONDS or clockSeconds < silentUntilSeconds then
    return
  end
  sincePollSeconds = 0
  local api = ecoConsApi()
  if not api then
    return
  end
  local context = api.getAdvisorContext()
  for _, due in ipairs(context.rounds) do
    if askedOpenFrame[due.ecoType] ~= due.openFrame and #due.families > 0 then
      return startRequest(context, due)
    end
  end
end

function widget:Shutdown()
  if inFlight then
    HttpClient.Cancel(inFlight.operation)
  end
  if modeOwner then
    modeOwner.setAdvisorMode(nil)
  end
  if totals.answered + totals.failed > 0 then
    log(string.format(
      'total: %d answered, %d failed, tokens %d+%d',
      totals.answered, totals.failed, totals.inputTokens, totals.outputTokens
    ))
  end
end

if ECO_CONS_JEV_TEST then
  return {
    buildState = buildState,
    buildQuestions = buildQuestions,
    interpret = interpret,
    describe = describe,
    parseResponse = parseResponse
  }
end
