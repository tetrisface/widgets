local DiagnosticsFactory = {}

local function AddModOptionStep(lookup, key, step)
	local optionKey = tostring(key or "")
	local numericStep = tonumber(step)
	if optionKey == "" or not numericStep or numericStep <= 0 then return end
	lookup[optionKey] = numericStep
	lookup[string.lower(optionKey)] = numericStep
end

local function CollectModOptionSteps(definitions, lookup, seen)
	if type(definitions) ~= "table" or seen[definitions] then return end
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

local function TopMatch(response)
	local matches = response and response.closest_matches
	return type(matches) == "table" and matches[1] or nil
end

local function IsExact(response)
	return string.lower(tostring(response and response.match_status or "")) == "exact"
end

local function IsClosest(response)
	return string.lower(tostring(response and response.match_status or "")) == "closest"
end

local function StartsWith(value, prefix)
	return string.sub(value, 1, #prefix) == prefix
end

local function HiddenDiffColumn(column)
	local lower = string.lower(tostring(column or ""))
	return lower == "" or lower == "ai_type" or StartsWith(lower, "tweakdefs") or StartsWith(lower, "tweakunits")
end

local function DiffValueText(value)
	if value == nil then return "-" end
	local valueType = type(value)
	if valueType == "boolean" then return value and "true" or "false" end
	if valueType == "number" or valueType == "string" then
		local text = tostring(value)
		return text == "" and "-" or text
	end
	return "<complex>"
end

local function LookupStep(lookup, column)
	if not lookup or not column then return nil end
	return tonumber(lookup[column] or lookup[tostring(column)] or lookup[string.lower(tostring(column))])
end

local function DiffStep(diff, options, response, topMatch)
	local explicit = diff and (diff.step or diff.option_step or diff.modoption_step or diff.mod_option_step)
	local explicitStep = tonumber(explicit)
	if explicitStep and explicitStep > 0 then return explicitStep end
	local column = diff and diff.column
	return LookupStep(options and options.modOptionSteps, column)
		or LookupStep(response and (response.mod_option_steps or response.modoption_steps), column)
		or LookupStep(topMatch and (topMatch.mod_option_steps or topMatch.modoption_steps), column)
end

local function DiagnosticHash(value)
	local text = tostring(value or "")
	return #text <= 12 and text or string.sub(text, 1, 12)
end

function DiagnosticsFactory.New(Display)
	local Diagnostics = {}

	function Diagnostics.ModOptionStepLookup(...)
		local lookup = {}
		for index = 1, select("#", ...) do
			CollectModOptionSteps(select(index, ...), lookup, {})
		end
		return lookup
	end

	local function DiffDisplayValue(value, diff, options, response, topMatch)
		local text = DiffValueText(value)
		local number = tonumber(value)
		if not number then return text end
		local step = DiffStep(diff, options, response, topMatch)
		if step then
			return Display.RoundedNumber(Display.RoundToStep(number, step), Display.DecimalPlacesForStep(step))
		end
		return Display.CleanFloat(value)
	end

	local function DisplayDiffCount(topMatch)
		if type(topMatch) ~= "table" then return 0 end
		if type(topMatch.display_diffs) == "table" then return #topMatch.display_diffs end
		local hidden = type(topMatch.hidden_diff_summary) == "table" and tonumber(topMatch.hidden_diff_summary.total) or nil
		local total = tonumber(topMatch.difference_count)
		return hidden and total and math.max(0, total - hidden) or 0
	end

	local function HiddenDifferenceText(topMatch)
		local hidden = topMatch and topMatch.hidden_diff_summary
		if type(hidden) ~= "table" or tonumber(hidden.total or 0) <= 0 then return nil end
		local total = math.floor(tonumber(hidden.total))
		return tostring(total) .. " additional field difference" .. (total == 1 and "" or "s") .. " hidden"
	end

	local function MatchSummaryText(response)
		if response and IsExact(response) then return "Match: exact setting" end
		local topMatch = TopMatch(response)
		if type(topMatch) ~= "table" then return "Match: no trusted setting match" end
		local parts = {
			tostring(topMatch.match_method or "") == "similar" and "similar setting" or "raw lobby fallback",
		}
		local visible = DisplayDiffCount(topMatch)
		parts[#parts + 1] = tostring(visible) .. " visible difference" .. (visible == 1 and "" or "s")
		local hidden = HiddenDifferenceText(topMatch)
		if hidden then parts[#parts + 1] = hidden end
		return "Match: " .. table.concat(parts, "; ")
	end

	local function RawOverlapText(response, topMatch)
		if type(topMatch) ~= "table" or tostring(topMatch.match_method or "") ~= "raw_fallback" then return nil end
		local completeness = response and response.request_completeness
		local total = tonumber(completeness and completeness.total_hash_columns)
		local missing = tonumber(completeness and completeness.missing_hash_columns) or 0
		local differences = tonumber(topMatch.difference_count)
		if not total or total <= 0 or not differences then return "lobby-field comparison unavailable" end
		local compared = math.max(0, total - missing)
		local knownDifferences = math.max(0, differences - missing)
		local matching = math.max(0, compared - knownDifferences)
		if compared <= 0 then return tostring(math.floor(missing)) .. " unknown fields" end
		local unknownText = missing > 0 and ("; " .. tostring(math.floor(missing)) .. " unknown") or ""
		return Display.RoundedNumber(100 * matching / compared, 1) .. "% ("
			.. tostring(math.floor(matching)) .. "/" .. tostring(math.floor(compared))
			.. " compared" .. unknownText .. ")"
	end

	local function AddRow(rows, label, value)
		if value == nil or tostring(value) == "" then return end
		rows[#rows + 1] = {label = label, value = tostring(value)}
	end

	function Diagnostics.Evidence(response, options)
		-- This is the complete support-evidence allowlist shared by the visible,
		-- copied, and logged diagnostic representations. Detailed model evidence,
		-- response bodies, and backend topology never enter this structure.
		local evidence = {version = 1}
		local topMatch = TopMatch(response)
		local estimate = response and response.difficulty_estimate
		if type(estimate) == "table" and estimate.difficulty_target_sha256 then
			evidence.contract_hash = DiagnosticHash(estimate.difficulty_target_sha256)
		end
		if response then evidence.match_summary = MatchSummaryText(response) end
		evidence.raw_overlap = RawOverlapText(response, topMatch)
		local completeness = response and response.request_completeness
		if type(completeness) == "table" then
			evidence.request_fields = table.concat({
				"provided " .. tostring(completeness.provided_hash_columns or 0),
				"derived " .. tostring(#(completeness.derived_hash_column_names or {})),
				"defaulted " .. tostring(completeness.defaulted_hash_columns or 0),
				"missing " .. tostring(completeness.missing_hash_columns or 0),
				"total " .. tostring(completeness.total_hash_columns or 0),
			}, "; ")
		end
		local transport = options and options.transportEvidence
		if type(transport) == "table" then
			evidence.http_status = transport.http_status
			evidence.attempt = transport.attempt
			evidence.retry_class = transport.retry_class
			evidence.request_duration_ms = transport.request_duration_ms
			evidence.loading_elapsed_ms = transport.loading_elapsed_ms
			evidence.loading_expected_seconds = transport.loading_expected_seconds
			evidence.request_bytes = transport.request_bytes
			evidence.response_bytes = transport.response_bytes
			evidence.trace_id = transport.trace_id
			evidence.request_hash = transport.request_hash
		end
		if response and response.setting_hash then evidence.query_hash = DiagnosticHash(response.setting_hash) end
		if topMatch and topMatch.setting_hash then evidence.match_hash = DiagnosticHash(topMatch.setting_hash) end
		if options and options.currentGameId then evidence.game_id = tostring(options.currentGameId) end
		return evidence
	end

	local function DiagnosticRows(evidence)
		local rows = {}
		AddRow(rows, "Contract", evidence.contract_hash)
		AddRow(rows, "Match", evidence.match_summary)
		AddRow(rows, "Raw overlap", evidence.raw_overlap)
		AddRow(rows, "Request fields", evidence.request_fields)
		local http = {}
		if evidence.http_status then http[#http + 1] = tostring(evidence.http_status) end
		if evidence.attempt then http[#http + 1] = "attempt " .. tostring(evidence.attempt) end
		if evidence.retry_class then http[#http + 1] = tostring(evidence.retry_class) end
		AddRow(rows, "HTTP", #http > 0 and table.concat(http, "; ") or nil)
		AddRow(rows, "HTTP time", Display.Duration(evidence.request_duration_ms))
		local loading = Display.Duration(evidence.loading_elapsed_ms)
		if loading and evidence.loading_expected_seconds then
			loading = loading .. " (" .. Display.RoundedNumber(evidence.loading_expected_seconds, 1) .. " s expected)"
		end
		AddRow(rows, "Load time", loading)
		local transfer = {}
		local requestSize = Display.ByteSize(evidence.request_bytes)
		local responseSize = Display.ByteSize(evidence.response_bytes)
		if requestSize then transfer[#transfer + 1] = "request " .. requestSize end
		if responseSize then transfer[#transfer + 1] = "response " .. responseSize end
		AddRow(rows, "Transfer", #transfer > 0 and table.concat(transfer, "; ") or nil)
		local identities = {}
		if evidence.trace_id then identities[#identities + 1] = "trace " .. tostring(evidence.trace_id) end
		if evidence.request_hash then identities[#identities + 1] = "request " .. tostring(evidence.request_hash) end
		if evidence.query_hash then identities[#identities + 1] = "query " .. tostring(evidence.query_hash) end
		if evidence.match_hash then identities[#identities + 1] = "match " .. tostring(evidence.match_hash) end
		if evidence.game_id then identities[#identities + 1] = "game " .. tostring(evidence.game_id) end
		AddRow(rows, "IDs", #identities > 0 and table.concat(identities, "; ") or nil)
		return rows
	end

	function Diagnostics.FormatEvidenceLog(evidence)
		evidence = evidence or {version = 1}
		return table.concat({
			"pve_stats_evidence version=", tostring(evidence.version or 1),
			" attempt=", tostring(evidence.attempt or "-"),
			" request_ms=", tostring(evidence.request_duration_ms or "-"),
			" loading_ms=", tostring(evidence.loading_elapsed_ms or "-"),
			" retry_class=", tostring(evidence.retry_class or "-"),
			" request_hash=", tostring(evidence.request_hash or "-"),
			" trace_id=", tostring(evidence.trace_id or "-"),
			" request_bytes=", tostring(evidence.request_bytes or 0),
			" response_bytes=", tostring(evidence.response_bytes or 0),
			" http_status=", tostring(evidence.http_status or "-"),
		})
	end

	local function BuildDiffs(response, options)
		options = options or {}
		local topMatch = TopMatch(response)
		local visible = {}
		for _, diff in ipairs(topMatch and topMatch.display_diffs or {}) do
			if not HiddenDiffColumn(diff and diff.column) then
				local incoming = DiffDisplayValue(diff.incoming, diff, options, response, topMatch)
				local expected = DiffDisplayValue(diff.expected, diff, options, response, topMatch)
				if incoming ~= expected then
					visible[#visible + 1] = {field = tostring(diff.column or ""), current = incoming, closest = expected}
				end
			end
		end
		local hidden = HiddenDifferenceText(topMatch)
		local expanded = options.diffExpanded == true
		local limit = tonumber(options.diffCollapsedLimit) or 6
		local rows = {}
		local rowLimit = expanded and #visible or limit
		for index, row in ipairs(visible) do
			if index <= rowLimit then rows[#rows + 1] = row end
		end
		local method = tostring(topMatch and topMatch.match_method or "")
		local comparison = method == "raw_fallback" and "Fallback" or "Similar"
		local title = method == "raw_fallback" and "Raw fallback differs by " or "Similar match differs by "
		local hiddenText = ""
		if hidden then
			local prefix = #visible == 0 and "No displayable lobby fields differ. " or "Also hidden: "
			hiddenText = prefix .. hidden .. ". See Diagnostics for match details."
		end
		return {
			diffRows = rows,
			diffComparisonLabel = comparison,
			diffTitle = title .. tostring(#visible) .. " shown field" .. (#visible == 1 and "" or "s"),
			diffToggleText = expanded and "Show fewer" or ("+" .. tostring(math.max(0, #visible - limit)) .. " more"),
			hiddenDiffText = hiddenText,
			hasHiddenDiff = hidden ~= nil,
			hasVisibleDiffs = #visible > 0,
			hasDiffToggle = #visible > limit,
			hasDiffs = #visible > 0 or hidden ~= nil,
		}
	end

	function Diagnostics.MatchResultText(response)
		local value = response and response.match_status
		if value == nil then return "-" end
		local text = tostring(value)
		local normalized = string.lower(text)
		if normalized == "exact" then return "Exact" end
		if normalized == "closest" then
			local topMatch = TopMatch(response)
			if tostring(topMatch and topMatch.match_method or "") == "raw_fallback" then return "Raw fallback" end
			local similarity = tonumber(topMatch and topMatch.similarity)
			return similarity and ("Similar " .. Display.Number(similarity, 3)) or "Similar"
		end
		if normalized == "not_found" or normalized == "not found" then return "Not found" end
		if normalized == "win" or normalized == "won" or normalized == "victory" then return "Win" end
		if normalized == "loss" or normalized == "lost" or normalized == "defeat" then return "Loss" end
		if normalized == "draw" or normalized == "tie" then return "Draw" end
		return text
	end

	function Diagnostics.IsExact(response) return IsExact(response) end
	function Diagnostics.IsClosest(response) return IsClosest(response) end

	function Diagnostics.Build(response, options)
		local evidence = Diagnostics.Evidence(response, options)
		local rows = DiagnosticRows(evidence)
		local text = {"PvE Stats diagnostics"}
		for _, row in ipairs(rows) do text[#text + 1] = row.label .. ": " .. row.value end
		local diffs = BuildDiffs(response, options)
		diffs.evidenceSummaryText = response and MatchSummaryText(response) or ""
		diffs.hasEvidenceSummary = diffs.evidenceSummaryText ~= ""
		diffs.diagnosticRows = rows
		diffs.diagnosticsText = table.concat(text, "\n")
		diffs.hasDiagnostics = #rows > 0
		diffs.diagnosticsExpanded = options and options.diagnosticsExpanded == true and #rows > 0
		return diffs
	end

	return Diagnostics
end

return DiagnosticsFactory
