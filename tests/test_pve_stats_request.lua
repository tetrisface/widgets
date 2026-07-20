local root = PVE_STATS_TEST_ROOT or (arg and arg[1]) or "./"
local T = dofile(root .. "tests/support.lua")
local Request = dofile(root .. "include/request.lua")

local function RaptorsSpring()
	return {
		GetModOptionsCopy = function() return { stale = "old", startmetal = 1000 } end,
		GetModOptions = function() return { stale = "new", scav_boss_count = 8 } end,
		GetMyPlayerID = function() return 1 end,
		GetPlayerList = function() return {1, 2, 3} end,
		GetPlayerInfo = function(playerID)
			local players = {
				[1] = {"Alice", false, 10, {accountid = "101"}},
				[2] = {"Bob", false, 11, {accountID = 202}},
				[3] = {"Spectator", true, 12, {account_id = 303}},
			}
			local player = players[playerID]
			return player[1], nil, player[2], player[3], nil, nil, nil, nil, nil, player[4]
		end,
		GetTeamInfo = function(teamID)
			local multipliers = {[10] = 1, [11] = 1.25}
			return nil, nil, nil, false, nil, nil, multipliers[teamID]
		end,
		GetTeamList = function() return {} end,
		GetTeamColor = function(teamID)
			if teamID == 10 then return 0.1, 0.2, 0.3 end
			return 0.4, 0.5, 0.6
		end,
		Utilities = {Gametype = {IsRaptors = function() return true end, IsScavengers = function() return false end}},
	}
end

local function testBuildUsesTheLobbyDomain()
	local request = assert(Request.Build(RaptorsSpring(), {mapName = "Supreme Isthmus"}))
	T.equals(request.ai_type, "Raptors")
	T.equals(request.map, "Supreme Isthmus")
	T.equals(request.game_settings.stale, "new")
	T.equals(request.encounter_context.human_team_size, 2)
	T.equals(request.encounter_context.human_player_income_multipliers[2], 1.25)
	T.equals(request.player_names[3], "Spectator")
	T.equals(request.player_ids[3], 303)
	T.equals(request._own_player_id, 101)
	T.truthy(request._request_key)
end

local function testAiDetectionFailsClosedWhenNamedTeamsConflict()
	local spring = {
		GetTeamList = function() return {1, 2} end,
		GetAIInfo = function(teamID) return teamID, teamID == 1 and "Raptors" or "Scavengers" end,
		GetTeamInfo = function() return nil, nil, nil, true end,
	}
	local request, err = Request.Build(spring, {mapName = "Map"})
	T.equals(request, nil)
	T.equals(err, "ambiguous_team_ai_identity")
end

local function testGenericAiFallsBackToBarbarian()
	local spring = {
		GetTeamList = function() return {4} end,
		GetAIInfo = function() return 9, "Generic AI" end,
		GetTeamInfo = function() return nil, nil, nil, true, nil, nil, 1.5 end,
		GetPlayerList = function() return {} end,
		GetModOptions = function() return {} end,
	}
	local request = assert(Request.Build(spring, {mapName = "Delta Siege"}))
	T.equals(request.ai_type, "Barbarian")
	T.equals(request.encounter_context.enemy_ai_count, 1)
	T.equals(request.encounter_context.enemy_ai_income_multipliers[1], 1.5)
end

local function testScavengerModeUsesTheSingleControllerEncounter()
	local spring = {
		Utilities = {Gametype = {
			IsRaptors = function() return false end,
			IsScavengers = function() return true end,
		}},
		GetTeamList = function() return {4, 5} end,
		GetAIInfo = function(teamID) return teamID, "Scavengers" end,
		GetTeamInfo = function() return nil, nil, nil, true, nil, nil, 2 end,
		GetPlayerList = function() return {} end,
		GetModOptions = function() return {} end,
	}
	local request = assert(Request.Build(spring, {mapName = "Scavenger Map"}))
	T.equals(request.ai_type, "Scavengers")
	T.equals(request.encounter_context.enemy_ai_count, nil)
end

local function testWireRequestIsAPositiveAllowlist()
	local request = assert(Request.Build(RaptorsSpring(), {mapName = "Map"}))
	request.future_internal_value = "must not leave"
	request._another_private_value = "must not leave"
	local wire = assert(Request.Wire(request))
	local expected = {
		ai_type = true, map = true, game_settings = true, encounter_context = true,
		player_names = true, player_ids = true, player_filter_requested = true,
	}
	local count = 0
	for key in pairs(wire) do
		T.truthy(expected[key], "unexpected wire key " .. tostring(key))
		count = count + 1
	end
	T.equals(count, 7)
	T.equals(wire.future_internal_value, nil)
	T.equals(wire._another_private_value, nil)
end

local function testWireValidationRejectsInvalidInputs()
	local wire, err = Request.Wire({ai_type = "Raptors"})
	T.equals(wire, nil)
	T.equals(err, "invalid_map")
	wire, err = Request.Wire({
		ai_type = "Raptors", map = "Map", game_settings = {}, encounter_context = {},
		player_names = {2}, player_ids = {}, player_filter_requested = true,
	})
	T.equals(wire, nil)
	T.equals(err, "invalid_players")
end

local function RequestForIdentity(settings, encounter)
	return T.request({
		map = "Map", game_settings = settings,
		encounter_context = encounter, player_names = {"A"}, player_ids = {1},
	})
end

local function testCanonicalIdentitySupportsNestedData()
	local left = RequestForIdentity({b = 2, a = {true, "x"}}, {multipliers = {1, 1.25}})
	local right = RequestForIdentity({a = {true, "x"}, b = 2}, {multipliers = {1, 1.25}})
	T.equals(Request.SettingKey(left), Request.SettingKey(right))
	T.equals(Request.Key(left), Request.Key(right))
	right.encounter_context.multipliers[2] = 1.5
	T.truthy(Request.SettingKey(left) ~= Request.SettingKey(right))
	T.truthy(Request.SettingKey(RequestForIdentity({value = 1}, {}))
		~= Request.SettingKey(RequestForIdentity({value = "1"}, {})))
end

local function testCanonicalIdentityRejectsUnsupportedAndCyclicValues()
	local unsupported = RequestForIdentity({value = function() end}, {})
	local key, err = Request.SettingKey(unsupported)
	T.equals(key, nil)
	T.equals(err, "unsupported_type:function")
	local cycle = {}
	cycle.self = cycle
	local cyclicRequest = RequestForIdentity(cycle, {})
	key, err = Request.SettingKey(cyclicRequest)
	T.equals(key, nil)
	T.equals(err, "cyclic_table")
	key, err = Request.Key(cyclicRequest)
	T.equals(key, nil)
	T.equals(err, "cyclic_table")
end

local function testPlayerColorsAreCapturedAtTheEngineBoundary()
	local colors = Request.PlayerColorLookup(RaptorsSpring())
	T.equals(colors.Alice, "#1A334D")
	T.equals(colors[101], "#1A334D")
	T.equals(colors.Spectator, nil)
end

testBuildUsesTheLobbyDomain()
testAiDetectionFailsClosedWhenNamedTeamsConflict()
testGenericAiFallsBackToBarbarian()
testScavengerModeUsesTheSingleControllerEncounter()
testWireRequestIsAPositiveAllowlist()
testWireValidationRejectsInvalidInputs()
testCanonicalIdentitySupportsNestedData()
testCanonicalIdentityRejectsUnsupportedAndCyclicValues()
testPlayerColorsAreCapturedAtTheEngineBoundary()

print("test_pve_stats_request.lua: ok")
