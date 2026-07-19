local Support = {}

function Support.equals(actual, expected, message)
	if actual ~= expected then
		error((message or "values differ") .. ": expected " .. tostring(expected) .. ", actual " .. tostring(actual), 2)
	end
end

function Support.truthy(value, message)
	if not value then error(message or "expected truthy value", 2) end
end

function Support.falsy(value, message)
	if value then error(message or "expected falsy value", 2) end
end

function Support.contains(text, expected, message)
	if not string.find(tostring(text or ""), expected, 1, true) then
		error((message or "text does not contain expected value") .. ": " .. tostring(expected), 2)
	end
end

function Support.notContains(text, unexpected, message)
	if string.find(tostring(text or ""), unexpected, 1, true) then
		error((message or "text contains unexpected value") .. ": " .. tostring(unexpected), 2)
	end
end

function Support.read(path)
	local file = assert(io.open(path, "rb"))
	local content = file:read("*a")
	file:close()
	return content
end

function Support.request(overrides)
	local request = {
		ai_type = "Raptors",
		map = "Test Map",
		game_settings = {},
		encounter_context = {},
		player_names = {},
		player_ids = {},
		player_filter_requested = true,
	}
	for key, value in pairs(overrides or {}) do request[key] = value end
	return request
end

return Support
