local Request = {}

local WIRE_FIELDS = {
	"ai_type",
	"map",
	"game_settings",
	"encounter_context",
	"player_names",
	"player_ids",
	"player_filter_requested",
}

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
	local modOptions = {}
	for key, value in pairs(SafeCall(springApi, "GetModOptionsCopy") or {}) do
		modOptions[key] = value
	end
	for key, value in pairs(SafeCall(springApi, "GetModOptions") or {}) do
		modOptions[key] = value
	end
	return modOptions
end

local function ContainsFolded(value, pattern)
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
	local hasRaptors = ContainsFolded(value, "raptors") or ContainsFolded(value, "raptor")
	local hasScavengers = ContainsFolded(value, "scavengers") or ContainsFolded(value, "scavenger")
	if hasRaptors and not hasScavengers then
		return "Raptors"
	end
	if hasScavengers and not hasRaptors then
		return "Scavengers"
	end
	if hasRaptors and hasScavengers then
		return nil
	end
	if ContainsFolded(value, "barbarian") or ContainsFolded(value, "barb") then
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

	local aiType, source = AiTypeFromSeenTeams(seen)
	if aiType then
		return aiType, source, EnemyAiCount(aiType), seenTeamIds[aiType] or {}
	end
	if source then
		return nil, source
	end
	if genericAiTeamCount > 0 then
		return "Barbarian", "generic_ai_team", genericAiTeamCount, genericAiTeamIds
	end
	return nil, "missing_ai_type"
end

function Request.DetectAiType(springApi)
	local aiType = DetectAiTypeWithSource(springApi)
	return aiType
end

local function CollectPlayers(springApi)
	local allNames = {}
	local allIds = {}
	local activeNames = {}
	local activeIds = {}
	local spectatorNames = {}
	local spectatorIds = {}
	local activeTeamIds = {}
	local seenNames = {}
	local seenIds = {}
	local ownPlayerID = SafeCall(springApi, "GetMyPlayerID")
	local ownPlayerName = nil
	local ownAccountID = nil

	for _, playerID in ipairs(SafeCall(springApi, "GetPlayerList") or {}) do
		local name, _, spectator, teamID, _, _, _, _, _, customKeys, extraInfo = SafeCall(
			springApi,
			"GetPlayerInfo",
			playerID,
			false
		)
		if name then
			local groupNames = spectator and spectatorNames or activeNames
			AddUnique(allNames, seenNames, name)
			groupNames[#groupNames + 1] = name

			local accountID = AccountIdFromInfo(customKeys, extraInfo)
			if accountID then
				local groupIds = spectator and spectatorIds or activeIds
				AddUnique(allIds, seenIds, accountID)
				groupIds[#groupIds + 1] = accountID
			end
			if not spectator and teamID ~= nil then
				activeTeamIds[#activeTeamIds + 1] = teamID
			end
			if playerID == ownPlayerID then
				ownPlayerName = name
				ownAccountID = accountID
			end
		end
	end

	table.sort(allNames)
	table.sort(allIds)
	table.sort(activeNames)
	table.sort(activeIds)
	table.sort(spectatorNames)
	table.sort(spectatorIds)

	return allNames, allIds, {
		active_player_names = activeNames,
		active_player_ids = activeIds,
		spectator_names = spectatorNames,
		spectator_ids = spectatorIds,
		own_player_name = ownPlayerName,
		own_player_id = ownAccountID,
		active_player_team_ids = activeTeamIds,
	}
end

function Request.CollectPlayers(springApi)
	return CollectPlayers(springApi)
end

local function ColorByte(value)
	local number = math.max(0, math.min(1, tonumber(value) or 1))
	return math.floor(number * 255 + 0.5)
end

function Request.PlayerColorLookup(springApi)
	local lookup = {}
	for _, playerID in ipairs(SafeCall(springApi, "GetPlayerList") or {}) do
		local name, _, spectator, teamID, _, _, _, _, _, customKeys, extraInfo = SafeCall(
			springApi,
			"GetPlayerInfo",
			playerID,
			false
		)
		if name and spectator == false and teamID ~= nil then
			local red, green, blue = SafeCall(springApi, "GetTeamColor", teamID)
			if red ~= nil and green ~= nil and blue ~= nil then
				local color = string.format("#%02X%02X%02X", ColorByte(red), ColorByte(green), ColorByte(blue))
				lookup[name] = color
				local accountID = AccountIdFromInfo(customKeys, extraInfo)
				if accountID then
					lookup[accountID] = color
					lookup[tostring(accountID)] = color
				end
			end
		end
	end
	return lookup
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

local function IsArray(value)
	local count = 0
	local maximum = 0
	for key in pairs(value) do
		if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
			return false
		end
		count = count + 1
		maximum = math.max(maximum, key)
	end
	return maximum == count
end

local function AppendCanonical(parts, value, active)
	local valueType = type(value)
	if valueType == "nil" then
		parts[#parts + 1] = "z;"
		return true
	end
	if valueType == "boolean" then
		parts[#parts + 1] = value and "b1;" or "b0;"
		return true
	end
	if valueType == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return false, "unsupported_number"
		end
		parts[#parts + 1] = "n"
		parts[#parts + 1] = string.format("%.17g", value)
		parts[#parts + 1] = ";"
		return true
	end
	if valueType == "string" then
		parts[#parts + 1] = "s"
		parts[#parts + 1] = tostring(#value)
		parts[#parts + 1] = ":"
		parts[#parts + 1] = value
		parts[#parts + 1] = ";"
		return true
	end
	if valueType ~= "table" then
		return false, "unsupported_type:" .. valueType
	end
	if active[value] then
		return false, "cyclic_table"
	end

	active[value] = true
	if IsArray(value) then
		parts[#parts + 1] = "a["
		for index = 1, #value do
			local ok, err = AppendCanonical(parts, value[index], active)
			if not ok then
				active[value] = nil
				return false, err
			end
		end
		parts[#parts + 1] = "]"
	else
		local entries = {}
		for key, entryValue in pairs(value) do
			local keyParts = {}
			local ok, err = AppendCanonical(keyParts, key, {})
			if not ok then
				active[value] = nil
				return false, err
			end
			entries[#entries + 1] = {
				key = key,
				value = entryValue,
				encodedKey = table.concat(keyParts),
			}
		end
		table.sort(entries, function(left, right)
			return left.encodedKey < right.encodedKey
		end)
		parts[#parts + 1] = "m{"
		for _, entry in ipairs(entries) do
			parts[#parts + 1] = entry.encodedKey
			local ok, err = AppendCanonical(parts, entry.value, active)
			if not ok then
				active[value] = nil
				return false, err
			end
		end
		parts[#parts + 1] = "}"
	end
	active[value] = nil
	return true
end

local function CanonicalKey(value)
	local parts = {}
	local ok, err = AppendCanonical(parts, value, {})
	if not ok then
		return nil, err
	end
	return table.concat(parts)
end

function Request.SettingKey(request)
	if not request then
		return nil, "missing_request"
	end
	return CanonicalKey({
		ai_type = request.ai_type,
		map = request.map,
		encounter_context = request.encounter_context or {},
		game_settings = request.game_settings or {},
	})
end

function Request.Key(request)
	if not request then
		return nil, "missing_request"
	end
	local settingKey, settingError = Request.SettingKey(request)
	if not settingKey then return nil, settingError end
	return CanonicalKey({
		setting_key = settingKey,
		player_ids = request.player_ids or {},
		player_names = request.player_names or {},
		player_filter_requested = request.player_filter_requested == true,
	})
end

local function IsStringArray(values)
	if type(values) ~= "table" or not IsArray(values) then
		return false
	end
	for _, value in ipairs(values) do
		if type(value) ~= "string" then
			return false
		end
	end
	return true
end

local function IsPositiveNumberArray(values)
	if type(values) ~= "table" or not IsArray(values) then
		return false
	end
	for _, value in ipairs(values) do
		if type(value) ~= "number" or value <= 0 then
			return false
		end
	end
	return true
end

function Request.Wire(request)
	if type(request) ~= "table" then
		return nil, "invalid_request"
	end
	if type(request.ai_type) ~= "string" or request.ai_type == "" then
		return nil, "invalid_ai_type"
	end
	if type(request.map) ~= "string" or request.map == "" then
		return nil, "invalid_map"
	end
	if type(request.game_settings) ~= "table" or type(request.encounter_context) ~= "table" then
		return nil, "invalid_context"
	end
	if not IsStringArray(request.player_names) or not IsPositiveNumberArray(request.player_ids) then
		return nil, "invalid_players"
	end

	local wire = {}
	for _, field in ipairs(WIRE_FIELDS) do
		wire[field] = request[field]
	end
	wire.player_filter_requested = request.player_filter_requested == true
	return wire
end

function Request.Build(springApi, gameApi)
	local aiType, aiTypeSource, enemyAiCount, enemyAiTeamIds = DetectAiTypeWithSource(springApi)
	if not aiType then
		return nil, aiTypeSource or "missing_ai_type"
	end

	local mapName = gameApi and (gameApi.mapName or gameApi.map_name)
	if not mapName or tostring(mapName) == "" then
		return nil, "missing_map"
	end

	local playerNames, playerIds, playerGroups = CollectPlayers(springApi)
	local encounterContext = {
		human_team_size = #(playerGroups.active_player_names or {}),
	}
	local humanMultipliers = TeamIncomeMultipliers(springApi, playerGroups.active_player_team_ids)
	if #humanMultipliers > 0 then
		encounterContext.human_player_income_multipliers = humanMultipliers
	end

	-- Raptor and Scavenger Lua AIs are boolean activators for one backend
	-- controller. Repeated lobby AI slots do not increase encounter strength.
	-- BARbarian slots are separate opponents, so their count remains meaningful.
	if aiType == "Barbarian" and enemyAiCount then
		encounterContext.enemy_ai_count = enemyAiCount
		local enemyMultipliers = TeamIncomeMultipliers(springApi, enemyAiTeamIds)
		if #enemyMultipliers > 0 then
			encounterContext.enemy_ai_income_multipliers = enemyMultipliers
		end
	end

	local request = {
		ai_type = aiType,
		map = tostring(mapName),
		game_settings = CollectModOptions(springApi),
		encounter_context = encounterContext,
		player_names = playerNames,
		player_ids = playerIds,
		player_filter_requested = true,
		_spectator_names = playerGroups.spectator_names,
		_spectator_ids = playerGroups.spectator_ids,
		_own_player_name = playerGroups.own_player_name,
		_own_player_id = playerGroups.own_player_id,
	}
	local key, keyError = Request.Key(request)
	if not key then
		return nil, keyError
	end
	request._request_key = key
	return request
end

return Request
