local HistogramFactory = {}

local MILESTONES = {
	{score = 20, field = "challenge_20_clears"},
	{score = 25, field = "challenge_25_clears"},
	{score = 30, field = "challenge_30_clears"},
}

local function ContainsDifficulty(bin, difficulty)
	if not difficulty then return false end
	local lower = tonumber(bin and bin.lower_bound) or 0
	local upper = tonumber(bin and bin.upper_bound) or lower
	return difficulty >= lower and (difficulty < upper or (upper >= 34 and difficulty <= 34))
end

function HistogramFactory.New(Display, PlayerStats)
	local Histogram = {}

	local function Data(response, request)
		local histogram = response and response.difficulty_histogram
		local bins = histogram and histogram.bins
		if type(histogram) ~= "table" or type(bins) ~= "table" or #bins == 0 then
			return nil
		end
		local ownPlayer = PlayerStats.OwnPlayer(response, request)
		local challenges = PlayerStats.AccomplishmentGroup(ownPlayer, "challenges")
		local ownBins = type(challenges.clear_histogram) == "table" and challenges.clear_histogram or {}
		local totalGames = 0
		local totalOwnClears = 0
		for index, bin in ipairs(bins) do
			totalGames = totalGames + (tonumber(bin.games) or 0)
			totalOwnClears = totalOwnClears + (tonumber(ownBins[index]) or 0)
		end
		totalGames = tonumber(histogram.total_games) or totalGames
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
			totalGames = totalGames,
			totalOwnClears = totalOwnClears,
			maxShare = maxShare,
			currentDifficulty = tonumber(histogram.current_difficulty),
		}
	end

	local function BoundText(value)
		local number = tonumber(value) or 0
		return Display.Number(number, number == math.floor(number) and 0 or 1)
	end

	local function CrossedMilestoneText(data, lower, upper)
		if not data.ownPlayer then return nil end
		for _, milestone in ipairs(MILESTONES) do
			if lower < milestone.score and milestone.score < upper then
				local exactClears = tonumber(data.challenges[milestone.field])
				if exactClears ~= nil then
					return "This bucket crosses " .. Display.Number(milestone.score, 0)
						.. "; your exact " .. Display.Number(milestone.score, 0) .. "+ Clears total is "
						.. Display.Number(exactClears, 0) .. "."
				end
			end
		end
		return nil
	end

	function Histogram.HelpText(response, request)
		local data = Data(response, request)
		if not data then return "" end
		local ownText = data.ownPlayer
			and (" Cyan shows your " .. Display.Number(data.totalOwnClears, 0) .. " eligible clears.")
			or " Cyan appears when your player history is available."
		return "Dark bars show " .. Display.Number(data.totalGames, 0)
			.. " eligible games by challenge score."
			.. ownText
			.. " Both use one percentage scale. Each bar covers a score range; the Milestones table uses exact 20+/25+/30+ cutoffs."
			.. " Cyan above dark means this range contains a larger share of your clears than of all played games."
	end

	function Histogram.BinHelpText(response, request, binIndex)
		local data = Data(response, request)
		local index = tonumber(binIndex)
		local bin = data and index and data.bins[index]
		if not bin then return Histogram.HelpText(response, request) end
		local games = tonumber(bin.games) or 0
		local wins = tonumber(bin.wins) or 0
		local ownClears = tonumber(data.ownBins[index]) or 0
		local lower = tonumber(bin.lower_bound) or 0
		local upper = tonumber(bin.upper_bound) or lower
		local gameShare = data.totalGames > 0 and games / data.totalGames * 100 or 0
		local winRate = games > 0 and wins / games * 100 or 0
		local parts = {
			"Challenge " .. BoundText(lower) .. "-" .. BoundText(upper) .. ":",
			Display.Number(games, 0) .. " eligible games (" .. Display.Number(gameShare, 1) .. "% of played games),",
			Display.Number(wins, 0) .. " human wins (" .. Display.Number(winRate, 1) .. "%).",
		}
		if data.ownPlayer then
			local ownShare = data.totalOwnClears > 0 and ownClears / data.totalOwnClears * 100 or 0
			parts[#parts + 1] = "Your clears: " .. Display.Number(ownClears, 0)
				.. " of " .. Display.Number(data.totalOwnClears, 0)
				.. " (" .. Display.Number(ownShare, 1) .. "%)."
		end
		local crossed = CrossedMilestoneText(data, lower, upper)
		if crossed then parts[#parts + 1] = crossed end
		if ContainsDifficulty(bin, data.currentDifficulty) then
			parts[#parts + 1] = "Your current setup is here at " .. Display.Number(data.currentDifficulty, 1) .. "."
		end
		parts[#parts + 1] = "Both bars use one percentage scale; cyan above dark means your clears are more concentrated here than played games are."
		return table.concat(parts, " ")
	end

	function Histogram.Build(response, request)
		local data = Data(response, request)
		if not data then
			return {histogramBins = {}, histogramCaption = "", hasHistogram = false}
		end
		local rows = {}
		for index, bin in ipairs(data.bins) do
			local games = tonumber(bin.games) or 0
			local ownClears = tonumber(data.ownBins[index]) or 0
			local populationShare = data.totalGames > 0 and games / data.totalGames or 0
			local ownShare = data.totalOwnClears > 0 and ownClears / data.totalOwnClears or 0
			local populationHeight = data.maxShare > 0 and games > 0
				and math.max(2, math.floor((populationShare / data.maxShare) * 100 + 0.5)) or 0
			local ownHeight = data.maxShare > 0 and ownClears > 0
				and math.max(3, math.floor((ownShare / data.maxShare) * 100 + 0.5)) or 0
			rows[#rows + 1] = {
				index = index,
				populationHeight = tostring(populationHeight) .. "%",
				ownHeight = tostring(ownHeight) .. "%",
				hasOwn = ownClears > 0,
				isCurrent = ContainsDifficulty(bin, data.currentDifficulty),
			}
		end
		local caption
		if data.currentDifficulty then
			local percentile = tonumber(data.histogram.current_percentile)
			caption = "Challenge " .. Display.Number(data.currentDifficulty, 1)
			if percentile then
				caption = caption .. " - harder than " .. Display.Number(percentile, 0) .. "% of played "
					.. tostring(request and request.ai_type or "PvE") .. " games"
			end
		else
			caption = "Current setup: not yet placed"
		end
		local highest = tonumber(data.challenges.highest_challenge_cleared)
		if highest then caption = caption .. " - your best " .. Display.Number(highest, 1) end
		return {histogramBins = rows, histogramCaption = caption, hasHistogram = true}
	end

	return Histogram
end

return HistogramFactory
