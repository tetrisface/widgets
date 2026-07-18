local repoRoot = (arg and arg[1]) or "./"
local Model = dofile(repoRoot .. "include/pve_stats_rml_model.lua")

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

local function assertBefore(text, left, right, message)
	local leftIndex = string.find(text, left, 1, true)
	local rightIndex = string.find(text, right, 1, true)
	assertTrue(leftIndex ~= nil, "missing left value: " .. tostring(left))
	assertTrue(rightIndex ~= nil, "missing right value: " .. tostring(right))
	assertTrue(leftIndex < rightIndex, message or (tostring(left) .. " should appear before " .. tostring(right)))
end

local function testBoundedExponentialBackoffSeconds()
	assertEquals(Model.BoundedExponentialBackoffSeconds(1, 2, 30), 2)
	assertEquals(Model.BoundedExponentialBackoffSeconds(2, 2, 30), 4)
	assertEquals(Model.BoundedExponentialBackoffSeconds(3, 2, 30), 8)
	assertEquals(Model.BoundedExponentialBackoffSeconds(4, 2, 30), 16)
	assertEquals(Model.BoundedExponentialBackoffSeconds(5, 2, 30), 30)
	assertEquals(Model.BoundedExponentialBackoffSeconds(6, 2, 30), 30)
end

local function testRetryErrorsClassifyExpectedStartupTransients()
	local timeout = "receive_failed:timeout"
	local reserved = 'http_429:{"Reason":"ReservedFunctionConcurrentInvocationLimitExceeded"}'
	assertEquals(Model.RetryErrorClass(timeout), "request_timeout")
	assertEquals(Model.RetryErrorClass(reserved), "reserved_concurrency")
	assertEquals(Model.RetryErrorClass("http_429:busy"), "rate_limited")
	assertEquals(Model.RetryErrorClass("connect_failed:refused"), nil)
	assertTrue(Model.IsExpectedStartupTransient(timeout))
	assertTrue(Model.IsExpectedStartupTransient(reserved))
	assertEquals(Model.IsExpectedStartupTransient("http_429:busy"), false)
end

local function testEstimatedLoadingProgressIsMonotonicAndWaitsBelowComplete()
	local previous = -1
	for _, elapsed in ipairs({ 0, 1, 3, 6, 10, 15, 17, 100 }) do
		local progress = Model.EstimatedLoadingProgress(elapsed, 17)
		assertTrue(progress >= previous, 'loading progress should be monotonic')
		assertTrue(progress >= 0 and progress <= 0.92, 'loading progress should remain bounded')
		previous = progress
	end
	assertEquals(Model.EstimatedLoadingProgress(0, 17), 0)
	assertTrue(Model.EstimatedLoadingProgress(17, 17) >= 0.89)
	assertTrue(Model.EstimatedLoadingProgress(100, 17) < 1)
end

local function fakeSpringWithRaptors()
	return {
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
		GetModOptions = function()
			return {
				startmetal = '2000',
				raptor_difficulty = 'normal',
			}
		end,
		GetPlayerList = function()
			return { 2, 1, 3 }
		end,
		GetMyPlayerID = function()
			return 1
		end,
		GetPlayerInfo = function(playerID)
			if playerID == 1 then
				return 'Alice', true, false, 11, nil, nil, nil, nil, nil, nil, { accountid = 101 }
			end
			if playerID == 2 then
				return 'Bob', true, false, 12, nil, nil, nil, nil, nil, nil, { accountid = 202 }
			end
			return 'Spectator', true, true, nil, nil, nil, nil, nil, nil, nil, { accountid = 303 }
		end,
		GetTeamInfo = function(teamID)
			if teamID == 11 then
				return teamID, nil, false, false, nil, nil, 1.0
			end
			if teamID == 12 then
				return teamID, nil, false, false, nil, nil, 1.25
			end
		end,
	}
end

local function testBuildRequestUsesInGameContext()
	local request = assert(Model.BuildRequest(fakeSpringWithRaptors(), { mapName = 'Supreme Isthmus' }))

	assertEquals(request.ai_type, 'Raptors')
	assertEquals(request.map, 'Supreme Isthmus')
	assertEquals(request.game_settings.startmetal, '2000')
	assertEquals(request.game_settings.raptor_difficulty, 'normal')
	assertEquals(request.player_filter_requested, true)
	assertEquals(request.player_names[1], 'Alice')
	assertEquals(request.player_names[2], 'Bob')
	assertEquals(request.player_names[3], 'Spectator')
	assertEquals(request.player_ids[1], 101)
	assertEquals(request.player_ids[2], 202)
	assertEquals(request.player_ids[3], 303)
	assertEquals(request._active_player_names[1], 'Alice')
	assertEquals(request._active_player_names[2], 'Bob')
	assertEquals(request._spectator_names[1], 'Spectator')
	assertEquals(request._spectator_ids[1], 303)
	assertEquals(request._own_player_name, 'Alice')
	assertEquals(request._own_player_id, 101)
	assertEquals(request._ai_type_source, 'spring_utilities_gametype')
	assertEquals(request.encounter_context.human_team_size, 2)
	assertEquals(request.encounter_context.enemy_ai_count, nil)
	assertEquals(request.encounter_context.human_player_income_multipliers[1], 1.25)
	assertEquals(request.encounter_context.human_player_income_multipliers[2], 1.0)
	assertTrue(request._request_key and request._request_key ~= '')
end

local function testBuildRequestUsesIterableModOptionsCopyWhenAvailable()
	local spring = fakeSpringWithRaptors()
	local backingModOptions = {
		startmetal = '3000',
		raptor_difficulty = 'hard',
	}
	local readOnlyProxy = {}
	setmetatable(readOnlyProxy, { __index = backingModOptions })

	spring.GetModOptions = function()
		return readOnlyProxy
	end
	spring.GetModOptionsCopy = function()
		return {
			startmetal = backingModOptions.startmetal,
			raptor_difficulty = backingModOptions.raptor_difficulty,
		}
	end

	local request = assert(Model.BuildRequest(spring, { mapName = 'Supreme Isthmus' }))

	assertEquals(request.game_settings.startmetal, '3000')
	assertEquals(request.game_settings.raptor_difficulty, 'hard')
end

local function testBuildRequestUsesLiveModOptionsOverStaleCopy()
	local spring = {
		Utilities = {
			Gametype = {
				IsRaptors = function()
					return false
				end,
				IsScavengers = function()
					return true
				end,
			},
		},
		GetModOptionsCopy = function()
			return {
				scav_difficulty = 'normal',
				scav_boss_count = '20',
				maxunits = '850',
			}
		end,
		GetModOptions = function()
			return {
				scav_difficulty = 'normal',
				scav_boss_count = '8',
				maxunits = '850',
			}
		end,
		GetPlayerList = function()
			return {}
		end,
	}

	local request = assert(Model.BuildRequest(spring, { mapName = 'Full Metal Plate' }))

	assertEquals(request.ai_type, 'Scavengers')
	assertEquals(request.encounter_context.enemy_ai_count, nil)
	assertEquals(request.game_settings.scav_boss_count, '8')
	assertTrue(string.find(request._request_key, 'scav_boss_count', 1, true) ~= nil)
	assertTrue(string.find(request._request_key, '1:8', 1, true) ~= nil)
end

local function testModOptionStepLookupUsesNestedDefinitions()
	local lookup = Model.ModOptionStepLookup({
		{
			key = 'multiplier_builddistance',
			step = 0.1,
		},
		{
			options = {
				{
					key = 'raptor_graceperiodmult',
					step = '0.25',
				},
			},
		},
	})

	assertEquals(lookup.multiplier_builddistance, 0.1)
	assertEquals(lookup.raptor_graceperiodmult, 0.25)
end

local function testDetectsRaptorsFromTeamLuaAiWithoutIncidentalScavengerText()
	local spring = {
		GetTeamList = function()
			return { 7 }
		end,
		GetAIInfo = function()
			return nil, nil, nil, nil, nil, {
				name = 'scavengers should not be considered ai identity',
			}
		end,
		GetTeamLuaAI = function()
			return 'RaptorsDefense AI'
		end,
		GetGameRulesParam = function()
			return nil
		end,
		GetModOptions = function()
			return {
				lootboxes = 'scav_only',
				scav_difficulty = 'epic',
				raptor_difficulty = 'normal',
			}
		end,
		GetPlayerList = function()
			return {}
		end,
	}

	local request = assert(Model.BuildRequest(spring, { mapName = 'Supreme Isthmus' }))

	assertEquals(request.ai_type, 'Raptors')
	assertEquals(request._ai_type_source, 'team_ai_identity')
	assertEquals(request.encounter_context.enemy_ai_count, nil)
end

local function testAmbiguousPveAiIdentityFailsClosed()
	local spring = {
		GetTeamList = function()
			return { 7, 8 }
		end,
		GetAIInfo = function()
			return nil
		end,
		GetTeamLuaAI = function(teamID)
			return teamID == 7 and 'RaptorsDefense AI' or 'ScavengersDefense AI'
		end,
		GetModOptions = function()
			return {}
		end,
		GetPlayerList = function()
			return {}
		end,
	}

	local request, err = Model.BuildRequest(spring, { mapName = 'Supreme Isthmus' })

	assertEquals(request, nil)
	assertEquals(err, 'ambiguous_team_ai_identity')
end

local function testDetectsBarbarianFromAiInfo()
	local spring = {
		Utilities = {
			Gametype = {
				IsRaptors = function()
					return false
				end,
				IsScavengers = function()
					return false
				end,
			},
		},
		GetTeamList = function()
			return { 7 }
		end,
		GetAIInfo = function()
			return nil, nil, nil, 'BARbarianAI'
		end,
		GetTeamInfo = function(teamID)
			return teamID, nil, false, true, nil, nil, 1.6
		end,
		GetModOptions = function()
			return {}
		end,
		GetPlayerList = function()
			return {}
		end,
	}

	local request = assert(Model.BuildRequest(spring, { mapName = 'Delta Siege' }))

	assertEquals(request.ai_type, 'Barbarian')
	assertEquals(request.player_filter_requested, true)
	assertEquals(request.encounter_context.enemy_ai_count, 1)
	assertEquals(request.encounter_context.enemy_ai_income_multipliers[1], 1.6)
end

local function testDetectsBarbarianFromGenericAiTeam()
	local spring = {
		Utilities = {
			Gametype = {
				IsRaptors = function()
					return false
				end,
				IsScavengers = function()
					return false
				end,
			},
		},
		GetTeamList = function()
			return { 7 }
		end,
		GetAIInfo = function()
			return nil
		end,
		GetTeamInfo = function()
			return nil, nil, nil, true
		end,
		GetModOptions = function()
			return {}
		end,
		GetPlayerList = function()
			return {}
		end,
	}

	local request = assert(Model.BuildRequest(spring, { mapName = 'Delta Siege' }))

	assertEquals(request.ai_type, 'Barbarian')
end

local function testDetectsBarbarianFromTeamLuaAi()
	local spring = {
		Utilities = {
			Gametype = {
				IsRaptors = function()
					return false
				end,
				IsScavengers = function()
					return false
				end,
			},
		},
		GetTeamList = function()
			return { 7 }
		end,
		GetAIInfo = function()
			return nil
		end,
		GetTeamLuaAI = function()
			return 'BARbarianAI'
		end,
		GetModOptions = function()
			return {}
		end,
		GetPlayerList = function()
			return {}
		end,
	}

	local request = assert(Model.BuildRequest(spring, { mapName = 'Delta Siege' }))

	assertEquals(request.ai_type, 'Barbarian')
end

local function testWireRequestStripsLocalFields()
	local request = assert(Model.BuildRequest(fakeSpringWithRaptors(), { mapName = 'Supreme Isthmus' }))
	local wire = Model.WireRequest(request)

	assertEquals(wire._request_key, nil)
	assertEquals(wire._active_player_names, nil)
	assertEquals(wire._spectator_names, nil)
	assertEquals(wire._own_player_name, nil)
	assertEquals(wire._own_player_id, nil)
	assertEquals(wire._ai_type_source, nil)
	assertEquals(wire.ai_type, 'Raptors')
	assertEquals(wire.map, 'Supreme Isthmus')
	assertEquals(wire.encounter_context.human_team_size, 2)
end

local function testEncounterContextParticipatesInSettingCacheIdentity()
	local left = {
		ai_type = 'Barbarian',
		map = 'Delta Siege',
		game_settings = { multiplier_resourceincome = '1' },
		encounter_context = { human_team_size = 1, enemy_ai_count = 1 },
	}
	local right = {
		ai_type = left.ai_type,
		map = left.map,
		game_settings = left.game_settings,
		encounter_context = { human_team_size = 2, enemy_ai_count = 1 },
	}

	assertTrue(Model.SettingRequestKey(left) ~= Model.SettingRequestKey(right))
end

local function testResponseUsesApiMatchStatus()
	local request = {
		ai_type = 'Raptors',
	}
	local view = Model.ViewModelFromResponse({
		match_status = 'closest',
		match_result = 'win',
		request_completeness = { total_hash_columns = 8 },
		closest_matches = {
			{
				difference_count = 1,
				match_method = 'raw_fallback',
				similarity = 0.875,
				display_diffs = {
					{ column = 'raptor_difficulty', incoming = 'epic', expected = 'hard' },
				},
			},
		},
		difficulty_estimate = {
			player_win_probability = 0.25,
			evidence_games = 120,
		},
		difficulty_histogram = {
			current_difficulty = 23.75,
			current_percentile = 76.5,
			bins = {
				{ bin_index = 11, lower_bound = 22, upper_bound = 24, games = 120, wins = 30 },
			},
		},
		players = {
			{
				player_name = '<Ace>',
				exact_wins = 3,
				harder_wins = 4,
				setup_clears = 3,
				setup_plays = 7,
			},
		},
	}, nil, request)

	assertEquals(view.modeText, 'Raptors')
	assertEquals(view.statusText, 'Ready')
	assertEquals(view.matchText, 'Raw fallback')
	assertEquals(view.isExactMatch, false)
	assertEquals(view.difficultyText, '-')
	assertEquals(view.exactWinsText, '25%')
	assertEquals(view.extendedWinsText, '120')
	assertEquals(view.evidenceGamesText, 'P76')
	assertEquals(view.winsLabelText, 'Win Chance')
	assertEquals(view.playerStatOneLabel, 'Setup Clears v')
	assertTrue(string.find(view.matchHelpText, 'does not determine whether either setup is harder', 1, true) ~= nil)
	assertTrue(string.find(view.evidenceSummaryRml, 'raw lobby fallback', 1, true) ~= nil)
	assertTrue(string.find(view.evidenceSummaryRml, 'difficulty', 1, true) == nil)
	assertEquals(view.hasDiffs, true)
	assertTrue(string.find(view.diffsRml, 'raptor_difficulty', 1, true) ~= nil)
	assertTrue(string.find(view.diffsRml, 'Current -> Similar', 1, true) == nil)
	assertTrue(string.find(view.diffsRml, 'Field</span><span class="pve-stats-diff-current">Current</span><span class="pve-stats-diff-closest">Fallback', 1, true) ~= nil)
	assertTrue(string.find(view.diffsRml, 'pve-stats-diff-current', 1, true) ~= nil)
	assertBefore(view.diffsRml, 'epic', 'hard')
	assertTrue(string.find(view.playersRml, '&lt;Ace&gt;', 1, true) ~= nil)
	assertTrue(string.find(view.playersRml, '<span class="pve-stats-player-stat">3</span><span class="pve-stats-player-stat">7</span>', 1, true) ~= nil)
	assertTrue(string.find(view.playersRml, 'player-rating', 1, true) == nil)

	local exactView = Model.ViewModelFromResponse({
		found = true,
		match_status = 'exact',
		setting = {
			difficulty_rating = 12,
		},
	}, nil, request)
	assertEquals(exactView.matchText, 'Exact')
	assertEquals(exactView.isExactMatch, true)
	assertEquals(exactView.winsLabelText, 'Win Chance')
	assertEquals(exactView.hasDiffs, false)

	local notFoundView = Model.ViewModelFromResponse({
		found = false,
		match_status = 'not_found',
	}, nil, request)
	assertEquals(notFoundView.matchText, 'Not found')
	assertEquals(notFoundView.isExactMatch, false)
end

local function testDefaultPlayerTabPrefersAwardsUnlessMatchIsExact()
	assertEquals(Model.DefaultPlayerTab(nil), 'awards')
	assertEquals(Model.DefaultPlayerTab({ found = false, match_status = 'closest' }), 'awards')
	assertEquals(Model.DefaultPlayerTab({ found = false, match_status = 'not_found' }), 'awards')
	assertEquals(Model.DefaultPlayerTab({ found = true, match_status = 'exact' }), 'setup')
end

local function testClientVersionNoticeIsInformational()
	local request = {
		ai_type = 'Raptors',
	}
	local function viewForVersion(clientVersion)
		return Model.ViewModelFromResponse({
			found = true,
			match_status = 'exact',
			client_version = clientVersion,
			setting = {
				exact_wins = 12,
				extended_wins = 14,
				unique_players = 3,
				difficulty_rating = 18.25,
			},
			players = {},
		}, nil, request)
	end

	local missing = viewForVersion(nil)
	assertEquals(missing.statusText, 'Ready')
	assertEquals(missing.hasNotice, false)
	assertEquals(missing.noticeText, '')
	assertEquals(missing.exactWinsText, '-')

	local same = viewForVersion(Model.CLIENT_VERSION)
	assertEquals(same.statusText, 'Ready')
	assertEquals(same.hasNotice, false)

	local older = viewForVersion(Model.CLIENT_VERSION - 1)
	assertEquals(older.statusText, 'Ready')
	assertEquals(older.hasNotice, false)

	local newer = viewForVersion(Model.CLIENT_VERSION + 1)
	assertEquals(newer.statusText, 'Update')
	assertEquals(newer.hasNotice, true)
	assertEquals(newer.hasError, false)
	assertTrue(string.find(newer.noticeText, 'Widget update available', 1, true) ~= nil)
	assertTrue(string.find(newer.noticeText, 'v' .. tostring(Model.CLIENT_VERSION + 1), 1, true) ~= nil)
	assertEquals(newer.exactWinsText, '-')
	assertEquals(newer.difficultyText, '-')
end

local function testSourceWindowMetadataIsDisplayedWhenPresent()
	local request = {
		ai_type = 'Raptors',
	}
	local view = Model.ViewModelFromResponse({
		found = true,
		match_status = 'exact',
		source_window = {
			earliest_replay_time = '2024-03-10T22:53:40Z',
			latest_replay_time = '2026-06-20T22:46:17Z',
			latest_replay_age_days = 4,
			display = '2024-03-10 - 4 days ago',
		},
		setting = {
			difficulty_rating = 10,
		},
	}, nil, request)

	assertEquals(view.sourceWindowText, '2024-03-10 - 4 days ago')
	assertEquals(view.hasSourceWindow, true)

	local fallback = Model.ViewModelFromResponse({
		found = true,
		match_status = 'exact',
		source_window = {
			earliest_replay_time = '2024-03-10T22:53:40Z',
			latest_replay_age_days = 1,
		},
		setting = {
			difficulty_rating = 10,
		},
	}, nil, request)
	assertEquals(fallback.sourceWindowText, '2024-03-10 - 1 day ago')

	local hours = Model.ViewModelFromResponse({
		found = true,
		match_status = 'exact',
		source_window = {
			earliest_replay_time = '2024-03-10T22:53:40Z',
			latest_replay_age_seconds = 47 * 60 * 60,
			latest_replay_age_days = 2,
			display = '2024-03-10 - 2 days ago',
		},
		setting = {
			difficulty_rating = 10,
		},
	}, nil, request)
	assertEquals(hours.sourceWindowText, '2024-03-10 - 1 day 23 hours ago')

	local daysAndHours = Model.ViewModelFromResponse({
		found = true,
		match_status = 'exact',
		source_window = {
			earliest_replay_time = '2024-03-10T22:53:40Z',
			latest_replay_age_seconds = (12 * 24 * 60 * 60) + (4 * 60 * 60) + (22 * 60),
		},
		setting = {
			difficulty_rating = 10,
		},
	}, nil, request)
	assertEquals(daysAndHours.sourceWindowText, '2024-03-10 - 12 days 4 hours ago')

	local hoursAndMinutes = Model.ViewModelFromResponse({
		found = true,
		match_status = 'exact',
		source_window = {
			earliest_replay_time = '2024-03-10T22:53:40Z',
			latest_replay_age_seconds = (22 * 60 * 60) + (4 * 60),
		},
		setting = {
			difficulty_rating = 10,
		},
	}, nil, request)
	assertEquals(hoursAndMinutes.sourceWindowText, '2024-03-10 - 22 hours 4 minutes ago')

	local localTick = Model.ViewModelFromResponse(
		{
			found = true,
			match_status = 'exact',
			source_window = {
				earliest_replay_time = '2024-03-10T22:53:40Z',
				latest_replay_age_seconds = (22 * 60 * 60) + (4 * 60) + 30,
			},
			setting = {
				difficulty_rating = 10,
			},
		},
		nil,
		request,
		nil,
		{
			sourceWindowAgeOffsetSeconds = 60,
		}
	)
	assertEquals(localTick.sourceWindowText, '2024-03-10 - 22 hours 5 minutes ago')

	local missing = Model.ViewModelFromResponse({
		found = true,
		match_status = 'exact',
		setting = {
			difficulty_rating = 10,
		},
	}, nil, request)
	assertEquals(missing.sourceWindowText, '-')
	assertEquals(missing.hasSourceWindow, false)
end

local function testSourceWindowFreshnessUsesWallClockTimestamp()
	local request = {
		ai_type = 'Raptors',
	}
	local response = {
		found = true,
		match_status = 'exact',
		source_window = {
			earliest_replay_time = '1970-01-01T00:00:00Z',
			latest_replay_time = '1970-01-01T00:00:00Z',
			latest_replay_age_seconds = 30,
		},
		setting = {
			difficulty_rating = 10,
		},
	}

	local view = Model.ViewModelFromResponse(response, nil, request, nil, {
		sourceWindowNowSeconds = 5 * 60,
	})

	assertEquals(view.sourceWindowText, '1970-01-01 - 5 minutes ago')
	assertEquals(Model.SourceWindowAgeMinute(response, { sourceWindowNowSeconds = 5 * 60 }), 5)
end

local function testClosestDiffsCanExpandHiddenVisibleRows()
	local request = {
		ai_type = 'Raptors',
	}
	local response = {
		found = false,
		match_status = 'closest',
		closest_matches = {
			{
				display_diffs = {
					{ column = 'Map', incoming = 'A', expected = 'B' },
					{ column = 'raptor_difficulty', incoming = 'epic', expected = 'hard' },
					{ column = 'startmetal', incoming = '1000', expected = '2000' },
					{ column = 'multiplier_buildpower', incoming = '1.7', expected = '1.5' },
					{ column = 'ruins', incoming = 'disabled', expected = 'enabled' },
					{ column = 'lootboxes', incoming = 'disabled', expected = 'enabled' },
					{ column = 'commanderbuildersenabled', incoming = 'disabled', expected = 'true' },
					{ column = 'assistdronesenabled', incoming = 'enabled', expected = 'false' },
					{ column = 'tweakdefs', incoming = 'opaque', expected = 'other' },
					{ column = 'startenergy', incoming = '1000', expected = '1000' },
				},
			},
		},
		setting = {
			difficulty_rating = 23.75,
		},
	}

	local collapsed = Model.ViewModelFromResponse(response, nil, request)
	assertEquals(collapsed.hasDiffs, true)
	assertTrue(string.find(collapsed.diffsRml, 'Similar match differs by 8 shown fields', 1, true) ~= nil)
	assertTrue(string.find(collapsed.diffsRml, '+2 more', 1, true) ~= nil)
	assertTrue(string.find(collapsed.diffsRml, 'widget:ToggleDiffs(event)', 1, true) ~= nil)
	assertTrue(string.find(collapsed.diffsRml, 'commanderbuildersenabled', 1, true) == nil)
	assertTrue(string.find(collapsed.diffsRml, 'assistdronesenabled', 1, true) == nil)
	assertTrue(string.find(collapsed.diffsRml, 'tweakdefs', 1, true) == nil)
	assertTrue(string.find(collapsed.diffsRml, 'startenergy', 1, true) == nil)

	local expanded = Model.ViewModelFromResponse(response, nil, request, nil, { diffExpanded = true })
	assertTrue(string.find(expanded.diffsRml, 'Show fewer', 1, true) ~= nil)
	assertTrue(string.find(expanded.diffsRml, 'commanderbuildersenabled', 1, true) ~= nil)
	assertTrue(string.find(expanded.diffsRml, 'assistdronesenabled', 1, true) ~= nil)
	assertTrue(string.find(expanded.diffsRml, 'tweakdefs', 1, true) == nil)
	assertTrue(string.find(expanded.diffsRml, 'startenergy', 1, true) == nil)
end

local function testDifficultyEvidenceAndHiddenDiffDiagnostics()
	local population = Model.ViewModelFromResponse({
		found = true,
		match_status = 'exact',
		setting_hash = 'population-setting-hash',
		setting = { difficulty_rating = 25.5, evidence_games = 4 },
		difficulty_estimate = {
			difficulty_target_sha256 = 'e356de8d118e02151773e4ba211606114d8d90de18616342e582124a44367ccb',
			player_win_probability = 0.25,
			evidence_games = 37,
		},
	}, nil, { ai_type = 'Raptors' }, nil, {
		diagnosticsExpanded = true,
		transportEvidence = {
			http_status = 200,
			attempt = 2,
			request_duration_ms = 19118,
			loading_elapsed_ms = 21245,
			loading_expected_seconds = 19,
			request_bytes = 5426,
			response_bytes = 11850,
			trace_id = '0123456789abcdef0123456789abcdef',
			request_hash = 'f3c34000',
		},
	})

	assertEquals(population.evidenceGamesLabel, 'Difficulty Percentile')
	assertEquals(population.extendedWinsText, '37')
	assertEquals(population.evidenceGamesText, 'Unplaced')
	assertTrue(string.find(population.winChanceHelpText, 'not the identities or skill ratings', 1, true) ~= nil)
	assertTrue(string.find(population.difficultyPercentileHelpText, 'eligible played Raptors', 1, true) ~= nil)
	assertTrue(string.find(population.trainingGamesHelpText, '37 eligible Raptors games', 1, true) ~= nil)
	assertTrue(string.find(population.matchHelpText, 'separate from Win Chance', 1, true) ~= nil)
	assertTrue(string.find(population.evidenceSummaryRml, 'Match: exact setting', 1, true) ~= nil)
	assertEquals(population.diagnosticsExpanded, true)
	assertTrue(string.find(population.diagnosticsRml, 'e356de8d', 1, true) ~= nil)
	assertTrue(string.find(population.diagnosticsRml, '19.118 s', 1, true) ~= nil)
	assertTrue(string.find(population.diagnosticsRml, '21.245 s (19 s expected)', 1, true) ~= nil)
	assertTrue(string.find(population.diagnosticsRml, 'request 5.3 KiB; response 11.6 KiB', 1, true) ~= nil)
	assertTrue(string.find(population.diagnosticsRml, 'trace 0123456789abcdef0123456789abcdef', 1, true) ~= nil)
	assertTrue(string.find(population.diagnosticsRml, 'request f3c34000', 1, true) ~= nil)

	local fallback = Model.ViewModelFromResponse({
		match_status = 'closest',
		setting_hash = 'query-setting-hash',
		request_completeness = { total_hash_columns = 54, provided_hash_columns = 54, defaulted_hash_columns = 0, missing_hash_columns = 0 },
		closest_matches = {
			{
				setting_hash = 'fallback-setting-hash',
				match_method = 'raw_fallback',
				similarity = 0.963,
				difference_count = 2,
				hidden_diff_summary = { total = 2 },
			},
		},
	}, nil, { ai_type = 'Raptors' })

	assertEquals(fallback.matchText, 'Raw fallback')
	assertEquals(fallback.evidenceGamesLabel, 'Difficulty Percentile')
	assertEquals(fallback.evidenceGamesText, 'Unplaced')
	assertTrue(string.find(fallback.evidenceSummaryRml, '2 additional field differences hidden', 1, true) ~= nil)
	assertEquals(fallback.hasDiffs, true)
	assertTrue(string.find(fallback.diffsRml, 'No displayable lobby fields differ', 1, true) ~= nil)
	assertTrue(string.find(fallback.diagnosticsRml, '96.3% (52/54 compared)', 1, true) ~= nil)
	assertTrue(string.find(fallback.diagnosticsText, 'PvE Stats diagnostics', 1, true) ~= nil)
end

local function testCurrentGameIdRenders()
	local view = Model.ViewModelFromResponse(
		{
			found = true,
			match_status = 'exact',
			setting_hash = 'abcdef1234567890abcdef1234567890',
			setting = { difficulty_rating = 10 },
		},
		nil,
		{ ai_type = 'Raptors' },
		nil,
		{
			currentGameId = '1234567890abcdef1234567890abcdef',
		}
	)

	assertEquals(view.hasDiffs, false)
	assertTrue(string.find(view.diagnosticsRml, 'query abcdef123456', 1, true) ~= nil)
	assertTrue(string.find(view.diagnosticsRml, 'game 1234567890abcdef1234567890abcdef', 1, true) ~= nil)
end

local function testUnresolvedRequestedPlayersRemainVisible()
	local request = {
		ai_type = 'Scavengers',
		_active_player_names = { 'Known', 'Darth_raider' },
		_spectator_names = { 'UnknownSpec' },
	}
	local view = Model.ViewModelFromResponse({
		found = true,
		match_status = 'exact',
		setting = { difficulty_rating = 10 },
		players = {
			{ player_id = 7, player_name = 'Known', exact_wins = 2, harder_wins = 3 },
		},
		unresolved_player_names = { 'Darth_raider', 'UnknownSpec', 'Known' },
	}, nil, request, nil, { showSpectators = true, sortColumn = 0, sortDescending = false })

	assertTrue(string.find(view.playersRml, 'Darth_raider', 1, true) ~= nil)
	assertTrue(string.find(view.playersRml, 'UnknownSpec', 1, true) ~= nil)
	assertEquals(select(2, string.gsub(view.playersRml, 'Known', '')), 1)
	assertEquals(view.hasPlayers, true)
end

local function testFailedRequestKeepsTransportDiagnosticsAvailable()
	local view = Model.ViewModelFromResponse(nil, 'http_503:unavailable', nil, nil, {
		diagnosticsExpanded = true,
		transportEvidence = {
			http_status = 503,
			attempt = 3,
			request_duration_ms = 3000,
			loading_elapsed_ms = 17450,
			loading_expected_seconds = 19,
			request_bytes = 5426,
			response_bytes = 96,
			trace_id = 'fedcba9876543210fedcba9876543210',
			request_hash = 'deadbeef',
			retry_class = 'server_busy',
		},
	})

	assertEquals(view.hasError, true)
	assertEquals(view.hasDiagnostics, true)
	assertEquals(view.diagnosticsExpanded, true)
	assertTrue(string.find(view.diagnosticsRml, '503; attempt 3; server_busy', 1, true) ~= nil)
	assertTrue(string.find(view.diagnosticsRml, '3 s', 1, true) ~= nil)
	assertTrue(string.find(view.diagnosticsRml, '17.45 s (19 s expected)', 1, true) ~= nil)
	assertTrue(string.find(view.diagnosticsRml, 'trace fedcba9876543210fedcba9876543210', 1, true) ~= nil)
end

local function testClosestDiffsRoundFloatNoiseToModOptionSteps()
	local request = {
		ai_type = 'Raptors',
	}
	local response = {
		found = false,
		match_status = 'closest',
		closest_matches = {
			{
				display_diffs = {
					{ column = 'multiplier_builddistance', incoming = '1.70000005', expected = '1.5' },
					{ column = 'multiplier_buildpower', incoming = '1.39999998', expected = '1.29999995' },
					{ column = 'multiplier_same', incoming = '1.70000005', expected = '1.7' },
				},
			},
		},
	}
	local view = Model.ViewModelFromResponse(response, nil, request, nil, {
		modOptionSteps = {
			multiplier_builddistance = 0.1,
			multiplier_buildpower = 0.1,
			multiplier_same = 0.1,
		},
	})

	assertEquals(view.hasDiffs, true)
	assertTrue(string.find(view.diffsRml, 'Similar match differs by 2 shown fields', 1, true) ~= nil)
	assertTrue(string.find(view.diffsRml, '1.70000005', 1, true) == nil)
	assertTrue(string.find(view.diffsRml, '1.39999998', 1, true) == nil)
	assertTrue(string.find(view.diffsRml, '1.29999995', 1, true) == nil)
	assertTrue(string.find(view.diffsRml, 'multiplier_same', 1, true) == nil)
	assertBefore(view.diffsRml, '1.7', '1.5')
	assertBefore(view.diffsRml, '1.4', '1.3')
end

local function testClosestDiffsCleanFloatNoiseWithoutStepMetadata()
	local request = {
		ai_type = 'Raptors',
	}
	local view = Model.ViewModelFromResponse({
		found = false,
		match_status = 'closest',
		closest_matches = {
			{
				display_diffs = {
					{ column = 'multiplier_resourceincome', incoming = '1.89999998', expected = '1.5' },
				},
			},
		},
	}, nil, request)

	assertEquals(view.hasDiffs, true)
	assertTrue(string.find(view.diffsRml, '1.89999998', 1, true) == nil)
	assertBefore(view.diffsRml, '1.9', '1.5')
end

local function testPlayerRowsUseColorLookup()
	local rows = Model.PlayerRowsRml({
		{
			player_name = 'Alice',
			exact_wins = 1,
			harder_wins = 2,
			setup_clears = 1,
			setup_plays = 3,
		},
	}, {
		Alice = '#12ABEF',
	})

	assertTrue(string.find(rows, 'background-color: #12ABEF', 1, true) ~= nil)
	assertTrue(string.find(rows, '<span class="pve-stats-player-stat">1</span><span class="pve-stats-player-stat">3</span>', 1, true) ~= nil)
end

local function testPlayerRowsAlwaysRenderColorFallback()
	local rows = Model.PlayerRowsRml({
		{
			exact_wins = 1,
			harder_wins = 2,
		},
	}, {
		[''] = 'not-a-color',
	})

	assertTrue(string.find(rows, 'background-color: #', 1, true) ~= nil)
	assertTrue(string.find(rows, 'Unknown', 1, true) ~= nil)
end

local function testPlayerRowsCanHideColorAccent()
	local rows = Model.PlayerRowsRml({
		{
			player_name = 'Alice',
			exact_wins = 1,
			harder_wins = 2,
		},
	}, {
		Alice = '#12ABEF',
	}, {
		showColors = false,
	})

	assertTrue(string.find(rows, 'pve-stats-player-accent-empty', 1, true) ~= nil)
	assertTrue(string.find(rows, '#12ABEF', 1, true) == nil)
	assertTrue(string.find(rows, 'Alice', 1, true) ~= nil)
end

local function testSpectatorsRenderAsSeparateGroupWhenEnabled()
	local request = {
		ai_type = 'Raptors',
		_active_player_names = { 'Alice' },
		_spectator_names = { 'SpecBob' },
	}
	local view = Model.ViewModelFromResponse(
		{
			found = true,
			match_status = 'exact',
			setting = {
				difficulty_rating = 10,
			},
			players = {
				{
					player_name = 'Alice',
					exact_wins = 1,
					harder_wins = 2,
				},
				{
					player_name = 'SpecBob',
					exact_wins = 4,
					harder_wins = 5,
				},
			},
		},
		nil,
		request,
		{
			Alice = '#12ABEF',
			SpecBob = '#ABCDEF',
		},
		{ showSpectators = true }
	)

	assertTrue(string.find(view.playersRml, 'Players', 1, true) ~= nil)
	assertTrue(string.find(view.playersRml, 'Spectators', 1, true) ~= nil)
	assertTrue(string.find(view.playersRml, 'SpecBob', 1, true) ~= nil)
	assertTrue(string.find(view.playersRml, '#12ABEF', 1, true) ~= nil)
	assertTrue(string.find(view.playersRml, '#ABCDEF', 1, true) == nil)
	assertTrue(string.find(view.playersRml, 'pve-stats-player-accent-empty', 1, true) ~= nil)
end

local function testPlayersAndSpectatorsSortByNameWithoutCompetitiveTieBreakers()
	local request = {
		ai_type = 'Raptors',
		_active_player_names = { 'Aaron', 'Alice', 'Bob', 'Clara', 'Delta' },
		_spectator_names = { 'SpecA', 'SpecHigh', 'SpecZ' },
	}
	local view = Model.ViewModelFromResponse({
		found = true,
		match_status = 'closest',
		setting = {
			difficulty_rating = 10,
		},
		players = {
			{
				player_name = 'Delta',
				exact_wins = 99,
				harder_wins = 4,
			},
			{
				player_name = 'Bob',
				exact_wins = 10,
				harder_wins = 5,
			},
			{
				player_name = 'SpecZ',
				exact_wins = 1,
				harder_wins = 1,
			},
			{
				player_name = 'Alice',
				exact_wins = 10,
				harder_wins = 5,
			},
			{
				player_name = 'SpecHigh',
				exact_wins = 0,
				harder_wins = 2,
			},
			{
				player_name = 'Clara',
				exact_wins = 8,
				harder_wins = 5,
			},
			{
				player_name = 'Aaron',
				exact_wins = 10,
				harder_wins = 5,
			},
			{
				player_name = 'SpecA',
				exact_wins = 1,
				harder_wins = 1,
			},
		},
	}, nil, request, nil, { showSpectators = true, sortColumn = 0, sortDescending = false })

	assertBefore(view.playersRml, 'Aaron', 'Alice')
	assertBefore(view.playersRml, 'Alice', 'Bob')
	assertBefore(view.playersRml, 'Bob', 'Clara')
	assertBefore(view.playersRml, 'Clara', 'Delta')
	assertBefore(view.playersRml, 'SpecA', 'SpecZ')
	assertBefore(view.playersRml, 'SpecHigh', 'SpecZ')
end

local function testPlayerSortingUsesTabStatsAndKeepsMissingValuesLast()
	local request = {
		ai_type = 'Scavengers',
		_active_player_names = { 'Alpha', 'Bravo', 'Missing' },
	}
	local response = {
		found = true,
		match_status = 'closest',
		setting = { difficulty_rating = 10 },
		players = {
			{ player_id = 1, player_name = 'Alpha', awards = { most_killed = { scavengers = 2 } } },
			{ player_id = 2, player_name = 'Bravo', awards = { most_killed = { scavengers = 9 } } },
			{ player_id = 3, player_name = 'Missing' },
		},
	}

	assertEquals(Model.DefaultPlayerSortColumn('awards', request), 2)
	assertEquals(Model.DefaultPlayerSortColumn('encounters', request), 2)
	assertEquals(Model.DefaultPlayerSortColumn('adventures', request), 2)
	assertEquals(Model.DefaultPlayerSortColumn('milestones', request), 1)
	assertEquals(Model.DefaultPlayerSortColumn('setup', request), 1)

	local descending = Model.ViewModelFromResponse(response, nil, request, nil, {
		playerTab = 'awards',
		sortColumn = 2,
		sortDescending = true,
	})
	assertBefore(descending.playersRml, 'Bravo', 'Alpha')
	assertBefore(descending.playersRml, 'Alpha', 'Missing')
	assertEquals(descending.playerStatTwoLabel, 'Scav Most Killed v')

	local ascending = Model.ViewModelFromResponse(response, nil, request, nil, {
		playerTab = 'awards',
		sortColumn = 2,
		sortDescending = false,
	})
	assertBefore(ascending.playersRml, 'Alpha', 'Bravo')
	assertBefore(ascending.playersRml, 'Bravo', 'Missing')
	assertEquals(ascending.playerStatTwoLabel, 'Scav Most Killed ^')
end

local function testOwnPlayerRowIsHighlightedByIdAndNameFallback()
	local byID = Model.PlayerRowsRml({
		{ player_id = 7, player_name = 'Renamed', exact_wins = 0, harder_wins = 0 },
	}, nil, { playerTab = 'setup', ownPlayerId = 7, ownPlayerName = 'OldName' })
	assertTrue(string.find(byID, 'pve-stats-player-row own-player', 1, true) ~= nil)

	local byName = Model.PlayerRowsRml({
		{ player_id = 0, player_name = 'LocalSpec', exact_wins = 0, harder_wins = 0 },
	}, nil, { playerTab = 'setup', ownPlayerName = 'localspec' })
	assertTrue(string.find(byName, 'pve-stats-player-row own-player', 1, true) ~= nil)
end

local function testOwnSpectatorAndUnresolvedPlaceholderAreHighlighted()
	local request = {
		ai_type = 'Raptors',
		_spectator_names = { 'LocalSpec' },
		_own_player_name = 'localspec',
	}
	local response = {
		found = false,
		match_status = 'not_found',
		players = {},
		unresolved_player_names = { 'LocalSpec' },
	}
	local view = Model.ViewModelFromResponse(response, nil, request, nil, {
		playerTab = 'awards',
		showSpectators = true,
	})

	assertTrue(string.find(view.playersRml, 'Spectators', 1, true) ~= nil)
	assertTrue(string.find(view.playersRml, 'LocalSpec', 1, true) ~= nil)
	assertTrue(string.find(view.playersRml, 'pve-stats-player-row own-player', 1, true) ~= nil)
end

local function testAccomplishmentTabsRenderPerpendicularProgress()
	local player = {
		player_name = 'Explorer',
		exact_wins = 3,
		harder_wins = 2,
		accomplishments = {
			participation = {
				games_played = 42,
				victories = 17,
				victory_time_ms = 19800000,
				distinct_maps_played = 12,
				distinct_maps_won = 9,
			},
			encounters = {
				raptor_queens_defeated = 8,
				scavenger_bosses_defeated = 6,
				barbarian_ais_defeated = 11,
			},
			personal_bests = {},
			difficulty_victories = {
				hard_victories = 4,
				veryhard_victories = 3,
				epic_victories = 2,
			},
			challenges = {
				challenge_20_clears = 12,
				challenge_25_clears = 5,
				challenge_30_clears = 2,
			},
		},
		awards = {
			most_killed = {
				raptors = 7,
				scavengers = 5,
				barbarians = 3,
			},
		},
	}
	local baseResponse = {
		found = true,
		match_status = 'exact',
		setting = { difficulty_rating = 10 },
		players = { player },
	}
	local request = { ai_type = 'Raptors' }

	local adventures = Model.ViewModelFromResponse(baseResponse, nil, request, nil, { playerTab = 'adventures' })
	assertEquals(adventures.playerStatOneLabel, 'Games')
	assertEquals(adventures.playerStatTwoLabel, 'Victories v')
	assertEquals(adventures.playerStatThreeLabel, 'Maps')
	assertTrue(string.find(adventures.playersRml, '>42</span>', 1, true) ~= nil)
	assertTrue(string.find(adventures.playersRml, '>17</span>', 1, true) ~= nil)

	local encounters = Model.ViewModelFromResponse(baseResponse, nil, request, nil, { playerTab = 'encounters' })
	assertEquals(encounters.playerStatOneLabel, 'Queens Killed v')
	assertEquals(encounters.playerStatTwoLabel, 'Bosses Killed')
	assertEquals(encounters.playerStatThreeLabel, 'BARbarians Killed')
	assertTrue(string.find(encounters.playersRml, '>8</span>', 1, true) ~= nil)
	assertTrue(string.find(encounters.playersRml, '>11</span>', 1, true) ~= nil)

	local milestones = Model.ViewModelFromResponse(baseResponse, nil, request, nil, { playerTab = 'milestones' })
	assertEquals(milestones.playerStatOneLabel, '20+ Clears v')
	assertEquals(milestones.playerStatThreeLabel, '30+ Clears')
	assertTrue(string.find(Model.PlayerStatHelpText('milestones', 2), '26.5%', 1, true) ~= nil)
	assertTrue(string.find(milestones.playersRml, '>12</span>', 1, true) ~= nil)
	assertTrue(string.find(milestones.playersRml, '>2</span>', 1, true) ~= nil)

	local awards = Model.ViewModelFromResponse(baseResponse, nil, request, nil, {playerTab = "awards"})
	assertEquals(awards.playerStatOneLabel, "Raptor Most Killed v")
	assertEquals(awards.playerStatTwoLabel, "Scav Most Killed")
	assertEquals(awards.playerStatThreeLabel, "BARb Most Killed")
	assertTrue(string.find(Model.PlayerStatHelpText("awards", 1), "fighting-unit value destroyed", 1, true) ~= nil)
	assertTrue(string.find(awards.playersRml, ">7</span>", 1, true) ~= nil)
	assertTrue(string.find(awards.playersRml, ">3</span>", 1, true) ~= nil)
end

local function testHistogramComparesPopulationAndPersonalSharesOnOneScale()
	local response = {
		found = true,
		match_status = 'exact',
		difficulty_histogram = {
			current_status = 'placed',
			current_difficulty = 1.5,
			current_percentile = 25,
			total_games = 100,
			bins = {
				{ bin_index = 0, lower_bound = 0, upper_bound = 2, games = 25, wins = 20 },
				{ bin_index = 1, lower_bound = 2, upper_bound = 4, games = 75, wins = 30 },
			},
		},
		players = {
			{
				player_id = 42,
				player_name = 'Explorer',
				accomplishments = {
					challenges = {
						clear_histogram = { 8, 2 },
						highest_challenge_cleared = 3.5,
					},
				},
			},
		},
	}
	local request = { ai_type = 'Raptors', _own_player_id = 42 }
	local view = Model.ViewModelFromResponse(response, nil, request, nil, { playerTab = 'milestones' })

	assertTrue(string.find(view.histogramRml, 'data-bin-index="1"', 1, true) ~= nil)
	assertTrue(string.find(view.histogramRml, 'ShowHistogramBinHelp', 1, true) ~= nil)
	assertTrue(string.find(view.histogramRml, 'Played games', 1, true) ~= nil)
	assertTrue(string.find(view.histogramRml, 'Your clears', 1, true) ~= nil)
	assertTrue(string.find(view.histogramRml, 'common % scale', 1, true) ~= nil)
	assertTrue(string.find(view.histogramRml, 'left: 58.824%\">20</span>', 1, true) ~= nil)
	assertTrue(string.find(view.histogramRml, 'left: 73.529%\">25</span>', 1, true) ~= nil)
	assertTrue(string.find(view.histogramRml, 'left: 88.235%\">30</span>', 1, true) ~= nil)
	assertTrue(string.find(view.histogramRml, '>25+</span>', 1, true) == nil)
	assertTrue(string.find(view.histogramRml, 'pve-stats-histogram-population" style="height: 31%', 1, true) ~= nil)
	assertTrue(string.find(view.histogramRml, 'pve-stats-histogram-own" style="height: 100%', 1, true) ~= nil)

	local firstHelp = Model.HistogramBinHelpText(response, request, 1)
	assertTrue(string.find(firstHelp, '25 eligible games (25.0% of played games)', 1, true) ~= nil)
	assertTrue(string.find(firstHelp, '20 human wins (80.0%)', 1, true) ~= nil)
	assertTrue(string.find(firstHelp, 'Your clears: 8 of 10 (80.0%)', 1, true) ~= nil)
	assertTrue(string.find(firstHelp, 'current setup is here at 1.5', 1, true) ~= nil)
	assertTrue(string.find(firstHelp, 'cyan above dark means your clears are more concentrated here', 1, true) ~= nil)

	local generalHelp = Model.HistogramHelpText(response, request)
	assertTrue(string.find(generalHelp, '100 eligible games', 1, true) ~= nil)
	assertTrue(string.find(generalHelp, '10 eligible clears', 1, true) ~= nil)
	assertTrue(string.find(generalHelp, 'Both use one percentage scale', 1, true) ~= nil)
	assertTrue(string.find(generalHelp, 'Each bar covers a score range', 1, true) ~= nil)
	assertTrue(string.find(generalHelp, 'exact 20+/25+/30+ cutoffs', 1, true) ~= nil)
	assertTrue(string.find(generalHelp, 'larger share of your clears', 1, true) ~= nil)
end

local function testHistogramExplainsBucketCrossingExactMilestone()
	local response = {
		difficulty_histogram = {
			total_games = 1,
			bins = {
				{ bin_index = 12, lower_bound = 24, upper_bound = 26, games = 1, wins = 1 },
			},
		},
		players = {
			{
				player_id = 42,
				player_name = 'Explorer',
				accomplishments = {
					challenges = {
						clear_histogram = { 1 },
						challenge_25_clears = 0,
						highest_challenge_cleared = 24.8,
					},
				},
			},
		},
	}
	local request = { ai_type = 'Raptors', _own_player_id = 42 }

	local help = Model.HistogramBinHelpText(response, request, 1)

	assertTrue(string.find(help, 'Challenge 24-26', 1, true) ~= nil)
	assertTrue(string.find(help, 'This bucket crosses 25; your exact 25+ Clears total is 0.', 1, true) ~= nil)
end

testBoundedExponentialBackoffSeconds()
testRetryErrorsClassifyExpectedStartupTransients()
testEstimatedLoadingProgressIsMonotonicAndWaitsBelowComplete()
testBuildRequestUsesInGameContext()
testBuildRequestUsesIterableModOptionsCopyWhenAvailable()
testBuildRequestUsesLiveModOptionsOverStaleCopy()
testModOptionStepLookupUsesNestedDefinitions()
testDetectsRaptorsFromTeamLuaAiWithoutIncidentalScavengerText()
testAmbiguousPveAiIdentityFailsClosed()
testDetectsBarbarianFromAiInfo()
testDetectsBarbarianFromGenericAiTeam()
testDetectsBarbarianFromTeamLuaAi()
testWireRequestStripsLocalFields()
testEncounterContextParticipatesInSettingCacheIdentity()
testResponseUsesApiMatchStatus()
testDefaultPlayerTabPrefersAwardsUnlessMatchIsExact()
testClientVersionNoticeIsInformational()
testSourceWindowMetadataIsDisplayedWhenPresent()
testSourceWindowFreshnessUsesWallClockTimestamp()
testClosestDiffsCanExpandHiddenVisibleRows()
testDifficultyEvidenceAndHiddenDiffDiagnostics()
testCurrentGameIdRenders()
testUnresolvedRequestedPlayersRemainVisible()
testFailedRequestKeepsTransportDiagnosticsAvailable()
testClosestDiffsRoundFloatNoiseToModOptionSteps()
testClosestDiffsCleanFloatNoiseWithoutStepMetadata()
testPlayerRowsUseColorLookup()
testPlayerRowsAlwaysRenderColorFallback()
testPlayerRowsCanHideColorAccent()
testSpectatorsRenderAsSeparateGroupWhenEnabled()
testPlayersAndSpectatorsSortByNameWithoutCompetitiveTieBreakers()
testPlayerSortingUsesTabStatsAndKeepsMissingValuesLast()
testOwnPlayerRowIsHighlightedByIdAndNameFallback()
testOwnSpectatorAndUnresolvedPlaceholderAreHighlighted()
testAccomplishmentTabsRenderPerpendicularProgress()
testHistogramComparesPopulationAndPersonalSharesOnOneScale()
testHistogramExplainsBucketCrossingExactMilestone()

print("test_pve_stats_rml_model.lua: ok")
