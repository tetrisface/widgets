local Model = {}

Model.CLIENT_VERSION = 9

local function CopyTable(source)
	local copy = {}
	for key, value in pairs(source or {}) do
		copy[key] = value
	end
	return copy
end

local function AddModOptionStep(lookup, key, step)
	local optionKey = tostring(key or "")
	local numericStep = tonumber(step)
	if optionKey == "" or not numericStep or numericStep <= 0 then
		return
	end
	lookup[optionKey] = numericStep
	lookup[string.lower(optionKey)] = numericStep
end

local function CollectModOptionSteps(definitions, lookup, seen)
	if type(definitions) ~= "table" then
		return
	end
	if seen[definitions] then
		return
	end
	seen[definitions] = true

	AddModOptionStep(lookup, definitions.key or definitions.name or definitions.id, definitions.step)
	for key, value in pairs(definitions) do
		if type(value) == "table" then
			AddModOptionStep(lookup, key, value.step)
			CollectModOptionSteps(value.options or value.items or value.children or value.entries, lookup, seen)
			CollectModOptionSteps(value, lookup, seen)
		end
	end
end

function Model.ModOptionStepLookup(...)
	local lookup = {}
	for index = 1, select("#", ...) do
		CollectModOptionSteps(select(index, ...), lookup, {})
	end
	return lookup
end

local function AppendValue(parts, value)
	local text = tostring(value or "")
	parts[#parts + 1] = tostring(#text)
	parts[#parts + 1] = ":"
	parts[#parts + 1] = text
end

local function AppendArray(parts, values)
	parts[#parts + 1] = "["
	for _, value in ipairs(values or {}) do
		AppendValue(parts, value)
		parts[#parts + 1] = ","
	end
	parts[#parts + 1] = "]"
end

local function AppendMap(parts, values)
	local keys = {}
	for key in pairs(values or {}) do
		keys[#keys + 1] = key
	end
	table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)

	parts[#parts + 1] = "{"
	for _, key in ipairs(keys) do
		AppendValue(parts, key)
		parts[#parts + 1] = "="
		AppendValue(parts, values[key])
		parts[#parts + 1] = ";"
	end
	parts[#parts + 1] = "}"
end

local function SafeCall(object, methodName, ...)
	local method = object and object[methodName]
	if not method then
		return nil
	end

	local ok, first, second, third, fourth, fifth, sixth, seventh, eighth, ninth, tenth, eleventh = pcall(method, ...)
	if not ok then
		return nil
	end
	return first, second, third, fourth, fifth, sixth, seventh, eighth, ninth, tenth, eleventh
end

local function CollectModOptions(springApi)
	local modOptions = CopyTable(SafeCall(springApi, "GetModOptionsCopy") or {})
	for key, value in pairs(SafeCall(springApi, "GetModOptions") or {}) do
		modOptions[key] = value
	end
	return modOptions
end

local function HasAiName(value, pattern)
	return string.find(string.lower(tostring(value or "")), pattern, 1, true) ~= nil
end

local function AiTypeFromFlags(isRaptors, isScavengers)
	if isRaptors == true and isScavengers ~= true then
		return "Raptors"
	end
	if isScavengers == true and isRaptors ~= true then
		return "Scavengers"
	end
	return nil
end

local function AccountIdFromInfo(...)
	for index = 1, select("#", ...) do
		local info = select(index, ...)
		if type(info) == "table" then
			local accountID = tonumber(info.accountid or info.accountID or info.account_id)
			if accountID and accountID > 0 then
				return accountID
			end
		end
	end
	return nil
end

local function AddUnique(values, seen, value)
	if value and not seen[value] then
		seen[value] = true
		values[#values + 1] = value
	end
end

local function AiTypeFromText(value)
	local hasRaptors = HasAiName(value, "raptors") or HasAiName(value, "raptor")
	local hasScavengers = HasAiName(value, "scavengers") or HasAiName(value, "scavenger")
	if hasRaptors and not hasScavengers then
		return "Raptors"
	end
	if hasScavengers and not hasRaptors then
		return "Scavengers"
	end
	if hasRaptors and hasScavengers then
		return nil
	end
	if HasAiName(value, "barbarian") or HasAiName(value, "barb") then
		return "Barbarian"
	end
	return nil
end

local function AiTypeFromSeenTeams(seen)
	local hasRaptors = seen.Raptors == true
	local hasScavengers = seen.Scavengers == true
	if hasRaptors and not hasScavengers then
		return "Raptors", "team_ai_identity"
	end
	if hasScavengers and not hasRaptors then
		return "Scavengers", "team_ai_identity"
	end
	if hasRaptors or hasScavengers then
		return nil, "ambiguous_team_ai_identity"
	end
	if seen.Barbarian then
		return "Barbarian", "team_ai_identity"
	end
	return nil, nil
end

local function DetectAiTypeWithSource(springApi)
	local utilities = springApi and springApi.Utilities
	local gametype = utilities and utilities.Gametype
	local gametypeAiType = nil
	if gametype then
		gametypeAiType = AiTypeFromFlags(SafeCall(gametype, "IsRaptors"), SafeCall(gametype, "IsScavengers"))
	end

	local teamList = SafeCall(springApi, "GetTeamList") or {}
	local hasGenericAiTeam = false
	local genericAiTeamCount = 0
	local seen = {}
	local seenCounts = {}
	local seenTeamIds = {}
	local genericAiTeamIds = {}
	for _, teamID in ipairs(teamList) do
		local aiId, possibleAiName, _hostingPlayerID, aiName, version = SafeCall(springApi, "GetAIInfo", teamID)
		local _, _, _, isAiTeam = SafeCall(springApi, "GetTeamInfo", teamID, false)
		local teamLuaAi = SafeCall(springApi, "GetTeamLuaAI", teamID)
		local gameRulesAiName = SafeCall(springApi, "GetGameRulesParam", "ainame_" .. tostring(teamID))
		local haystack = table.concat({
			tostring(aiId or ""),
			tostring(possibleAiName or ""),
			tostring(aiName or ""),
			tostring(version or ""),
			tostring(teamLuaAi or ""),
			tostring(gameRulesAiName or ""),
		}, " ")

		local aiType = AiTypeFromText(haystack)
		if aiType then
			seen[aiType] = true
			seenCounts[aiType] = (seenCounts[aiType] or 0) + 1
			seenTeamIds[aiType] = seenTeamIds[aiType] or {}
			seenTeamIds[aiType][#seenTeamIds[aiType] + 1] = teamID
		end
		if aiId or possibleAiName or aiName or teamLuaAi or isAiTeam == true then
			hasGenericAiTeam = true
			genericAiTeamCount = genericAiTeamCount + 1
			genericAiTeamIds[#genericAiTeamIds + 1] = teamID
		end
	end

	local function EnemyAiCount(aiType)
		local namedCount = seenCounts[aiType] or 0
		if namedCount > 0 then
			return namedCount
		end
		if aiType == "Barbarian" and genericAiTeamCount > 0 then
			return genericAiTeamCount
		end
		return nil
	end

	if gametypeAiType then
		return gametypeAiType, "spring_utilities_gametype", EnemyAiCount(gametypeAiType), seenTeamIds[gametypeAiType] or {}
	end

	local aiType, aiTypeSource = AiTypeFromSeenTeams(seen)
	if aiType then
		return aiType, aiTypeSource, EnemyAiCount(aiType), seenTeamIds[aiType] or {}
	end
	if aiTypeSource then
		return nil, aiTypeSource
	end

	if hasGenericAiTeam then
		return "Barbarian", "generic_ai_team", genericAiTeamCount, genericAiTeamIds
	end

	return nil, "missing_ai_type"
end

function Model.DetectAiType(springApi)
	local aiType = DetectAiTypeWithSource(springApi)
	return aiType
end

function Model.CollectPlayers(springApi)
	local playerNames = {}
	local playerIds = {}
	local activePlayerNames = {}
	local activePlayerIds = {}
	local spectatorNames = {}
	local spectatorIds = {}
	local activePlayerTeamIds = {}
	local seenNames = {}
	local seenIds = {}
	local playerList = SafeCall(springApi, "GetPlayerList") or {}
	local ownPlayerID = SafeCall(springApi, "GetMyPlayerID")
	local ownPlayerName = nil
	local ownAccountID = nil

	for _, playerID in ipairs(playerList) do
		local name, _, spectator, teamID, _, _, _, _, _, customKeys, extraInfo = SafeCall(springApi, "GetPlayerInfo", playerID, false)
		if name then
			local groupNames = spectator and spectatorNames or activePlayerNames
			AddUnique(playerNames, seenNames, name)
			groupNames[#groupNames + 1] = name

			local accountID = AccountIdFromInfo(customKeys, extraInfo)
			if accountID then
				local groupIds = spectator and spectatorIds or activePlayerIds
				AddUnique(playerIds, seenIds, accountID)
				groupIds[#groupIds + 1] = accountID
			end
			if not spectator and teamID ~= nil then
				activePlayerTeamIds[#activePlayerTeamIds + 1] = teamID
			end
			if playerID == ownPlayerID then
				ownPlayerName = name
				ownAccountID = accountID
			end
		end
	end

	table.sort(playerNames)
	table.sort(playerIds)
	table.sort(activePlayerNames)
	table.sort(activePlayerIds)
	table.sort(spectatorNames)
	table.sort(spectatorIds)

	return playerNames, playerIds, {
		active_player_names = activePlayerNames,
		active_player_ids = activePlayerIds,
		spectator_names = spectatorNames,
		spectator_ids = spectatorIds,
		own_player_name = ownPlayerName,
		own_player_id = ownAccountID,
		active_player_team_ids = activePlayerTeamIds,
	}
end

local function TeamIncomeMultiplier(springApi, teamID)
	local _, _, _, _, _, _, incomeMultiplier = SafeCall(springApi, "GetTeamInfo", teamID, false)
	local numeric = tonumber(incomeMultiplier)
	if numeric and numeric >= 0 then
		return numeric
	end
	return nil
end

local function TeamIncomeMultipliers(springApi, teamIDs)
	local result = {}
	for _, teamID in ipairs(teamIDs or {}) do
		local multiplier = TeamIncomeMultiplier(springApi, teamID)
		if multiplier ~= nil then
			result[#result + 1] = multiplier
		end
	end
	return result
end

function Model.SettingRequestKey(request)
	if not request then
		return nil
	end

	local parts = {}
	AppendValue(parts, request.ai_type)
	parts[#parts + 1] = "|"
	AppendValue(parts, request.map)
	parts[#parts + 1] = "|"
	AppendMap(parts, request.encounter_context)
	parts[#parts + 1] = "|"
	AppendMap(parts, request.game_settings)
	return table.concat(parts)
end

function Model.RequestKey(request)
	if not request then
		return nil
	end

	local parts = {Model.SettingRequestKey(request), "|"}
	AppendArray(parts, request.player_ids)
	parts[#parts + 1] = "|"
	AppendArray(parts, request.player_names)
	parts[#parts + 1] = "|"
	AppendValue(parts, request.player_filter_requested and "1" or "0")
	return table.concat(parts)
end

function Model.WireRequest(request)
	local wire = {}
	for key, value in pairs(request or {}) do
		if not string.match(tostring(key), "^_") then
			wire[key] = value
		end
	end
	return wire
end

function Model.BuildRequest(springApi, gameApi)
	local aiType, aiTypeSource, enemyAiCount, enemyAiTeamIds = DetectAiTypeWithSource(springApi)
	if not aiType then
		return nil, aiTypeSource or "missing_ai_type"
	end

	local mapName = gameApi and (gameApi.mapName or gameApi.map_name)
	if not mapName or tostring(mapName) == "" then
		return nil, "missing_map"
	end

	local playerNames, playerIds, playerGroups = Model.CollectPlayers(springApi)
	local encounterContext = {
		human_team_size = #(playerGroups and playerGroups.active_player_names or {}),
	}
	local humanIncomeMultipliers = TeamIncomeMultipliers(
		springApi,
		playerGroups and playerGroups.active_player_team_ids or {}
	)
	if #humanIncomeMultipliers > 0 then
		encounterContext.human_player_income_multipliers = humanIncomeMultipliers
	end
	-- Raptor and Scavenger Lua AIs are boolean activators for one backend
	-- controller. Repeated lobby AI slots do not increase encounter strength.
	-- BARbarian slots are separate opponents, so their count remains meaningful.
	if aiType == "Barbarian" and enemyAiCount then
		encounterContext.enemy_ai_count = enemyAiCount
		local enemyIncomeMultipliers = TeamIncomeMultipliers(springApi, enemyAiTeamIds)
		if #enemyIncomeMultipliers > 0 then
			encounterContext.enemy_ai_income_multipliers = enemyIncomeMultipliers
		end
	end
	local request = {
		ai_type = aiType,
		map = mapName,
		game_settings = CollectModOptions(springApi),
		encounter_context = encounterContext,
		player_names = playerNames,
		player_ids = playerIds,
		player_filter_requested = true,
		_ai_type_source = aiTypeSource,
		_active_player_names = playerGroups and playerGroups.active_player_names or {},
		_active_player_ids = playerGroups and playerGroups.active_player_ids or {},
		_spectator_names = playerGroups and playerGroups.spectator_names or {},
		_spectator_ids = playerGroups and playerGroups.spectator_ids or {},
		_own_player_name = playerGroups and playerGroups.own_player_name or nil,
		_own_player_id = playerGroups and playerGroups.own_player_id or nil,
	}
	request._request_key = Model.RequestKey(request)
	return request
end

function Model.EscapeRml(value)
	local text = tostring(value or "")
	text = string.gsub(text, "&", "&amp;")
	text = string.gsub(text, "<", "&lt;")
	text = string.gsub(text, ">", "&gt;")
	text = string.gsub(text, "\"", "&quot;")
	text = string.gsub(text, "'", "&#39;")
	return text
end

local function FormatNumber(value, decimals)
	local number = tonumber(value)
	if not number then
		return "-"
	end
	return string.format("%." .. tostring(decimals or 0) .. "f", number)
end

local function FormatInteger(value)
	local number = tonumber(value)
	if not number then
		return nil
	end
	return string.format("%d", math.floor(number))
end

local function ApiClientVersion(response)
	return tonumber(response and response.client_version)
end

local function ClientUpdateNotice(response)
	local apiVersion = ApiClientVersion(response)
	if apiVersion and apiVersion > Model.CLIENT_VERSION then
		return table.concat({
			"Widget update available: v",
			FormatInteger(apiVersion) or tostring(apiVersion),
		})
	end
	return ""
end

local function PluralizeUnit(value, unit)
	if value == 1 then
		return "1 " .. unit
	end
	return tostring(value) .. " " .. unit .. "s"
end

local function AddAgePart(parts, value, unit)
	if value and value > 0 and #parts < 2 then
		parts[#parts + 1] = PluralizeUnit(value, unit)
	end
end

local DAYS_BEFORE_MONTH = {
	0,
	31,
	59,
	90,
	120,
	151,
	181,
	212,
	243,
	273,
	304,
	334,
}

local DAYS_IN_MONTH = {
	31,
	28,
	31,
	30,
	31,
	30,
	31,
	31,
	30,
	31,
	30,
	31,
}

local function IsLeapYear(year)
	return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
end

local function DaysBeforeYear(year)
	local previousYear = year - 1
	return (previousYear * 365)
		+ math.floor(previousYear / 4)
		- math.floor(previousYear / 100)
		+ math.floor(previousYear / 400)
end

local EPOCH_DAYS = DaysBeforeYear(1970)

local function UtcEpochSeconds(year, month, day, hour, minute, second)
	if month < 1 or month > 12 then
		return nil
	end
	if hour < 0 or hour > 23 or minute < 0 or minute > 59 or second < 0 or second > 60 then
		return nil
	end

	local daysInMonth = DAYS_IN_MONTH[month]
	if month == 2 and IsLeapYear(year) then
		daysInMonth = 29
	end
	if day < 1 or day > daysInMonth then
		return nil
	end

	local days = DaysBeforeYear(year) - EPOCH_DAYS + DAYS_BEFORE_MONTH[month] + day - 1
	if month > 2 and IsLeapYear(year) then
		days = days + 1
	end
	return ((((days * 24) + hour) * 60) + minute) * 60 + second
end

local function ParseUtcTimestamp(value)
	local year, month, day, hour, minute, second = string.match(
		tostring(value or ""),
		"^(%d%d%d%d)%-(%d%d)%-(%d%d)[Tt ](%d%d):(%d%d):(%d%d)"
	)
	if not year then
		return nil
	end
	return UtcEpochSeconds(
		tonumber(year),
		tonumber(month),
		tonumber(day),
		tonumber(hour),
		tonumber(minute),
		tonumber(second)
	)
end

local function SourceWindowAgeSeconds(sourceWindow, options)
	local nowSeconds = tonumber(options and options.sourceWindowNowSeconds)
	local latestReplaySeconds = ParseUtcTimestamp(sourceWindow.latest_replay_time)
	if nowSeconds and latestReplaySeconds then
		return math.max(0, nowSeconds - latestReplaySeconds)
	end

	local ageSeconds = tonumber(sourceWindow.latest_replay_age_seconds)
	if ageSeconds and ageSeconds >= 0 then
		local ageOffsetSeconds = tonumber(options and options.sourceWindowAgeOffsetSeconds) or 0
		return math.max(0, ageSeconds + ageOffsetSeconds)
	end
	return nil
end

function Model.SourceWindowAgeMinute(response, options)
	local sourceWindow = response and response.source_window
	if type(sourceWindow) ~= "table" then
		return nil
	end

	local ageSeconds = SourceWindowAgeSeconds(sourceWindow, options)
	if not ageSeconds then
		return nil
	end
	return math.floor(ageSeconds / 60)
end

local function SourceWindowFreshnessText(sourceWindow, options)
	local ageSeconds = SourceWindowAgeSeconds(sourceWindow, options)
	if ageSeconds then
		local totalMinutes = math.floor(ageSeconds / 60)
		if totalMinutes < 1 then
			return "less than 1 minute ago"
		end

		local ageDays = math.floor(totalMinutes / (24 * 60))
		local remainingMinutes = totalMinutes - (ageDays * 24 * 60)
		local ageHours = math.floor(remainingMinutes / 60)
		local ageMinutes = remainingMinutes - (ageHours * 60)
		local parts = {}

		AddAgePart(parts, ageDays, "day")
		AddAgePart(parts, ageHours, "hour")
		AddAgePart(parts, ageMinutes, "minute")

		if #parts > 0 then
			return table.concat(parts, " ") .. " ago"
		end
	end

	local ageDays = tonumber(sourceWindow.latest_replay_age_days)
	if ageDays then
		if ageDays == 0 then
			return "today"
		end
		if ageDays == 1 then
			return "1 day ago"
		end
		return tostring(math.floor(ageDays)) .. " days ago"
	end

	return nil
end

local function SourceWindowText(response, options)
	local sourceWindow = response and response.source_window
	if type(sourceWindow) ~= "table" then
		return "-"
	end

	local earliest = tostring(sourceWindow.earliest_replay_time or "")
	local freshness = SourceWindowFreshnessText(sourceWindow, options)
	if earliest ~= "" and freshness then
		return string.sub(earliest, 1, 10) .. " - " .. freshness
	end

	if type(sourceWindow.display) == "string" and sourceWindow.display ~= "" then
		return sourceWindow.display
	end

	if earliest == "" then
		return "-"
	end
	earliest = string.sub(earliest, 1, 10)

	local latest = tostring(sourceWindow.latest_replay_time or "")
	if latest ~= "" then
		return earliest .. " - " .. string.sub(latest, 1, 10)
	end
	return "-"
end

function Model.BoundedExponentialBackoffSeconds(attempt, initialSeconds, maxSeconds)
	local safeAttempt = math.max(1, tonumber(attempt) or 1)
	local safeInitial = math.max(0, tonumber(initialSeconds) or 0)
	local safeMax = math.max(safeInitial, tonumber(maxSeconds) or safeInitial)
	local delay = safeInitial * (2 ^ (safeAttempt - 1))
	return math.min(delay, safeMax)
end

function Model.RetryErrorClass(err)
	local text = string.lower(tostring(err or ""))
	if string.find(text, "reservedfunctionconcurrentinvocationlimitexceeded", 1, true) then
		return "reserved_concurrency"
	end
	if string.find(text, "receive_failed:timeout", 1, true) then
		return "request_timeout"
	end
	if string.find(text, "http_429:", 1, true) then
		return "rate_limited"
	end
	return nil
end

function Model.IsExpectedStartupTransient(err)
	local errorClass = Model.RetryErrorClass(err)
	return errorClass == "request_timeout" or errorClass == "reserved_concurrency"
end

function Model.EstimatedLoadingProgress(elapsedSeconds, expectedSeconds)
	local elapsed = math.max(0, tonumber(elapsedSeconds) or 0)
	local expected = math.max(0.001, tonumber(expectedSeconds) or 0.001)
	local normalized = elapsed / expected
	if normalized <= 1 then
		return 0.90 * (1 - ((1 - normalized) ^ 2))
	end
	return math.min(0.92, 0.90 + 0.02 * (1 - math.exp(-(normalized - 1))))
end

local function TopClosestMatch(response)
	local matches = response and response.closest_matches
	return type(matches) == "table" and matches[1] or nil
end

local function ClosestSimilarityScore(response)
	local topMatch = TopClosestMatch(response)
	return tonumber(topMatch and topMatch.similarity)
end

local function MatchResultText(response)
	local value = response and response.match_status
	if value == nil then
		return "-"
	end

	local text = tostring(value)
	local normalized = string.lower(text)
	if normalized == "exact" then
		return "Exact"
	end
	if normalized == "closest" then
		local topMatch = TopClosestMatch(response)
		if tostring(topMatch and topMatch.match_method or "") == "raw_fallback" then
			return "Raw fallback"
		end
		local similarity = ClosestSimilarityScore(response)
		if similarity then
			return "Similar " .. FormatNumber(similarity, 3)
		end
		return "Similar"
	end
	if normalized == "not_found" or normalized == "not found" then
		return "Not found"
	end
	if normalized == "win" or normalized == "won" or normalized == "victory" then
		return "Win"
	end
	if normalized == "loss" or normalized == "lost" or normalized == "defeat" then
		return "Loss"
	end
	if normalized == "draw" or normalized == "tie" then
		return "Draw"
	end
	return text
end

local function IsExactMatch(response)
	local value = response and response.match_status
	return string.lower(tostring(value or "")) == "exact"
end

function Model.DefaultPlayerTab(response)
	if response and IsExactMatch(response) then
		return "setup"
	end
	return "awards"
end

local function IsClosestResponse(response)
	return string.lower(tostring(response and response.match_status or "")) == "closest"
end

local function WinsLabels(response)
	if IsClosestResponse(response) then
		return "Similar Wins"
	end
	return "Exact Wins"
end

local function StartsWith(value, prefix)
	return string.sub(value, 1, #prefix) == prefix
end

local function HiddenDiffColumn(column)
	local lower = string.lower(tostring(column or ""))
	return lower == "" or lower == "ai_type" or StartsWith(lower, "tweakdefs") or StartsWith(lower, "tweakunits")
end

local function DiffValueText(value)
	local valueType = type(value)
	if value == nil then
		return "-"
	end
	if valueType == "boolean" then
		return value and "true" or "false"
	end
	if valueType == "number" or valueType == "string" then
		local text = tostring(value)
		if text == "" then
			return "-"
		end
		return text
	end
	return "<complex>"
end

local function TrimTrailingZeros(text)
	text = string.gsub(text, "(%..-)0+$", "%1")
	return string.gsub(text, "%.$", "")
end

local function RoundNumber(value)
	if value >= 0 then
		return math.floor(value + 0.5)
	end
	return math.ceil(value - 0.5)
end

local function DecimalPlacesForStep(step)
	local text = tostring(step)
	if string.find(text, "[eE]") then
		text = string.format("%.10f", tonumber(step) or 0)
	end
	text = TrimTrailingZeros(text)
	local dotIndex = string.find(text, ".", 1, true)
	if not dotIndex then
		return 0
	end
	return math.max(0, #text - dotIndex)
end

local function FormatRoundedNumber(value, decimals)
	local places = math.max(0, tonumber(decimals) or 0)
	return TrimTrailingZeros(string.format("%." .. tostring(places) .. "f", value))
end

local function RoundToStep(value, step)
	local numericStep = tonumber(step)
	if not numericStep or numericStep <= 0 then
		return value
	end
	return RoundNumber(value / numericStep) * numericStep
end

local function NumericValue(value)
	local number = tonumber(value)
	if not number then
		return nil
	end
	return number
end

local function CleanFloatNoise(value, number)
	local text = tostring(value)
	if not string.find(text, "[%.eE]") then
		return text
	end
	for decimals = 0, 6 do
		local factor = 10 ^ decimals
		local rounded = RoundNumber(number * factor) / factor
		if math.abs(number - rounded) < 0.000001 then
			return FormatRoundedNumber(rounded, decimals)
		end
	end
	return text
end

local function LookupStep(lookup, column)
	if not lookup or not column then
		return nil
	end
	return tonumber(lookup[column] or lookup[tostring(column)] or lookup[string.lower(tostring(column))])
end

local function DiffStep(diff, options, response, topMatch)
	local explicit = diff and (diff.step or diff.option_step or diff.modoption_step or diff.mod_option_step)
	local explicitStep = tonumber(explicit)
	if explicitStep and explicitStep > 0 then
		return explicitStep
	end

	local column = diff and diff.column
	return LookupStep(options and options.modOptionSteps, column)
		or LookupStep(response and (response.mod_option_steps or response.modoption_steps), column)
		or LookupStep(topMatch and (topMatch.mod_option_steps or topMatch.modoption_steps), column)
end

local function DiffDisplayValue(value, diff, options, response, topMatch)
	local text = DiffValueText(value)
	local number = NumericValue(value)
	if not number then
		return text
	end

	local step = DiffStep(diff, options, response, topMatch)
	if step then
		return FormatRoundedNumber(RoundToStep(number, step), DecimalPlacesForStep(step))
	end
	return CleanFloatNoise(value, number)
end

local function SameDiffValue(diff, options, response, topMatch)
	return DiffDisplayValue(diff.incoming, diff, options, response, topMatch) == DiffDisplayValue(diff.expected, diff, options, response, topMatch)
end

local function DiagnosticHash(value)
	local text = tostring(value or "")
	if #text <= 12 then
		return text
	end
	return string.sub(text, 1, 12)
end

local function PercentText(value)
	local number = tonumber(value)
	if not number then
		return nil
	end
	return FormatRoundedNumber(number * 100, 1) .. "%"
end

local function DisplayDiffCount(topMatch)
	if type(topMatch) ~= "table" then
		return 0
	end
	if type(topMatch.display_diffs) == "table" then
		return #topMatch.display_diffs
	end
	local hidden = type(topMatch.hidden_diff_summary) == "table" and tonumber(topMatch.hidden_diff_summary.total) or nil
	local total = tonumber(topMatch.difference_count)
	if hidden and total then
		return math.max(0, total - hidden)
	end
	return 0
end

local function HiddenDifferenceText(topMatch)
	local hidden = topMatch and topMatch.hidden_diff_summary
	if type(hidden) ~= "table" or tonumber(hidden.total or 0) <= 0 then
		return nil
	end
	local total = math.floor(tonumber(hidden.total))
	return tostring(total) .. " additional field difference" .. (total == 1 and "" or "s") .. " hidden"
end

local function MatchSummaryText(response)
	if response and IsExactMatch(response) then
		return "Match: exact setting"
	end
	local topMatch = TopClosestMatch(response)
	if type(topMatch) ~= "table" then
		return "Match: no trusted setting match"
	end
	local method = tostring(topMatch.match_method or "")
	local parts = {}
	if method == "similar" then
		parts[#parts + 1] = "similar setting"
	else
		parts[#parts + 1] = "raw lobby fallback"
	end
	local visible = DisplayDiffCount(topMatch)
	parts[#parts + 1] = tostring(visible) .. " visible difference" .. (visible == 1 and "" or "s")
	local hiddenText = HiddenDifferenceText(topMatch)
	if hiddenText then
		parts[#parts + 1] = hiddenText
	end
	return "Match: " .. table.concat(parts, "; ")
end

local function EvidenceSummaryRml(response)
	if not response then
		return ""
	end
	return table.concat({
		"<div class=\"pve-stats-evidence-line\">", Model.EscapeRml(MatchSummaryText(response)), "</div>",
	})
end

local function RawOverlapText(response, topMatch)
	if type(topMatch) ~= "table" or tostring(topMatch.match_method or "") ~= "raw_fallback" then
		return nil
	end
	local total = tonumber(response and response.request_completeness and response.request_completeness.total_hash_columns)
	local missing = tonumber(response and response.request_completeness and response.request_completeness.missing_hash_columns) or 0
	local differences = tonumber(topMatch.difference_count)
	if not total or total <= 0 or not differences then
		return "lobby-field comparison unavailable"
	end
	local compared = math.max(0, total - missing)
	local knownDifferences = math.max(0, differences - missing)
	local matching = math.max(0, compared - knownDifferences)
	if compared <= 0 then
		return tostring(math.floor(missing)) .. " unknown fields"
	end
	local percent = 100 * matching / compared
	local unknownText = missing > 0 and ("; " .. tostring(math.floor(missing)) .. " unknown") or ""
	return FormatRoundedNumber(percent, 1) .. "% (" .. tostring(math.floor(matching)) .. "/" .. tostring(math.floor(compared)) .. " compared" .. unknownText .. ")"
end

local function AddDiagnostic(rows, label, value)
	if value == nil or tostring(value) == "" then
		return
	end
	rows[#rows + 1] = {label = label, value = tostring(value)}
end

local function DurationText(milliseconds)
	local value = tonumber(milliseconds)
	if not value then
		return nil
	end
	if value < 1000 then
		return tostring(math.floor(value + 0.5)) .. " ms"
	end
	return FormatRoundedNumber(value / 1000, 3) .. " s"
end

local function ByteSizeText(bytes)
	local value = tonumber(bytes)
	if not value then
		return nil
	end
	if value < 1024 then
		return tostring(math.floor(value)) .. " B"
	end
	if value < 1024 * 1024 then
		return FormatRoundedNumber(value / 1024, 1) .. " KiB"
	end
	return FormatRoundedNumber(value / (1024 * 1024), 1) .. " MiB"
end

local function DiagnosticsRows(response, options)
	-- Keep this user-facing support contract narrow. Detailed decision evidence
	-- stays server-side and is correlated through the request ID.
	local rows = {}
	local topMatch = TopClosestMatch(response)
	local estimate = response and response.difficulty_estimate
	if type(estimate) == "table" and estimate.difficulty_target_sha256 then
		AddDiagnostic(rows, "Contract", DiagnosticHash(estimate.difficulty_target_sha256))
	end
	AddDiagnostic(rows, "Match", MatchSummaryText(response))
	AddDiagnostic(rows, "Raw overlap", RawOverlapText(response, topMatch))
	local completeness = response and response.request_completeness
	if type(completeness) == "table" then
		AddDiagnostic(rows, "Request fields", table.concat({
			"provided " .. tostring(completeness.provided_hash_columns or 0),
			"derived " .. tostring(#(completeness.derived_hash_column_names or {})),
			"defaulted " .. tostring(completeness.defaulted_hash_columns or 0),
			"missing " .. tostring(completeness.missing_hash_columns or 0),
			"total " .. tostring(completeness.total_hash_columns or 0),
		}, "; "))
		if #(completeness.derived_hash_column_names or {}) > 0 then
			AddDiagnostic(rows, "Derived fields", table.concat(completeness.derived_hash_column_names, ", "))
		end
		if #(completeness.missing_hash_column_names or {}) > 0 then
			AddDiagnostic(rows, "Unknown fields", table.concat(completeness.missing_hash_column_names, ", "))
		end
	end
	local transport = options and options.transportEvidence
	if type(transport) == "table" then
		local http = {}
		if transport.http_status then http[#http + 1] = tostring(transport.http_status) end
		if transport.attempt then http[#http + 1] = "attempt " .. tostring(transport.attempt) end
		if transport.retry_class then http[#http + 1] = tostring(transport.retry_class) end
		AddDiagnostic(rows, "HTTP", #http > 0 and table.concat(http, "; ") or nil)
		AddDiagnostic(rows, "HTTP time", DurationText(transport.request_duration_ms))
		local loading = DurationText(transport.loading_elapsed_ms)
		if loading and transport.loading_expected_seconds then
			loading = loading .. " (" .. FormatRoundedNumber(transport.loading_expected_seconds, 1) .. " s expected)"
		end
		AddDiagnostic(rows, "Load time", loading)
		local transfer = {}
		local requestSize = ByteSizeText(transport.request_bytes)
		local responseSize = ByteSizeText(transport.response_bytes)
		if requestSize then transfer[#transfer + 1] = "request " .. requestSize end
		if responseSize then transfer[#transfer + 1] = "response " .. responseSize end
		AddDiagnostic(rows, "Transfer", #transfer > 0 and table.concat(transfer, "; ") or nil)
	end
	local identities = {}
	if type(transport) == "table" and transport.trace_id then identities[#identities + 1] = "trace " .. tostring(transport.trace_id) end
	if type(transport) == "table" and transport.request_hash then identities[#identities + 1] = "request " .. tostring(transport.request_hash) end
	if response and response.setting_hash then identities[#identities + 1] = "query " .. DiagnosticHash(response.setting_hash) end
	if topMatch and topMatch.setting_hash then identities[#identities + 1] = "match " .. DiagnosticHash(topMatch.setting_hash) end
	if options and options.currentGameId then identities[#identities + 1] = "game " .. tostring(options.currentGameId) end
	AddDiagnostic(rows, "IDs", #identities > 0 and table.concat(identities, "; ") or nil)
	return rows
end

local function DiagnosticsRml(response, options)
	local parts = {}
	for _, row in ipairs(DiagnosticsRows(response, options)) do
		parts[#parts + 1] = table.concat({
			"<div class=\"pve-stats-diagnostic-row\"><span class=\"pve-stats-diagnostic-label\">",
			Model.EscapeRml(row.label),
			"</span><span class=\"pve-stats-diagnostic-value\">",
			Model.EscapeRml(row.value),
			"</span></div>",
		})
	end
	return table.concat(parts, "\n")
end

local function DiagnosticsText(response, options)
	local parts = {"PvE Stats diagnostics"}
	for _, row in ipairs(DiagnosticsRows(response, options)) do
		parts[#parts + 1] = row.label .. ": " .. row.value
	end
	return table.concat(parts, "\n")
end

local function ClosestDiffsRml(response, options)
	options = options or {}
	local matches = response and response.closest_matches
	local topMatch = matches and matches[1]
	local diffs = {}
	if topMatch and type(topMatch.display_diffs) == "table" then
		diffs = topMatch.display_diffs
	end
	local rows = {}
	local visibleCount = 0
	local visibleDiffs = {}
	local expanded = options.diffExpanded == true
	local collapsedLimit = options.diffCollapsedLimit or 6

	for _, diff in ipairs(diffs) do
		local column = diff and diff.column
		if not HiddenDiffColumn(column) and not SameDiffValue(diff, options, response, topMatch) then
			visibleCount = visibleCount + 1
			visibleDiffs[#visibleDiffs + 1] = diff
		end
	end

	local hiddenText = HiddenDifferenceText(topMatch)
	if visibleCount == 0 and not hiddenText then
		return "", false
	end
	if visibleCount > 0 then
		local comparisonLabel = tostring(topMatch and topMatch.match_method or "") == "raw_fallback" and "Fallback" or "Similar"
		rows[#rows + 1] = table.concat({
			"<div class=\"pve-stats-diff-row pve-stats-diff-header\">",
			"<span class=\"pve-stats-diff-field\">Field</span>",
			"<span class=\"pve-stats-diff-current\">Current</span>",
			"<span class=\"pve-stats-diff-closest\">", comparisonLabel, "</span>",
			"</div>",
		})
		local rowLimit = expanded and visibleCount or collapsedLimit
		for index, diff in ipairs(visibleDiffs) do
			if index <= rowLimit then
				rows[#rows + 1] = table.concat({
					"<div class=\"pve-stats-diff-row\">",
					"<span class=\"pve-stats-diff-field\">", Model.EscapeRml(diff.column), "</span>",
					"<span class=\"pve-stats-diff-current\">", Model.EscapeRml(DiffDisplayValue(diff.incoming, diff, options, response, topMatch)), "</span>",
					"<span class=\"pve-stats-diff-closest\">", Model.EscapeRml(DiffDisplayValue(diff.expected, diff, options, response, topMatch)), "</span>",
					"</div>",
				})
			end
		end

		if visibleCount > collapsedLimit then
			local toggleText = expanded and "Show fewer" or table.concat({"+", tostring(visibleCount - collapsedLimit), " more"})
			rows[#rows + 1] = table.concat({
				"<div class=\"pve-stats-diff-more\" onclick=\"widget:ToggleDiffs(event)\">",
				Model.EscapeRml(toggleText),
				"</div>",
			})
		end
	end
	local sections = {}
	if hiddenText then
		local prefix = visibleCount == 0 and "No displayable lobby fields differ. " or "Also hidden: "
		sections[#sections + 1] = table.concat({
			"<div class=\"pve-stats-hidden-diff-summary\">",
			Model.EscapeRml(prefix .. hiddenText .. ". See Diagnostics for match details."),
			"</div>",
		})
	end
	if visibleCount > 0 then
		local title = tostring(topMatch and topMatch.match_method or "") == "raw_fallback" and "Raw fallback differs by " or "Similar match differs by "
		sections[#sections + 1] = table.concat({
			"<div class=\"pve-stats-diff-title\">", title,
			tostring(visibleCount),
			" shown field",
			visibleCount == 1 and "" or "s",
			"</div>",
			table.concat(rows, "\n"),
		})
	end
	return table.concat(sections, "\n"), true
end

local PLAYER_COLOR_FALLBACKS = {
	"#0066FF",
	"#FFCC00",
	"#FF3333",
	"#FF00CC",
	"#9966FF",
	"#33FFCC",
	"#CC6600",
	"#FFFFFF",
	"#00CC66",
	"#00CCCC",
	"#FF9966",
	"#66FF00",
}
local DEFAULT_PLAYER_COLOR = "#FFFFFF"

local function StableIndex(value, count)
	local text = tostring(value or "")
	local hash = 0
	for index = 1, #text do
		hash = (hash * 33 + string.byte(text, index)) % 2147483647
	end
	return (hash % count) + 1
end

local function PlayerColor(player, colorLookup)
	local lookup = colorLookup or {}
	local name = player and player.player_name
	local id = player and (player.player_id or player.playerId or player.account_id or player.accountId)
	local color = lookup[name] or lookup[tostring(name or "")] or lookup[id] or lookup[tostring(id or "")]
	if color and string.match(tostring(color), "^#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$") then
		return tostring(color)
	end
	local fallbackCount = #PLAYER_COLOR_FALLBACKS
	if fallbackCount <= 0 then
		return DEFAULT_PLAYER_COLOR
	end
	return PLAYER_COLOR_FALLBACKS[StableIndex(name or id or "player", fallbackCount)] or DEFAULT_PLAYER_COLOR
end

local function PlayerAccentRml(player, colorLookup, showColors)
	if showColors == false then
		return "<div class=\"pve-stats-player-accent pve-stats-player-accent-empty\"></div>"
	end

	local color = PlayerColor(player, colorLookup) or DEFAULT_PLAYER_COLOR
	return table.concat({
		"<div class=\"pve-stats-player-accent\" style=\"background-color: ",
		color,
		";\"></div>",
	})
end

local function ToSet(values)
	local set = {}
	for _, value in ipairs(values or {}) do
		set[value] = true
		set[tostring(value)] = true
	end
	return set
end

local function PlayerId(player)
	return player and (player.player_id or player.playerId or player.account_id or player.accountId)
end

local function PlayerNameForAscendingSort(player)
	local name = tostring(player and player.player_name or "")
	return string.lower(name), name
end

local function PlayerComesBefore(left, right)
	local leftLowerName, leftName = PlayerNameForAscendingSort(left)
	local rightLowerName, rightName = PlayerNameForAscendingSort(right)
	if leftLowerName ~= rightLowerName then
		return leftLowerName < rightLowerName
	end
	if leftName ~= rightName then
		return leftName < rightName
	end
	return (tonumber(PlayerId(left)) or 0) < (tonumber(PlayerId(right)) or 0)
end

local function CurrentAiColumn(request)
	local aiType = string.lower(tostring(request and request.ai_type or ""))
	if aiType == "scavengers" then
		return 2
	end
	if aiType == "barbarian" then
		return 3
	end
	return 1
end

local function AccomplishmentGroup(player, group)
	local accomplishments = player and player.accomplishments
	local value = accomplishments and accomplishments[group]
	return type(value) == "table" and value or {}
end

local function AwardGroup(player, group)
	local awards = player and player.awards
	local value = awards and awards[group]
	return type(value) == "table" and value or {}
end

local PLAYER_TAB_DEFINITIONS = {
	setup = {
		labels = {"Setup Clears", "Setup Plays", "PvE Games"},
		help = {
			"Eligible victories with this exact effective setup and encounter context. Similar settings never contribute.",
			"Eligible games with this exact effective setup and encounter context, regardless of outcome.",
			"All curated PvE games played in this mode.",
		},
		values = function(player)
			local participation = AccomplishmentGroup(player, "participation")
			return player.setup_clears, player.setup_plays, participation.games_played
		end,
		defaultSortColumn = function() return 1 end,
	},
	adventures = {
		labels = {"Games", "Victories", "Maps"},
		help = {
			"All curated PvE games played in this mode.",
			"All curated PvE victories in this mode.",
			"Distinct maps played in this mode.",
		},
		values = function(player)
			local participation = AccomplishmentGroup(player, "participation")
			return participation.games_played, participation.victories, participation.distinct_maps_played
		end,
		defaultSortColumn = function() return 2 end,
	},
	encounters = {
		labels = {"Queens Killed", "Bosses Killed", "BARbarians Killed"},
		help = {
			"Total Raptor queens defeated in victories.",
			"Total Scavenger bosses defeated in victories.",
			"Total Barbarian AI opponents defeated in victories.",
		},
		values = function(player)
			local encounters = AccomplishmentGroup(player, "encounters")
			return encounters.raptor_queens_defeated, encounters.scavenger_bosses_defeated, encounters.barbarian_ais_defeated
		end,
		defaultSortColumn = CurrentAiColumn,
	},
	milestones = {
		labels = {"20+ Clears", "25+ Clears", "30+ Clears"},
		help = {
			"Eligible wins at governed challenge 20 or above: modeled population win chance at most 41.2%.",
			"Eligible wins at governed challenge 25 or above: modeled population win chance at most 26.5%.",
			"Eligible wins at governed challenge 30 or above: modeled population win chance at most 11.8%.",
		},
		values = function(player)
			local challenges = AccomplishmentGroup(player, "challenges")
			return challenges.challenge_20_clears, challenges.challenge_25_clears, challenges.challenge_30_clears
		end,
		defaultSortColumn = function() return 1 end,
	},
	awards = {
		labels = {"Raptor Most Killed", "Scav Most Killed", "BARb Most Killed"},
		help = {
			"Times this player earned Most Killed against Raptors by ranking first in fighting-unit value destroyed.",
			"Times this player earned Most Killed against Scavengers by ranking first in fighting-unit value destroyed.",
			"Times this player earned Most Killed against BARbarians by ranking first in fighting-unit value destroyed.",
		},
		values = function(player)
			local mostKilled = AwardGroup(player, "most_killed")
			return mostKilled.raptors, mostKilled.scavengers, mostKilled.barbarians
		end,
		defaultSortColumn = CurrentAiColumn,
	},
}

local function PlayerTabDefinition(tab)
	return PLAYER_TAB_DEFINITIONS[tab] or PLAYER_TAB_DEFINITIONS.setup
end

function Model.PlayerStatHelpText(tab, columnIndex)
	local definition = PlayerTabDefinition(tab)
	return definition.help and definition.help[columnIndex] or ""
end

function Model.DefaultPlayerSortColumn(tab, request)
	local definition = PlayerTabDefinition(tab)
	local column = definition.defaultSortColumn and definition.defaultSortColumn(request) or 1
	return tonumber(column) or 1
end

local function PlayerStatValue(player, definition, column)
	local first, second, third = definition.values(player)
	if column == 1 then return tonumber(first) end
	if column == 2 then return tonumber(second) end
	if column == 3 then return tonumber(third) end
	return nil
end

local function SortPlayers(players, definition, sortColumn, descending)
	table.sort(players, function(left, right)
		if sortColumn == 0 then
			if descending then
				return PlayerComesBefore(right, left)
			end
			return PlayerComesBefore(left, right)
		end

		local leftValue = PlayerStatValue(left, definition, sortColumn)
		local rightValue = PlayerStatValue(right, definition, sortColumn)
		if leftValue == nil and rightValue ~= nil then return false end
		if leftValue ~= nil and rightValue == nil then return true end
		if leftValue ~= nil and rightValue ~= nil and leftValue ~= rightValue then
			if descending then return leftValue > rightValue end
			return leftValue < rightValue
		end
		return PlayerComesBefore(left, right)
	end)
	return players
end

local function PlayersWithUnresolvedNames(response)
	local players = {}
	local seenNames = {}
	for _, player in ipairs(response and response.players or {}) do
		players[#players + 1] = player
		local name = string.lower(tostring(player and player.player_name or ""))
		if name ~= "" then
			seenNames[name] = true
		end
	end

	for _, unresolvedName in ipairs(response and response.unresolved_player_names or {}) do
		local name = tostring(unresolvedName or "")
		local foldedName = string.lower(name)
		if name ~= "" and not seenNames[foldedName] then
			players[#players + 1] = {
				player_id = 0,
				player_name = name,
				exact_wins = 0,
				harder_wins = 0,
			}
			seenNames[foldedName] = true
		end
	end
	return players
end

local function SplitPlayers(players, request, definition, sortColumn, sortDescending)
	local activePlayers = {}
	local spectators = {}
	local spectatorNames = ToSet(request and request._spectator_names)
	local spectatorIds = ToSet(request and request._spectator_ids)

	for _, player in ipairs(players or {}) do
		local name = player.player_name
		local id = PlayerId(player)
		if spectatorNames[name] or spectatorNames[tostring(name or "")] or spectatorIds[id] or spectatorIds[tostring(id or "")] then
			spectators[#spectators + 1] = player
		else
			activePlayers[#activePlayers + 1] = player
		end
	end

	SortPlayers(activePlayers, definition, sortColumn, sortDescending)
	SortPlayers(spectators, definition, sortColumn, sortDescending)

	return activePlayers, spectators
end

local function IsOwnPlayer(player, options)
	local ownID = options and options.ownPlayerId
	local playerID = PlayerId(player)
	if ownID ~= nil and playerID ~= nil and tostring(ownID) == tostring(playerID) then
		return true
	end
	local ownName = string.lower(tostring(options and options.ownPlayerName or ""))
	local playerName = string.lower(tostring(player and player.player_name or ""))
	return ownName ~= "" and ownName == playerName
end

local function OwnPlayer(response, request)
	for _, player in ipairs(response and response.players or {}) do
		if IsOwnPlayer(player, {
			ownPlayerId = request and request._own_player_id,
			ownPlayerName = request and request._own_player_name,
		}) then
			return player
		end
	end
	return nil
end

local function DifficultyHistogramData(response, request)
	local histogram = response and response.difficulty_histogram
	local bins = histogram and histogram.bins
	if type(histogram) ~= "table" or type(bins) ~= "table" or #bins == 0 then
		return nil
	end
	local ownPlayer = OwnPlayer(response, request)
	local challenges = AccomplishmentGroup(ownPlayer, "challenges")
	local ownBins = type(challenges.clear_histogram) == "table" and challenges.clear_histogram or {}
	local summedGames = 0
	local summedWins = 0
	local totalOwnClears = 0
	for index, bin in ipairs(bins) do
		local games = tonumber(bin.games) or 0
		local wins = tonumber(bin.wins) or 0
		local ownClears = tonumber(ownBins[index]) or 0
		summedGames = summedGames + games
		summedWins = summedWins + wins
		totalOwnClears = totalOwnClears + ownClears
	end
	local totalGames = tonumber(histogram.total_games) or summedGames
	local maxShare = 0
	for index, bin in ipairs(bins) do
		local populationShare = totalGames > 0 and (tonumber(bin.games) or 0) / totalGames or 0
		local ownShare = totalOwnClears > 0 and (tonumber(ownBins[index]) or 0) / totalOwnClears or 0
		maxShare = math.max(maxShare, populationShare, ownShare)
	end
	return {
		histogram = histogram,
		bins = bins,
		ownPlayer = ownPlayer,
		challenges = challenges,
		ownBins = ownBins,
		maxShare = maxShare,
		totalGames = totalGames,
		totalWins = summedWins,
		totalOwnClears = totalOwnClears,
		currentDifficulty = tonumber(histogram.current_difficulty),
	}
end

local function HistogramContainsDifficulty(bin, difficulty)
	if not difficulty then
		return false
	end
	local lower = tonumber(bin and bin.lower_bound) or 0
	local upper = tonumber(bin and bin.upper_bound) or lower
	return difficulty >= lower and (difficulty < upper or (upper >= 34 and difficulty <= 34))
end

local function HistogramBoundText(value)
	local number = tonumber(value) or 0
	if number == math.floor(number) then
		return FormatNumber(number, 0)
	end
	return FormatNumber(number, 1)
end

local HISTOGRAM_MILESTONES = {
	{ score = 20, field = "challenge_20_clears" },
	{ score = 25, field = "challenge_25_clears" },
	{ score = 30, field = "challenge_30_clears" },
}

local function HistogramCrossedMilestoneText(data, lower, upper)
	if not data.ownPlayer then
		return nil
	end
	for _, milestone in ipairs(HISTOGRAM_MILESTONES) do
		if lower < milestone.score and milestone.score < upper then
			local exactClears = tonumber(data.challenges[milestone.field])
			if exactClears ~= nil then
				return "This bucket crosses " .. FormatNumber(milestone.score, 0)
					.. "; your exact " .. FormatNumber(milestone.score, 0) .. "+ Clears total is "
					.. FormatNumber(exactClears, 0) .. "."
			end
		end
	end
	return nil
end

function Model.HistogramHelpText(response, request)
	local data = DifficultyHistogramData(response, request)
	if not data then
		return ""
	end
	local ownText = data.ownPlayer
		and (" Cyan shows your " .. FormatNumber(data.totalOwnClears, 0) .. " eligible clears.")
		or " Cyan appears when your player history is available."
	return "Dark bars show " .. FormatNumber(data.totalGames, 0)
		.. " eligible games by challenge score."
		.. ownText
		.. " Both use one percentage scale. Each bar covers a score range; the Milestones table uses exact 20+/25+/30+ cutoffs."
		.. " Cyan above dark means this range contains a larger share of your clears than of all played games."
end

function Model.HistogramBinHelpText(response, request, binIndex)
	local data = DifficultyHistogramData(response, request)
	local index = tonumber(binIndex)
	local bin = data and index and data.bins[index]
	if not bin then
		return Model.HistogramHelpText(response, request)
	end
	local games = tonumber(bin.games) or 0
	local wins = tonumber(bin.wins) or 0
	local ownClears = tonumber(data.ownBins[index]) or 0
	local lower = tonumber(bin.lower_bound) or 0
	local upper = tonumber(bin.upper_bound) or lower
	local gameShare = data.totalGames > 0 and games / data.totalGames * 100 or 0
	local winRate = games > 0 and wins / games * 100 or 0
	local parts = {
		"Challenge " .. HistogramBoundText(lower) .. "-" .. HistogramBoundText(upper) .. ":",
		FormatNumber(games, 0) .. " eligible games (" .. FormatNumber(gameShare, 1) .. "% of played games),",
		FormatNumber(wins, 0) .. " human wins (" .. FormatNumber(winRate, 1) .. "%).",
	}
	if data.ownPlayer then
		local ownShare = data.totalOwnClears > 0 and ownClears / data.totalOwnClears * 100 or 0
		parts[#parts + 1] = "Your clears: " .. FormatNumber(ownClears, 0)
			.. " of " .. FormatNumber(data.totalOwnClears, 0)
			.. " (" .. FormatNumber(ownShare, 1) .. "%)."
	end
	local crossedMilestoneText = HistogramCrossedMilestoneText(data, lower, upper)
	if crossedMilestoneText then
		parts[#parts + 1] = crossedMilestoneText
	end
	if HistogramContainsDifficulty(bin, data.currentDifficulty) then
		parts[#parts + 1] = "Your current setup is here at " .. FormatNumber(data.currentDifficulty, 1) .. "."
	end
	parts[#parts + 1] = "Both bars use one percentage scale; cyan above dark means your clears are more concentrated here than played games are."
	return table.concat(parts, " ")
end

local function DifficultyHistogramRml(response, request)
	local data = DifficultyHistogramData(response, request)
	if not data then
		return "", "", false
	end
	local histogram = data.histogram
	local bins = data.bins
	local challenges = data.challenges
	local ownBins = data.ownBins
	local maxShare = data.maxShare
	local currentDifficulty = tonumber(histogram.current_difficulty)
	local rows = {}
	for index, bin in ipairs(bins) do
		local games = tonumber(bin.games) or 0
		local ownClears = tonumber(ownBins[index]) or 0
		local populationShare = data.totalGames > 0 and games / data.totalGames or 0
		local ownShare = data.totalOwnClears > 0 and ownClears / data.totalOwnClears or 0
		local populationHeight = maxShare > 0 and games > 0 and math.max(2, math.floor((populationShare / maxShare) * 100 + 0.5)) or 0
		local ownHeight = maxShare > 0 and ownClears > 0 and math.max(3, math.floor((ownShare / maxShare) * 100 + 0.5)) or 0
		local isCurrent = HistogramContainsDifficulty(bin, currentDifficulty)
		rows[#rows + 1] = table.concat({
			"<div class=\"pve-stats-histogram-bin", isCurrent and " current" or "",
			"\" data-bin-index=\"", tostring(index),
			"\" onmouseover=\"widget:ShowHistogramBinHelp(event)\" onmouseout=\"widget:HideHelp(event)\">",
			"<div class=\"pve-stats-histogram-population\" style=\"height: ", tostring(populationHeight), "%\"></div>",
			ownClears > 0 and table.concat({
				"<div class=\"pve-stats-histogram-own\" style=\"height: ", tostring(ownHeight), "%\"></div>",
			}) or "",
			isCurrent and "<div class=\"pve-stats-histogram-current\"></div>" or "",
			"</div>",
		})
	end
	local caption
	if currentDifficulty then
		local percentile = tonumber(histogram.current_percentile)
		caption = "Current " .. FormatNumber(currentDifficulty, 1)
		if percentile then
			caption = caption .. " - harder than " .. FormatNumber(percentile, 0) .. "% of played " .. tostring(request and request.ai_type or "PvE") .. " games"
		end
	else
		caption = "Current setup: not yet placed"
	end
	local highest = tonumber(challenges.highest_challenge_cleared)
	if highest then
		caption = caption .. " - your best " .. FormatNumber(highest, 1)
	end
	return table.concat({
		"<div class=\"pve-stats-histogram-chart\">", table.concat(rows), "</div>",
		"<div class=\"pve-stats-histogram-scale\">",
		"<span class=\"pve-stats-histogram-scale-start\">0</span>",
		"<span class=\"pve-stats-histogram-scale-threshold\" style=\"left: 58.824%\">20</span>",
		"<span class=\"pve-stats-histogram-scale-threshold\" style=\"left: 73.529%\">25</span>",
		"<span class=\"pve-stats-histogram-scale-threshold\" style=\"left: 88.235%\">30</span>",
		"<span class=\"pve-stats-histogram-scale-end\">34</span></div>",
		"<div class=\"pve-stats-histogram-legend\" onmouseover=\"widget:ShowHistogramHelp(event)\" onmouseout=\"widget:HideHelp(event)\">",
		"<span><span class=\"pve-stats-histogram-swatch population\"></span>Played games</span>",
		"<span><span class=\"pve-stats-histogram-swatch own\"></span>Your clears</span>",
		"<span><span class=\"pve-stats-histogram-swatch current\"></span>Current</span>",
		"<span>common % scale</span></div>",
	}), caption, true
end

function Model.PlayerRowsRml(players, colorLookup, options)
	if not players or #players == 0 then
		return "<div class=\"pve-stats-empty\">No player stats</div>"
	end

	options = options or {}
	local definition = PlayerTabDefinition(options.playerTab)
	local rows = {}
	for _, player in ipairs(players) do
		local name = Model.EscapeRml(player.player_name or "Unknown")
		local first, second, third = definition.values(player)
		local rowClass = IsOwnPlayer(player, options) and "pve-stats-player-row own-player" or "pve-stats-player-row"
		rows[#rows + 1] = table.concat({
			"<div class=\"", rowClass, "\">",
			PlayerAccentRml(player, colorLookup, options.showColors),
			"<span class=\"pve-stats-player-name\">", name, "</span>",
			"<span class=\"pve-stats-player-stat\">", FormatNumber(first, definition.digits and definition.digits[1] or 0), "</span>",
			"<span class=\"pve-stats-player-stat\">", FormatNumber(second, definition.digits and definition.digits[2] or 0), "</span>",
			"<span class=\"pve-stats-player-stat\">", FormatNumber(third, definition.digits and definition.digits[3] or 0), "</span>",
			"</div>",
		})
	end
	return table.concat(rows, "\n")
end

local function PlayerGroupRml(label, players, colorLookup, emptyText, options)
	if not players or #players == 0 then
		return table.concat({
			"<div class=\"pve-stats-group-label\">",
			Model.EscapeRml(label),
			"</div><div class=\"pve-stats-empty\">",
			Model.EscapeRml(emptyText),
			"</div>",
		})
	end

	return table.concat({
		"<div class=\"pve-stats-group-label\">",
		Model.EscapeRml(label),
		"</div>",
		Model.PlayerRowsRml(players, colorLookup, options),
	})
end

local function SortLabel(label, column, activeColumn, descending)
	if column ~= activeColumn then
		return label
	end
	return label .. (descending and " v" or " ^")
end

function Model.EmptyViewModel()
	return {
		statusText = "Ready",
		modeText = "-",
		difficultyText = "-",
		winChanceHelpText = "Estimated chance that a representative current BAR human team wins this map and effective setup. Named player identities and skill ratings are not used.",
		difficultyPercentileHelpText = "Where this setup's challenge score falls among eligible played games for this AI type.",
		trainingGamesHelpText = "Eligible games for this AI type used to train the model. This is not the number of exact or nearby matches.",
		exactWinsText = "-",
		extendedWinsText = "-",
		evidenceGamesText = "-",
		evidenceGamesLabel = "Difficulty Percentile",
		winsLabelText = "Win Chance",
		playerTab = "setup",
		playerHeaderLabel = "Player",
		playerStatOneLabel = "Setup Clears",
		playerStatTwoLabel = "Setup Plays",
		playerStatThreeLabel = "PvE Games",
		matchText = "-",
		matchHelpText = "The matched lobby setting supplies setting-specific statistics and displayed differences. Match is separate from Win Chance and is not a confidence score.",
		sourceWindowText = "-",
		isExactMatch = false,
		errorText = "",
		noticeText = "",
		playersRml = "<div class=\"pve-stats-empty\">No player stats</div>",
		diffsRml = "",
		evidenceSummaryRml = "",
		diagnosticsRml = "",
		diagnosticsText = "",
		diagnosticsExpanded = false,
		histogramRml = "",
		histogramCaption = "",
		hasHistogram = false,
		spectatorText = "Spec",
		hasError = false,
		hasNotice = false,
		hasPlayers = false,
		hasDiffs = false,
		hasEvidenceSummary = false,
		hasDiagnostics = false,
		hasSourceWindow = false,
		showSpectators = false,
		sortColumn = 2,
		sortDescending = true,
		hasUpdate = false,
		updateHelpText = "",
		clientVersion = Model.CLIENT_VERSION,
		apiClientVersion = nil,
	}
end

function Model.ViewModelFromResponse(response, errorMessage, request, colorLookup, options)
	options = options or {}
	local view = Model.EmptyViewModel()
	view.playerTab = PLAYER_TAB_DEFINITIONS[options.playerTab] and options.playerTab or "setup"
	local tabDefinition = PlayerTabDefinition(view.playerTab)
	local defaultSortColumn = Model.DefaultPlayerSortColumn(view.playerTab, request)
	view.sortColumn = tonumber(options.sortColumn)
	if view.sortColumn == nil or view.sortColumn < 0 or view.sortColumn > 3 then
		view.sortColumn = defaultSortColumn
	end
	view.sortDescending = options.sortDescending ~= false
	view.playerHeaderLabel = SortLabel("Player", 0, view.sortColumn, view.sortDescending)
	view.playerStatOneLabel = SortLabel(tabDefinition.labels[1], 1, view.sortColumn, view.sortDescending)
	view.playerStatTwoLabel = SortLabel(tabDefinition.labels[2], 2, view.sortColumn, view.sortDescending)
	view.playerStatThreeLabel = SortLabel(tabDefinition.labels[3], 3, view.sortColumn, view.sortDescending)
	view.showSpectators = options.showSpectators == true
	view.spectatorText = view.showSpectators and "Spec" or "Spec"
	if request and request.ai_type then
		view.modeText = tostring(request.ai_type)
	end

	if errorMessage then
		view.statusText = "Unavailable"
		view.errorText = tostring(errorMessage)
		view.hasError = true
		view.diagnosticsRml = DiagnosticsRml(nil, options)
		view.diagnosticsText = DiagnosticsText(nil, options)
		view.hasDiagnostics = view.diagnosticsRml ~= ""
		view.diagnosticsExpanded = options.diagnosticsExpanded == true and view.hasDiagnostics
		return view
	end
	if not response then
		return view
	end

	view.statusText = "Ready"
	view.apiClientVersion = ApiClientVersion(response)
	view.noticeText = ClientUpdateNotice(response)
	view.hasNotice = view.noticeText ~= ""
	view.hasUpdate = view.hasNotice
	if view.hasUpdate then
		view.updateHelpText = view.noticeText .. ". Click to copy the installation link."
	end
	if view.hasNotice then
		view.statusText = "Update"
	end
	view.difficultyText = "-"
	local estimate = response.difficulty_estimate
	local aiType = tostring(request and request.ai_type or "PvE")
	local trainingGames = type(estimate) == "table" and tonumber(estimate.evidence_games) or nil
	view.winsLabelText = "Win Chance"
	view.exactWinsText = type(estimate) == "table" and (PercentText(estimate.player_win_probability) or "-") or "-"
	view.extendedWinsText = trainingGames and FormatNumber(trainingGames, 0) or "-"
	view.evidenceGamesLabel = "Difficulty Percentile"
	local histogram = response.difficulty_histogram
	local playedPercentile = type(histogram) == "table" and tonumber(histogram.current_percentile) or nil
	view.evidenceGamesText = playedPercentile and ("P" .. FormatNumber(playedPercentile, 0)) or "Unplaced"
	view.winChanceHelpText = "Estimated chance that a representative current BAR human team wins this map and effective setup. It uses team size and relevant encounter context, but not the identities or skill ratings of the players currently in the lobby."
	view.difficultyPercentileHelpText = playedPercentile
		and ("This setup's challenge score is harder than approximately " .. FormatNumber(playedPercentile, 0) .. "% of eligible played " .. aiType .. " games.")
		or ("This setup has not been placed in the eligible played " .. aiType .. " game distribution.")
	view.trainingGamesHelpText = trainingGames
		and (FormatNumber(trainingGames, 0) .. " eligible " .. aiType .. " games were used to train this model after validity and grace-period filtering. This is overall model data, not the number of exact or nearby matches and not a confidence score.")
		or ("Eligible " .. aiType .. " games train the model after validity and grace-period filtering. This is overall model data, not the number of exact or nearby matches and not a confidence score.")
	view.matchText = MatchResultText(response)
	if IsClosestResponse(response) then
		local topMatch = TopClosestMatch(response)
		if topMatch and tostring(topMatch.match_method or "") == "raw_fallback" then
			view.matchHelpText = "Raw fallback compares available lobby fields for the setting-specific statistics and differences shown below. The overlap is not model confidence and does not determine whether either setup is harder. Match selection is separate from Win Chance."
		else
			view.matchHelpText = "Similarity summarizes the selected comparison used for the setting-specific statistics and differences shown below. A score of 1.000 is the closest possible match; it is not confidence and does not say which setup is harder. Match selection is separate from Win Chance."
		end
	end
	view.sourceWindowText = SourceWindowText(response, options)
	view.hasSourceWindow = view.sourceWindowText ~= "-"
	view.isExactMatch = IsExactMatch(response)
	view.diffsRml, view.hasDiffs = ClosestDiffsRml(response, options)
	view.evidenceSummaryRml = EvidenceSummaryRml(response)
	view.hasEvidenceSummary = view.evidenceSummaryRml ~= ""
	view.diagnosticsRml = DiagnosticsRml(response, options)
	view.diagnosticsText = DiagnosticsText(response, options)
	view.hasDiagnostics = view.diagnosticsRml ~= ""
	view.diagnosticsExpanded = options.diagnosticsExpanded == true and view.hasDiagnostics
	view.histogramRml, view.histogramCaption, view.hasHistogram = DifficultyHistogramRml(response, request)
	local displayedPlayers = PlayersWithUnresolvedNames(response)
	local activePlayers, spectators = SplitPlayers(
		displayedPlayers,
		request,
		tabDefinition,
		view.sortColumn,
		view.sortDescending
	)
	local rowOptions = {
		playerTab = view.playerTab,
		ownPlayerId = request and request._own_player_id,
		ownPlayerName = request and request._own_player_name,
	}
	if view.showSpectators then
		local spectatorOptions = CopyTable(rowOptions)
		spectatorOptions.showColors = false
		view.playersRml = table.concat({
			PlayerGroupRml("Players", activePlayers, colorLookup, "No player stats", rowOptions),
			"\n",
			PlayerGroupRml("Spectators", spectators, colorLookup, "No spectator stats", spectatorOptions),
		})
	else
		view.playersRml = Model.PlayerRowsRml(activePlayers, colorLookup, rowOptions)
	end
	view.hasPlayers = #displayedPlayers > 0
	return view
end

return Model
