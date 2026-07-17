local repoRoot = (arg and arg[1]) or "./"

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

local function makeElement()
	return {
		style = {},
		SetClass = function() end,
	}
end

local function installEnvironment(options)
	options = options or {}
	_G.widget = {}
	_G.WG = {}
	_G.Game = {
		mapName = "Test Map",
	}
	_G.Json = {
		encode = function()
			return "{}"
		end,
		decode = function()
			return {}
		end,
	}
	_G.VFS = {
		Include = function(path)
			if path == "LuaUI/Widgets/gui_pve_stats/include/pve_stats_rml_model.lua" then
				return dofile(repoRoot .. "include/pve_stats_rml_model.lua")
			end
			if path == "LuaUI/Widgets/gui_pve_stats/include/pve_stats_http_client.lua" then
				return dofile(repoRoot .. "include/pve_stats_http_client.lua")
			end
			error("unexpected include: " .. tostring(path))
		end,
	}
	_G.RmlUi = {
		GetContext = function()
			return {
				OpenDataModel = function()
					return {}
				end,
				LoadDocument = function()
					return {
						GetElementById = function()
							return makeElement()
						end,
						ReloadStyleSheet = function() end,
						Show = function() end,
						Hide = function() end,
						Close = function() end,
					}
				end,
				RemoveDataModel = function() end,
			}
		end,
	}
	_G.Spring = {
		GetConfigString = function(_, defaultValue)
			return defaultValue
		end,
		GetConfigInt = function(key, defaultValue)
			if key == "PveStatsAutoFetch" then
				return 0
			end
			if key == "PveStatsEvidenceLog" then
				return 0
			end
			if key == "LuaSocketEnabled" then
				return 0
			end
			return defaultValue
		end,
		SetConfigInt = function() end,
		GetViewGeometry = function()
			return 1920, 1080
		end,
		GetModOptions = function()
			return {}
		end,
		GetPlayerList = function()
			return {}
		end,
		Utilities = {
			Gametype = {
				IsRaptors = function()
					return true
				end,
				IsScavengers = function()
					return false
				end,
			},
		},
	}
	if options.withEngineTimer then
		local now = 0
		_G.Spring.GetTimer = function()
			return now
		end
		_G.Spring.DiffTimers = function(currentTimer, startTimer)
			return currentTimer - startTimer
		end
		return function(value)
			now = value
		end
	end
	return nil
end

local function loadWidget()
	dofile(repoRoot .. "gui_pve_stats.lua")
	assertTrue(widget.Initialize ~= nil, "widget Initialize should be defined")
	widget:Initialize()
	assertTrue(WG.PveStatsRml ~= nil, "widget API should be installed")
end

local function testScheduleUsesDeltaTimeWhenNoTimerIsAvailable()
	local originalOs = os
	local originalSocket = socket
	os = nil
	socket = nil

	local ok, err = pcall(function()
		installEnvironment()
		loadWidget()
		WG.PveStatsRml.ScheduleFetch(2)

		widget:Update(0.5)
		assertEquals(WG.PveStatsRml.GetLastError(), nil)
		widget:Update(1.4)
		assertEquals(WG.PveStatsRml.GetLastError(), nil)
		widget:Update(0.1)
		assertEquals(WG.PveStatsRml.GetLastError(), "lua_socket_disabled")
	end)

	os = originalOs
	socket = originalSocket
	if not ok then
		error(err, 0)
	end
end

local function testScheduleUsesEngineTimerWhenAvailable()
	local setNow = installEnvironment({ withEngineTimer = true })
	loadWidget()
	WG.PveStatsRml.ScheduleFetch(2)

	setNow(1.9)
	widget:Update()
	assertEquals(WG.PveStatsRml.GetLastError(), nil)
	setNow(2)
	widget:Update()
	assertEquals(WG.PveStatsRml.GetLastError(), "lua_socket_disabled")
end

testScheduleUsesDeltaTimeWhenNoTimerIsAvailable()
testScheduleUsesEngineTimerWhenAvailable()

print("test_pve_stats_widget_schedule.lua: ok")
