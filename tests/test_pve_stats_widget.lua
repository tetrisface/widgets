local root = PVE_STATS_TEST_ROOT or (arg and arg[1]) or "./"
local T = dofile(root .. "tests/support.lua")

local function InstallEnvironment(options)
	options = options or {}
	local environment = {
		configReads = {},
		configWrites = {},
		socketCreates = 0,
		removedModels = 0,
	}
	_G.widget = {}
	_G.WG = {}
	_G.Game = {mapName = "Test Map", gameID = "game-id", modOptions = {}}
	_G.Json = {
		encode = function() return "{}" end,
		decode = function() return {} end,
	}
	_G.socket = {
		tcp = function()
			environment.socketCreates = environment.socketCreates + 1
			return nil
		end,
		select = function() return {}, {} end,
	}
	_G.Spring = {
		GetConfigInt = function(key, defaultValue)
			environment.configReads[key] = true
			if key == "LuaSocketEnabled" then return 0 end
			if key == "PveStatsAutoFetch" then return options.autoFetch and 1 or 0 end
			return defaultValue
		end,
		GetConfigFloat = function(_, defaultValue) return defaultValue end,
		SetConfigInt = function(key, value) environment.configWrites[key] = value end,
		GetViewGeometry = function() return 1920, 1080 end,
		Echo = function(message) environment.lastLog = message end,
		SetClipboard = function(value) environment.clipboard = value end,
	}
	_G.VFS = {
		Include = function(path)
			local prefix = "LuaUI/Widgets/gui_pve_stats/"
			if string.sub(path, 1, #prefix) == prefix then
				return dofile(root .. string.sub(path, #prefix + 1))
			end
			if path == "gamedata/modoptions.lua" then return {} end
			if path == "common/luaUtilities/json.lua" then return _G.Json end
			error("unexpected include: " .. tostring(path))
		end,
	}

	local panel = {style = {}}
	local document = {
		shown = false,
		hidden = false,
		closed = false,
		GetElementById = function(_, id) return id == "pve-stats-root" and panel or nil end,
		ReloadStyleSheet = function(self)
			if options.throwOnReload then error("simulated document failure") end
			self.reloaded = true
		end,
		Show = function(self)
			if not self.shown then
				T.equals(_G.WG.PveStatsRml, nil, "WG API installed before document initialization completed")
			end
			self.shown = true
		end,
		Hide = function(self) self.hidden = true end,
		Close = function(self) self.closed = true end,
	}
	local context = {
		OpenDataModel = function(_, name, model, controller)
			environment.modelName = name
			environment.model = model
			environment.controller = controller
			if options.openModelFails then return nil end
			local declaredKeys = {}
			for key in pairs(model) do declaredKeys[key] = true end
			setmetatable(model, {
				__newindex = function(target, key, value)
					if not declaredKeys[key] then
						error("new DataModel root key: " .. tostring(key))
					end
					rawset(target, key, value)
				end,
			})
			return model
		end,
		LoadDocument = function(_, path)
			environment.documentPath = path
			T.equals(_G.WG.PveStatsRml, nil, "WG API installed before document load")
			if options.loadDocumentFails then return nil end
			return document
		end,
		RemoveDataModel = function(_, name)
			environment.removedModels = environment.removedModels + 1
			environment.removedModelName = name
		end,
	}
	_G.RmlUi = {GetContext = function() return options.noContext and nil or context end}
	environment.document = document
	environment.context = context
	environment.panel = panel
	return environment
end

local function LoadWidget(options)
	local environment = InstallEnvironment(options)
	dofile(root .. "gui_pve_stats.lua")
	return _G.widget, environment
end

local function AttributeEvent(attribute, value)
	return {current_element = {GetAttribute = function(_, requested)
		if requested == attribute then return value end
		return nil
	end}}
end

local function testInitializationAndPublicApi()
	local loadedWidget, environment = LoadWidget({autoFetch = false})
	loadedWidget:Initialize()
	local api = assert(_G.WG.PveStatsRml)
	T.truthy(environment.document.shown)
	T.truthy(environment.document.reloaded)
	T.equals(environment.modelName, "pve_stats_model")
	T.equals(environment.documentPath, "LuaUI/Widgets/gui_pve_stats/gui_pve_stats.rml")
	T.equals(api.FetchStatsOnce, nil)
	T.truthy(api.FetchStats)
	T.truthy(api.ScheduleFetch)
	local target = api.GetEndpoint()
	T.equals(target.host, "d29i3oohxql6zz.cloudfront.net")
	T.equals(target.port, 80)
	target.host = "changed.invalid"
	T.equals(api.GetEndpoint().host, "d29i3oohxql6zz.cloudfront.net")
	for _, removedSetting in ipairs({"PveStatsUrl", "PveStatsHost", "PveStatsPort", "PveStatsPath"}) do
		T.falsy(environment.configReads[removedSetting], "read removed endpoint setting " .. removedSetting)
	end
	loadedWidget:SetPlayerTab(AttributeEvent("data-tab", "setup"))
	T.equals(api.GetViewModel().playerTab, "setup")
	loadedWidget:ToggleMinimized()
	T.equals(environment.configWrites.PveStatsMinimized, 1)
	loadedWidget:RecvLuaMsg("LobbyOverlayActive1")
	T.truthy(environment.document.hidden)
	loadedWidget:RecvLuaMsg("LobbyOverlayActive0")
	T.truthy(environment.document.shown)
	loadedWidget:Shutdown()
	T.equals(_G.WG.PveStatsRml, nil)
	T.truthy(environment.document.closed)
	T.equals(environment.removedModels, 1)
end

local function testScheduledAndManualFetchUseTheDisabledGate()
	local loadedWidget, environment = LoadWidget({autoFetch = false})
	loadedWidget:Initialize()
	local api = assert(_G.WG.PveStatsRml)
	local ok = api.ScheduleFetch(2)
	T.truthy(ok)
	loadedWidget:Update(1)
	T.equals(api.GetLastError(), nil)
	loadedWidget:Update(1)
	T.equals(api.GetLastError(), "lua_socket_disabled")
	T.equals(environment.socketCreates, 0)
	T.equals(api.GetViewModel().statusText, "Unavailable")
	loadedWidget:Update(100)
	T.equals(environment.socketCreates, 0, "periodic request was created")
	ok = api.FetchStats()
	T.truthy(ok)
	loadedWidget:Update(0)
	T.equals(api.GetLastError(), "lua_socket_disabled")
	T.equals(environment.socketCreates, 0)
	loadedWidget:Shutdown()
end

local function testInitialFetchAndShutdownCancellation()
	local loadedWidget, environment = LoadWidget({autoFetch = true})
	loadedWidget:Initialize()
	local api = assert(_G.WG.PveStatsRml)
	T.truthy(api.GetLoadingState().active)
	loadedWidget:Update(0.4)
	T.equals(api.GetLastError(), nil)
	loadedWidget:Update(0.1)
	T.equals(api.GetLastError(), "lua_socket_disabled")
	T.falsy(api.GetLoadingState().active)
	loadedWidget:Shutdown()
	loadedWidget:Update(100)
	T.equals(environment.socketCreates, 0)
end

local function testInitializationFailureUnwindsResources()
	local loadedWidget, environment = LoadWidget({loadDocumentFails = true})
	local initialized = loadedWidget:Initialize()
	T.equals(initialized, false)
	T.equals(_G.WG.PveStatsRml, nil)
	T.equals(environment.removedModels, 1)

	loadedWidget, environment = LoadWidget({openModelFails = true})
	initialized = loadedWidget:Initialize()
	T.equals(initialized, false)
	T.equals(_G.WG.PveStatsRml, nil)
	T.equals(environment.removedModels, 0)

	loadedWidget, environment = LoadWidget({throwOnReload = true})
	initialized = loadedWidget:Initialize()
	T.equals(initialized, false)
	T.equals(_G.WG.PveStatsRml, nil)
	T.equals(environment.removedModels, 1)
	T.truthy(environment.document.closed)
end

local function testEngineGlobalsStayAtTheCompositionBoundary()
	for _, path in ipairs({
		"include/remote.lua",
		"include/fetch.lua",
		"include/display.lua",
		"include/player_stats.lua",
		"include/histogram.lua",
		"include/diagnostics.lua",
		"include/view_model.lua",
	}) do
		local source = T.read(root .. path)
		for _, globalName in ipairs({"Spring.", "Game.", "RmlUi", "VFS.", "WG."}) do
			T.notContains(source, globalName, path .. " accesses an engine global")
		end
	end
end

testInitializationAndPublicApi()
testScheduledAndManualFetchUseTheDisabledGate()
testInitialFetchAndShutdownCancellation()
testInitializationFailureUnwindsResources()
testEngineGlobalsStayAtTheCompositionBoundary()

print("test_pve_stats_widget.lua: ok")
