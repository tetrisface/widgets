local repoRoot = (arg and arg[1]) or "./"
local HttpClient = dofile(repoRoot .. "include/pve_stats_http_client.lua")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", actual " .. tostring(actual), 2)
	end
end

local function assertTrue(value, message)
	if not value then
		error(message or "assertTrue failed", 2)
	end
end

local function testRequestCompletesAcrossNonBlockingPolls()
	local sendCalls = 0
	local receiveCalls = 0
	local closed = false
	local client = {
		settimeout = function(_self, timeout)
			assertEquals(timeout, 0)
		end,
		connect = function()
			return nil, "timeout"
		end,
		send = function(_self, request, start)
			sendCalls = sendCalls + 1
			if sendCalls == 1 then
				return nil, "timeout", math.min(#request, start + 9)
			end
			return #request
		end,
		receive = function()
			receiveCalls = receiveCalls + 1
			if receiveCalls == 1 then
				return nil, "timeout", "HTTP/1.1 200 OK\r\n"
			end
			return nil, "closed", "Content-Length: 2\r\n\r\n{}"
		end,
		close = function()
			closed = true
		end,
	}
	local selectCalls = 0
	local socketApi = {
		tcp = function()
			return client
		end,
		select = function(readable, writable)
			selectCalls = selectCalls + 1
			if #writable > 0 then
				return {}, {client}, nil
			end
			return {client}, {}, nil
		end,
	}

	local operation = assert(HttpClient.Start(socketApi, {host = "example.test", port = 80, path = "/stats"}, "{}", {
		started_seconds = 10,
		timeout_seconds = 20,
	}))
	assertEquals(operation.phase, "connecting")

	local raw, err, finished = HttpClient.Poll(operation, 10)
	assertEquals(raw, nil)
	assertEquals(err, nil)
	assertEquals(finished, false)
	assertEquals(operation.phase, "sending")

	raw, err, finished = HttpClient.Poll(operation, 10.1)
	assertEquals(finished, false)
	assertEquals(operation.phase, "sending")
	raw, err, finished = HttpClient.Poll(operation, 10.2)
	assertEquals(finished, false)
	assertEquals(operation.phase, "receiving")
	raw, err, finished = HttpClient.Poll(operation, 10.3)
	assertEquals(finished, false)
	raw, err, finished = HttpClient.Poll(operation, 10.4)
	assertEquals(err, nil)
	assertEquals(finished, true)
	assertEquals(raw, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}")
	assertTrue(closed)
	assertTrue(selectCalls >= 3)
end

local function testRequestTimesOutWithoutBlocking()
	local closed = false
	local client = {
		settimeout = function() end,
		connect = function() return nil, "timeout" end,
		close = function() closed = true end,
	}
	local socketApi = {
		tcp = function() return client end,
		select = function() return {}, {}, "timeout" end,
	}
	local operation = assert(HttpClient.Start(socketApi, {host = "example.test", port = 80, path = "/stats"}, "{}", {
		started_seconds = 5,
		timeout_seconds = 20,
	}))
	local raw, err, finished = HttpClient.Poll(operation, 25)
	assertEquals(raw, nil)
	assertEquals(err, "connect_failed:timeout")
	assertEquals(finished, true)
	assertTrue(closed)
end

testRequestCompletesAcrossNonBlockingPolls()
testRequestTimesOutWithoutBlocking()

print("test_pve_stats_http_client.lua: ok")
