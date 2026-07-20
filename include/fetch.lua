local Fetch = {}

local MAX_ATTEMPTS = 5
local RETRY_INITIAL_SECONDS = 2
local RETRY_MAX_SECONDS = 30

local function Error(code)
	return {code = tostring(code or "unknown_error"), retryable = false}
end

local function StableHash(value)
	local text = tostring(value or "")
	local hash = 5381
	for index = 1, #text do
		hash = (hash * 33 + string.byte(text, index)) % 4294967296
	end
	return string.format("%08x", hash)
end

local function RetryDelay(attempt)
	local retryNumber = math.max(1, attempt - 1)
	return math.min(RETRY_INITIAL_SECONDS * (2 ^ (retryNumber - 1)), RETRY_MAX_SECONDS)
end

local function ApplyMeta(evidence, meta)
	if type(meta) ~= "table" then return end
	evidence.http_status = meta.http_status
	evidence.response_bytes = meta.response_bytes
	evidence.trace_id = meta.trace_id
end

function Fetch.New(remote, socketApi, buildRequest, wireRequest, jsonApi)
	local controller = {
		phase = "idle",
		operation = nil,
		attempt = 0,
		dueSeconds = nil,
		delayRemaining = nil,
		lastRequest = nil,
		lastResponse = nil,
		lastError = nil,
		lastErrorInfo = nil,
		lastEvidence = nil,
		requestStartedSeconds = nil,
		encodedBody = nil,
	}

	local function SetWait(phase, delay, nowSeconds)
		controller.phase = phase
		controller.delayRemaining = math.max(0, tonumber(delay) or 0)
		controller.dueSeconds = tonumber(nowSeconds) and (tonumber(nowSeconds) + controller.delayRemaining) or nil
	end

	local function FinishFailure(err, nowSeconds)
		err = type(err) == "table" and err or Error(err)
		controller.lastErrorInfo = err
		controller.lastError = err.code
		if controller.lastEvidence then
			controller.lastEvidence.retry_class = err.code
			controller.lastEvidence.http_status = err.httpStatus or controller.lastEvidence.http_status
			controller.lastEvidence.status = "error"
		end
		if err.retryable == true and controller.attempt < MAX_ATTEMPTS then
			local delay = RetryDelay(controller.attempt + 1)
			SetWait("retry_wait", delay, nowSeconds)
			return {
				kind = "retrying",
				error = err,
				delay = delay,
				attempt = controller.attempt,
				maxAttempts = MAX_ATTEMPTS,
			}
		end
		controller.phase = "idle"
		controller.encodedBody = nil
		controller.dueSeconds = nil
		controller.delayRemaining = nil
		return {kind = "failed", error = err, attempt = controller.attempt, maxAttempts = MAX_ATTEMPTS}
	end

	local function StartAttempt(nowSeconds)
		controller.attempt = controller.attempt + 1
		local body = controller.encodedBody
		if not body then
			local request, requestError = buildRequest()
			controller.lastRequest = request
			if not request then return FinishFailure(Error(requestError), nowSeconds) end

			local wire, wireError = wireRequest(request)
			if not wire then return FinishFailure(Error(wireError), nowSeconds) end
			local ok, encoded = pcall(jsonApi.encode, wire)
			if not ok or type(encoded) ~= "string" then return FinishFailure(Error("encode_failed"), nowSeconds) end
			body = encoded
			controller.encodedBody = body
		end

		controller.lastEvidence = {
			version = 1,
			status = "pending",
			attempt = controller.attempt,
			request_bytes = #body,
			request_hash = StableHash(
				controller.lastRequest and controller.lastRequest._request_key or body
			),
		}
		controller.requestStartedSeconds = tonumber(nowSeconds)
		local operation, remoteError = remote.Start(socketApi, body, nowSeconds)
		if not operation then return FinishFailure(remoteError, nowSeconds) end
		controller.operation = operation
		controller.phase = "requesting"
		controller.lastError = nil
		controller.lastErrorInfo = nil
		return {kind = "started", attempt = controller.attempt}
	end

	local function WaitElapsed(deltaTime, nowSeconds)
		if controller.dueSeconds and tonumber(nowSeconds) then return tonumber(nowSeconds) >= controller.dueSeconds end
		local delta = math.max(0, tonumber(deltaTime) or 0)
		controller.delayRemaining = math.max(0, (controller.delayRemaining or 0) - delta)
		return controller.delayRemaining <= 0.001
	end

	function controller:Schedule(delay, nowSeconds)
		if self.phase ~= "idle" then return false, "request_in_progress" end
		self.attempt = 0
		self.lastError = nil
		self.lastErrorInfo = nil
		self.encodedBody = nil
		SetWait("scheduled", delay, nowSeconds)
		return true, nil
	end

	function controller:Request(nowSeconds)
		return self:Schedule(0, nowSeconds)
	end

	function controller:Update(deltaTime, nowSeconds)
		if self.phase == "requesting" then
			local body, remoteError, finished, meta = remote.Poll(self.operation, nowSeconds)
			if not finished then return nil end
			self.operation = nil
			if self.lastEvidence and self.requestStartedSeconds and tonumber(nowSeconds) then
				self.lastEvidence.request_duration_ms = math.floor(
					math.max(0, tonumber(nowSeconds) - self.requestStartedSeconds) * 1000 + 0.5
				)
			end
			ApplyMeta(self.lastEvidence or {}, meta)
			if remoteError then return FinishFailure(remoteError, nowSeconds) end

			local ok, decoded = pcall(jsonApi.decode, body)
			if not ok or type(decoded) ~= "table" then return FinishFailure(Error("invalid_json"), nowSeconds) end
			self.lastResponse = decoded
			self.lastError = nil
			self.lastErrorInfo = nil
			if self.lastEvidence then self.lastEvidence.status = "ok" end
			self.phase = "idle"
			self.encodedBody = nil
			self.dueSeconds = nil
			self.delayRemaining = nil
			return {kind = "succeeded", response = decoded, request = self.lastRequest, attempt = self.attempt}
		end

		if (self.phase == "scheduled" or self.phase == "retry_wait") and WaitElapsed(deltaTime, nowSeconds) then
			self.dueSeconds = nil
			self.delayRemaining = nil
			return StartAttempt(nowSeconds)
		end
		return nil
	end

	function controller:Cancel()
		if self.operation then remote.Cancel(self.operation) end
		self.operation = nil
		self.phase = "idle"
		self.encodedBody = nil
		self.dueSeconds = nil
		self.delayRemaining = nil
	end

	function controller:Snapshot()
		local retryAttempt = math.max(0, self.attempt - 1)
		if self.phase == "retry_wait" then retryAttempt = self.attempt end
		if self.phase == "idle" and self.lastError == nil then retryAttempt = 0 end
		return {
			phase = self.phase,
			lastRequest = self.lastRequest,
			lastResponse = self.lastResponse,
			lastError = self.lastError,
			lastErrorInfo = self.lastErrorInfo,
			lastEvidence = self.lastEvidence,
			attempt = self.attempt,
			retryAttempt = retryAttempt,
			retryActive = self.phase == "retry_wait",
			requestPending = self.phase == "requesting",
		}
	end

	return controller
end

return Fetch
