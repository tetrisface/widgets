local root = PVE_STATS_TEST_ROOT or (arg and arg[1]) or "./"
local T = dofile(root .. "tests/support.lua")
local Fetch = dofile(root .. "include/fetch.lua")

local function FakeRemote(outcomes)
	local remote = {starts = 0, cancellations = 0, outcomes = outcomes or {}, bodies = {}}
	function remote.Start(_socket, body, started)
		remote.starts = remote.starts + 1
		remote.bodies[#remote.bodies + 1] = body
		local outcome = table.remove(remote.outcomes, 1) or {body = "{}", meta = {http_status = 200, response_bytes = 2}}
		if outcome.startError then return nil, outcome.startError end
		return {body = body, started = started, outcome = outcome}
	end
	function remote.Poll(operation)
		local outcome = operation.outcome
		return outcome.body, outcome.error, true, outcome.meta
	end
	function remote.Cancel()
		remote.cancellations = remote.cancellations + 1
	end
	return remote
end

local function testRetriesReuseOneRequestIdentity()
	local remote = FakeRemote({
		{error = {code = "receive_timeout", retryable = true}},
		{body = "{}", meta = {http_status = 200, response_bytes = 2}},
	})
	local builds = 0
	local encodes = 0
	local fetch = Fetch.New(
		remote,
		{},
		function()
			builds = builds + 1
			return {ai_type = "Raptors", map = "Map", identity = builds}
		end,
		function(request) return request end,
		{
			encode = function(request)
				encodes = encodes + 1
				return "request-" .. tostring(request.identity)
			end,
			decode = function() return {} end,
		}
	)
	fetch:Request(0)
	T.equals(fetch:Update(0, 0).kind, "started")
	local retry = fetch:Update(0, 0.1)
	T.equals(retry.kind, "retrying")
	T.equals(fetch:Snapshot().retryAttempt, 1)
	T.equals(fetch:Update(retry.delay, 0.1 + retry.delay).kind, "started")
	T.equals(fetch:Update(0, 0.2 + retry.delay).kind, "succeeded")
	T.equals(fetch:Snapshot().retryAttempt, 0)
	T.equals(builds, 1)
	T.equals(encodes, 1)
	T.equals(remote.bodies[1], remote.bodies[2])
end

local function Json(response)
	return {
		encode = function() return "encoded-request" end,
		decode = function(body)
			if body == "invalid" then error("not json") end
			return response or {match_status = "exact"}
		end,
	}
end

local function Controller(remote, json)
	return Fetch.New(
		remote,
		{},
		function() return T.request() end,
		function(request) return request end,
		json or Json()
	)
end

local function testScheduleSuccessAndNoPeriodicRequests()
	local remote = FakeRemote()
	local fetch = Controller(remote)
	T.truthy(fetch:Schedule(2, 0))
	T.equals(fetch:Snapshot().phase, "scheduled")
	T.equals(fetch:Update(1, 1), nil)
	local started = fetch:Update(1, 2)
	T.equals(started.kind, "started")
	T.equals(fetch:Snapshot().phase, "requesting")
	local succeeded = fetch:Update(0, 2.1)
	T.equals(succeeded.kind, "succeeded")
	T.equals(fetch:Snapshot().phase, "idle")
	T.equals(fetch:Snapshot().lastError, nil)
	T.equals(fetch:Snapshot().lastEvidence.status, "ok")
	for now = 3, 20 do T.equals(fetch:Update(1, now), nil) end
	T.equals(remote.starts, 1)
end

local function testOnlyOneRequestCanBeScheduled()
	local fetch = Controller(FakeRemote())
	T.truthy(fetch:Request(0))
	local ok, err = fetch:Request(0)
	T.falsy(ok)
	T.equals(err, "request_in_progress")
	T.equals(fetch:Snapshot().phase, "scheduled")
end

local function testRetryStopsAfterFiveTotalAttempts()
	local outcomes = {}
	for _ = 1, 5 do outcomes[#outcomes + 1] = {error = {code = "receive_timeout", retryable = true}} end
	local remote = FakeRemote(outcomes)
	local fetch = Controller(remote)
	fetch:Request(0)
	local now = 0
	for attempt = 1, 5 do
		local started = fetch:Update(0, now)
		T.equals(started.kind, "started")
		local result = fetch:Update(0, now + 0.1)
		if attempt < 5 then
			T.equals(result.kind, "retrying")
			T.equals(fetch:Snapshot().phase, "retry_wait")
			now = now + 0.1 + result.delay
		else
			T.equals(result.kind, "failed")
			T.equals(fetch:Snapshot().phase, "idle")
		end
	end
	T.equals(remote.starts, 5)
	T.equals(fetch:Snapshot().attempt, 5)
	T.equals(fetch:Snapshot().lastError, "receive_timeout")
end

local function testTerminalFailuresDoNotRetry()
	local remote = FakeRemote({{startError = {code = "lua_socket_disabled", retryable = false}}})
	local fetch = Controller(remote)
	fetch:Request(0)
	local result = fetch:Update(0, 0)
	T.equals(result.kind, "failed")
	T.equals(fetch:Snapshot().phase, "idle")
	T.equals(fetch:Snapshot().lastError, "lua_socket_disabled")
	T.equals(remote.starts, 1)
end

local function testMalformedJsonIsTerminal()
	local remote = FakeRemote({{body = "invalid", meta = {http_status = 200, response_bytes = 7}}})
	local fetch = Controller(remote, Json())
	fetch:Request(0)
	T.equals(fetch:Update(0, 0).kind, "started")
	local result = fetch:Update(0, 1)
	T.equals(result.kind, "failed")
	T.equals(result.error.code, "invalid_json")
	T.falsy(result.error.retryable)
end

local function testCancellationReturnsToIdle()
	local remote = FakeRemote()
	local fetch = Controller(remote)
	fetch:Request(0)
	fetch:Update(0, 0)
	fetch:Cancel()
	T.equals(fetch:Snapshot().phase, "idle")
	T.equals(remote.cancellations, 1)
end

local function testEvidenceUsesOnlySupportFields()
	local remote = FakeRemote({{body = "{}", meta = {http_status = 200, response_bytes = 2, trace_id = "opaque"}}})
	local fetch = Controller(remote)
	fetch:Request(0)
	fetch:Update(0, 0)
	fetch:Update(0, 0.5)
	local evidence = fetch:Snapshot().lastEvidence
	T.equals(evidence.http_status, 200)
	T.equals(evidence.trace_id, "opaque")
	T.equals(evidence.request_duration_ms, 500)
	local allowed = {
		version = true, status = true, attempt = true, request_bytes = true,
		request_hash = true, request_duration_ms = true, http_status = true,
		response_bytes = true, trace_id = true, retry_class = true,
	}
	for key in pairs(evidence) do T.truthy(allowed[key], "unexpected support-evidence field") end
end

testScheduleSuccessAndNoPeriodicRequests()
testOnlyOneRequestCanBeScheduled()
testRetryStopsAfterFiveTotalAttempts()
testRetriesReuseOneRequestIdentity()
testTerminalFailuresDoNotRetry()
testMalformedJsonIsTerminal()
testCancellationReturnsToIdle()
testEvidenceUsesOnlySupportFields()

print("test_pve_stats_fetch.lua: ok")
