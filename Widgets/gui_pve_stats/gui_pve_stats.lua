if not RmlUi then
	return
end

local widget = widget

function widget:GetInfo()
	return {
		name = "PvE Stats",
		desc = "Shows PvE stats from the stats API",
		author = "tetrisface",
		date = "2026",
		license = "GNU GPL, v2 or later",
		layer = 1,
		enabled = true,
	}
end

local LOG_SECTION = "pve_stats_rml"
local LOG_PREFIX = "pve_stats"
local MODEL_NAME = "pve_stats_model"
local WIDGET_PATH = "LuaUI/Widgets/gui_pve_stats/"
local INCLUDE_PATH = WIDGET_PATH .. "include/"
local RML_PATH = WIDGET_PATH .. "gui_pve_stats.rml"
local PANEL_ID = "pve-stats-root"
local UPDATE_URL = "https://discord.com/channels/549281623154229250/1527813859497476270"

local DEFAULT_AUTO_FETCH = 1
local DEFAULT_EVIDENCE_LOG = 1
local DEFAULT_LUA_SOCKET_ENABLED = 1
local DEFAULT_SHOW_SPECTATORS = 0
local DEFAULT_MINIMIZED = 0
local DEFAULT_DEBUG_LOG = 0
local DEFAULT_LOADING_EXPECTED_SECONDS = 19
local LOADING_COMPLETE_HOLD_SECONDS = 0.25
local DEFAULT_VIEW_WIDTH = 1920
local DEFAULT_VIEW_HEIGHT = 1080
local PANEL_WIDTH = 420
local PANEL_TOP = 138
local PANEL_RIGHT = 18

local Request = VFS.Include(INCLUDE_PATH .. "request.lua")
local Display = VFS.Include(INCLUDE_PATH .. "display.lua")
local PlayerStats = VFS.Include(INCLUDE_PATH .. "player_stats.lua").New(Display)
local Histogram = VFS.Include(INCLUDE_PATH .. "histogram.lua").New(Display, PlayerStats)
local Diagnostics = VFS.Include(INCLUDE_PATH .. "diagnostics.lua").New(Display)
local ViewModel = VFS.Include(INCLUDE_PATH .. "view_model.lua").New(Display, PlayerStats, Histogram, Diagnostics)
local Remote = VFS.Include(INCLUDE_PATH .. "remote.lua")
local Fetch = VFS.Include(INCLUDE_PATH .. "fetch.lua")
local Json = Json or VFS.Include("common/luaUtilities/json.lua")

-- This is the only production injection of the LuaSocket global. All remote
-- operations are implemented and bounded inside remote.lua.
local remoteSocket = socket

local state = {
	rmlContext = nil,
	document = nil,
	dmHandle = nil,
	viewModel = ViewModel.Empty(),
	windowClosed = false,
	showSpectators = false,
	minimized = false,
	playerTab = "awards",
	playerTabContextKey = nil,
	playerSortColumn = 1,
	playerSortDescending = true,
	diffsExpanded = false,
	diagnosticsExpanded = false,
	sourceWindowAgeLastMinute = nil,
	modOptionSteps = nil,
	modOptionDefsLoaded = false,
	modOptionDefs = nil,
	fetchTimerBase = nil,
	fallbackClockSeconds = 0,
	loadingActive = false,
	loadingStartedSeconds = nil,
	loadingStartedWithResponse = false,
	loadingCompletedDueSeconds = nil,
	loadingProgressPercent = nil,
	helpText = "",
	helpVisible = false,
	tableHelpText = "",
	tableHelpVisible = false,
}

local function SafeCall(method, ...)
	if not method then return nil end
	local ok, first, second, third = pcall(method, ...)
	if not ok then return nil end
	return first, second, third
end

local function GetConfigInt(key, defaultValue)
	if Spring.GetConfigInt then return Spring.GetConfigInt(key, defaultValue) end
	return defaultValue
end

local function GetConfigFloat(key, defaultValue)
	if Spring.GetConfigFloat then return tonumber(Spring.GetConfigFloat(key, defaultValue)) or defaultValue end
	if Spring.GetConfigString then return tonumber(Spring.GetConfigString(key, tostring(defaultValue))) or defaultValue end
	return defaultValue
end

local function SetConfigInt(key, value)
	if Spring.SetConfigInt then
		Spring.SetConfigInt(key, value)
	elseif Spring.SetConfigString then
		Spring.SetConfigString(key, tostring(value))
	end
end

local function IsLuaSocketEnabled()
	return GetConfigInt("LuaSocketEnabled", DEFAULT_LUA_SOCKET_ENABLED) == 1
end

local function EngineTimerSeconds()
	if not Spring.GetTimer or not Spring.DiffTimers then return nil end
	local current = SafeCall(Spring.GetTimer)
	if not current then return nil end
	if not state.fetchTimerBase then
		state.fetchTimerBase = current
		return 0
	end
	return tonumber(SafeCall(Spring.DiffTimers, current, state.fetchTimerBase))
end

local function ScheduleSeconds()
	return EngineTimerSeconds() or state.fallbackClockSeconds
end

local function WallClockSeconds()
	if os and os.time then return tonumber(SafeCall(os.time)) end
	return nil
end

local function CurrentGameId()
	local gameID = Game and Game.gameID
	if gameID == nil and Spring.GetGameRulesParam then gameID = SafeCall(Spring.GetGameRulesParam, "GameID") end
	if gameID == nil or tostring(gameID) == "" then return nil end
	return tostring(gameID)
end

local function LoadModOptionDefs()
	if state.modOptionDefsLoaded then return state.modOptionDefs end
	state.modOptionDefsLoaded = true
	if VFS and VFS.Include then
		local ok, definitions = pcall(VFS.Include, "gamedata/modoptions.lua")
		if ok then state.modOptionDefs = definitions end
	end
	return state.modOptionDefs
end

local function ModOptionStepLookup()
	if state.modOptionSteps then return state.modOptionSteps end
	state.modOptionSteps = Diagnostics.ModOptionStepLookup(
		Game and (Game.modOptions or Game.modoptions or Game.mod_options),
		LoadModOptionDefs()
	)
	return state.modOptionSteps
end

local function BuildFetchRequest()
	if not IsLuaSocketEnabled() then return nil, "lua_socket_disabled" end
	return Request.Build(Spring, Game)
end

local fetch = Fetch.New(Remote, remoteSocket, BuildFetchRequest, Request.Wire, Json)

local function FetchSnapshot()
	return fetch:Snapshot()
end

local function LoadingExpectedSeconds()
	return math.max(1, GetConfigFloat("PveStatsLoadingExpectedSeconds", DEFAULT_LOADING_EXPECTED_SECONDS))
end

local function LoadingElapsedSeconds()
	if not state.loadingStartedSeconds then return nil end
	return math.max(0, ScheduleSeconds() - state.loadingStartedSeconds)
end

local function TransportEvidence()
	local evidence = {}
	for key, value in pairs(FetchSnapshot().lastEvidence or {}) do evidence[key] = value end
	if not next(evidence) then return nil end
	local elapsed = LoadingElapsedSeconds()
	if elapsed then evidence.loading_elapsed_ms = math.floor(elapsed * 1000 + 0.5) end
	evidence.loading_expected_seconds = LoadingExpectedSeconds()
	return evidence
end

local function ViewOptions()
	return {
		showSpectators = state.showSpectators,
		playerTab = state.playerTab,
		diffExpanded = state.diffsExpanded,
		diagnosticsExpanded = state.diagnosticsExpanded,
		modOptionSteps = ModOptionStepLookup(),
		sourceWindowNowSeconds = WallClockSeconds(),
		currentGameId = CurrentGameId(),
		transportEvidence = TransportEvidence(),
		sortColumn = state.playerSortColumn,
		sortDescending = state.playerSortDescending,
	}
end

local function BuildViewModel(response, errorCode, request)
	return ViewModel.Build(response, errorCode, request, Request.PlayerColorLookup(Spring), ViewOptions())
end

local function ApplyUiState()
	local dm = state.dmHandle
	if not dm then return end
	dm.minimized = state.minimized
	dm.minimizeText = state.minimized and "[]" or "-"
	dm.loadingVisible = state.loadingActive
	dm.loadingWidth = string.format("%.1f%%", state.loadingProgressPercent or 0)
	dm.helpText = state.helpText
	dm.helpVisible = state.helpVisible
	dm.tableHelpText = state.tableHelpText
	dm.tableHelpVisible = state.tableHelpVisible
end

local function ApplyViewModel(viewModel)
	state.viewModel = viewModel or ViewModel.Empty()
	if state.dmHandle then
		for key, value in pairs(state.viewModel) do state.dmHandle[key] = value end
		ApplyUiState()
	end
end

local function RefreshViewModel()
	local snapshot = FetchSnapshot()
	ApplyViewModel(BuildViewModel(snapshot.lastResponse, snapshot.lastError, snapshot.lastRequest))
end

local function SetLoadingProgress(progress)
	local percent = math.max(0, math.min(100, math.floor((tonumber(progress) or 0) * 1000 + 0.5) / 10))
	if state.loadingProgressPercent == percent then return end
	state.loadingProgressPercent = percent
	if state.dmHandle then state.dmHandle.loadingWidth = string.format("%.1f%%", percent) end
end

local function ApplyLoadingViewModel()
	local snapshot = FetchSnapshot()
	local view = BuildViewModel(snapshot.lastResponse, nil, snapshot.lastRequest)
	view.statusText = "Loading..."
	view.hasError = false
	view.errorText = ""
	view.hasNotice = false
	view.noticeText = ""
	view.messageText = ""
	view.hasUpdate = false
	ApplyViewModel(view)
end

local function BeginLoading()
	if state.loadingActive then return end
	state.loadingActive = true
	state.loadingStartedSeconds = ScheduleSeconds()
	state.loadingStartedWithResponse = FetchSnapshot().lastResponse ~= nil
	state.loadingCompletedDueSeconds = nil
	state.loadingProgressPercent = nil
	SetLoadingProgress(0)
	ApplyLoadingViewModel()
	ApplyUiState()
end

local function CancelLoading()
	state.loadingActive = false
	state.loadingStartedSeconds = nil
	state.loadingStartedWithResponse = false
	state.loadingCompletedDueSeconds = nil
	state.loadingProgressPercent = nil
	ApplyUiState()
end

local function CompleteLoading()
	if not state.loadingActive then return end
	SetLoadingProgress(1)
	state.loadingCompletedDueSeconds = ScheduleSeconds() + LOADING_COMPLETE_HOLD_SECONDS
end

local function UpdateLoadingProgress()
	if not state.loadingActive then return end
	local now = ScheduleSeconds()
	if state.loadingCompletedDueSeconds then
		if now >= state.loadingCompletedDueSeconds then CancelLoading() end
		return
	end
	local elapsed = LoadingElapsedSeconds()
	if elapsed then SetLoadingProgress(ViewModel.EstimatedLoadingProgress(elapsed, LoadingExpectedSeconds())) end
end

local function ShowHelpIn(tableHelp, text)
	if not text or text == "" then return end
	state.helpVisible = not tableHelp
	state.tableHelpVisible = tableHelp
	if tableHelp then state.tableHelpText = text else state.helpText = text end
	ApplyUiState()
end

local function ShowHelp(text) ShowHelpIn(false, text) end
local function ShowTableHelp(text) ShowHelpIn(true, text) end

local function HideHelpPanels()
	state.helpVisible = false
	state.tableHelpVisible = false
	ApplyUiState()
end

local function LogMessage(message)
	local text = LOG_PREFIX .. " " .. tostring(message or "")
	if Spring.Echo then
		Spring.Echo("[" .. LOG_SECTION .. "] " .. text)
	elseif Spring.Log and LOG and LOG.INFO then
		Spring.Log(LOG_SECTION, LOG.INFO, text)
	end
end

local function DebugLog(message)
	if GetConfigInt("PveStatsDebugLog", DEFAULT_DEBUG_LOG) == 1 then LogMessage(message) end
end

local function DiagnosticEvidence()
	local snapshot = FetchSnapshot()
	return Diagnostics.Evidence(snapshot.lastResponse, {
		currentGameId = CurrentGameId(),
		transportEvidence = TransportEvidence(),
	})
end

local function MaybeLogEvidence()
	if GetConfigInt("PveStatsEvidenceLog", DEFAULT_EVIDENCE_LOG) == 1 then
		LogMessage(Diagnostics.FormatEvidenceLog(DiagnosticEvidence()))
	end
end

local function CurrentViewGeometry()
	if Spring.GetViewGeometry then
		local width, height = Spring.GetViewGeometry()
		if width and height and width > 0 and height > 0 then return width, height end
	end
	if gl and gl.GetViewSizes then
		local width, height = gl.GetViewSizes()
		if width and height and width > 0 and height > 0 then return width, height end
	end
	return DEFAULT_VIEW_WIDTH, DEFAULT_VIEW_HEIGHT
end

local function PositionDocument()
	if not state.document then return end
	local panel = state.document:GetElementById(PANEL_ID)
	if not panel then return end
	local viewWidth = CurrentViewGeometry()
	panel.style.left = tostring(math.max(0, viewWidth - PANEL_WIDTH - PANEL_RIGHT)) .. "px"
	panel.style.top = tostring(PANEL_TOP) .. "px"
	panel.style.width = tostring(PANEL_WIDTH) .. "dp"
end

local function ResetPlayerSort(tab, request)
	state.playerSortColumn = PlayerStats.DefaultSortColumn(tab, request)
	state.playerSortDescending = true
end

local function UpdateDefaultPlayerTab(request, response)
	if not response then return end
	local defaultTab = PlayerStats.DefaultTab(response)
	local contextKey = tostring(Request.SettingKey(request) or "") .. "|" .. defaultTab
	if state.playerTabContextKey == contextKey then return end
	state.playerTabContextKey = contextKey
	state.playerTab = defaultTab
	ResetPlayerSort(defaultTab, request)
end

local function SourceWindowAgeMinute(response)
	return ViewModel.SourceWindowAgeMinute(response, {sourceWindowNowSeconds = WallClockSeconds()})
end

local function ResetSourceWindowAgeClock(response)
	state.sourceWindowAgeLastMinute = SourceWindowAgeMinute(response)
end

local function UpdateSourceWindowAgeClock()
	local snapshot = FetchSnapshot()
	if not snapshot.lastResponse or snapshot.lastError then return end
	local currentMinute = SourceWindowAgeMinute(snapshot.lastResponse)
	if currentMinute == nil or currentMinute == state.sourceWindowAgeLastMinute then return end
	state.sourceWindowAgeLastMinute = currentMinute
	RefreshViewModel()
end

local function RetryView(event)
	local snapshot = FetchSnapshot()
	if not state.loadingStartedWithResponse and event.error.code == "reserved_concurrency" then
		ApplyLoadingViewModel()
		return
	end
	CancelLoading()
	local view = BuildViewModel(snapshot.lastResponse, snapshot.lastError, snapshot.lastRequest)
	view.statusText = "Retrying"
	view.errorText = table.concat({
		"PvE Stats unavailable (", tostring(snapshot.lastError), "). Retrying in ",
		string.format("%.0f", event.delay or 0), "s (", tostring(event.attempt), "/", tostring(event.maxAttempts), ").",
	})
	view.messageText = view.errorText
	ApplyViewModel(view)
end

local function HandleFetchEvent(event)
	if not event then return end
	if event.kind == "started" then
		DebugLog("fetch_started attempt=" .. tostring(event.attempt))
		return
	end
	MaybeLogEvidence()
	if event.kind == "succeeded" then
		state.diffsExpanded = false
		UpdateDefaultPlayerTab(event.request, event.response)
		ResetSourceWindowAgeClock(event.response)
		CompleteLoading()
		RefreshViewModel()
		return
	end
	if event.kind == "retrying" then
		RetryView(event)
		return
	end
	if event.kind == "failed" then
		CancelLoading()
		ResetSourceWindowAgeClock(nil)
		RefreshViewModel()
	end
end

local function ScheduleFetch(delay)
	return fetch:Schedule(delay, ScheduleSeconds())
end

local function RequestStats()
	if FetchSnapshot().phase ~= "idle" then return false, "request_in_progress" end
	if state.loadingActive then CancelLoading() end
	BeginLoading()
	local ok, err = fetch:Request(ScheduleSeconds())
	if not ok then CancelLoading() end
	return ok, err
end

local function ModelWithUiState()
	local model = {}
	for key, value in pairs(state.viewModel or {}) do model[key] = value end
	model.minimized = state.minimized
	model.minimizeText = state.minimized and "[]" or "-"
	model.loadingVisible = state.loadingActive
	model.loadingWidth = string.format("%.1f%%", state.loadingProgressPercent or 0)
	model.helpText = state.helpText
	model.helpVisible = state.helpVisible
	model.tableHelpText = state.tableHelpText
	model.tableHelpVisible = state.tableHelpVisible
	return model
end

local function InstallApi()
	WG.PveStatsRml = {
		BuildRequest = function() return Request.Build(Spring, Game) end,
		FetchStats = RequestStats,
		ScheduleFetch = ScheduleFetch,
		GetLastRequest = function() return FetchSnapshot().lastRequest end,
		GetLastResponse = function() return FetchSnapshot().lastResponse end,
		GetLastError = function() return FetchSnapshot().lastError end,
		GetLoadingState = function()
			return {active = state.loadingActive, elapsed_seconds = LoadingElapsedSeconds(), progress_percent = state.loadingProgressPercent}
		end,
		GetLastEvidence = function() return TransportEvidence() end,
		GetRetryAttempt = function() return FetchSnapshot().retryAttempt end,
		IsRetryActive = function() return FetchSnapshot().retryActive end,
		IsRequestPending = function() return FetchSnapshot().requestPending end,
		LogLastEvidence = function()
			local evidence = TransportEvidence()
			LogMessage(Diagnostics.FormatEvidenceLog(DiagnosticEvidence()))
			return evidence
		end,
		GetEndpoint = Remote.Target,
		IsLuaSocketEnabled = IsLuaSocketEnabled,
		GetViewModel = function() return state.viewModel end,
		GetShowSpectators = function() return state.showSpectators end,
		SetShowSpectators = function(enabled)
			state.showSpectators = enabled == true
			SetConfigInt("PveStatsShowSpectators", state.showSpectators and 1 or 0)
			RefreshViewModel()
		end,
	}
end

local function ReleaseWindowResources()
	pcall(fetch.Cancel, fetch)
	if state.rmlContext and state.dmHandle then
		pcall(state.rmlContext.RemoveDataModel, state.rmlContext, MODEL_NAME)
		state.dmHandle = nil
	end
	if state.document then
		pcall(state.document.Close, state.document)
		state.document = nil
	end
	if WG.PveStatsRml then WG.PveStatsRml = nil end
	state.rmlContext = nil
	state.loadingActive = false
end

function widget:Initialize()
	state.windowClosed = false
	state.showSpectators = GetConfigInt("PveStatsShowSpectators", DEFAULT_SHOW_SPECTATORS) == 1
	state.minimized = GetConfigInt("PveStatsMinimized", DEFAULT_MINIMIZED) == 1
	local modelOk, initialViewModel = pcall(BuildViewModel, nil, nil, nil)
	if not modelOk then
		state.windowClosed = true
		return false
	end
	state.viewModel = initialViewModel
	local contextOk, context = pcall(RmlUi.GetContext, "shared")
	state.rmlContext = contextOk and context or nil
	if not state.rmlContext then
		state.windowClosed = true
		return false
	end
	local initialized, complete = pcall(function()
		state.dmHandle = state.rmlContext:OpenDataModel(MODEL_NAME, ModelWithUiState(), self)
		if not state.dmHandle then return false end
		state.document = state.rmlContext:LoadDocument(RML_PATH, self)
		if not state.document then return false end
		state.document:ReloadStyleSheet()
		PositionDocument()
		state.document:Show()
		ApplyViewModel(state.viewModel)
		return true
	end)
	if not initialized or not complete then
		ReleaseWindowResources()
		state.windowClosed = true
		return false
	end
	InstallApi()
	if GetConfigInt("PveStatsAutoFetch", DEFAULT_AUTO_FETCH) == 1 then
		BeginLoading()
		ScheduleFetch(0.5)
	end
end

function widget:ViewResize()
	PositionDocument()
end

function widget:ToggleSpectators()
	state.showSpectators = not state.showSpectators
	SetConfigInt("PveStatsShowSpectators", state.showSpectators and 1 or 0)
	RefreshViewModel()
end

function widget:ToggleMinimized()
	state.minimized = not state.minimized
	SetConfigInt("PveStatsMinimized", state.minimized and 1 or 0)
	ApplyUiState()
end

local function EventAttribute(event, name)
	local element = event and event.current_element
	if not element or not element.GetAttribute then return nil end
	return element:GetAttribute(name)
end

function widget:SetPlayerTab(event)
	local tab = tostring(EventAttribute(event, "data-tab") or "")
	if tab ~= "setup" and tab ~= "adventures" and tab ~= "encounters" and tab ~= "milestones" and tab ~= "awards" then return end
	state.playerTab = tab
	ResetPlayerSort(tab, FetchSnapshot().lastRequest)
	RefreshViewModel()
end

function widget:SortPlayerColumn(event)
	local column = tonumber(EventAttribute(event, "data-column"))
	if not column or column < 0 or column > 3 then return end
	if state.playerSortColumn == column then
		state.playerSortDescending = not state.playerSortDescending
	else
		state.playerSortColumn = column
		state.playerSortDescending = true
	end
	RefreshViewModel()
end

function widget:ShowPlayerStatHelp(event)
	local column = tonumber(EventAttribute(event, "data-column"))
	if column and column >= 1 and column <= 3 then ShowTableHelp(PlayerStats.HelpText(state.playerTab, column)) end
end

function widget:ShowSummaryHelp(event)
	local help = EventAttribute(event, "data-help")
	local texts = {
		win = state.viewModel.winChanceHelpText,
		challenge = state.viewModel.challengeHelpText,
		percentile = state.viewModel.difficultyPercentileHelpText,
		training = state.viewModel.trainingGamesHelpText,
		match = state.viewModel.matchHelpText,
	}
	ShowHelp(texts[help])
end

function widget:ShowHistogramHelp()
	local snapshot = FetchSnapshot()
	ShowHelp(Histogram.HelpText(snapshot.lastResponse, snapshot.lastRequest))
end

function widget:ShowHistogramBinHelp(event)
	local snapshot = FetchSnapshot()
	ShowHelp(Histogram.BinHelpText(snapshot.lastResponse, snapshot.lastRequest, EventAttribute(event, "data-bin-index")))
end

function widget:ShowDiagnosticsHelp()
	ShowHelp("Show field differences, request timing, field coverage, match details, and troubleshooting IDs.")
end

function widget:ShowUpdateHelp()
	if state.viewModel.hasUpdate then ShowHelp(state.viewModel.updateHelpText) end
end

function widget:CopyUpdateLink()
	if not state.viewModel.hasUpdate then return end
	if Spring.SetClipboard and pcall(Spring.SetClipboard, UPDATE_URL) then
		ShowHelp("Widget installation link copied to clipboard.")
		return
	end
	ShowHelp("Widget update: " .. UPDATE_URL)
end

function widget:HideHelp()
	HideHelpPanels()
end

function widget:ToggleDiffs()
	state.diffsExpanded = not state.diffsExpanded
	RefreshViewModel()
end

function widget:ToggleDiagnostics()
	if not state.viewModel.hasDiagnostics then return end
	state.diagnosticsExpanded = not state.diagnosticsExpanded
	RefreshViewModel()
end

function widget:CopyDiagnostics()
	local diagnostics = state.viewModel.diagnosticsText
	if not diagnostics or diagnostics == "" then return end
	if Spring.SetClipboard and pcall(Spring.SetClipboard, diagnostics) then
		ShowHelp("PvE Stats diagnostics copied to clipboard.")
		return
	end
	ShowHelp("Clipboard unavailable. Diagnostics remain visible in the expanded panel.")
end

function widget:CloseWindow()
	if state.windowClosed then return end
	state.windowClosed = true
	ReleaseWindowResources()
end

function widget:Shutdown()
	state.windowClosed = true
	ReleaseWindowResources()
end

function widget:Update(deltaTime)
	if state.windowClosed then return end
	state.fallbackClockSeconds = state.fallbackClockSeconds + math.max(0, tonumber(deltaTime) or 0)
	UpdateLoadingProgress()
	local event = fetch:Update(deltaTime, ScheduleSeconds())
	if event then
		HandleFetchEvent(event)
		return
	end
	UpdateSourceWindowAgeClock()
end

function widget:RecvLuaMsg(message)
	if not state.document then return end
	if message:sub(1, 19) == "LobbyOverlayActive0" then
		state.document:Show()
	elseif message:sub(1, 19) == "LobbyOverlayActive1" then
		state.document:Hide()
	end
end
