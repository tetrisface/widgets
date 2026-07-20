local root = PVE_STATS_TEST_ROOT or (arg and arg[1]) or "./"
local T = dofile(root .. "tests/support.lua")
local Display = dofile(root .. "include/display.lua")
local PlayerStats = dofile(root .. "include/player_stats.lua").New(Display)
local Histogram = dofile(root .. "include/histogram.lua").New(Display, PlayerStats)
local Diagnostics = dofile(root .. "include/diagnostics.lua").New(Display)
local ViewModel = dofile(root .. "include/view_model.lua").New(
	Display,
	PlayerStats,
	Histogram,
	Diagnostics
)

local request = T.request({
	map = "Supreme Isthmus",
	game_settings = {startmetal = 1000},
	encounter_context = {human_team_size = 2},
	player_names = {"Alice", "Bob", "Spectator"},
	player_ids = {101, 202, 303},
	player_filter_requested = true,
	_own_player_id = 101,
	_own_player_name = "Alice",
	_spectator_names = {"Spectator"},
	_spectator_ids = {303},
})

local response = {
	client_version = 10,
	match_status = "closest",
	setting_hash = "query-hash-that-is-long",
	difficulty_estimate = {
		player_win_probability = 0.625,
		evidence_games = 1234,
		difficulty_target_sha256 = "contract-hash-that-is-long",
	},
	difficulty_histogram = {
		total_games = 10,
		current_difficulty = 21,
		current_percentile = 73,
		bins = {
			{lower_bound = 15, upper_bound = 20, games = 4, wins = 3},
			{lower_bound = 20, upper_bound = 25, games = 6, wins = 2},
		},
	},
	players = {
		{
			player_id = 101,
			player_name = "Alice",
			setup_clears = 3,
			setup_plays = 4,
			accomplishments = {
				participation = {games_played = 50, victories = 30, distinct_maps_played = 12},
				encounters = {raptor_queens_defeated = 10, scavenger_bosses_defeated = 2, barbarian_ais_defeated = 1},
				challenges = {
					challenge_20_clears = 5,
					challenge_25_clears = 2,
					challenge_30_clears = 1,
					highest_challenge_cleared = 28.5,
					clear_histogram = {1, 3},
				},
			},
			awards = {most_killed = {raptors = 4, scavengers = 2, barbarians = 1}},
		},
		{
			player_id = 202,
			player_name = "Bob",
			setup_clears = 2,
			setup_plays = 5,
			accomplishments = {
				participation = {games_played = 40, victories = 20, distinct_maps_played = 8},
				challenges = {challenge_20_clears = 2, challenge_25_clears = 0, challenge_30_clears = 0},
			},
			awards = {most_killed = {raptors = 2}},
		},
		{player_id = 303, player_name = "Spectator", accomplishments = {}},
	},
	unresolved_player_names = {"Unresolved"},
	closest_matches = {{
		match_method = "similar",
		similarity = 0.875,
		setting_hash = "matched-hash-that-is-long",
		difference_count = 4,
		display_diffs = {
			{column = "startmetal", incoming = 1001, expected = 994},
		},
		hidden_diff_summary = {total = 2},
	}},
	request_completeness = {
		provided_hash_columns = 7,
		derived_hash_column_names = {},
		defaulted_hash_columns = 1,
		missing_hash_columns = 1,
		missing_hash_column_names = {},
		total_hash_columns = 10,
	},
	source_window = {
		earliest_replay_time = "2026-01-01T00:00:00Z",
		latest_replay_age_seconds = 120,
	},
}

local options = {
	playerTab = "milestones",
	showSpectators = true,
	sortColumn = 1,
	sortDescending = true,
	diagnosticsExpanded = true,
	modOptionSteps = {startmetal = 10},
	currentGameId = "game-opaque-id",
	transportEvidence = {
		http_status = 200,
		attempt = 2,
		request_duration_ms = 1250,
		loading_elapsed_ms = 1500,
		loading_expected_seconds = 19,
		request_bytes = 512,
		response_bytes = 2048,
		request_hash = "request-opaque-id",
		trace_id = "trace-opaque-id",
		unapproved_detail = "excluded-support-detail",
	},
}

local function FindPlayer(groups, name)
	for _, group in ipairs(groups) do
		for _, player in ipairs(group.players) do
			if player.name == name then return player, group end
		end
	end
	return nil
end

local function AssertNoRmlFragments(value, seen)
	if type(value) ~= "table" then return end
	seen = seen or {}
	if seen[value] then return end
	seen[value] = true
	for key, child in pairs(value) do
		T.falsy(string.match(tostring(key), "Rml$"), "presenter returned generated RML field " .. tostring(key))
		AssertNoRmlFragments(child, seen)
	end
end

local function AssertSameRootKeys(expected, actual)
	for key in pairs(expected) do
		T.truthy(actual[key] ~= nil, "view model removed root key " .. tostring(key))
	end
	for key in pairs(actual) do
		T.truthy(expected[key] ~= nil, "view model added undeclared root key " .. tostring(key))
	end
end

local function testDataModelRootSchemaIsStable()
	local empty = ViewModel.Empty()
	AssertSameRootKeys(empty, ViewModel.Build(response, nil, request, nil, options))
	AssertSameRootKeys(empty, ViewModel.Build(nil, "invalid_json", request, nil, {}))
	T.equals(empty.apiClientVersion, 0)
end

local function testStructuredViewModel()
	local view = ViewModel.Build(response, nil, request, {Alice = "#112233", Bob = "#445566"}, options)
	T.equals(view.difficultyText, "21.0")
	T.equals(view.exactWinsText, "62.5%")
	T.equals(view.evidenceGamesText, "P73")
	T.equals(view.matchText, "Similar 0.875")
	T.truthy(view.hasHistogram)
	T.equals(#view.histogramBins, 2)
	T.falsy(view.histogramBins[1].isCurrent)
	T.truthy(view.histogramBins[2].isCurrent)
	T.equals(view.histogramBins[2].populationHeight, "80%")
	T.equals(view.histogramBins[2].ownHeight, "100%")
	local alice = assert(FindPlayer(view.playerGroups, "Alice"))
	T.truthy(alice.isOwn)
	T.equals(alice.color, "#112233")
	local spectator, spectatorGroup = FindPlayer(view.playerGroups, "Spectator")
	T.truthy(spectator)
	T.equals(spectatorGroup.label, "Spectators")
	T.equals(view.diffRows[1].field, "startmetal")
	T.equals(view.diffRows[1].current, "1000")
	T.equals(view.diffRows[1].closest, "990")
	T.truthy(view.hasUpdate)
	T.contains(view.sourceWindowText, "2 minutes ago")
	AssertNoRmlFragments(view)
end

local function testDiagnosticsUseOneNarrowEvidenceContract()
	local evidence = Diagnostics.Evidence(response, options)
	T.equals(evidence.http_status, 200)
	T.equals(evidence.query_hash, "query-hash-t")
	T.equals(evidence.unapproved_detail, nil)
	local presentation = Diagnostics.Build(response, options)
	T.contains(presentation.diagnosticsText, "HTTP: 200; attempt 2")
	T.contains(presentation.diagnosticsText, "request 512 B; response 2 KiB")
	T.notContains(presentation.diagnosticsText, "excluded-support-detail")
	local logText = Diagnostics.FormatEvidenceLog(evidence)
	T.contains(logText, "http_status=200")
	T.notContains(logText, "excluded-support-detail")
end

local function testErrorsAndFreshnessArePresentationState()
	local unavailable = ViewModel.Build(nil, "invalid_json", request, nil, {})
	T.equals(unavailable.statusText, "Unavailable")
	T.truthy(unavailable.hasError)
	T.equals(unavailable.playerGroups[1].players[1], nil)
	T.equals(ViewModel.SourceWindowAgeMinute(response, {}), 2)
	local early = ViewModel.EstimatedLoadingProgress(1, 10)
	local late = ViewModel.EstimatedLoadingProgress(20, 10)
	T.truthy(early > 0 and early < 0.9)
	T.truthy(late >= 0.9 and late <= 0.92)
end

local function testFeatureTabsSortingAndHelpMatchPresentation()
	T.equals(PlayerStats.DefaultTab({match_status = "exact"}), "setup")
	T.equals(PlayerStats.DefaultTab(response), "awards")
	for _, tab in ipairs({"setup", "adventures", "encounters", "milestones", "awards"}) do
		local model = PlayerStats.Build(response, request, nil, {
			playerTab = tab,
			sortColumn = PlayerStats.DefaultSortColumn(tab, request),
			sortDescending = true,
		})
		T.equals(model.playerTab, tab)
		T.truthy(model.playerStatOneLabel ~= "")
		T.truthy(PlayerStats.HelpText(tab, 1) ~= "")
	end
	local withoutSpectators = PlayerStats.Build(response, request, nil, {
		playerTab = "setup",
		showSpectators = false,
		sortColumn = 0,
		sortDescending = false,
	})
	T.equals(FindPlayer(withoutSpectators.playerGroups, "Spectator"), nil)
	T.contains(Histogram.HelpText(response, request), "eligible games")
	T.contains(Histogram.BinHelpText(response, request, 2), "current setup is here")
end

local function testPlayerSortingIsStrictAndDirectional()
	local players = {}
	for index = 1, 40 do
		players[index] = {
			player_id = index,
			player_name = string.format("Player %02d", index),
			setup_clears = index,
			setup_plays = index,
			accomplishments = {participation = {games_played = index}},
		}
	end
	local sortResponse = {players = players}
	local descending = PlayerStats.Build(sortResponse, request, nil, {
		playerTab = "setup",
		sortColumn = 1,
		sortDescending = true,
	})
	T.equals(descending.playerGroups[1].players[1].name, "Player 40")
	T.equals(descending.playerGroups[1].players[40].name, "Player 01")

	local ascending = PlayerStats.Build(sortResponse, request, nil, {
		playerTab = "setup",
		sortColumn = 1,
		sortDescending = false,
	})
	T.equals(ascending.playerGroups[1].players[1].name, "Player 01")
	T.equals(ascending.playerGroups[1].players[40].name, "Player 40")

	local namesDescending = PlayerStats.Build(sortResponse, request, nil, {
		playerTab = "setup",
		sortColumn = 0,
		sortDescending = true,
	})
	T.equals(namesDescending.playerGroups[1].players[1].name, "Player 40")
	T.equals(namesDescending.playerGroups[1].players[40].name, "Player 01")
end

local function testRmlOwnsDynamicMarkup()
	local rml = T.read(root .. "gui_pve_stats.rml")
	local entrypoint = T.read(root .. "gui_pve_stats.lua")
	T.contains(rml, "data-for=\"bin : histogramBins\"")
	T.contains(rml, "data-for=\"row : diagnosticRows\"")
	T.contains(rml, "data-for=\"diff : diffRows\"")
	T.contains(rml, "data-for=\"player : group.players\"")
	T.contains(rml, "data-style-height=\"bin.populationHeight\"")
	T.contains(rml, "data-if=\"bin.hasOwn\"")
	T.notContains(entrypoint, "inner_rml")
	T.notContains(entrypoint, "playersRml")
end

testStructuredViewModel()
testDataModelRootSchemaIsStable()
testDiagnosticsUseOneNarrowEvidenceContract()
testErrorsAndFreshnessArePresentationState()
testFeatureTabsSortingAndHelpMatchPresentation()
testPlayerSortingIsStrictAndDirectional()
testRmlOwnsDynamicMarkup()

print("test_pve_stats_presenter.lua: ok")
