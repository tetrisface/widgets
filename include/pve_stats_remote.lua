-- This is the widget's complete remote-connection policy and its only
-- production remote-I/O module:
--   POST JSON to http://d29i3oohxql6zz.cloudfront.net:80/stats
--   accept JSON; represent every request as an independent non-blocking operation
--   enforce a 30-second attempt deadline, 256 KiB request-body limit,
--   64 KiB response-header limit, and 1 MiB response-body limit
--   do not redirect, authenticate, retain cookies, download or write files,
--   or interpret response data as executable content
-- Callers cannot supply or override the destination.

local Remote = {}

local TARGET = {
	host = "d29i3oohxql6zz.cloudfront.net",
	port = 80,
	path = "/stats",
}

local METHOD = "POST"
local CONTENT_TYPE = "application/json"
local ATTEMPT_TIMEOUT_SECONDS = 30
local MAX_REQUEST_BYTES = 256 * 1024
local MAX_RESPONSE_HEADER_BYTES = 64 * 1024
local MAX_RESPONSE_BODY_BYTES = 1024 * 1024

local CONNECT_PENDING_ERRORS = {
	["timeout"] = true,
	["Operation already in progress"] = true,
	["already in progress"] = true,
}

local function Error(code, retryable, httpStatus)
	return {
		code = code,
		retryable = retryable == true,
		httpStatus = httpStatus,
	}
end

local function Close(operation)
	if operation.client then
		if operation.client.close then pcall(operation.client.close, operation.client) end
		operation.client = nil
	end
end

local function FinishError(operation, err)
	Close(operation)
	operation.phase = "finished"
	operation.error = err
	operation.response = nil
	operation.responseParts = {}
	return nil, err, true, operation.meta
end

local function BuildHttpRequest(body)
	return table.concat({
		METHOD .. " " .. TARGET.path .. " HTTP/1.1\r\n",
		"Host: " .. TARGET.host .. ":" .. tostring(TARGET.port) .. "\r\n",
		"Content-Type: " .. CONTENT_TYPE .. "\r\n",
		"Accept: " .. CONTENT_TYPE .. "\r\n",
		"Content-Length: " .. tostring(#body) .. "\r\n",
		"Connection: close\r\n",
		"\r\n",
		body,
	})
end

local function HeaderValue(header, expectedName)
	local expected = string.lower(expectedName)
	for line in string.gmatch(header or "", "[^\r\n]+") do
		local name, value = string.match(line, "^%s*([^:]+):%s*(.-)%s*$")
		if name and string.lower(name) == expected then
			return string.sub(value, 1, 128)
		end
	end
	return nil
end

local function ParseResponse(raw)
	local headerEnd = string.find(raw, "\r\n\r\n", 1, true)
	if not headerEnd then
		return nil, Error("invalid_http_response", false)
	end
	local header = string.sub(raw, 1, headerEnd - 1)
	local body = string.sub(raw, headerEnd + 4)
	if #header > MAX_RESPONSE_HEADER_BYTES then
		return nil, Error("response_headers_too_large", false)
	end
	if #body > MAX_RESPONSE_BODY_BYTES then
		return nil, Error("response_body_too_large", false)
	end

	local status = tonumber(string.match(header, "^HTTP/%d%.%d%s+(%d+)") or "")
	if not status then
		return nil, Error("invalid_http_status", false)
	end
	local meta = {
		http_status = status,
		response_bytes = #body,
		trace_id = HeaderValue(header, "x-request-id")
			or HeaderValue(header, "x-amzn-requestid")
			or HeaderValue(header, "x-amz-cf-id"),
	}

	local transferEncoding = string.lower(HeaderValue(header, "transfer-encoding") or "")
	if transferEncoding ~= "" and transferEncoding ~= "identity" then
		return nil, Error("unsupported_transfer_encoding", false, status), meta
	end
	local contentType = string.lower(HeaderValue(header, "content-type") or "")
	if status >= 200 and status < 300 and not string.find(contentType, "application/json", 1, true) then
		return nil, Error("unexpected_content_type", false, status), meta
	end
	local contentLength = tonumber(HeaderValue(header, "content-length"))
	if contentLength and contentLength ~= #body then
		return nil, Error("invalid_content_length", false, status), meta
	end

	if status >= 300 and status < 400 then
		return nil, Error("http_redirect", false, status), meta
	end
	if status < 200 or status >= 300 then
		local reservedConcurrency = string.find(
			string.lower(body),
			"reservedfunctionconcurrentinvocationlimitexceeded",
			1,
			true
		) ~= nil
		if reservedConcurrency then
			return nil, Error("reserved_concurrency", true, status), meta
		end
		if status == 429 then
			return nil, Error("rate_limited", true, status), meta
		end
		return nil, Error("http_" .. tostring(status), status >= 500, status), meta
	end
	return body, nil, meta
end

local function BufferedResponse(operation)
	return table.concat(operation.responseParts)
end

local function CheckBufferedLimits(operation)
	local raw = BufferedResponse(operation)
	local headerEnd = string.find(raw, "\r\n\r\n", 1, true)
	if not headerEnd then
		if #raw > MAX_RESPONSE_HEADER_BYTES then
			return Error("response_headers_too_large", false)
		end
		return nil
	end
	if headerEnd - 1 > MAX_RESPONSE_HEADER_BYTES then
		return Error("response_headers_too_large", false)
	end
	if #raw - (headerEnd + 3) > MAX_RESPONSE_BODY_BYTES then
		return Error("response_body_too_large", false)
	end
	return nil
end

local function AppendResponse(operation, value)
	if value and value ~= "" then
		operation.responseParts[#operation.responseParts + 1] = value
	end
	return CheckBufferedLimits(operation)
end

function Remote.Target()
	return {
		host = TARGET.host,
		port = TARGET.port,
		path = TARGET.path,
		method = METHOD,
		content_type = CONTENT_TYPE,
	}
end

function Remote.Start(socketApi, jsonBody, startedSeconds)
	if type(jsonBody) ~= "string" or jsonBody == "" then
		return nil, Error("invalid_request_body", false)
	end
	local body = jsonBody
	if #body > MAX_REQUEST_BYTES then
		return nil, Error("request_body_too_large", false)
	end
	if not socketApi or type(socketApi.tcp) ~= "function" or type(socketApi.select) ~= "function" then
		return nil, Error("lua_socket_disabled", false)
	end
	local createOk, client = pcall(socketApi.tcp)
	if not createOk or not client then
		return nil, Error("socket_create_failed", false)
	end
	if type(client.settimeout) ~= "function"
		or type(client.connect) ~= "function"
		or type(client.send) ~= "function"
		or type(client.receive) ~= "function"
		or type(client.close) ~= "function"
	then
		if client.close then pcall(client.close, client) end
		return nil, Error("invalid_socket_client", false)
	end
	local timeoutOk = pcall(client.settimeout, client, 0)
	if not timeoutOk then
		pcall(client.close, client)
		return nil, Error("socket_setup_failed", false)
	end
	local connectOk, connected, connectErr = pcall(client.connect, client, TARGET.host, TARGET.port)
	if not connectOk then
		pcall(client.close, client)
		return nil, Error("connect_failed", true)
	end
	if not connected and not CONNECT_PENDING_ERRORS[tostring(connectErr)] then
		client:close()
		return nil, Error("connect_failed", true)
	end

	local started = tonumber(startedSeconds) or 0
	local operation = {
		socketApi = socketApi,
		client = client,
		phase = connected and "sending" or "connecting",
		request = BuildHttpRequest(body),
		sentBytes = 0,
		responseParts = {},
		deadlineSeconds = started + ATTEMPT_TIMEOUT_SECONDS,
		meta = {},
	}
	return operation
end

local function PollConnection(operation)
	local selectOk, _, writable, selectErr = pcall(
		operation.socketApi.select,
		{},
		{operation.client},
		0
	)
	if not selectOk then return FinishError(operation, Error("connect_failed", true)) end
	if selectErr and selectErr ~= "timeout" then
		return FinishError(operation, Error("connect_failed", true))
	end
	if not writable or #writable == 0 then
		return nil, nil, false, operation.meta
	end
	operation.phase = "sending"
	return nil, nil, false, operation.meta
end

local function PollSend(operation)
	local sendOk, lastByte, sendErr, partial = pcall(
		operation.client.send,
		operation.client,
		operation.request,
		operation.sentBytes + 1
	)
	if not sendOk then return FinishError(operation, Error("send_failed", true)) end
	if lastByte then
		operation.sentBytes = lastByte
	elseif partial and partial > operation.sentBytes then
		operation.sentBytes = partial
	elseif sendErr ~= "timeout" then
		return FinishError(operation, Error("send_failed", true))
	end
	if operation.sentBytes >= #operation.request then
		operation.phase = "receiving"
	end
	return nil, nil, false, operation.meta
end

local function PollReceive(operation)
	local selectOk, readable, _, selectErr = pcall(
		operation.socketApi.select,
		{operation.client},
		{},
		0
	)
	if not selectOk then return FinishError(operation, Error("receive_failed", true)) end
	if selectErr and selectErr ~= "timeout" then
		return FinishError(operation, Error("receive_failed", true))
	end
	if not readable or #readable == 0 then
		return nil, nil, false, operation.meta
	end

	local receiveOk, response, receiveErr, partial = pcall(
		operation.client.receive,
		operation.client,
		"*a"
	)
	if not receiveOk then return FinishError(operation, Error("receive_failed", true)) end
	local limitError = AppendResponse(operation, response) or AppendResponse(operation, partial)
	if limitError then
		return FinishError(operation, limitError)
	end
	if receiveErr == "timeout" then
		return nil, nil, false, operation.meta
	end
	if receiveErr and receiveErr ~= "closed" then
		return FinishError(operation, Error("receive_failed", true))
	end

	local raw = BufferedResponse(operation)
	if raw == "" then
		return FinishError(operation, Error("receive_failed", true))
	end
	Close(operation)
	operation.phase = "finished"
	local body, err, meta = ParseResponse(raw)
	operation.responseParts = {}
	operation.response = body
	operation.error = err
	operation.meta = meta or operation.meta
	return body, err, true, operation.meta
end

function Remote.Poll(operation, nowSeconds)
	if not operation or operation.phase == "finished" then
		local err = operation and operation.error or Error("missing_operation", false)
		return operation and operation.response or nil, err, true, operation and operation.meta or nil
	end
	if tonumber(nowSeconds) and tonumber(nowSeconds) >= operation.deadlineSeconds then
		return FinishError(operation, Error(operation.phase .. "_timeout", true))
	end
	if operation.phase == "connecting" then
		return PollConnection(operation)
	end
	if operation.phase == "sending" then
		return PollSend(operation)
	end
	if operation.phase == "receiving" then
		return PollReceive(operation)
	end
	return FinishError(operation, Error("invalid_remote_phase", false))
end

function Remote.Cancel(operation)
	if not operation or operation.phase == "finished" then
		return
	end
	Close(operation)
	operation.phase = "finished"
	operation.error = Error("cancelled", false)
end

return Remote
