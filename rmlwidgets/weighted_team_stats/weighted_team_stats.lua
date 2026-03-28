if not RmlUi then
	return
end

local widget = widget ---@type Widget
local WIDGET_NAME = 'Weighted Team Stats'
local MODEL_NAME = 'weighted_team_stats'
local RML_PATH = 'luaui/rmlwidgets/weighted_team_stats/weighted_team_stats.rml'
local STATS_UPDATE_FREQUENCY = 60 -- ~2 seconds
local UI_UPDATE_FREQUENCY = 30 -- ~1 second

function widget:GetInfo()
	return {
		name = WIDGET_NAME,
		desc = 'Time-weighted team statistics with inflation adjustment',
		author = 'tetrisface',
		date = '2026',
		license = 'GNU GPL, v2 or later',
		layer = 5,
		enabled = true,
		handler = true,
	}
end

--------------------------------------------------------------------------------
-- Localized Spring API
--------------------------------------------------------------------------------

local spGetTeamStatsHistory = Spring.GetTeamStatsHistory
local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetTeamList = Spring.GetTeamList
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamColor = Spring.GetTeamColor
local spGetPlayerInfo = Spring.GetPlayerInfo
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetSpectatingState = Spring.GetSpectatingState
local spGetMyTeamID = Spring.GetMyTeamID
local spGetMyAllyTeamID = Spring.GetMyAllyTeamID
local spIsGUIHidden = Spring.IsGUIHidden
local spGetConfigString = Spring.GetConfigString
local spSetConfigString = Spring.SetConfigString
local spGetViewGeometry = Spring.GetViewGeometry
local spGetModKeyState = Spring.GetModKeyState
local spGetMouseState = Spring.GetMouseState

local glColor = gl.Color
local glRect = gl.Rect
local glBeginEnd = gl.BeginEnd
local glVertex = gl.Vertex
local glLineWidth = gl.LineWidth
local glText = gl.Text
local glCreateList = gl.CreateList
local glCallList = gl.CallList
local glDeleteList = gl.DeleteList
local GL_TRIANGLE_STRIP = GL.TRIANGLE_STRIP
local GL_LINE_STRIP = GL.LINE_STRIP

local math_max = math.max
local math_min = math.min
local math_floor = math.floor
local string_format = string.format

--------------------------------------------------------------------------------
-- Layer A: Stats Engine (pure math, no Spring API)
--------------------------------------------------------------------------------

local StatsEngine = {}

StatsEngine.STAT_KEYS = {
	'damageDealt', 'damageReceived',
	'metalProduced', 'metalUsed', 'metalExcess', 'metalSent', 'metalReceived',
	'energyProduced', 'energyUsed', 'energyExcess', 'energySent', 'energyReceived',
	'unitsProduced', 'unitsKilled', 'unitsDied',
}

StatsEngine.ECO_DEFLATOR_STATS = {
	metalProduced = true, metalUsed = true, metalExcess = true, metalSent = true, metalReceived = true,
	energyProduced = true, energyUsed = true, energyExcess = true, energySent = true, energyReceived = true,
	unitsProduced = true,
}

StatsEngine.MIL_DEFLATOR_STATS = {
	damageDealt = true, damageReceived = true,
	unitsKilled = true, unitsDied = true,
}

StatsEngine.INDEX_WEIGHTS = {
	damageDealt = 0.20,
	metalProduced = 0.15,
	energyProduced = 0.10,
	metalExcess = 0.15,
	energyExcess = 0.10,
	metalSent = 0.10,
	energySent = 0.05,
	unitsKilled = 0.10,
	metalUsed = 0.05,
}

--- Compute per-window deltas from cumulative snapshots.
--- @param snapshots table[] Array of cumulative stat snapshots with .frame field
--- @return table[] deltas Array of per-window delta tables with .frame and .dt fields
function StatsEngine.ComputeDeltas(snapshots)
	local deltas = {}
	for i = 2, #snapshots do
		local prev = snapshots[i - 1]
		local curr = snapshots[i]
		local delta = { frame = curr.frame }
		delta.dt = curr.frame - prev.frame
		if delta.dt <= 0 then
			delta.dt = 1
		end
		for _, key in ipairs(StatsEngine.STAT_KEYS) do
			local val = (curr[key] or 0) - (prev[key] or 0)
			delta[key] = math_max(val, 0) -- clamp negative deltas (shouldn't happen but guard)
		end
		deltas[#deltas + 1] = delta
	end
	return deltas
end

--- Aggregate consecutive deltas into larger windows.
--- @param deltas table[] Array of per-window delta tables
--- @param factor number Number of deltas to merge into one window
--- @return table[] aggregated Array of aggregated delta tables
function StatsEngine.AggregateDeltas(deltas, factor)
	if factor <= 1 then return deltas end
	local result = {}
	for i = 1, #deltas, factor do
		local merged = { frame = 0, dt = 0 }
		for _, key in ipairs(StatsEngine.STAT_KEYS) do
			merged[key] = 0
		end
		local count = 0
		for j = i, math_min(i + factor - 1, #deltas) do
			local d = deltas[j]
			merged.frame = d.frame -- use last frame in group
			merged.dt = merged.dt + d.dt
			for _, key in ipairs(StatsEngine.STAT_KEYS) do
				merged[key] = merged[key] + (d[key] or 0)
			end
			count = count + 1
		end
		if count > 0 then
			result[#result + 1] = merged
		end
	end
	return result
end

--- Smoothing modes for share computation.
--- 'laplace': Bayesian smoothing — adds a prior so low-activity windows pull toward 1/N.
--- 'relativistic': Weight each window's share contribution by its deflated magnitude.
---                  Low-activity windows contribute less. Uses deflation to keep early windows relevant.
StatsEngine.SMOOTHING_MODES = { 'laplace', 'relativistic' }

--- Compute weighted stats for all teams in an ally group.
--- @param allDeltas table<number, table[]> Map of teamID -> deltas array
--- @param smoothingMode string 'laplace' or 'relativistic'
--- @return table<number, table<string, number>> shares Map of teamID -> { statKey -> average_share }
--- @return table<number, table<string, number>> deflated Map of teamID -> { statKey -> deflated_total }
--- @return table<number, table<string, number[]>> perWindowShares Map of teamID -> { statKey -> share_per_window[] }
--- @return table<number, table<string, number[]>> perWindowRaw Map of teamID -> { statKey -> raw_delta_per_window[] }
--- @return table<number, table<string, number[]>> perWindowDeflated Map of teamID -> { statKey -> deflated_delta_per_window[] }
--- @return table<number, table<string, number>> efficiency Map of teamID -> { damagePerMetal, damagePerEnergy, damagePerResource }
function StatsEngine.ComputeWeightedStats(allDeltas, smoothingMode)
	smoothingMode = smoothingMode or 'laplace'

	local teamIDs = {}
	local windowCount = math.huge
	for teamID, deltas in pairs(allDeltas) do
		teamIDs[#teamIDs + 1] = teamID
		if #deltas < windowCount then
			windowCount = #deltas
		end
	end
	if windowCount == 0 or windowCount == math.huge then
		return {}, {}, {}, {}, {}, {}
	end

	-- Compute per-window deflators
	local ecoDeflators = {}
	local milDeflators = {}
	for w = 1, windowCount do
		local totalEco = 0
		local totalMil = 0
		for _, teamID in ipairs(teamIDs) do
			local d = allDeltas[teamID][w]
			totalEco = totalEco + (d.metalProduced or 0) + (d.energyProduced or 0)
			totalMil = totalMil + (d.damageDealt or 0)
		end
		ecoDeflators[w] = math_max(totalEco, 1)
		milDeflators[w] = math_max(totalMil, 1)
	end
	local baseEco = ecoDeflators[1]
	local baseMil = milDeflators[1]

	-- Initialize result tables
	local shares = {}
	local deflated = {}
	local perWindowShares = {}
	local perWindowRaw = {}
	local perWindowDeflated = {}
	for _, teamID in ipairs(teamIDs) do
		shares[teamID] = {}
		deflated[teamID] = {}
		perWindowShares[teamID] = {}
		perWindowRaw[teamID] = {}
		perWindowDeflated[teamID] = {}
		for _, key in ipairs(StatsEngine.STAT_KEYS) do
			shares[teamID][key] = 0
			deflated[teamID][key] = 0
			perWindowShares[teamID][key] = {}
			perWindowRaw[teamID][key] = {}
			perWindowDeflated[teamID][key] = {}
		end
	end

	local numPlayers = #teamIDs

	-- Compute per-window stats
	for _, statKey in ipairs(StatsEngine.STAT_KEYS) do
		local isMil = StatsEngine.MIL_DEFLATOR_STATS[statKey]

		-- First pass: compute totals needed for smoothing
		local totalAcrossAllWindows = 0
		for w = 1, windowCount do
			for _, teamID in ipairs(teamIDs) do
				local val = allDeltas[teamID][w][statKey] or 0
				if val > 0 then
					totalAcrossAllWindows = totalAcrossAllWindows + val
				end
			end
		end

		-- Laplace prior (used in 'laplace' mode)
		local priorDivisor = windowCount * numPlayers
		local prior = priorDivisor > 0 and (totalAcrossAllWindows / priorDivisor) or 0

		-- Relativistic: track total deflated weight for normalization
		local totalDeflatedWeight = 0

		for w = 1, windowCount do
			-- Sum across teams for this window
			local windowTotal = 0
			for _, teamID in ipairs(teamIDs) do
				local val = allDeltas[teamID][w][statKey] or 0
				if val > 0 then
					windowTotal = windowTotal + val
				end
			end

			local deflator = isMil and milDeflators[w] or ecoDeflators[w]
			local baseDeflator = isMil and baseMil or baseEco
			local deflationRatio = baseDeflator / deflator

			-- In relativistic mode, each window's weight is its deflated total
			-- This means early windows (boosted by deflation) contribute more,
			-- but tiny-activity windows still contribute proportionally little
			local windowDeflatedTotal = windowTotal * deflationRatio
			if smoothingMode == 'relativistic' then
				totalDeflatedWeight = totalDeflatedWeight + windowDeflatedTotal
			end

			for _, teamID in ipairs(teamIDs) do
				local val = allDeltas[teamID][w][statKey] or 0
				if val < 0 then
					val = 0
				end

				-- Compute share based on smoothing mode
				local share
				if smoothingMode == 'relativistic' then
					-- Raw share (no smoothing), will be magnitude-weighted below
					if windowTotal > 0 then
						share = val / windowTotal
					else
						share = 0
					end
					-- Weight this window's share by its deflated magnitude
					shares[teamID][statKey] = shares[teamID][statKey] + share * windowDeflatedTotal
				else
					-- Laplace-smoothed contribution share
					-- (val + prior) / (windowTotal + numPlayers * prior)
					-- When windowTotal >> prior: converges to val/windowTotal
					-- When windowTotal << prior: converges to 1/numPlayers
					share = (val + prior) / (windowTotal + numPlayers * prior)
					shares[teamID][statKey] = shares[teamID][statKey] + share
				end
				perWindowShares[teamID][statKey][w] = share

				-- Raw per-window
				perWindowRaw[teamID][statKey][w] = val

				-- Deflated value
				local deflatedVal = val * deflationRatio
				deflated[teamID][statKey] = deflated[teamID][statKey] + deflatedVal
				perWindowDeflated[teamID][statKey][w] = deflatedVal
			end
		end

		-- Normalize shares
		for _, teamID in ipairs(teamIDs) do
			if smoothingMode == 'relativistic' then
				-- Divide by total deflated weight (magnitude-weighted average)
				if totalDeflatedWeight > 0 then
					shares[teamID][statKey] = shares[teamID][statKey] / totalDeflatedWeight
				else
					shares[teamID][statKey] = 1 / numPlayers
				end
			else
				-- Simple average across windows (Laplace already smoothed per-window)
				shares[teamID][statKey] = shares[teamID][statKey] / windowCount
			end
		end
	end

	-- Rescale deflated totals so they're on a comparable magnitude to raw totals.
	-- Deflated values are in "window 1 units" which can be tiny late game.
	-- This preserves relative proportions between players while making numbers readable.
	for _, statKey in ipairs(StatsEngine.STAT_KEYS) do
		local totalRaw = 0
		local totalDefl = 0
		for _, teamID in ipairs(teamIDs) do
			local lastSnap = allDeltas[teamID]
			local rawSum = 0
			for w = 1, windowCount do
				rawSum = rawSum + (lastSnap[w][statKey] or 0)
			end
			totalRaw = totalRaw + rawSum
			totalDefl = totalDefl + deflated[teamID][statKey]
		end
		if totalDefl > 0 then
			local scale = totalRaw / totalDefl
			for _, teamID in ipairs(teamIDs) do
				deflated[teamID][statKey] = deflated[teamID][statKey] * scale
			end
		end
	end

	-- Compute inter-player efficiency: damage output relative to resource consumption
	-- "How much damage did you deal per unit of resources you consumed?"
	-- Helper to safely divide, returning 0 on NaN/inf
	local function safeDivide(a, b)
		if b <= 0 then
			return 0
		end
		local result = a / b
		if result ~= result or result == math.huge or result == -math.huge then
			return 0
		end
		return result
	end

	local efficiency = {}
	for _, teamID in ipairs(teamIDs) do
		local dmgShare = shares[teamID].damageDealt or 0
		local metalShare = shares[teamID].metalUsed or (1 / numPlayers)
		local energyShare = shares[teamID].energyUsed or (1 / numPlayers)
		local resourceShare = (metalShare + energyShare) / 2

		efficiency[teamID] = {
			-- Ratio of damage share to resource share
			-- > 1.0 means dealing more damage than your resource consumption would predict
			-- < 1.0 means consuming more resources than your damage output justifies
			damagePerResource = safeDivide(dmgShare, resourceShare),
			damagePerMetal = safeDivide(dmgShare, metalShare),
			damagePerEnergy = safeDivide(dmgShare, energyShare),
		}
	end

	return shares, deflated, perWindowShares, perWindowRaw, perWindowDeflated, efficiency
end

--- Compute a composite contribution index from a player's share row.
--- @param shareRow table<string, number> Map of statKey -> average_share
--- @return number index 0-100 contribution index
function StatsEngine.ComputeContributionIndex(shareRow)
	local index = 0
	local totalWeight = 0
	for statKey, weight in pairs(StatsEngine.INDEX_WEIGHTS) do
		local val = shareRow[statKey]
		-- Guard against NaN (NaN ~= NaN in Lua)
		if val and val == val then
			index = index + val * weight
			totalWeight = totalWeight + weight
		end
	end
	if totalWeight > 0 then
		index = index / totalWeight
	end
	-- Clamp to 0-100 range
	local result = math_floor(index * 100 + 0.5)
	if result ~= result then
		result = 0
	end
	return math_max(0, math_min(100, result))
end

--------------------------------------------------------------------------------
-- Layer B: Data Collection (Spring API)
--------------------------------------------------------------------------------

local gaiaTeamID
local cachedSnapshotCounts = {} -- [teamID] = last known snapshot count

--- Collect all team stat snapshots grouped by allyTeam.
--- @return table<number, table<number, table[]>> allyTeamSnapshots Map of allyTeamID -> { teamID -> snapshots[] }
local function CollectAllTeamSnapshots()
	local result = {}
	local gaiaAllyID
	if gaiaTeamID then
		gaiaAllyID = select(6, spGetTeamInfo(gaiaTeamID, false))
	end

	for _, allyID in ipairs(spGetAllyTeamList()) do
		if allyID ~= gaiaAllyID then
			local teams = spGetTeamList(allyID)
			if teams then
				local allySnapshots = {}
				local hasData = false
				for _, teamID in ipairs(teams) do
					local range = spGetTeamStatsHistory(teamID)
					if range and range > 1 then
						local history = spGetTeamStatsHistory(teamID, 0, range)
						if history and #history > 1 then
							allySnapshots[teamID] = history
							hasData = true
						end
					end
				end
				if hasData then
					result[allyID] = allySnapshots
				end
			end
		end
	end
	return result
end

--- Check if new snapshot data is available.
--- @return boolean hasNew True if any team has new snapshots since last check
local function HasNewSnapshots()
	local hasNew = false
	local gaiaAllyID
	if gaiaTeamID then
		gaiaAllyID = select(6, spGetTeamInfo(gaiaTeamID, false))
	end

	for _, allyID in ipairs(spGetAllyTeamList()) do
		if allyID ~= gaiaAllyID then
			local teams = spGetTeamList(allyID)
			if teams then
				for _, teamID in ipairs(teams) do
					local range = spGetTeamStatsHistory(teamID)
					if range and range ~= (cachedSnapshotCounts[teamID] or 0) then
						cachedSnapshotCounts[teamID] = range
						hasNew = true
					end
				end
			end
		end
	end
	return hasNew
end

--- Get player name and color for a team.
--- @param teamID number
--- @return string name Player or AI name
--- @return number r Red component 0-1
--- @return number g Green component 0-1
--- @return number b Blue component 0-1
local function GetTeamPlayerInfo(teamID)
	local _, leader, isDead, isAI = spGetTeamInfo(teamID, false)
	local name = 'Unknown'
	if isAI then
		local aiName = Spring.GetGameRulesParam('ainame_' .. teamID)
		name = aiName or ('AI ' .. teamID)
	elseif leader then
		local playerName = spGetPlayerInfo(leader, false)
		name = playerName or ('Team ' .. teamID)
	end
	local r, g, b = spGetTeamColor(teamID)
	return name, r or 1, g or 1, b or 1
end

--------------------------------------------------------------------------------
-- Layer C: Widget Lifecycle & RML Binding
--------------------------------------------------------------------------------

-- Widget state
local document
local dm_handle
local frameCounter = 0
local dataDirty = false
local graphDirty = false
local panelHeightSet = false
local isSpectator = false
local fullView = false
local myAllyTeamID

-- UI state
local widgetPosX = 100
local widgetPosY = 100
local tableVisible = true
local graphVisible = true
local viewMode = 'raw' -- 'raw' | 'share' | 'weighted'
local activeStat = 'damageDealt'
local graphMode = 'absolute' -- 'absolute' | 'normalized' | 'overlay'
local graphDeflated = false
local smoothingMode = 'laplace' -- always laplace
local sortKey = nil -- nil = sort by contribution index, or a stat key string
local sortAscending = false
local groupByAlly = true
local selectedAllyTeam = nil -- nil = first ally team, or an allyTeamID
local fontScale = 1.0
local windowAggregation = 8 -- merge N engine snapshots into one window
local lastUIHiddenState = false

-- Cached computation results
local cachedShares = {}
local cachedDeflated = {}
local cachedPerWindowShares = {}
local cachedPerWindowRaw = {}
local cachedPerWindowDeflated = {}
local cachedRawTotals = {} -- [teamID][statKey] = cumulative raw total
local cachedEfficiency = {} -- [teamID] = { damagePerResource, damagePerMetal, damagePerEnergy }
local cachedAllyTeams = {} -- { { allyID=N, teamIDs={...} }, ... }
local cachedTeamInfo = {} -- [teamID] = { name=str, r=N, g=N, b=N }
local windowCount = 0
local windowFrames = {} -- frame numbers for X-axis

-- Graph display list
local graphDisplayList
local graphAreaX, graphAreaY, graphAreaW, graphAreaH = 0, 0, 0, 0

-- Number formatting
local function FormatSI(value)
	if value >= 1e9 then
		return string_format('%.1fG', value / 1e9)
	elseif value >= 1e6 then
		return string_format('%.1fM', value / 1e6)
	elseif value >= 1e3 then
		return string_format('%.1fk', value / 1e3)
	elseif value >= 100 then
		return string_format('%.0f', value)
	elseif value >= 10 then
		return string_format('%.1f', value)
	else
		return string_format('%.2f', value)
	end
end

-- Position persistence
local function LoadPosition()
	local configString = spGetConfigString('WeightedTeamStats_Position', '')
	if configString and configString ~= '' then
		local x, y = configString:match('^(%d+),(%d+)$')
		if x and y then
			widgetPosX = tonumber(x)
			widgetPosY = tonumber(y)
		end
	end
end

local function SavePosition()
	spSetConfigString('WeightedTeamStats_Position', widgetPosX .. ',' .. widgetPosY)
end

local function LoadUIState()
	viewMode = spGetConfigString('WeightedTeamStats_ViewMode', 'raw')
	activeStat = spGetConfigString('WeightedTeamStats_ActiveStat', 'damageDealt')
	graphMode = spGetConfigString('WeightedTeamStats_GraphMode', 'absolute')
	graphDeflated = spGetConfigString('WeightedTeamStats_GraphDeflated', 'false') == 'true'
	tableVisible = spGetConfigString('WeightedTeamStats_TableVisible', 'true') == 'true'
	graphVisible = spGetConfigString('WeightedTeamStats_GraphVisible', 'true') == 'true'
	windowAggregation = tonumber(spGetConfigString('WeightedTeamStats_WindowAggregation', '8')) or 8
	groupByAlly = spGetConfigString('WeightedTeamStats_GroupByAlly', 'true') == 'true'
	fontScale = tonumber(spGetConfigString('WeightedTeamStats_FontScale', '1.0')) or 1.0
	local savedSortKey = spGetConfigString('WeightedTeamStats_SortKey', '')
	sortKey = savedSortKey ~= '' and savedSortKey or nil
	sortAscending = spGetConfigString('WeightedTeamStats_SortAscending', 'false') == 'true'
	local savedAllyTeam = tonumber(spGetConfigString('WeightedTeamStats_SelectedAllyTeam', ''))
	selectedAllyTeam = savedAllyTeam
end

local function SaveUIState()
	spSetConfigString('WeightedTeamStats_ViewMode', viewMode)
	spSetConfigString('WeightedTeamStats_ActiveStat', activeStat)
	spSetConfigString('WeightedTeamStats_GraphMode', graphMode)
	spSetConfigString('WeightedTeamStats_GraphDeflated', tostring(graphDeflated))

	spSetConfigString('WeightedTeamStats_TableVisible', tostring(tableVisible))
	spSetConfigString('WeightedTeamStats_GraphVisible', tostring(graphVisible))
	spSetConfigString('WeightedTeamStats_WindowAggregation', tostring(windowAggregation))
	spSetConfigString('WeightedTeamStats_GroupByAlly', tostring(groupByAlly))
	spSetConfigString('WeightedTeamStats_FontScale', tostring(fontScale))
	spSetConfigString('WeightedTeamStats_SortKey', sortKey or '')
	spSetConfigString('WeightedTeamStats_SortAscending', tostring(sortAscending))
	spSetConfigString('WeightedTeamStats_SelectedAllyTeam', selectedAllyTeam and tostring(selectedAllyTeam) or '')
end

local function UpdateDocumentPosition()
	if document then
		local panel = document:GetElementById('wts-panel')
		if panel then
			local currentLeft = panel.style.left
			local currentTop = panel.style.top
			if not currentLeft or currentLeft == '' or not currentTop or currentTop == '' then
				panel.style.left = widgetPosX .. 'px'
				panel.style.top = widgetPosY .. 'px'
			end
		end
	end
end

--- Recompute all weighted stats from fresh snapshots.
local function RecomputeStats()
	local allSnapshots = CollectAllTeamSnapshots()

	cachedAllyTeams = {}
	cachedTeamInfo = {}

	for allyID, teamSnapshots in pairs(allSnapshots) do
		local teamIDs = {}
		local allDeltas = {}

		for teamID, snapshots in pairs(teamSnapshots) do
			teamIDs[#teamIDs + 1] = teamID
			allDeltas[teamID] = StatsEngine.AggregateDeltas(StatsEngine.ComputeDeltas(snapshots), windowAggregation)

			-- Cache team info
			local name, r, g, b = GetTeamPlayerInfo(teamID)
			cachedTeamInfo[teamID] = { name = name, r = r, g = g, b = b }

			-- Cache raw totals from last snapshot
			local lastSnap = snapshots[#snapshots]
			cachedRawTotals[teamID] = {}
			for _, key in ipairs(StatsEngine.STAT_KEYS) do
				cachedRawTotals[teamID][key] = lastSnap[key] or 0
			end
		end

		cachedAllyTeams[#cachedAllyTeams + 1] = { allyID = allyID, teamIDs = teamIDs }

		local shares, deflated, perWindowShares, perWindowRaw, perWindowDeflated, efficiency =
			StatsEngine.ComputeWeightedStats(allDeltas, smoothingMode)

		for teamID, s in pairs(shares) do
			cachedShares[teamID] = s
		end
		for teamID, e in pairs(efficiency) do
			cachedEfficiency[teamID] = e
		end
		for teamID, d in pairs(deflated) do
			cachedDeflated[teamID] = d
		end
		for teamID, pw in pairs(perWindowShares) do
			cachedPerWindowShares[teamID] = pw
		end
		for teamID, pw in pairs(perWindowRaw) do
			cachedPerWindowRaw[teamID] = pw
		end
		for teamID, pw in pairs(perWindowDeflated) do
			cachedPerWindowDeflated[teamID] = pw
		end

		-- Extract window frames from first team's deltas
		if #teamIDs > 0 then
			local firstDeltas = allDeltas[teamIDs[1]]
			windowCount = #firstDeltas
			windowFrames = {}
			for w = 1, windowCount do
				windowFrames[w] = firstDeltas[w].frame
			end
		end
	end
end

--- Build the stat columns array for the data model.
local STAT_COLUMN_DEFS = {
	{ key = 'unitsKilled', label = 'Kills' },
	{ key = 'damageDealt', label = 'Dmg' },
	{ key = 'metalProduced', label = 'Metal' },
	{ key = 'energyProduced', label = 'Energy' },
	{ key = 'metalExcess', label = 'M Exc' },
	{ key = 'energyExcess', label = 'E Exc' },
	{ key = 'metalSent', label = 'M Sent' },
}

local function BuildStatColumns()
	local columns = {}
	for _, def in ipairs(STAT_COLUMN_DEFS) do
		local isSorted = sortKey == def.key
		columns[#columns + 1] = {
			key = def.key,
			label = def.label,
			active = (activeStat == def.key),
			sort_asc = isSorted and sortAscending,
			sort_desc = isSorted and not sortAscending,
		}
	end
	return columns
end

--- Update RML data model from cached results.
local function UpdateRMLuiData()
	if not dm_handle then
		return
	end

	local hasData = windowCount > 0
	local allyTeamsData = {}
	local statColumns = BuildStatColumns()

	for _, allyInfo in ipairs(cachedAllyTeams) do
		local players = {}
		for _, teamID in ipairs(allyInfo.teamIDs) do
			local info = cachedTeamInfo[teamID]
			if info then
				local displayValues = {}
				for _, col in ipairs(statColumns) do
					local value
					if viewMode == 'share' then
						local s = cachedShares[teamID] and cachedShares[teamID][col.key] or 0
						value = string_format('%.1f%%', s * 100)
					elseif viewMode == 'weighted' then
						local d = cachedDeflated[teamID] and cachedDeflated[teamID][col.key] or 0
						value = FormatSI(d)
					else -- raw
						local r = cachedRawTotals[teamID] and cachedRawTotals[teamID][col.key] or 0
						value = FormatSI(r)
					end
					displayValues[#displayValues + 1] = { value = value }
				end

				local idx = cachedShares[teamID] and StatsEngine.ComputeContributionIndex(cachedShares[teamID]) or 0

				-- Damage Efficiency: (damage dealt / damage received) * 100
				local dmgDealt = cachedRawTotals[teamID] and cachedRawTotals[teamID].damageDealt or 0
				local dmgRecv = cachedRawTotals[teamID] and cachedRawTotals[teamID].damageReceived or 0
				local dmgEffValue = dmgRecv > 0 and (dmgDealt / dmgRecv * 100) or 0
				if dmgEffValue ~= dmgEffValue or dmgEffValue == math.huge or dmgEffValue == -math.huge then
					dmgEffValue = 0
				end
				local dmgEffDisplay = string_format('%.0f%%', dmgEffValue)

				-- DmgRes Efficiency: damage share / resource share ratio
				local eff = cachedEfficiency[teamID]
				local effValue = eff and eff.damagePerResource or 0
				if effValue ~= effValue or effValue == math.huge or effValue == -math.huge then
					effValue = 0
				end
				local effDisplay = string_format('%.0f%%', effValue * 100)

				-- Compute sort value based on current sort key and view mode
				local sortValue
				if sortKey then
					if viewMode == 'share' then
						sortValue = cachedShares[teamID] and cachedShares[teamID][sortKey] or 0
					elseif viewMode == 'weighted' then
						sortValue = cachedDeflated[teamID] and cachedDeflated[teamID][sortKey] or 0
					else -- raw
						sortValue = cachedRawTotals[teamID] and cachedRawTotals[teamID][sortKey] or 0
					end
					if sortValue ~= sortValue then sortValue = 0 end -- NaN guard
				end

				players[#players + 1] = {
					team_id = teamID,
					name = info.name,
					color = string_format('rgb(%d,%d,%d)', math_floor(info.r * 255), math_floor(info.g * 255), math_floor(info.b * 255)),
					display_values = displayValues,
					contribution_index = idx,
					contribution_bar_width = idx,
					dmg_efficiency = dmgEffDisplay,
					efficiency = effDisplay,
					sort_value = sortValue,
				}
			end
		end

		-- Sort players
		if sortKey then
			if sortAscending then
				table.sort(players, function(a, b) return a.sort_value < b.sort_value end)
			else
				table.sort(players, function(a, b) return a.sort_value > b.sort_value end)
			end
		else
			table.sort(players, function(a, b) return a.contribution_index > b.contribution_index end)
		end

		allyTeamsData[#allyTeamsData + 1] = {
			id = allyInfo.allyID,
			players = players,
		}
	end

	-- Sort ally team groups by aggregate value
	if groupByAlly and #allyTeamsData > 1 then
		for _, at in ipairs(allyTeamsData) do
			local groupTotal = 0
			local groupIdx = 0
			for _, p in ipairs(at.players) do
				if sortKey then
					groupTotal = groupTotal + (p.sort_value or 0)
				end
				groupIdx = groupIdx + p.contribution_index
			end
			at.group_sort = sortKey and groupTotal or groupIdx
		end
		if sortKey and sortAscending then
			table.sort(allyTeamsData, function(a, b) return a.group_sort < b.group_sort end)
		else
			table.sort(allyTeamsData, function(a, b) return a.group_sort > b.group_sort end)
		end
	end

	-- Flat mode: merge all ally teams into one list
	if not groupByAlly then
		local allPlayers = {}
		for _, at in ipairs(allyTeamsData) do
			for _, p in ipairs(at.players) do
				allPlayers[#allPlayers + 1] = p
			end
		end
		-- Re-sort the merged list
		if sortKey then
			if sortAscending then
				table.sort(allPlayers, function(a, b) return a.sort_value < b.sort_value end)
			else
				table.sort(allPlayers, function(a, b) return a.sort_value > b.sort_value end)
			end
		else
			table.sort(allPlayers, function(a, b) return a.contribution_index > b.contribution_index end)
		end
		allyTeamsData = { { id = -1, players = allPlayers } }
	end

	-- Resolve selectedAllyTeam: default to first ally team if unset or invalid
	local validAllyTeam = false
	if selectedAllyTeam then
		for _, allyInfo in ipairs(cachedAllyTeams) do
			if allyInfo.allyID == selectedAllyTeam then
				validAllyTeam = true
				break
			end
		end
	end
	if not validAllyTeam and #cachedAllyTeams > 0 then
		selectedAllyTeam = cachedAllyTeams[1].allyID
	end

	local graphModeLabels = { absolute = 'Abs', normalized = 'Norm', overlay = 'Lines' }

	-- Set panel height once data is available so flex layout works
	if hasData and not panelHeightSet and document then
		local panel = document:GetElementById('wts-panel')
		if panel then
			panel.style.height = '320dp'
			panelHeightSet = true
		end
	end

	dm_handle.has_data = hasData
	dm_handle.empty_text = frameCounter > 0 and 'Collecting data...' or 'Starting...'
	dm_handle.table_visible = tableVisible
	dm_handle.view_mode = viewMode
	dm_handle.active_stat = activeStat
	dm_handle.graph_mode = graphMode
	dm_handle.graph_mode_label = graphModeLabels[graphMode] or graphMode
	dm_handle.graph_deflated = graphDeflated
	dm_handle.graph_deflated_label = graphDeflated and 'Deflated' or 'Raw'
	dm_handle.graph_visible = graphVisible
	dm_handle.group_by_ally = groupByAlly
	dm_handle.group_label = groupByAlly and 'Grp' or 'Flat'
	dm_handle.ally_team_label = selectedAllyTeam and ('Team ' .. (selectedAllyTeam + 1)) or 'Team ?'
	dm_handle.show_ally_selector = #cachedAllyTeams > 1
	dm_handle.window_agg_label = windowAggregation == 1 and '1x' or (windowAggregation .. 'x')
	dm_handle.ally_teams = allyTeamsData
	dm_handle.stat_columns = statColumns
end

--- Rebuild the GL display list for the graph.
local function RebuildGraphDisplayList()
	if graphDisplayList then
		glDeleteList(graphDisplayList)
		graphDisplayList = nil
	end

	if windowCount < 2 then
		return
	end

	-- Collect teams that have per-window data for the active stat
	-- Graph focuses on the selected ally team
	local graphTeams = {} -- { {teamID, color, data[]}, ... }
	for _, allyInfo in ipairs(cachedAllyTeams) do
		if not selectedAllyTeam or allyInfo.allyID == selectedAllyTeam then
			for _, teamID in ipairs(allyInfo.teamIDs) do
				local info = cachedTeamInfo[teamID]
				local dataSource
				if graphDeflated then
					dataSource = cachedPerWindowDeflated[teamID] and cachedPerWindowDeflated[teamID][activeStat]
				else
					dataSource = cachedPerWindowRaw[teamID] and cachedPerWindowRaw[teamID][activeStat]
				end
				if info and dataSource and #dataSource > 0 then
					graphTeams[#graphTeams + 1] = {
						teamID = teamID,
						r = info.r, g = info.g, b = info.b,
						data = dataSource,
					}
				end
			end
		end
	end

	if #graphTeams == 0 then
		return
	end

	-- Sort graph teams by cumulative value of the sort key (or active stat)
	-- Highest cumulative at bottom of stack (drawn first) for visibility
	for _, team in ipairs(graphTeams) do
		local total = 0
		for _, v in ipairs(team.data) do
			total = total + (v or 0)
		end
		team.cumulative = total
	end
	if sortKey and sortAscending then
		table.sort(graphTeams, function(a, b) return a.cumulative < b.cumulative end)
	else
		table.sort(graphTeams, function(a, b) return a.cumulative > b.cumulative end)
	end

	local wc = math_min(windowCount, #graphTeams[1].data)
	if wc < 2 then
		return
	end
	local wcDivisor = wc - 1

	graphDisplayList = glCreateList(function()
		if graphMode == 'overlay' then
			-- Overlay mode: independent lines per player
			local maxVal = 0
			for _, team in ipairs(graphTeams) do
				for w = 1, wc do
					maxVal = math_max(maxVal, team.data[w] or 0)
				end
			end
			if maxVal <= 0 then
				maxVal = 1
			end

			for _, team in ipairs(graphTeams) do
				-- Filled area
				glColor(team.r, team.g, team.b, 0.5)
				glBeginEnd(GL_TRIANGLE_STRIP, function()
					for w = 1, wc do
						local x = (w - 1) / wcDivisor
						local y = (team.data[w] or 0) / maxVal
						glVertex(x, 0)
						glVertex(x, y)
					end
				end)

				-- Line with full alpha
				glColor(team.r, team.g, team.b, 1.0)
				glLineWidth(2)
				glBeginEnd(GL_LINE_STRIP, function()
					for w = 1, wc do
						local x = (w - 1) / wcDivisor
						local y = (team.data[w] or 0) / maxVal
						glVertex(x, y)
					end
				end)
			end

		elseif graphMode == 'normalized' then
			-- Normalized mode: stacked area, always fills 100%
			-- Compute per-window totals
			local windowTotals = {}
			for w = 1, wc do
				local total = 0
				for _, team in ipairs(graphTeams) do
					total = total + math_max(team.data[w] or 0, 0)
				end
				windowTotals[w] = math_max(total, 1)
			end

			-- Draw stacked bands bottom to top
			local baselines = {}
			for w = 1, wc do
				baselines[w] = 0
			end

			for _, team in ipairs(graphTeams) do
				glColor(team.r, team.g, team.b, 0.8)
				glBeginEnd(GL_TRIANGLE_STRIP, function()
					for w = 1, wc do
						local x = (w - 1) / wcDivisor
						local share = (team.data[w] or 0) / windowTotals[w]
						local bottom = baselines[w]
						local top = bottom + share
						glVertex(x, bottom)
						glVertex(x, top)
					end
				end)
				-- Update baselines
				for w = 1, wc do
					baselines[w] = baselines[w] + (team.data[w] or 0) / windowTotals[w]
				end
			end

		else -- absolute
			-- Absolute mode: stacked area, Y auto-scaled
			local maxTotal = 0
			for w = 1, wc do
				local total = 0
				for _, team in ipairs(graphTeams) do
					total = total + math_max(team.data[w] or 0, 0)
				end
				maxTotal = math_max(maxTotal, total)
			end
			if maxTotal <= 0 then
				maxTotal = 1
			end

			local baselines = {}
			for w = 1, wc do
				baselines[w] = 0
			end

			for _, team in ipairs(graphTeams) do
				glColor(team.r, team.g, team.b, 0.8)
				glBeginEnd(GL_TRIANGLE_STRIP, function()
					for w = 1, wc do
						local x = (w - 1) / wcDivisor
						local val = math_max(team.data[w] or 0, 0)
						local bottom = baselines[w] / maxTotal
						local top = (baselines[w] + val) / maxTotal
						glVertex(x, bottom)
						glVertex(x, top)
					end
				end)
				for w = 1, wc do
					baselines[w] = baselines[w] + math_max(team.data[w] or 0, 0)
				end
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- Widget callbacks
--------------------------------------------------------------------------------

function widget:Initialize()
	gaiaTeamID = spGetGaiaTeamID()

	local spec, fullV = spGetSpectatingState()
	isSpectator = spec
	fullView = fullV
	myAllyTeamID = spGetMyAllyTeamID()

	LoadPosition()
	LoadUIState()

	widget.rmlContext = RmlUi.GetContext('shared')
	if not widget.rmlContext then
		Spring.Echo(WIDGET_NAME .. ': ERROR - Failed to get RML context')
		return false
	end

	local initialModel = {
		has_data = false,
		empty_text = 'Starting...',
		table_visible = tableVisible,
		view_mode = viewMode,
		active_stat = activeStat,
		graph_mode = graphMode,
		graph_mode_label = 'Norm',
		graph_deflated = graphDeflated,
		graph_deflated_label = graphDeflated and 'Deflated' or 'Raw',
		graph_visible = graphVisible,
		group_by_ally = groupByAlly,
		group_label = groupByAlly and 'Grp' or 'Flat',
		ally_team_label = 'Team ?',
		show_ally_selector = false, -- updated to true once multiple ally teams detected
		window_agg_label = windowAggregation == 1 and '1x' or (windowAggregation .. 'x'),
		ally_teams = {},
		stat_columns = BuildStatColumns(),
	}

	dm_handle = widget.rmlContext:OpenDataModel(MODEL_NAME, initialModel)
	if not dm_handle then
		Spring.Echo(WIDGET_NAME .. ': ERROR - Failed to create data model')
		return false
	end

	document = widget.rmlContext:LoadDocument(RML_PATH, widget)
	if not document then
		Spring.Echo(WIDGET_NAME .. ': ERROR - Failed to load document: ' .. RML_PATH)
		widget:Shutdown()
		return false
	end

	document:ReloadStyleSheet()

	-- Apply persisted font scale
	if fontScale ~= 1.0 then
		local panel = document:GetElementById('wts-panel')
		if panel then
			panel.style['font-size'] = math_floor(12 * fontScale) .. 'dp'
		end
	end

	if not spIsGUIHidden() then
		document:Show()
	end

	UpdateDocumentPosition()

	-- Force initial data load instead of waiting for first STATS_UPDATE_FREQUENCY
	RecomputeStats()
	UpdateRMLuiData()

	return true
end

function widget:Update()
	if not document then
		return
	end

	local isHidden = spIsGUIHidden()
	if isHidden ~= lastUIHiddenState then
		lastUIHiddenState = isHidden
		if isHidden then
			document:Hide()
		else
			document:Show()
		end
	end
end

function widget:PlayerChanged(playerID)
	local spec, fullV = spGetSpectatingState()
	isSpectator = spec
	fullView = fullV
	myAllyTeamID = spGetMyAllyTeamID()
	dataDirty = true
end

function widget:GameFrame()
	frameCounter = frameCounter + 1

	if frameCounter % STATS_UPDATE_FREQUENCY == 0 then
		if HasNewSnapshots() then
			RecomputeStats()
			dataDirty = true
			graphDirty = true
		end
	end

	if dataDirty and frameCounter % UI_UPDATE_FREQUENCY == 0 then
		UpdateRMLuiData()
		dataDirty = false
	end

	if graphDirty then
		RebuildGraphDisplayList()
		graphDirty = false
	end
end

function widget:DrawScreen()
	if spIsGUIHidden() or not document or not graphVisible then
		return
	end

	if not graphDisplayList then
		return
	end

	-- Get graph area position from the RML element
	local graphElement = document:GetElementById('graph-area')
	if not graphElement then
		return
	end

	local vsx, vsy = spGetViewGeometry()
	local gx = graphElement.absolute_left
	local gy = graphElement.absolute_top
	local gw = graphElement.offset_width
	local gh = graphElement.offset_height

	if gw <= 0 or gh <= 0 then
		return
	end

	-- RML coordinates are top-down, GL screen coordinates are bottom-up
	local screenX = gx
	local screenY = vsy - gy - gh
	local screenW = gw
	local screenH = gh

	-- Draw dark background
	glColor(0.08, 0.08, 0.1, 0.65)
	glRect(screenX, screenY, screenX + screenW, screenY + screenH)

	-- Draw subtle grid lines
	glColor(0.25, 0.3, 0.38, 0.6)
	glLineWidth(1)
	for i = 1, 3 do
		local y = screenY + screenH * (i / 4)
		glBeginEnd(GL.LINES, function()
			glVertex(screenX, y)
			glVertex(screenX + screenW, y)
		end)
	end
	for i = 1, 3 do
		local x = screenX + screenW * (i / 4)
		glBeginEnd(GL.LINES, function()
			glVertex(x, screenY)
			glVertex(x, screenY + screenH)
		end)
	end

	-- Transform and draw the graph
	-- The display list uses normalized coords (0-1), we need to scale to screen coords
	gl.PushMatrix()
	gl.Translate(screenX, screenY, 0)
	gl.Scale(screenW, screenH, 1)
	glCallList(graphDisplayList)
	gl.PopMatrix()

	-- Draw border
	glColor(0.2, 0.25, 0.3, 0.6)
	glLineWidth(1)
	glBeginEnd(GL.LINE_LOOP, function()
		glVertex(screenX, screenY)
		glVertex(screenX + screenW, screenY)
		glVertex(screenX + screenW, screenY + screenH)
		glVertex(screenX, screenY + screenH)
	end)

	-- Draw time labels
	if windowCount > 0 and #windowFrames > 0 then
		glColor(0.5, 0.6, 0.7, 0.7)
		local firstFrame = windowFrames[1]
		local lastFrame = windowFrames[#windowFrames]
		local startMin = math_floor(firstFrame / 30 / 60)
		local endMin = math_floor(lastFrame / 30 / 60)
		glText(startMin .. 'm', screenX + 2, screenY - 12, 10, 'o')
		glText(endMin .. 'm', screenX + screenW - 2, screenY - 12, 10, 'or')
	end

	-- Mouse crosshair tooltip
	if windowCount >= 2 then
		local mx, my = spGetMouseState()
		if mx >= screenX and mx <= screenX + screenW and my >= screenY and my <= screenY + screenH then
			-- Determine which window the mouse is over
			local relX = (mx - screenX) / screenW
			local wIdx = math_floor(relX * (windowCount - 1) + 0.5) + 1
			wIdx = math_max(1, math_min(wIdx, windowCount))

			-- Draw vertical crosshair line
			glColor(0.7, 0.8, 0.9, 0.5)
			glLineWidth(1)
			glBeginEnd(GL.LINES, function()
				glVertex(mx, screenY)
				glVertex(mx, screenY + screenH)
			end)

			-- Draw horizontal crosshair line
			glBeginEnd(GL.LINES, function()
				glVertex(screenX, my)
				glVertex(screenX + screenW, my)
			end)

			-- Y-axis value label
			local relY = (my - screenY) / screenH
			local yLabel
			if graphMode == 'normalized' then
				yLabel = string_format('%.0f%%', relY * 100)
			else
				-- For absolute/overlay, need the max value to convert back
				-- Compute max from visible data at this window
				local maxVal = 0
				if graphMode == 'overlay' then
					for _, allyInfo in ipairs(cachedAllyTeams) do
						if not selectedAllyTeam or allyInfo.allyID == selectedAllyTeam then
							for _, teamID in ipairs(allyInfo.teamIDs) do
								local ds = graphDeflated and (cachedPerWindowDeflated[teamID] and cachedPerWindowDeflated[teamID][activeStat])
									or (cachedPerWindowRaw[teamID] and cachedPerWindowRaw[teamID][activeStat])
								if ds then
									for w = 1, windowCount do
										maxVal = math_max(maxVal, ds[w] or 0)
									end
								end
							end
						end
					end
				else -- absolute stacked
					for w = 1, windowCount do
						local total = 0
						for _, allyInfo in ipairs(cachedAllyTeams) do
							if not selectedAllyTeam or allyInfo.allyID == selectedAllyTeam then
								for _, teamID in ipairs(allyInfo.teamIDs) do
									local ds = graphDeflated and (cachedPerWindowDeflated[teamID] and cachedPerWindowDeflated[teamID][activeStat])
										or (cachedPerWindowRaw[teamID] and cachedPerWindowRaw[teamID][activeStat])
									if ds then
										total = total + math_max(ds[w] or 0, 0)
									end
								end
							end
						end
						maxVal = math_max(maxVal, total)
					end
				end
				if maxVal > 0 then
					yLabel = FormatSI(relY * maxVal)
				else
					yLabel = '0'
				end
			end
			glColor(0.8, 0.9, 1.0, 0.8)
			glText(yLabel, screenX + 2, my + 2, 9, 'o')

			-- Time label at crosshair
			local frame = windowFrames[wIdx] or 0
			local mins = math_floor(frame / 30 / 60)
			local secs = math_floor((frame / 30) % 60)
			local timeStr = string_format('%d:%02d', mins, secs)

			-- Gather per-player values at this window
			local tooltipLines = {} ---@type table[]
			local tooltipTime = timeStr
			for _, allyInfo in ipairs(cachedAllyTeams) do
				if not selectedAllyTeam or allyInfo.allyID == selectedAllyTeam then
					for _, teamID in ipairs(allyInfo.teamIDs) do
						local info = cachedTeamInfo[teamID]
						if info then
							local dataSource
							if graphDeflated then
								dataSource = cachedPerWindowDeflated[teamID] and cachedPerWindowDeflated[teamID][activeStat]
							else
								dataSource = cachedPerWindowRaw[teamID] and cachedPerWindowRaw[teamID][activeStat]
							end
							if dataSource and dataSource[wIdx] then
								local val = dataSource[wIdx]
								tooltipLines[#tooltipLines + 1] = {
									name = info.name,
									value = FormatSI(val),
									r = info.r, g = info.g, b = info.b,
								}
							end
						end
					end
				end
			end

			-- Draw tooltip background and text
			if #tooltipLines > 0 then
				local lineH = 12
				local tooltipH = (#tooltipLines + 1) * lineH + 6
				local tooltipW = 100
				local tx = mx + 10
				local ty = screenY + screenH - 4

				-- Keep tooltip within graph bounds
				if tx + tooltipW > screenX + screenW then
					tx = mx - tooltipW - 10
				end

				-- Background
				glColor(0.05, 0.05, 0.07, 0.85)
				glRect(tx, ty - tooltipH, tx + tooltipW, ty)

				-- Time header
				glColor(0.8, 0.9, 1.0, 0.9)
				glText(tooltipTime, tx + 4, ty - lineH + 2, 10, 'o')

				-- Player values
				for i = 1, #tooltipLines do
					local line = tooltipLines[i]
					local ly = ty - (i + 1) * lineH + 2
					glColor(line.r, line.g, line.b, 0.9)
					glText(line.name, tx + 4, ly, 9, 'o')
					glColor(0.85, 0.9, 0.95, 0.9)
					glText(line.value, tx + tooltipW - 4, ly, 9, 'or')
				end
			end
		end
	end

	glColor(1, 1, 1, 1)
	glLineWidth(1)
end

function widget:Shutdown()
	if graphDisplayList then
		glDeleteList(graphDisplayList)
		graphDisplayList = nil
	end

	if widget.rmlContext and dm_handle then
		widget.rmlContext:RemoveDataModel(MODEL_NAME)
		dm_handle = nil
	end

	if document then
		document:Close()
		document = nil
	end
end

--------------------------------------------------------------------------------
-- RML Event Handlers
--------------------------------------------------------------------------------

function widget:CloseWidget(event)
	Spring.SendCommands('luaui disablewidget ' .. WIDGET_NAME)
end

function widget:OnDragEnd(event)
	if not document then
		return
	end
	local panel = document:GetElementById('wts-panel')
	if panel then
		widgetPosX = math_floor(panel.absolute_left)
		widgetPosY = math_floor(panel.absolute_top)
		SavePosition()
	end
end

function widget:ToggleTable(event)
	tableVisible = not tableVisible
	dataDirty = true
	SaveUIState()
end

function widget:ToggleGraph(event)
	graphVisible = not graphVisible
	dataDirty = true
	SaveUIState()
end

function widget:CycleWindowAggregation(event)
	-- Cycle through: 1, 2, 4, 8
	if windowAggregation >= 8 then
		windowAggregation = 1
	else
		windowAggregation = windowAggregation * 2
	end
	RecomputeStats()
	dataDirty = true
	graphDirty = true
	SaveUIState()
end

function widget:SetViewMode(event)
	local element = event.current_element
	if not element then
		return
	end
	local mode = element:GetAttribute('data-mode')
	if mode and (mode == 'weighted' or mode == 'share' or mode == 'raw') then
		viewMode = mode
		dataDirty = true
		SaveUIState()
	end
end

function widget:SetActiveStat(event)
	local element = event.current_element
	if not element then
		return
	end
	local key = element:GetAttribute('data-key')
	if key then
		if key == activeStat then
			-- Cycle sort: descending -> ascending -> default (contribution index)
			if sortKey == key and not sortAscending then
				sortAscending = true
			elseif sortKey == key and sortAscending then
				sortKey = nil
				sortAscending = false
			else
				sortKey = key
				sortAscending = false
			end
		else
			activeStat = key
			sortKey = key
			sortAscending = false
		end
		dataDirty = true
		graphDirty = true
		SaveUIState()
	end
end

function widget:CycleGraphMode(event)
	if graphMode == 'normalized' then
		graphMode = 'absolute'
	elseif graphMode == 'absolute' then
		graphMode = 'overlay'
	else
		graphMode = 'normalized'
	end
	dataDirty = true
	graphDirty = true
	SaveUIState()
end

function widget:ToggleDeflation(event)
	graphDeflated = not graphDeflated
	dataDirty = true
	graphDirty = true
	SaveUIState()
end


function widget:ToggleGrouping(event)
	groupByAlly = not groupByAlly
	dataDirty = true
	graphDirty = true
	SaveUIState()
end

function widget:CycleAllyTeam(event)
	if #cachedAllyTeams < 2 then return end
	local currentIdx = 1
	for i, allyInfo in ipairs(cachedAllyTeams) do
		if allyInfo.allyID == selectedAllyTeam then
			currentIdx = i
			break
		end
	end
	selectedAllyTeam = cachedAllyTeams[(currentIdx % #cachedAllyTeams) + 1].allyID
	dataDirty = true
	graphDirty = true
	SaveUIState()
end

function widget:IsAbove(x, y)
	if not document then return false end
	local panel = document:GetElementById('wts-panel')
	if not panel then return false end
	local vsx, vsy = spGetViewGeometry()
	local px = panel.absolute_left
	local py = panel.absolute_top
	local pw = panel.offset_width
	local ph = panel.offset_height
	-- RML is top-down, Spring mouse coords are bottom-up
	local mouseY = vsy - y
	return x >= px and x <= px + pw and mouseY >= py and mouseY <= py + ph
end

function widget:MouseWheel(up, value)
	local ctrl = select(2, spGetModKeyState())
	if not ctrl then return false end
	if up then
		fontScale = math_min(fontScale + 0.1, 2.0)
	else
		fontScale = math_max(fontScale - 0.1, 0.5)
	end
	-- Apply font scale to the panel root element
	if document then
		local panel = document:GetElementById('wts-panel')
		if panel then
			panel.style['font-size'] = math_floor(12 * fontScale) .. 'dp'
		end
	end
	dataDirty = true
	SaveUIState()
	return true
end
