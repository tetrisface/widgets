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

local DEV = 0
local LOG_SECTION = 'pve_stats_rml'
local LOG_PREFIX = 'pve_stats'
local MODEL_NAME = 'pve_stats_model'
local WIDGET_PATH = 'LuaUI/Widgets/gui_pve_stats/'
local INCLUDE_PATH = WIDGET_PATH .. 'include/'
local RML_PATH = WIDGET_PATH .. 'gui_pve_stats.rml'
local PANEL_ID = 'pve-stats-root'
local DEFAULT_HOST = DEV == 1 and '127.0.0.1' or 'd29i3oohxql6zz.cloudfront.net'
local DEFAULT_PORT = DEV == 1 and 8080 or 80
local DEFAULT_PATH = '/stats'
local UPDATE_URL = 'https://discord.com/channels/549281623154229250/1527813859497476270'
local DEFAULT_URL = ''
local DEFAULT_AUTO_FETCH = 1
local DEFAULT_EVIDENCE_LOG = 1
local DEFAULT_LUA_SOCKET_ENABLED = 1
local DEFAULT_SHOW_SPECTATORS = 0
local DEFAULT_MINIMIZED = 0
local DEFAULT_DEBUG_LOG = 0
local DEFAULT_TIMEOUT_MS = 3000
local DEFAULT_ASYNC_TIMEOUT_MS = 30000
local DEFAULT_RETRY_MAX_ATTEMPTS = 5
local DEFAULT_RETRY_INITIAL_SECONDS = 2
local DEFAULT_RETRY_MAX_SECONDS = 30
local DEFAULT_LOADING_EXPECTED_SECONDS = 19
local LOADING_COMPLETE_HOLD_SECONDS = 0.25
local FETCH_DELAY_EPSILON_SECONDS = 0.001
local DEFAULT_VIEW_WIDTH = 1920
local DEFAULT_VIEW_HEIGHT = 1080
local DEFAULT_PANEL_WIDTH = 420
local DEFAULT_PANEL_TOP = 138
local DEFAULT_PANEL_RIGHT = 18
local HASH_MODULO = 4294967296

local Model = VFS.Include(INCLUDE_PATH .. 'pve_stats_rml_model.lua')
local HttpClient = VFS.Include(INCLUDE_PATH .. 'pve_stats_http_client.lua')
local Json = Json or VFS.Include('common/luaUtilities/json.lua')
local CLIENT_VERSION = Model.CLIENT_VERSION or 1

local socketLib = socket

local state = {
	rmlContext = nil,
	document = nil,
	dmHandle = nil,
	viewModel = Model.EmptyViewModel(),
	lastRequest = nil,
	lastResponse = nil,
	lastError = nil,
	lastEvidence = nil,
	pendingFetch = false,
	fetchDelay = 0,
	fetchDueSeconds = nil,
	fetchDelayRemaining = nil,
	fetchTimerBase = nil,
	retryAttempt = 0,
	retryActive = false,
	httpOperation = nil,
	httpContext = nil,
	loadingActive = false,
	loadingStartedSeconds = nil,
	loadingStartedWithResponse = false,
	loadingCompletedDueSeconds = nil,
	loadingProgressPercent = nil,
	showSpectators = false,
	minimized = false,
	windowClosed = false,
	playerTab = 'awards',
	playerTabContextKey = nil,
	playerSortColumn = 1,
	playerSortDescending = true,
	diffsExpanded = false,
	diagnosticsExpanded = false,
	sourceWindowAgeLastMinute = nil,
	modOptionSteps = nil,
	modOptionDefsLoaded = false,
	modOptionDefs = nil,
}

local function GetConfigString(key, defaultValue)
	if Spring.GetConfigString then
		return Spring.GetConfigString(key, defaultValue)
	end
	return defaultValue
end

local function GetConfigInt(key, defaultValue)
	if Spring.GetConfigInt then
		return Spring.GetConfigInt(key, defaultValue)
	end
	return defaultValue
end

local function GetConfigFloat(key, defaultValue)
	if Spring.GetConfigFloat then
		return tonumber(Spring.GetConfigFloat(key, defaultValue)) or defaultValue
	end
	return tonumber(GetConfigString(key, tostring(defaultValue))) or defaultValue
end

local function SetConfigInt(key, value)
	if Spring.SetConfigInt then
		Spring.SetConfigInt(key, value)
	elseif Spring.SetConfigString then
		Spring.SetConfigString(key, tostring(value))
	end
end

local function SetText(elementId, value)
	if not state.document then
		return
	end
	local element = state.document:GetElementById(elementId)
	if element then
		element.inner_rml = Model.EscapeRml(value)
	end
end

local function SetRml(elementId, value)
	if not state.document then
		return
	end
	local element = state.document:GetElementById(elementId)
	if element then
		element.inner_rml = value or ''
	end
end

local function SetClass(elementId, className, enabled)
	if not state.document then
		return
	end
	local element = state.document:GetElementById(elementId)
	if element then
		element:SetClass(className, enabled)
	end
end

local function SetStyle(elementId, property, value)
	if not state.document then
		return
	end
	local element = state.document:GetElementById(elementId)
	if element then
		element.style[property] = value
	end
end

local function HideHelpPanels()
	SetClass('pve-stats-help', 'hidden', true)
	SetClass('pve-stats-table-help', 'hidden', true)
end

local function ShowHelpIn(elementId, text)
	if not text or text == '' then
		return
	end
	HideHelpPanels()
	SetText(elementId, text)
	SetClass(elementId, 'hidden', false)
end

local function ShowHelp(text)
	ShowHelpIn('pve-stats-help', text)
end

local function ShowTableHelp(text)
	ShowHelpIn('pve-stats-table-help', text)
end

local function ApplyViewModel(viewModel)
	state.viewModel = viewModel or Model.EmptyViewModel()
	local dm = state.dmHandle
	if dm then
		dm.statusText = state.viewModel.statusText
		dm.modeText = state.viewModel.modeText
		dm.difficultyText = state.viewModel.difficultyText
		dm.exactWinsText = state.viewModel.exactWinsText
		dm.extendedWinsText = state.viewModel.extendedWinsText
		dm.evidenceGamesText = state.viewModel.evidenceGamesText
		dm.winsLabelText = state.viewModel.winsLabelText
		dm.matchText = state.viewModel.matchText
		dm.sourceWindowText = state.viewModel.sourceWindowText
		dm.errorText = state.viewModel.errorText
		dm.noticeText = state.viewModel.noticeText
	end

	local messageText = state.viewModel.hasError and state.viewModel.errorText or state.viewModel.noticeText
	SetText('pve-stats-status', state.viewModel.statusText)
	SetText('pve-stats-mode', state.viewModel.modeText)
	SetText('pve-stats-difficulty', state.viewModel.difficultyText)
	SetText('pve-stats-exact-wins', state.viewModel.exactWinsText)
	SetText('pve-stats-extended-wins', state.viewModel.extendedWinsText)
	SetText('pve-stats-evidence-games', state.viewModel.evidenceGamesText)
	SetText('pve-stats-evidence-games-label', state.viewModel.evidenceGamesLabel)
	SetText('pve-stats-exact-wins-label', state.viewModel.winsLabelText)
	SetText('pve-stats-player-label', state.viewModel.playerHeaderLabel)
	SetText('pve-stats-player-stat-one-label', state.viewModel.playerStatOneLabel)
	SetText('pve-stats-player-stat-two-label', state.viewModel.playerStatTwoLabel)
	SetText('pve-stats-player-stat-three-label', state.viewModel.playerStatThreeLabel)
	SetText('pve-stats-match', state.viewModel.matchText)
	SetText('pve-stats-source-window', state.viewModel.sourceWindowText)
	SetText('pve-stats-spectators-toggle', state.viewModel.spectatorText)
	SetText('pve-stats-error', messageText)
	SetRml('pve-stats-players', state.viewModel.playersRml)
	SetRml('pve-stats-diffs', state.viewModel.diffsRml)
	SetRml('pve-stats-evidence-summary', state.viewModel.evidenceSummaryRml)
	SetRml('pve-stats-diagnostics-content', state.viewModel.diagnosticsRml)
	SetRml('pve-stats-histogram-content', state.viewModel.histogramRml)
	SetText('pve-stats-histogram-caption', state.viewModel.histogramCaption)
	SetClass('pve-stats-root', 'has-error', state.viewModel.hasError)
	SetClass('pve-stats-root', 'has-notice', state.viewModel.hasNotice and not state.viewModel.hasError)
	SetClass('pve-stats-status', 'hidden', state.viewModel.statusText == 'Ready')
	SetClass('pve-stats-status', 'update-available', state.viewModel.hasUpdate)
	SetClass('pve-stats-match', 'exact-match', state.viewModel.isExactMatch)
	SetClass('pve-stats-error', 'notice', state.viewModel.hasNotice and not state.viewModel.hasError)
	SetClass('pve-stats-error', 'hidden', not state.viewModel.hasError and not state.viewModel.hasNotice)
	SetClass('pve-stats-source', 'hidden', not state.viewModel.hasSourceWindow)
	SetClass('pve-stats-diffs', 'hidden', not state.viewModel.hasDiffs)
	SetClass('pve-stats-evidence-summary', 'hidden', not state.viewModel.hasEvidenceSummary)
	SetClass('pve-stats-diagnostics', 'hidden', not state.viewModel.diagnosticsExpanded)
	SetClass('pve-stats-diagnostics-toggle', 'hidden', not state.viewModel.hasDiagnostics)
	SetClass('pve-stats-diagnostics-toggle', 'active', state.viewModel.diagnosticsExpanded)
	SetClass('pve-stats-histogram', 'hidden', not state.viewModel.hasHistogram)
	SetClass('pve-stats-spectators-toggle', 'active', state.viewModel.showSpectators)
	SetClass('pve-stats-root', 'minimized', state.minimized)
	SetClass('pve-stats-content', 'hidden', state.minimized)
	SetText('pve-stats-minimize', state.minimized and '[]' or '-')
	for _, tab in ipairs({ 'setup', 'adventures', 'encounters', 'milestones', 'awards' }) do
		SetClass('pve-stats-tab-' .. tab, 'active', state.viewModel.playerTab == tab)
	end
	for column, id in pairs({
		[0] = 'pve-stats-player-label',
		[1] = 'pve-stats-player-stat-one-label',
		[2] = 'pve-stats-player-stat-two-label',
		[3] = 'pve-stats-player-stat-three-label',
	}) do
		SetClass(id, 'active-sort', state.viewModel.sortColumn == column)
	end
end

local function StableHash(value)
	local text = tostring(value or '')
	local hash = 5381
	for index = 1, #text do
		hash = (hash * 33 + string.byte(text, index)) % HASH_MODULO
	end
	return string.format('%08x', hash)
end

local function EndpointLabel(endpoint)
	if not endpoint then
		return '-'
	end
	return table.concat({
		endpoint.scheme or 'http',
		'://',
		endpoint.host or '',
		':',
		tostring(endpoint.port or DEFAULT_PORT),
		endpoint.path or DEFAULT_PATH,
	})
end

local function CountValues(values)
	local count = 0
	for _ in ipairs(values or {}) do
		count = count + 1
	end
	return count
end

local function SafeCall(method, ...)
	if not method then
		return nil
	end
	local ok, first, second, third, fourth, fifth, sixth, seventh, eighth, ninth, tenth, eleventh = pcall(method, ...)
	if not ok then
		return nil
	end
	return first, second, third, fourth, fifth, sixth, seventh, eighth, ninth, tenth, eleventh
end

local function CurrentWallClockSeconds()
	local socketApi = socketLib or socket
	local socketSeconds = socketApi and SafeCall(socketApi.gettime)
	if socketSeconds then
		return tonumber(socketSeconds)
	end

	if os and os.time then
		return tonumber(SafeCall(os.time))
	end
	return nil
end

local function CurrentFetchTimerSeconds()
	if not Spring.GetTimer or not Spring.DiffTimers then
		return nil
	end

	local currentTimer = SafeCall(Spring.GetTimer)
	if not currentTimer then
		return nil
	end
	if not state.fetchTimerBase then
		state.fetchTimerBase = currentTimer
		return 0
	end

	return tonumber(SafeCall(Spring.DiffTimers, currentTimer, state.fetchTimerBase))
end

local function CurrentScheduleSeconds()
	return CurrentFetchTimerSeconds() or CurrentWallClockSeconds()
end

local function ColorByte(value)
	local number = tonumber(value) or 1
	number = math.max(0, math.min(1, number))
	return math.floor(number * 255 + 0.5)
end

local function HexColor(r, g, b)
	return string.format('#%02X%02X%02X', ColorByte(r), ColorByte(g), ColorByte(b))
end

local function AccountIdFromInfo(...)
	for index = 1, select('#', ...) do
		local info = select(index, ...)
		if type(info) == 'table' then
			local accountID = tonumber(info.accountid or info.accountID or info.account_id)
			if accountID and accountID > 0 then
				return accountID
			end
		end
	end
	return nil
end

local function BuildPlayerColorLookup()
	local lookup = {}
	local playerList = SafeCall(Spring.GetPlayerList) or {}
	for _, playerID in ipairs(playerList) do
		local name, _, spectator, teamID, _, _, _, _, _, customKeys, extraInfo = SafeCall(Spring.GetPlayerInfo, playerID, false)
		if name and spectator == false and teamID and Spring.GetTeamColor then
			local r, g, b = SafeCall(Spring.GetTeamColor, teamID)
			local color = HexColor(r, g, b)
			lookup[name] = color
			local accountID = AccountIdFromInfo(customKeys, extraInfo)
			if accountID then
				lookup[accountID] = color
				lookup[tostring(accountID)] = color
			end
		end
	end
	return lookup
end

local function LoadModOptionDefs()
	if state.modOptionDefsLoaded then
		return state.modOptionDefs
	end
	state.modOptionDefsLoaded = true
	if VFS and VFS.Include then
		local ok, definitions = pcall(VFS.Include, 'gamedata/modoptions.lua')
		if ok then
			state.modOptionDefs = definitions
		end
	end
	return state.modOptionDefs
end

local function BuildModOptionStepLookup()
	if state.modOptionSteps then
		return state.modOptionSteps
	end
	state.modOptionSteps = Model.ModOptionStepLookup(Game and (Game.modOptions or Game.modoptions or Game.mod_options), LoadModOptionDefs())
	return state.modOptionSteps
end

local function CurrentGameId()
	local gameId = Game and Game.gameID
	if gameId == nil and Spring and Spring.GetGameRulesParam then
		gameId = SafeCall(Spring.GetGameRulesParam, 'GameID')
	end
	if gameId == nil or tostring(gameId) == '' then
		return nil
	end
	return tostring(gameId)
end

local function BuildViewModel(response, err, request)
	return Model.ViewModelFromResponse(response, err, request, BuildPlayerColorLookup(), {
		showSpectators = state.showSpectators,
		playerTab = state.playerTab,
		diffExpanded = state.diffsExpanded,
		diagnosticsExpanded = state.diagnosticsExpanded,
		modOptionSteps = BuildModOptionStepLookup(),
		sourceWindowNowSeconds = CurrentWallClockSeconds(),
		currentGameId = CurrentGameId(),
		transportEvidence = state.lastEvidence,
		sortColumn = state.playerSortColumn,
		sortDescending = state.playerSortDescending,
	})
end

local DebugLog

local function LoadingExpectedSeconds()
	return math.max(1, GetConfigFloat('PveStatsLoadingExpectedSeconds', DEFAULT_LOADING_EXPECTED_SECONDS))
end

local function LoadingElapsedSeconds()
	if not state.loadingStartedSeconds then
		return nil
	end
	local nowSeconds = CurrentScheduleSeconds()
	if not nowSeconds then
		return nil
	end
	return math.max(0, nowSeconds - state.loadingStartedSeconds)
end

local function SetLoadingProgress(progress)
	local percent = math.max(0, math.min(100, math.floor((tonumber(progress) or 0) * 1000 + 0.5) / 10))
	if state.loadingProgressPercent == percent then
		return
	end
	state.loadingProgressPercent = percent
	SetStyle('pve-stats-loading-fill', 'width', string.format('%.1f%%', percent))
end

local function ApplyLoadingViewModel()
	local viewModel = BuildViewModel(state.lastResponse, nil, state.lastRequest)
	viewModel.statusText = 'Loading...'
	viewModel.hasError = false
	viewModel.errorText = ''
	viewModel.hasNotice = false
	viewModel.noticeText = ''
	viewModel.hasUpdate = false
	ApplyViewModel(viewModel)
end

local function BeginLoading()
	if state.loadingActive then
		return
	end
	state.loadingActive = true
	state.loadingStartedSeconds = CurrentScheduleSeconds()
	state.loadingStartedWithResponse = state.lastResponse ~= nil
	state.loadingCompletedDueSeconds = nil
	state.loadingProgressPercent = nil
	SetLoadingProgress(0)
	SetClass('pve-stats-loading', 'hidden', false)
	ApplyLoadingViewModel()
	DebugLog('loading_begin expected_seconds=' .. tostring(LoadingExpectedSeconds()))
end

local function CancelLoading()
	state.loadingActive = false
	state.loadingStartedSeconds = nil
	state.loadingStartedWithResponse = false
	state.loadingCompletedDueSeconds = nil
	state.loadingProgressPercent = nil
	SetClass('pve-stats-loading', 'hidden', true)
end

local function CompleteLoading()
	if not state.loadingActive then
		return
	end
	SetLoadingProgress(1)
	local nowSeconds = CurrentScheduleSeconds()
	if nowSeconds then
		state.loadingCompletedDueSeconds = nowSeconds + LOADING_COMPLETE_HOLD_SECONDS
	else
		CancelLoading()
	end
end

local function UpdateLoadingProgress()
	if not state.loadingActive then
		return
	end
	local nowSeconds = CurrentScheduleSeconds()
	if state.loadingCompletedDueSeconds then
		if nowSeconds and nowSeconds >= state.loadingCompletedDueSeconds then
			CancelLoading()
		end
		return
	end
	local elapsedSeconds = LoadingElapsedSeconds()
	if elapsedSeconds then
		SetLoadingProgress(Model.EstimatedLoadingProgress(elapsedSeconds, LoadingExpectedSeconds()))
	end
end

local function ResetPlayerSort(tab, request)
	state.playerSortColumn = Model.DefaultPlayerSortColumn(tab, request)
	state.playerSortDescending = true
end

local function UpdateDefaultPlayerTab(request, response)
	if not response then
		return
	end
	local defaultTab = Model.DefaultPlayerTab(response)
	local contextKey = tostring(Model.SettingRequestKey(request) or '') .. '|' .. defaultTab
	if state.playerTabContextKey == contextKey then
		return
	end
	state.playerTabContextKey = contextKey
	state.playerTab = defaultTab
	ResetPlayerSort(defaultTab, request)
end

local function RefreshViewModel()
	ApplyViewModel(BuildViewModel(state.lastResponse, state.lastError, state.lastRequest))
end

local function SourceWindowAgeMinute(response)
	return Model.SourceWindowAgeMinute(response, {
		sourceWindowNowSeconds = CurrentWallClockSeconds(),
	})
end

local function ResetSourceWindowAgeClock(response)
	state.sourceWindowAgeLastMinute = SourceWindowAgeMinute(response)
end

local function UpdateSourceWindowAgeClock()
	if not state.lastResponse or state.lastError then
		return
	end

	local currentMinute = SourceWindowAgeMinute(state.lastResponse)
	if currentMinute == nil or currentMinute == state.sourceWindowAgeLastMinute then
		return
	end

	state.sourceWindowAgeLastMinute = currentMinute
	RefreshViewModel()
end

local function BuildRequestEvidence(endpoint, body, request)
	return {
		version = 1,
		status = 'pending',
		attempt = state.retryAttempt + 1,
		loading_expected_seconds = LoadingExpectedSeconds(),
		endpoint = EndpointLabel(endpoint),
		ai_type = tostring(request and request.ai_type or ''),
		ai_type_source = tostring(request and request._ai_type_source or ''),
		map_hash = StableHash(request and request.map or ''),
		player_names_count = CountValues(request and request.player_names),
		player_ids_count = CountValues(request and request.player_ids),
		request_bytes = #tostring(body or ''),
		request_hash = StableHash(body),
		request_key_hash = StableHash(request and request._request_key or ''),
		game_id = CurrentGameId(),
		client_version = CLIENT_VERSION,
	}
end

local function LogMessage(message)
	message = LOG_PREFIX .. ' ' .. tostring(message or '')
	if Spring.Echo then
		Spring.Echo('[' .. LOG_SECTION .. '] ' .. message)
	elseif Spring.Log and LOG and LOG.INFO then
		Spring.Log(LOG_SECTION, LOG.INFO, message)
	end
end

DebugLog = function(message)
	if GetConfigInt('PveStatsDebugLog', DEFAULT_DEBUG_LOG) == 1 then
		LogMessage(message)
	end
end

local function CurrentViewGeometry()
	if Spring.GetViewGeometry then
		local viewWidth, viewHeight = Spring.GetViewGeometry()
		if viewWidth and viewHeight and viewWidth > 0 and viewHeight > 0 then
			return viewWidth, viewHeight
		end
	end
	if gl and gl.GetViewSizes then
		local viewWidth, viewHeight = gl.GetViewSizes()
		if viewWidth and viewHeight and viewWidth > 0 and viewHeight > 0 then
			return viewWidth, viewHeight
		end
	end
	return DEFAULT_VIEW_WIDTH, DEFAULT_VIEW_HEIGHT
end

local function PositionDocument()
	if not state.document then
		return
	end

	local panel = state.document:GetElementById(PANEL_ID)
	if not panel then
		DebugLog('position_failed reason=missing_panel id=' .. PANEL_ID)
		return
	end

	local viewWidth, viewHeight = CurrentViewGeometry()
	local left = math.max(0, viewWidth - DEFAULT_PANEL_WIDTH - DEFAULT_PANEL_RIGHT)
	panel.style.left = tostring(left) .. 'px'
	panel.style.top = tostring(DEFAULT_PANEL_TOP) .. 'px'
	panel.style.width = tostring(DEFAULT_PANEL_WIDTH) .. 'dp'

	DebugLog(table.concat({
		'position_panel left=',
		tostring(left),
		' top=',
		tostring(DEFAULT_PANEL_TOP),
		' width=',
		tostring(DEFAULT_PANEL_WIDTH),
		' view=',
		tostring(viewWidth),
		'x',
		tostring(viewHeight),
	}))
end

local function FormatEvidence(evidence)
	if not evidence then
		return 'pve_stats_evidence status=missing'
	end
	return table.concat({
		'pve_stats_evidence version=',
		tostring(evidence.version or 1),
		' status=',
		tostring(evidence.status or '-'),
		' attempt=',
		tostring(evidence.attempt or '-'),
		' request_ms=',
		tostring(evidence.request_duration_ms or '-'),
		' loading_ms=',
		tostring(evidence.loading_elapsed_ms or '-'),
		' loading_expected_seconds=',
		tostring(evidence.loading_expected_seconds or '-'),
		' retry_class=',
		tostring(evidence.retry_class or '-'),
		' startup_transient=',
		tostring(evidence.startup_transient or '-'),
		' endpoint=',
		tostring(evidence.endpoint or '-'),
		' ai_type=',
		tostring(evidence.ai_type or '-'),
		' ai_type_source=',
		tostring(evidence.ai_type_source or '-'),
		' map_hash=',
		tostring(evidence.map_hash or '-'),
		' player_names=',
		tostring(evidence.player_names_count or 0),
		' player_ids=',
		tostring(evidence.player_ids_count or 0),
		' request_hash=',
		tostring(evidence.request_hash or '-'),
		' request_key_hash=',
		tostring(evidence.request_key_hash or '-'),
		' trace_id=',
		tostring(evidence.trace_id or '-'),
		' query_hash=',
		tostring(evidence.setting_hash or '-'),
		' match_hash=',
		tostring(evidence.closest_match_hash or '-'),
		' game_id=',
		tostring(evidence.game_id or '-'),
		' source_window=',
		tostring(evidence.source_window or '-'),
		' source_earliest=',
		tostring(evidence.earliest_replay_time or '-'),
		' latest_replay=',
		tostring(evidence.latest_replay_time or '-'),
		' latest_replay_age_days=',
		tostring(evidence.latest_replay_age_days or '-'),
		' request_bytes=',
		tostring(evidence.request_bytes or 0),
		' response_hash=',
		tostring(evidence.response_hash or '-'),
		' response_bytes=',
		tostring(evidence.response_bytes or 0),
		' http_status=',
		tostring(evidence.http_status or '-'),
		' match_status=',
		tostring(evidence.match_status or '-'),
		' match_method=',
		tostring(evidence.match_method or '-'),
		' diff_display=',
		tostring(evidence.closest_match_display_diff_count or '-'),
		' diff_hidden=',
		tostring(evidence.closest_match_hidden_diff_total or '-'),
	})
end

local function MaybeLogEvidence(evidence)
	if GetConfigInt('PveStatsEvidenceLog', DEFAULT_EVIDENCE_LOG) == 1 then
		LogMessage(FormatEvidence(evidence))
	end
end

local function ResponseHeaderValue(header, expectedName)
	for line in string.gmatch(header or '', '[^\r\n]+') do
		local name, value = string.match(line, '^%s*([^:]+):%s*(.-)%s*$')
		if name and string.lower(name) == string.lower(expectedName) then
			return string.sub(value, 1, 128)
		end
	end
	return nil
end

local function ParseHttpResponse(raw)
	local headerEnd = string.find(raw, '\r\n\r\n', 1, true)
	if not headerEnd then
		return nil, 'invalid_http_response'
	end

	local header = string.sub(raw, 1, headerEnd - 1)
	local body = string.sub(raw, headerEnd + 4)
	local status = tonumber(string.match(header, '^HTTP/%d%.%d%s+(%d+)'))
	if not status then
		return nil, 'invalid_http_status'
	end
	local meta = {
		http_status = status,
		response_bytes = #body,
		response_hash = StableHash(body),
		trace_id = ResponseHeaderValue(header, 'x-request-id')
			or ResponseHeaderValue(header, 'x-amzn-requestid')
			or ResponseHeaderValue(header, 'x-amz-cf-id'),
	}
	if status < 200 or status >= 300 then
		return nil, 'http_' .. tostring(status) .. ':' .. body, meta
	end

	local ok, decoded = pcall(Json.decode, body)
	if not ok then
		return nil, 'invalid_json:' .. tostring(decoded), meta
	end
	return decoded, nil, meta
end

local function Trim(value)
	return string.match(tostring(value or ''), '^%s*(.-)%s*$')
end

local function NormalizePath(path)
	path = Trim(path)
	if path == '' then
		return DEFAULT_PATH
	end
	if string.sub(path, 1, 1) ~= '/' then
		return '/' .. path
	end
	return path
end

local function ParseHttpUrl(url)
	url = Trim(url)
	local scheme, rest = string.match(url, '^(%a[%w+.-]*)://(.+)$')
	if not scheme then
		return nil, 'invalid_url'
	end

	scheme = string.lower(scheme)
	if scheme ~= 'http' then
		return nil, 'unsupported_scheme:' .. scheme
	end

	local authority, path = string.match(rest, '^([^/]*)(/?.*)$')
	if not authority or authority == '' then
		return nil, 'missing_host'
	end
	if string.find(authority, '@', 1, true) then
		return nil, 'unsupported_url_auth'
	end

	local host, portText = string.match(authority, '^([^:]+):?(%d*)$')
	if not host or host == '' then
		return nil, 'invalid_host'
	end

	local port = DEFAULT_PORT
	if portText and portText ~= '' then
		port = tonumber(portText)
	else
		port = 80
	end
	if not port or port < 1 or port > 65535 then
		return nil, 'invalid_port'
	end

	return {
		scheme = scheme,
		host = host,
		port = port,
		path = NormalizePath(path),
	}
end

local function ResolveEndpoint()
	local configuredUrl = Trim(GetConfigString('PveStatsUrl', DEFAULT_URL))
	if configuredUrl ~= '' then
		return ParseHttpUrl(configuredUrl)
	end

	return {
		scheme = 'http',
		host = GetConfigString('PveStatsHost', DEFAULT_HOST),
		port = GetConfigInt('PveStatsPort', DEFAULT_PORT),
		path = NormalizePath(GetConfigString('PveStatsPath', DEFAULT_PATH)),
	}
end

local function IsLuaSocketEnabled()
	return GetConfigInt('LuaSocketEnabled', DEFAULT_LUA_SOCKET_ENABLED) == 1
end

local function PostJson(endpoint, body)
	if not IsLuaSocketEnabled() then
		return nil, 'lua_socket_disabled'
	end

	socketLib = socketLib or socket
	if not socketLib or not socketLib.tcp then
		return nil, 'missing_socket'
	end

	local timeout = GetConfigInt('PveStatsTimeoutMs', DEFAULT_TIMEOUT_MS) / 1000

	local client = socketLib.tcp()
	client:settimeout(timeout)
	local ok, err = client:connect(endpoint.host, endpoint.port)
	if not ok then
		client:close()
		return nil, 'connect_failed:' .. tostring(err)
	end

	local request = table.concat({
		'POST ' .. endpoint.path .. ' HTTP/1.1\r\n',
		'Host: ' .. endpoint.host .. ':' .. tostring(endpoint.port) .. '\r\n',
		'Content-Type: application/json\r\n',
		'Content-Length: ' .. tostring(#body) .. '\r\n',
		'Connection: close\r\n',
		'\r\n',
		body,
	})

	local sent = 0
	while sent < #request do
		local lastByte, sendErr, partial = client:send(request, sent + 1)
		if lastByte then
			sent = lastByte
		elseif partial and partial > sent then
			sent = partial
		else
			client:close()
			return nil, 'send_failed:' .. tostring(sendErr)
		end
	end

	local response, receiveErr, partial = client:receive('*a')
	client:close()
	response = response or partial
	if not response or response == '' then
		return nil, 'receive_failed:' .. tostring(receiveErr)
	end
	return ParseHttpResponse(response)
end

local function CompleteEvidence(evidence, response, err, meta)
	evidence = evidence or { version = 1 }
	evidence.status = err and 'error' or 'ok'
	evidence.error = err
	evidence.retry_class = Model.RetryErrorClass(err)
	evidence.startup_transient = Model.IsExpectedStartupTransient(err) or nil
	local loadingElapsedSeconds = LoadingElapsedSeconds()
	if loadingElapsedSeconds then
		evidence.loading_elapsed_ms = math.floor(loadingElapsedSeconds * 1000 + 0.5)
	end
	if meta then
		evidence.http_status = meta.http_status
		evidence.response_bytes = meta.response_bytes
		evidence.response_hash = meta.response_hash
		evidence.trace_id = meta.trace_id
	end
	if response then
		evidence.match_status = response.match_status
		evidence.setting_hash = response.setting_hash
		local topMatch = response.closest_matches and response.closest_matches[1]
		if type(topMatch) == 'table' then
			evidence.closest_match_hash = topMatch.setting_hash
			evidence.match_method = topMatch.match_method
			if type(topMatch.display_diffs) == 'table' then
				evidence.closest_match_display_diff_count = #topMatch.display_diffs
			elseif topMatch.difference_count == 0 then
				evidence.closest_match_display_diff_count = 0
			end
			if type(topMatch.hidden_diff_summary) == 'table' then
				evidence.closest_match_hidden_diff_total = topMatch.hidden_diff_summary.total
				if evidence.closest_match_display_diff_count == nil and tonumber(topMatch.difference_count) then
					evidence.closest_match_display_diff_count = math.max(
						0,
						tonumber(topMatch.difference_count) - tonumber(topMatch.hidden_diff_summary.total or 0)
					)
				end
			elseif topMatch.difference_count == 0 then
				evidence.closest_match_hidden_diff_total = 0
			end
		end
		if type(response.source_window) == 'table' then
			evidence.source_window = response.source_window.display
			evidence.earliest_replay_time = response.source_window.earliest_replay_time
			evidence.latest_replay_time = response.source_window.latest_replay_time
			evidence.latest_replay_age_days = response.source_window.latest_replay_age_days
		end
	end
	state.lastEvidence = evidence
	MaybeLogEvidence(evidence)
	return evidence
end

local function ResetRetryState()
	state.retryAttempt = 0
	state.retryActive = false
end

local function RetryMaxAttempts()
	return math.max(0, GetConfigInt('PveStatsRetryMaxAttempts', DEFAULT_RETRY_MAX_ATTEMPTS))
end

local function RetryDelaySeconds(attempt)
	return Model.BoundedExponentialBackoffSeconds(
		attempt,
		GetConfigInt('PveStatsRetryInitialSeconds', DEFAULT_RETRY_INITIAL_SECONDS),
		GetConfigInt('PveStatsRetryMaxSeconds', DEFAULT_RETRY_MAX_SECONDS)
	)
end

local function RetryErrorText(err, delay, attempt, maxAttempts)
	return table.concat({
		tostring(err or 'unknown_error'),
		' retrying in ',
		string.format('%.0f', delay or 0),
		's (',
		tostring(attempt or 0),
		'/',
		tostring(maxAttempts or 0),
		')',
	})
end

local function PrepareFetch()
	DebugLog('fetch_start')

	local request, err = Model.BuildRequest(Spring, Game)
	state.lastRequest = request
	if not request then
		state.lastError = err
		DebugLog('fetch_request_failed error=' .. tostring(err))
		ApplyViewModel(BuildViewModel(nil, err, nil))
		return nil, err
	end

	local ok, body = pcall(Json.encode, Model.WireRequest(request))
	if not ok then
		err = 'encode_failed:' .. tostring(body)
		state.lastError = err
		DebugLog('fetch_encode_failed error=' .. tostring(err))
		ApplyViewModel(BuildViewModel(nil, err, request))
		return nil, err
	end

	local endpoint
	endpoint, err = ResolveEndpoint()
	if not endpoint then
		state.lastError = err
		DebugLog('fetch_endpoint_failed error=' .. tostring(err))
		ApplyViewModel(BuildViewModel(nil, err, request))
		return nil, err
	end

	local evidence = BuildRequestEvidence(endpoint, body, request)
	state.lastEvidence = evidence
	DebugLog('fetch_post endpoint=' .. tostring(evidence.endpoint) .. ' request_bytes=' .. tostring(evidence.request_bytes))
	return {
		body = body,
		endpoint = endpoint,
		evidence = evidence,
		request = request,
		requestStartedSeconds = CurrentScheduleSeconds(),
	}, nil
end

local function FinishFetch(context, response, err, responseMeta)
	context = context or {}
	local requestFinishedSeconds = CurrentScheduleSeconds()
	if context.requestStartedSeconds and requestFinishedSeconds then
		context.evidence.request_duration_ms = math.floor(
			math.max(0, requestFinishedSeconds - context.requestStartedSeconds) * 1000 + 0.5
		)
	end
	state.diffsExpanded = false
	if response then
		state.lastResponse = response
		state.lastError = nil
		UpdateDefaultPlayerTab(context.request, response)
		ResetSourceWindowAgeClock(response)
		ResetRetryState()
	else
		state.lastError = err
		ResetSourceWindowAgeClock(nil)
	end
	CompleteEvidence(context.evidence, response, err, responseMeta)
	DebugLog('fetch_complete status=' .. tostring(context.evidence.status) .. ' error=' .. tostring(err or '-'))

	local viewModel = BuildViewModel(response, err, context.request)
	DebugLog(table.concat({
		'view_model status=',
		tostring(viewModel.statusText),
		' mode=',
		tostring(viewModel.modeText),
		' difficulty=',
		tostring(viewModel.difficultyText),
		' players=',
		tostring(response and response.players and #response.players or 0),
		' has_error=',
		tostring(viewModel.hasError),
	}))
	ApplyViewModel(viewModel)
	return response, err
end

local function FetchStats()
	local context, err = PrepareFetch()
	if not context then
		return nil, err
	end
	local response, responseMeta
	response, err, responseMeta = PostJson(context.endpoint, context.body)
	return FinishFetch(context, response, err, responseMeta)
end

local function StartFetchStats()
	if state.httpOperation then
		return false, 'request_in_progress'
	end
	if not IsLuaSocketEnabled() then
		state.lastError = 'lua_socket_disabled'
		ApplyViewModel(BuildViewModel(nil, state.lastError, state.lastRequest))
		return false, state.lastError
	end
	if not state.loadingActive then
		BeginLoading()
	end
	local context, err = PrepareFetch()
	if not context then
		return false, err
	end

	socketLib = socketLib or socket
	local operation
	operation, err = HttpClient.Start(socketLib, context.endpoint, context.body, {
		started_seconds = context.requestStartedSeconds,
		timeout_seconds = GetConfigInt('PveStatsAsyncTimeoutMs', DEFAULT_ASYNC_TIMEOUT_MS) / 1000,
	})
	if not operation then
		FinishFetch(context, nil, err, nil)
		return false, err
	end
	state.httpOperation = operation
	state.httpContext = context
	DebugLog('fetch_async_started timeout_ms=' .. tostring(GetConfigInt('PveStatsAsyncTimeoutMs', DEFAULT_ASYNC_TIMEOUT_MS)))
	return true, nil
end

local function PollFetchStats()
	if not state.httpOperation then
		return false, nil, nil
	end
	local raw, err, finished = HttpClient.Poll(state.httpOperation, CurrentScheduleSeconds())
	if not finished then
		return false, nil, nil
	end

	local context = state.httpContext
	state.httpOperation = nil
	state.httpContext = nil
	local response
	local responseMeta
	if raw then
		response, err, responseMeta = ParseHttpResponse(raw)
	end
	response, err = FinishFetch(context, response, err, responseMeta)
	return true, response, err
end

local function ScheduleFetch(delay, options)
	options = options or {}
	if options.retry ~= true then
		ResetRetryState()
	end
	state.pendingFetch = true
	state.fetchDelay = math.max(0, tonumber(delay) or 0)
	state.fetchDelayRemaining = state.fetchDelay
	local nowSeconds = CurrentScheduleSeconds()
	state.fetchDueSeconds = nowSeconds and (nowSeconds + state.fetchDelay) or nil
	DebugLog(table.concat({
		'schedule_fetch delay=',
		tostring(state.fetchDelay),
		' retry=',
		tostring(options.retry == true),
		' attempt=',
		tostring(state.retryAttempt),
	}))
end

local function IsScheduledFetchDue(deltaTime)
	if not state.pendingFetch then
		return false
	end
	if state.fetchDelay <= 0 then
		return true
	end

	local nowSeconds = CurrentScheduleSeconds()
	if nowSeconds and state.fetchDueSeconds then
		return nowSeconds >= state.fetchDueSeconds
	end

	local deltaSeconds = math.max(0, tonumber(deltaTime) or 0)
	if deltaSeconds <= 0 then
		return false
	end
	state.fetchDelayRemaining = math.max(0, (state.fetchDelayRemaining or state.fetchDelay) - deltaSeconds)
	return state.fetchDelayRemaining <= FETCH_DELAY_EPSILON_SECONDS
end

local function ScheduleRetry(err)
	local maxAttempts = RetryMaxAttempts()
	if maxAttempts <= 0 then
		CancelLoading()
		DebugLog('retry_disabled error=' .. tostring(err or '-'))
		return false
	end
	if state.retryAttempt >= maxAttempts then
		state.retryActive = false
		CancelLoading()
		DebugLog('retry_exhausted attempts=' .. tostring(state.retryAttempt) .. ' error=' .. tostring(err or '-'))
		return false
	end

	state.retryAttempt = state.retryAttempt + 1
	state.retryActive = true
	local delay = RetryDelaySeconds(state.retryAttempt)
	ScheduleFetch(delay, { retry = true })

	local startupTransient = not state.loadingStartedWithResponse and Model.IsExpectedStartupTransient(err)
	if startupTransient then
		ApplyLoadingViewModel()
	else
		CancelLoading()
		local viewModel = BuildViewModel(nil, RetryErrorText(err, delay, state.retryAttempt, maxAttempts), state.lastRequest)
		viewModel.statusText = 'Retrying'
		ApplyViewModel(viewModel)
	end

	DebugLog(table.concat({
		'schedule_retry attempt=',
		tostring(state.retryAttempt),
		' max_attempts=',
		tostring(maxAttempts),
		' delay=',
		tostring(delay),
		' class=',
		tostring(Model.RetryErrorClass(err) or '-'),
		' startup_transient=',
		tostring(startupTransient),
		' error=',
		tostring(err or '-'),
	}))
	return true
end

local function RequestStats()
	if state.httpOperation or state.pendingFetch then
		return false, 'request_in_progress'
	end
	if not state.loadingActive then
		BeginLoading()
	end
	ScheduleFetch(0)
	return true, nil
end

local function InstallApi()
	WG.PveStatsRml = {
		BuildRequest = function()
			return Model.BuildRequest(Spring, Game)
		end,
		FetchStats = RequestStats,
		FetchStatsOnce = FetchStats,
		ScheduleFetch = ScheduleFetch,
		GetLastRequest = function()
			return state.lastRequest
		end,
		GetLastResponse = function()
			return state.lastResponse
		end,
		GetLastError = function()
			return state.lastError
		end,
		GetLoadingState = function()
			return {
				active = state.loadingActive,
				elapsed_seconds = LoadingElapsedSeconds(),
				progress_percent = state.loadingProgressPercent,
			}
		end,
		GetLastEvidence = function()
			return state.lastEvidence
		end,
		GetRetryAttempt = function()
			return state.retryAttempt
		end,
		IsRetryActive = function()
			return state.retryActive
		end,
		IsRequestPending = function()
			return state.httpOperation ~= nil
		end,
		LogLastEvidence = function()
			LogMessage(FormatEvidence(state.lastEvidence))
			return state.lastEvidence
		end,
		GetEndpoint = ResolveEndpoint,
		IsLuaSocketEnabled = IsLuaSocketEnabled,
		GetViewModel = function()
			return state.viewModel
		end,
		GetShowSpectators = function()
			return state.showSpectators
		end,
		SetShowSpectators = function(enabled)
			state.showSpectators = enabled == true
			SetConfigInt('PveStatsShowSpectators', state.showSpectators and 1 or 0)
			RefreshViewModel()
		end,
	}
end

function widget:Initialize()
	DebugLog('initialize_begin')
	state.windowClosed = false
	state.showSpectators = GetConfigInt('PveStatsShowSpectators', DEFAULT_SHOW_SPECTATORS) == 1
	state.minimized = GetConfigInt('PveStatsMinimized', DEFAULT_MINIMIZED) == 1
	InstallApi()
	ApplyViewModel(BuildViewModel(nil, nil, nil))

	state.rmlContext = RmlUi.GetContext('shared')
	if not state.rmlContext then
		DebugLog('initialize_failed reason=missing_rml_context')
		return false
	end

	local dm = state.rmlContext:OpenDataModel(MODEL_NAME, state.viewModel, self)
	if not dm then
		DebugLog('initialize_failed reason=missing_data_model')
		return false
	end
	state.dmHandle = dm

	local document = state.rmlContext:LoadDocument(RML_PATH, self)
	if not document then
		DebugLog('initialize_failed reason=missing_document path=' .. RML_PATH)
		widget:Shutdown()
		return false
	end
	state.document = document
	document:ReloadStyleSheet()
	PositionDocument()
	document:Show()
	ApplyViewModel(state.viewModel)

	DebugLog(table.concat({
		'initialize_ready auto_fetch=',
		tostring(GetConfigInt('PveStatsAutoFetch', DEFAULT_AUTO_FETCH)),
		' evidence_log=',
		tostring(GetConfigInt('PveStatsEvidenceLog', DEFAULT_EVIDENCE_LOG)),
		' lua_socket=',
		tostring(GetConfigInt('LuaSocketEnabled', DEFAULT_LUA_SOCKET_ENABLED)),
		' show_spectators=',
		tostring(state.showSpectators and 1 or 0),
		' retry_max_attempts=',
		tostring(RetryMaxAttempts()),
		' retry_initial_seconds=',
		tostring(GetConfigInt('PveStatsRetryInitialSeconds', DEFAULT_RETRY_INITIAL_SECONDS)),
		' retry_max_seconds=',
		tostring(GetConfigInt('PveStatsRetryMaxSeconds', DEFAULT_RETRY_MAX_SECONDS)),
		' loading_expected_seconds=',
		tostring(LoadingExpectedSeconds()),
		' async_timeout_ms=',
		tostring(GetConfigInt('PveStatsAsyncTimeoutMs', DEFAULT_ASYNC_TIMEOUT_MS)),
	}))

	if GetConfigInt('PveStatsAutoFetch', DEFAULT_AUTO_FETCH) == 1 then
		BeginLoading()
		ScheduleFetch(0.5)
	end
end

function widget:ViewResize()
	PositionDocument()
end

function widget:ToggleSpectators()
	state.showSpectators = not state.showSpectators
	SetConfigInt('PveStatsShowSpectators', state.showSpectators and 1 or 0)
	DebugLog('toggle_spectators enabled=' .. tostring(state.showSpectators))
	RefreshViewModel()
end

function widget:ToggleMinimized()
	state.minimized = not state.minimized
	SetConfigInt('PveStatsMinimized', state.minimized and 1 or 0)
	DebugLog('toggle_minimized enabled=' .. tostring(state.minimized))
	ApplyViewModel(state.viewModel)
end

local function SetPlayerTab(tab)
	state.playerTab = tab
	ResetPlayerSort(tab, state.lastRequest)
	DebugLog('player_tab selected=' .. tostring(tab))
	RefreshViewModel()
end

local function SortPlayerColumn(column)
	if state.playerSortColumn == column then
		state.playerSortDescending = not state.playerSortDescending
	else
		state.playerSortColumn = column
		state.playerSortDescending = true
	end
	DebugLog('player_sort column=' .. tostring(column) .. ' descending=' .. tostring(state.playerSortDescending))
	RefreshViewModel()
end

function widget:SortPlayerColumnName()
	SortPlayerColumn(0)
end

function widget:SortPlayerColumnOne()
	SortPlayerColumn(1)
end

function widget:SortPlayerColumnTwo()
	SortPlayerColumn(2)
end

function widget:SortPlayerColumnThree()
	SortPlayerColumn(3)
end

function widget:SetPlayerTabSetup()
	SetPlayerTab('setup')
end

function widget:SetPlayerTabAdventures()
	SetPlayerTab('adventures')
end

function widget:SetPlayerTabEncounters()
	SetPlayerTab('encounters')
end

function widget:SetPlayerTabMilestones()
	SetPlayerTab('milestones')
end

function widget:SetPlayerTabAwards()
	SetPlayerTab('awards')
end

function widget:ShowPlayerStatOneHelp()
	ShowTableHelp(Model.PlayerStatHelpText(state.playerTab, 1))
end

function widget:ShowPlayerStatTwoHelp()
	ShowTableHelp(Model.PlayerStatHelpText(state.playerTab, 2))
end

function widget:ShowPlayerStatThreeHelp()
	ShowTableHelp(Model.PlayerStatHelpText(state.playerTab, 3))
end

function widget:ShowMatchHelp()
	ShowHelp(state.viewModel.matchHelpText)
end

function widget:ShowWinChanceHelp()
	ShowHelp(state.viewModel.winChanceHelpText)
end

function widget:ShowDifficultyPercentileHelp()
	ShowHelp(state.viewModel.difficultyPercentileHelpText)
end

function widget:ShowTrainingGamesHelp()
	ShowHelp(state.viewModel.trainingGamesHelpText)
end

function widget:ShowHistogramHelp()
	ShowHelp(Model.HistogramHelpText(state.lastResponse, state.lastRequest))
end

function widget:ShowHistogramBinHelp(event)
	local element = event and event.current_element
	local index = element and element.GetAttribute and element:GetAttribute('data-bin-index')
	ShowHelp(Model.HistogramBinHelpText(state.lastResponse, state.lastRequest, index))
end

function widget:ShowDiagnosticsHelp()
	ShowHelp('Show request timing, field coverage, match details, and troubleshooting IDs.')
end

function widget:ShowUpdateHelp()
	if state.viewModel.hasUpdate then
		ShowHelp(state.viewModel.updateHelpText)
	end
end

function widget:CopyUpdateLink()
	if not state.viewModel.hasUpdate then
		return
	end
	if Spring and Spring.SetClipboard then
		local ok = pcall(Spring.SetClipboard, UPDATE_URL)
		if ok then
			ShowHelp('Widget installation link copied to clipboard.')
			return
		end
	end
	ShowHelp('Widget update: ' .. UPDATE_URL)
end

function widget:HideHelp()
	HideHelpPanels()
end

function widget:ToggleDiffs()
	state.diffsExpanded = not state.diffsExpanded
	DebugLog('toggle_diffs expanded=' .. tostring(state.diffsExpanded))
	RefreshViewModel()
end

function widget:ToggleDiagnostics()
	if not state.viewModel.hasDiagnostics then
		return
	end
	state.diagnosticsExpanded = not state.diagnosticsExpanded
	DebugLog('toggle_diagnostics expanded=' .. tostring(state.diagnosticsExpanded))
	RefreshViewModel()
end

function widget:CopyDiagnostics()
	local diagnostics = state.viewModel.diagnosticsText
	if not diagnostics or diagnostics == '' then
		return
	end
	if Spring and Spring.SetClipboard then
		local ok = pcall(Spring.SetClipboard, diagnostics)
		if ok then
			ShowHelp('PvE Stats diagnostics copied to clipboard.')
			return
		end
	end
	ShowHelp('Clipboard unavailable. Diagnostics remain visible in the expanded panel.')
end

local function ReleaseWindowResources()
	if state.httpOperation then
		HttpClient.Cancel(state.httpOperation)
		state.httpOperation = nil
		state.httpContext = nil
	end
	state.pendingFetch = false
	state.fetchDueSeconds = nil
	state.fetchDelayRemaining = nil
	state.retryActive = false
	state.loadingActive = false
	if state.rmlContext and state.dmHandle then
		state.rmlContext:RemoveDataModel(MODEL_NAME)
		state.dmHandle = nil
	end
	if state.document then
		state.document:Close()
		state.document = nil
	end
	if WG.PveStatsRml then
		WG.PveStatsRml = nil
	end
	state.rmlContext = nil
end

function widget:CloseWindow()
	if state.windowClosed then
		return
	end
	state.windowClosed = true
	DebugLog('window_closed')
	ReleaseWindowResources()
end

function widget:Shutdown()
	state.windowClosed = true
	ReleaseWindowResources()
end

function widget:Update(deltaTime)
	if state.windowClosed then
		return
	end
	UpdateLoadingProgress()
	local finished, _, requestErr = PollFetchStats()
	if finished then
		if requestErr then
			ScheduleRetry(requestErr)
		else
			ResetRetryState()
			CompleteLoading()
		end
		return
	end
	if state.httpOperation then
		return
	end
	if IsScheduledFetchDue(deltaTime) then
		state.pendingFetch = false
		state.fetchDueSeconds = nil
		state.fetchDelayRemaining = nil
		local started, startErr = StartFetchStats()
		if not started then
			ScheduleRetry(startErr)
		end
		return
	end

	UpdateSourceWindowAgeClock()
end

function widget:RecvLuaMsg(message)
	if not state.document then
		return
	end
	if message:sub(1, 19) == "LobbyOverlayActive0" then
		DebugLog("visibility_show reason=lobby_overlay_inactive")
		state.document:Show()
	elseif message:sub(1, 19) == "LobbyOverlayActive1" then
		DebugLog("visibility_hide reason=lobby_overlay_active")
		state.document:Hide()
	end
end
