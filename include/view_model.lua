local ViewModelFactory = {}

local CLIENT_VERSION = 9

local function Merge(target, source)
	for key, value in pairs(source or {}) do target[key] = value end
	return target
end

function ViewModelFactory.New(Display, PlayerStats, Histogram, Diagnostics)
	local ViewModel = {CLIENT_VERSION = CLIENT_VERSION}

	local function SourceWindowAgeSeconds(sourceWindow, options)
		local nowSeconds = tonumber(options and options.sourceWindowNowSeconds)
		local latestSeconds = Display.ParseUtcTimestamp(sourceWindow.latest_replay_time)
		if nowSeconds and latestSeconds then return math.max(0, nowSeconds - latestSeconds) end
		local ageSeconds = tonumber(sourceWindow.latest_replay_age_seconds)
		if ageSeconds and ageSeconds >= 0 then
			return math.max(0, ageSeconds + (tonumber(options and options.sourceWindowAgeOffsetSeconds) or 0))
		end
		return nil
	end

	local function SourceWindowText(response, options)
		local sourceWindow = response and response.source_window
		if type(sourceWindow) ~= "table" then return "-" end
		local earliest = tostring(sourceWindow.earliest_replay_time or "")
		local freshness = Display.AgeText(SourceWindowAgeSeconds(sourceWindow, options))
		if not freshness then
			local days = tonumber(sourceWindow.latest_replay_age_days)
			if days == 0 then freshness = "today"
			elseif days == 1 then freshness = "1 day ago"
			elseif days then freshness = tostring(math.floor(days)) .. " days ago" end
		end
		if earliest ~= "" and freshness then return string.sub(earliest, 1, 10) .. " - " .. freshness end
		if type(sourceWindow.display) == "string" and sourceWindow.display ~= "" then return sourceWindow.display end
		if earliest == "" then return "-" end
		local latest = tostring(sourceWindow.latest_replay_time or "")
		return latest ~= "" and (string.sub(earliest, 1, 10) .. " - " .. string.sub(latest, 1, 10)) or "-"
	end

	function ViewModel.SourceWindowAgeMinute(response, options)
		local sourceWindow = response and response.source_window
		if type(sourceWindow) ~= "table" then return nil end
		local seconds = SourceWindowAgeSeconds(sourceWindow, options)
		return seconds and math.floor(seconds / 60) or nil
	end

	function ViewModel.EstimatedLoadingProgress(elapsedSeconds, expectedSeconds)
		local elapsed = math.max(0, tonumber(elapsedSeconds) or 0)
		local expected = math.max(0.001, tonumber(expectedSeconds) or 0.001)
		local normalized = elapsed / expected
		if normalized <= 1 then return 0.90 * (1 - ((1 - normalized) ^ 2)) end
		return math.min(0.92, 0.90 + 0.02 * (1 - math.exp(-(normalized - 1))))
	end

	function ViewModel.Empty()
		local view = {
			statusText = "Ready",
			difficultyText = "-",
			winChanceHelpText = "Estimated chance that a representative current BAR human team wins this map and effective setup. Named player identities and skill ratings are not used.",
			challengeHelpText = "An absolute 0-34 difficulty score for this setup. Challenge 17 represents an estimated 50% win chance for a representative current BAR human team; higher is harder. Difficulty Percentile is the relative placement among played games.",
			difficultyPercentileHelpText = "Where this setup's challenge score falls among eligible played games for this AI type.",
			trainingGamesHelpText = "Eligible games for this AI type used to train the model. This is not the number of exact or nearby matches.",
			exactWinsText = "-",
			extendedWinsText = "-",
			evidenceGamesText = "-",
			evidenceGamesLabel = "Difficulty Percentile",
			winsLabelText = "Win Chance",
			matchText = "-",
			matchHelpText = "The matched lobby setting supplies setting-specific statistics and displayed differences. Match is separate from Win Chance and is not a confidence score.",
			sourceWindowText = "-",
			errorText = "",
			noticeText = "",
			messageText = "",
			evidenceSummaryText = "",
			diagnosticsText = "PvE Stats diagnostics",
			histogramCaption = "",
			diffComparisonLabel = "Similar",
			diffTitle = "",
			diffToggleText = "",
			hiddenDiffText = "",
			isExactMatch = false,
			hasError = false,
			hasNotice = false,
			hasDiffs = false,
			hasVisibleDiffs = false,
			hasHiddenDiff = false,
			hasDiffToggle = false,
			hasEvidenceSummary = false,
			hasDiagnostics = false,
			diagnosticsExpanded = false,
			hasHistogram = false,
			hasSourceWindow = false,
			hasUpdate = false,
			updateHelpText = "",
			clientVersion = CLIENT_VERSION,
			apiClientVersion = 0,
			playerGroups = {},
			diagnosticRows = {},
			diffRows = {},
			histogramBins = {},
		}
		Merge(view, PlayerStats.Build(nil, nil, nil, {playerTab = "setup", sortColumn = 2, sortDescending = true}))
		return view
	end

	local function ClientUpdateNotice(response)
		local apiVersion = tonumber(response and response.client_version)
		if apiVersion and apiVersion > CLIENT_VERSION then
			return "Widget update available: v" .. (Display.Integer(apiVersion) or tostring(apiVersion))
		end
		return ""
	end

	function ViewModel.Build(response, errorCode, request, colorLookup, options)
		options = options or {}
		local view = ViewModel.Empty()
		Merge(view, PlayerStats.Build(response, request, colorLookup, options))
		Merge(view, Diagnostics.Build(response, options))
		Merge(view, Histogram.Build(response, request))
		if errorCode then
			view.statusText = "Unavailable"
			view.errorText = "PvE Stats unavailable (" .. tostring(errorCode) .. ")."
			view.messageText = view.errorText
			view.hasError = true
			return view
		end
		if not response then return view end

		view.apiClientVersion = tonumber(response.client_version) or 0
		view.noticeText = ClientUpdateNotice(response)
		view.hasNotice = view.noticeText ~= ""
		view.hasUpdate = view.hasNotice
		if view.hasUpdate then
			view.statusText = "Update"
			view.messageText = view.noticeText
			view.updateHelpText = view.noticeText .. ". Click to copy the installation link."
		end

		local estimate = response.difficulty_estimate
		local histogram = response.difficulty_histogram
		local aiType = tostring(request and request.ai_type or "PvE")
		local trainingGames = type(estimate) == "table" and tonumber(estimate.evidence_games) or nil
		local currentChallenge = type(histogram) == "table" and tonumber(histogram.current_difficulty) or nil
		local playedPercentile = type(histogram) == "table" and tonumber(histogram.current_percentile) or nil
		view.difficultyText = currentChallenge and Display.Number(currentChallenge, 1) or "Unplaced"
		view.exactWinsText = type(estimate) == "table" and (Display.Percent(estimate.player_win_probability) or "-") or "-"
		view.extendedWinsText = trainingGames and Display.Number(trainingGames, 0) or "-"
		view.evidenceGamesText = playedPercentile and ("P" .. Display.Number(playedPercentile, 0)) or "Unplaced"
		view.winChanceHelpText = "Estimated chance that a representative current BAR human team wins this map and effective setup. It uses team size and relevant encounter context, but not the identities or skill ratings of the players currently in the lobby."
		view.challengeHelpText = currentChallenge
			and ("Challenge " .. Display.Number(currentChallenge, 1) .. " is this setup's absolute difficulty on a 0-34 scale. Challenge 17 represents an estimated 50% win chance for a representative current BAR human team; higher is harder. Difficulty Percentile compares this score with eligible played games.")
			or "This setup does not have a Challenge score yet. Challenge is an absolute 0-34 difficulty score; Difficulty Percentile is the relative placement among eligible played games."
		view.difficultyPercentileHelpText = playedPercentile
			and ("This setup's Challenge score is harder than approximately " .. Display.Number(playedPercentile, 0) .. "% of eligible played " .. aiType .. " games. This is a relative placement, not the Challenge score itself.")
			or ("This setup has not been placed in the eligible played " .. aiType .. " game distribution.")
		view.trainingGamesHelpText = trainingGames
			and (Display.Number(trainingGames, 0) .. " eligible " .. aiType .. " games were used to train this model after validity and grace-period filtering. This is overall model data, not the number of exact or nearby matches and not a confidence score.")
			or ("Eligible " .. aiType .. " games train the model after validity and grace-period filtering. This is overall model data, not the number of exact or nearby matches and not a confidence score.")
		view.matchText = Diagnostics.MatchResultText(response)
		if Diagnostics.IsClosest(response) then
			local topMatch = response.closest_matches and response.closest_matches[1]
			view.matchHelpText = topMatch and tostring(topMatch.match_method or "") == "raw_fallback"
				and "Raw fallback compares available lobby fields for the setting-specific statistics and differences shown below. The overlap is not model confidence and does not determine whether either setup is harder. Match selection is separate from Win Chance."
				or "Similarity summarizes the selected comparison used for the setting-specific statistics and differences shown below. A score of 1.000 is the closest possible match; it is not confidence and does not say which setup is harder. Match selection is separate from Win Chance."
		end
		view.sourceWindowText = SourceWindowText(response, options)
		view.hasSourceWindow = view.sourceWindowText ~= "-"
		view.isExactMatch = Diagnostics.IsExact(response)
		return view
	end

	return ViewModel
end

return ViewModelFactory
