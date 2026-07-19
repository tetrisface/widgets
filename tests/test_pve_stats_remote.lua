local root = PVE_STATS_TEST_ROOT or (arg and arg[1]) or "./"
local T = dofile(root .. "tests/support.lua")
local Remote = dofile(root .. "include/pve_stats_remote.lua")

local function SocketForResponse(raw, options)
	options = options or {}
	local socket = {connectedHost = nil, connectedPort = nil, request = nil, closed = false}
	local client = {
		settimeout = function(_, value) socket.timeout = value end,
		connect = function(_, host, port)
			socket.connectedHost = host
			socket.connectedPort = port
			if options.pendingConnect then return nil, "timeout" end
			return true
		end,
		send = function(_, request, start)
			socket.request = request
			if options.partialSend and not socket.sentPart then
				socket.sentPart = true
				return nil, "timeout", math.min(#request, start + 8)
			end
			return #request
		end,
		receive = function()
			if options.partialReceive and not socket.receivedPart then
				socket.receivedPart = true
				return nil, "timeout", string.sub(raw, 1, 12)
			end
			local remainder = options.partialReceive and string.sub(raw, 13) or raw
			return nil, "closed", remainder
		end,
		close = function() socket.closed = true end,
	}
	socket.tcp = function()
		socket.created = (socket.created or 0) + 1
		return client
	end
	socket.select = function(readable, writable)
		if #writable > 0 then return {}, {client}, nil end
		return {client}, {}, nil
	end
	return socket
end

local function PollToCompletion(socket, body)
	local operation, err = Remote.Start(socket, body or "{}", 0)
	T.truthy(operation)
	T.equals(err, nil)
	for index = 1, 8 do
		local response, pollError, finished, meta = Remote.Poll(operation, index)
		if finished then return response, pollError, meta, operation end
	end
	error("remote operation did not finish")
end

local function testFixedTargetAndRequestContract()
	local raw = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}"
	local socket = SocketForResponse(raw, {partialSend = true, partialReceive = true})
	local response, err = PollToCompletion(socket, "{}")
	T.equals(response, "{}")
	T.equals(err, nil)
	T.equals(socket.connectedHost, "d29i3oohxql6zz.cloudfront.net")
	T.equals(socket.connectedPort, 80)
	T.equals(socket.timeout, 0)
	T.contains(socket.request, "POST /stats HTTP/1.1\r\n")
	T.contains(socket.request, "Host: d29i3oohxql6zz.cloudfront.net:80\r\n")
	T.contains(socket.request, "Content-Type: application/json\r\n")
	T.notContains(socket.request, "Authorization:")
	T.truthy(socket.closed)
end

local function testModuleHasOnlyTheAuditedOperations()
	local expected = {Start = true, Poll = true, Cancel = true, Target = true}
	for key in pairs(Remote) do T.truthy(expected[key], "unexpected remote export " .. tostring(key)) end
	local target = Remote.Target()
	target.host = "changed.test"
	T.equals(Remote.Target().host, "d29i3oohxql6zz.cloudfront.net")
end

local function testDisabledSocketCreatesNothing()
	local operation, err = Remote.Start(nil, "{}", 0)
	T.equals(operation, nil)
	T.equals(err.code, "lua_socket_disabled")
	T.falsy(err.retryable)
	operation, err = Remote.Start({tcp = function() error("unavailable") end, select = function() end}, "{}", 0)
	T.equals(operation, nil)
	T.equals(err.code, "socket_create_failed")
	T.falsy(err.retryable)
	operation, err = Remote.Start({tcp = function() error("must not be called") end, select = function() end}, {}, 0)
	T.equals(operation, nil)
	T.equals(err.code, "invalid_request_body")
end

local function testOnlyOneOperationCanBeActive()
	local firstSocket = SocketForResponse("", {pendingConnect = true})
	local first = assert(Remote.Start(firstSocket, "{}", 0))
	local secondSocket = SocketForResponse("")
	local second, err = Remote.Start(secondSocket, "{}", 0)
	T.equals(second, nil)
	T.equals(err.code, "request_in_progress")
	T.equals(secondSocket.created, nil)
	Remote.Cancel(first)
	local replacement = assert(Remote.Start(secondSocket, "{}", 0))
	Remote.Cancel(replacement)
end

local function testRequestAndResponseLimits()
	local created = false
	local socket = {tcp = function() created = true end, select = function() end}
	local operation, err = Remote.Start(socket, string.rep("x", 256 * 1024 + 1), 0)
	T.equals(operation, nil)
	T.equals(err.code, "request_body_too_large")
	T.falsy(created)

	local largeHeader = "HTTP/1.1 200 OK\r\nX-Test: " .. string.rep("x", 64 * 1024) .. "\r\n\r\n{}"
	local _, headerError = PollToCompletion(SocketForResponse(largeHeader), "{}")
	T.equals(headerError.code, "response_headers_too_large")
	local largeBody = string.rep("x", 1024 * 1024 + 1)
	local raw = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n" .. largeBody
	local _, bodyError = PollToCompletion(SocketForResponse(raw), "{}")
	T.equals(bodyError.code, "response_body_too_large")
end

local function testHttpFailuresAreClassifiedWithoutRetainingBodies()
	local redirect = "HTTP/1.1 302 Found\r\nContent-Length: 0\r\n\r\n"
	local _, redirectError = PollToCompletion(SocketForResponse(redirect))
	T.equals(redirectError.code, "http_redirect")
	T.falsy(redirectError.retryable)

	local body = '{"Reason":"ReservedFunctionConcurrentInvocationLimitExceeded","private":"discarded"}'
	local busy = "HTTP/1.1 503 Busy\r\nContent-Type: application/json\r\nContent-Length: " .. #body .. "\r\n\r\n" .. body
	local response, busyError, meta, operation = PollToCompletion(SocketForResponse(busy))
	T.equals(response, nil)
	T.equals(busyError.code, "reserved_concurrency")
	T.truthy(busyError.retryable)
	local allowedErrorFields = {code = true, retryable = true, httpStatus = true}
	for key in pairs(busyError) do T.truthy(allowedErrorFields[key], "unexpected remote error field") end
	T.equals(meta.http_status, 503)
	T.equals(#operation.responseParts, 0)

	for _, case in ipairs({
		{status = 429, code = "rate_limited", retryable = true},
		{status = 500, code = "http_500", retryable = true},
		{status = 400, code = "http_400", retryable = false},
	}) do
		local failure = "HTTP/1.1 " .. tostring(case.status) .. " Failure\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}"
		local _, failureError = PollToCompletion(SocketForResponse(failure))
		T.equals(failureError.code, case.code)
		T.equals(failureError.retryable, case.retryable)
	end
	local _, malformed = PollToCompletion(SocketForResponse("not http"))
	T.equals(malformed.code, "invalid_http_response")
	T.falsy(malformed.retryable)
end

local function testContentContractAndTimeouts()
	local wrongType = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 2\r\n\r\n{}"
	local _, contentError = PollToCompletion(SocketForResponse(wrongType))
	T.equals(contentError.code, "unexpected_content_type")
	local missingType = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}"
	_, contentError = PollToCompletion(SocketForResponse(missingType))
	T.equals(contentError.code, "unexpected_content_type")

	local pending = SocketForResponse("", {pendingConnect = true})
	local operation = assert(Remote.Start(pending, "{}", 0))
	local _, timeout, finished = Remote.Poll(operation, 30)
	T.truthy(finished)
	T.equals(timeout.code, "connecting_timeout")
	T.truthy(pending.closed)

	local sending = SocketForResponse("")
	operation = assert(Remote.Start(sending, "{}", 0))
	local _, sendTimeout = Remote.Poll(operation, 30)
	T.equals(sendTimeout.code, "sending_timeout")

	local receiving = SocketForResponse("")
	operation = assert(Remote.Start(receiving, "{}", 0))
	Remote.Poll(operation, 1)
	local _, receiveTimeout = Remote.Poll(operation, 30)
	T.equals(receiveTimeout.code, "receiving_timeout")
	T.truthy(receiving.closed)
end

local function testCancelClosesTheSocket()
	local socket = SocketForResponse("", {pendingConnect = true})
	local operation = assert(Remote.Start(socket, "{}", 0))
	Remote.Cancel(operation)
	T.equals(operation.phase, "finished")
	T.equals(operation.error.code, "cancelled")
	T.truthy(socket.closed)
end

local function testSocketPrimitivesStayInsideRemoteModule()
	local production = {
		"gui_pve_stats.lua",
		"include/pve_stats_request.lua",
		"include/pve_stats_display.lua",
		"include/pve_stats_player_stats.lua",
		"include/pve_stats_histogram.lua",
		"include/pve_stats_diagnostics.lua",
		"include/pve_stats_view_model.lua",
		"include/pve_stats_fetch.lua",
	}
	for _, path in ipairs(production) do
		local source = T.read(root .. path)
		for _, primitive in ipairs({"socket.tcp", ":connect(", ":send(", ":receive(", ".select("}) do
			T.notContains(source, primitive, path .. " must not perform remote I/O")
		end
	end
end

local function testReviewerAuditSurfaceIsLinkedAndComplete()
	local readme = T.read(root .. "README.md")
	T.contains(readme, "[`pve_stats_request.lua`](include/pve_stats_request.lua)")
	T.contains(readme, "[`pve_stats_remote.lua`](include/pve_stats_remote.lua)")
	T.contains(readme, "POST http://d29i3oohxql6zz.cloudfront.net:80/stats")
	T.contains(readme, "seven")
	T.contains(readme, "does not poll periodically")
	T.contains(readme, "30-second deadline")
	T.contains(readme, "256 KiB request body")
	T.contains(readme, "64 KiB response headers")
	T.contains(readme, "1 MiB response body")
	T.contains(readme, "unencrypted HTTP")
end

testFixedTargetAndRequestContract()
testModuleHasOnlyTheAuditedOperations()
testDisabledSocketCreatesNothing()
testOnlyOneOperationCanBeActive()
testRequestAndResponseLimits()
testHttpFailuresAreClassifiedWithoutRetainingBodies()
testContentContractAndTimeouts()
testCancelClosesTheSocket()
testSocketPrimitivesStayInsideRemoteModule()
testReviewerAuditSurfaceIsLinkedAndComplete()

print("test_pve_stats_remote.lua: ok")
