local HttpClient = {}

local CONNECT_PENDING_ERRORS = {
	["timeout"] = true,
	["Operation already in progress"] = true,
	["already in progress"] = true,
}

local function Close(operation)
	if operation.client then
		operation.client:close()
		operation.client = nil
	end
end

local function FinishError(operation, err)
	Close(operation)
	operation.phase = "finished"
	operation.error = err
	return nil, err, true
end

local function BuildRequest(endpoint, body)
	return table.concat({
		"POST " .. endpoint.path .. " HTTP/1.1\r\n",
		"Host: " .. endpoint.host .. ":" .. tostring(endpoint.port) .. "\r\n",
		"Content-Type: application/json\r\n",
		"Content-Length: " .. tostring(#body) .. "\r\n",
		"Connection: close\r\n",
		"\r\n",
		body,
	})
end

function HttpClient.Start(socketApi, endpoint, body, options)
	options = options or {}
	if not socketApi or not socketApi.tcp or not socketApi.select then
		return nil, "missing_nonblocking_socket"
	end

	local client = socketApi.tcp()
	client:settimeout(0)
	local connected, connectErr = client:connect(endpoint.host, endpoint.port)
	if not connected and not CONNECT_PENDING_ERRORS[tostring(connectErr)] then
		client:close()
		return nil, "connect_failed:" .. tostring(connectErr)
	end

	local startedSeconds = tonumber(options.started_seconds) or 0
	local timeoutSeconds = math.max(0.001, tonumber(options.timeout_seconds) or 20)
	return {
		socketApi = socketApi,
		client = client,
		phase = connected and "sending" or "connecting",
		request = BuildRequest(endpoint, tostring(body or "")),
		sentBytes = 0,
		responseParts = {},
		startedSeconds = startedSeconds,
		deadlineSeconds = startedSeconds + timeoutSeconds,
	}
end

local function PollConnection(operation)
	local _, writable, selectErr = operation.socketApi.select({}, {operation.client}, 0)
	if selectErr and selectErr ~= "timeout" then
		return FinishError(operation, "connect_failed:" .. tostring(selectErr))
	end
	if not writable or #writable == 0 then
		return nil, nil, false
	end
	operation.phase = "sending"
	return nil, nil, false
end

local function PollSend(operation)
	local lastByte, sendErr, partial = operation.client:send(operation.request, operation.sentBytes + 1)
	if lastByte then
		operation.sentBytes = lastByte
	elseif partial and partial > operation.sentBytes then
		operation.sentBytes = partial
	elseif sendErr ~= "timeout" then
		return FinishError(operation, "send_failed:" .. tostring(sendErr))
	end

	if operation.sentBytes >= #operation.request then
		operation.phase = "receiving"
	end
	return nil, nil, false
end

local function AppendResponse(operation, value)
	if value and value ~= "" then
		operation.responseParts[#operation.responseParts + 1] = value
	end
end

local function PollReceive(operation)
	local readable, _, selectErr = operation.socketApi.select({operation.client}, {}, 0)
	if selectErr and selectErr ~= "timeout" then
		return FinishError(operation, "receive_failed:" .. tostring(selectErr))
	end
	if not readable or #readable == 0 then
		return nil, nil, false
	end

	local response, receiveErr, partial = operation.client:receive("*a")
	AppendResponse(operation, response)
	AppendResponse(operation, partial)
	if receiveErr == "timeout" then
		return nil, nil, false
	end
	if receiveErr and receiveErr ~= "closed" then
		return FinishError(operation, "receive_failed:" .. tostring(receiveErr))
	end

	local raw = table.concat(operation.responseParts)
	if raw == "" then
		return FinishError(operation, "receive_failed:" .. tostring(receiveErr))
	end
	Close(operation)
	operation.phase = "finished"
	operation.response = raw
	return raw, nil, true
end

function HttpClient.Poll(operation, nowSeconds)
	if not operation or operation.phase == "finished" then
		return operation and operation.response or nil, operation and operation.error or "missing_operation", true
	end
	if tonumber(nowSeconds) and tonumber(nowSeconds) >= operation.deadlineSeconds then
		local timeoutErrors = {
			connecting = "connect_failed:timeout",
			sending = "send_failed:timeout",
			receiving = "receive_failed:timeout",
		}
		return FinishError(operation, timeoutErrors[operation.phase] or "request_failed:timeout")
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
	return FinishError(operation, "invalid_phase:" .. tostring(operation.phase))
end

function HttpClient.Cancel(operation)
	if not operation or operation.phase == "finished" then
		return
	end
	Close(operation)
	operation.phase = "finished"
	operation.error = "cancelled"
end

return HttpClient
