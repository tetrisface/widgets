local PipelinePolicy = {}

-- currentlyProcessing only ever contains incomplete builds (completed ones are
-- removed by the caller), so the reclaim window is positional: only the first
-- maxConcurrentReclaims entries may reclaim. A build keeps occupying its slot
-- from queue until completion — including while under construction — which is
-- what limits reclaim to "one in progress + one being prepared" instead of
-- letting the reclaim front run ahead of the construction front.
function PipelinePolicy.getReclaimEligibility(currentlyProcessing, sequentialMode, maxConcurrentReclaims)
	local eligibility = {}
	if not sequentialMode then
		for _, build in ipairs(currentlyProcessing) do
			eligibility[build] = true
		end
		return eligibility
	end

	for i, build in ipairs(currentlyProcessing) do
		eligibility[build] = i <= maxConcurrentReclaims
	end

	return eligibility
end

return PipelinePolicy
