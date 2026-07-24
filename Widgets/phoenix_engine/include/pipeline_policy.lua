local PipelinePolicy = {}

function PipelinePolicy.getReclaimEligibility(currentlyProcessing, isBlocked, sequentialMode, maxConcurrentReclaims)
	local eligibility = {}
	if not sequentialMode then
		for _, build in ipairs(currentlyProcessing) do
			eligibility[build] = true
		end
		return eligibility
	end

	local blockedAheadCount = 0
	for _, build in ipairs(currentlyProcessing) do
		eligibility[build] = blockedAheadCount < maxConcurrentReclaims
		if isBlocked(build) then
			blockedAheadCount = blockedAheadCount + 1
		end
	end

	return eligibility
end

return PipelinePolicy
