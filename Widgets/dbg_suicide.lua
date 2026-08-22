function widget:GetInfo()
	return {
		name = 'Suicide (alert test)',
		desc = 'Type /suicide [seconds] to self-destruct all your units after a delay (default 5s), then auto-exit to the lobby after game over. Ends the game solo for testing OS notification alerts.',
		author = 'tetrisface',
		date = '2026-08-22',
		layer = 0,
		enabled = true,
	}
end

local QUIT_AFTER_GAMEOVER_SECONDS = 8

local deadline
local armed = false
local quitAt

function widget:TextCommand(command)
	local secondsStr = command:match('^suicide%s*(%d*)$')
	if not secondsStr then
		return false
	end
	local seconds = tonumber(secondsStr) or 5
	deadline = Spring.GetGameSeconds() + seconds
	armed = true
	Spring.Echo(('[suicide] self-destructing all units in %d seconds, alt-tab now'):format(seconds))
	return true
end

function widget:GameFrame()
	if not deadline or Spring.GetGameSeconds() < deadline then
		return
	end
	deadline = nil
	local units = Spring.GetTeamUnits(Spring.GetMyTeamID())
	Spring.Echo(('[suicide] self-destructing %d units'):format(#units))
	Spring.GiveOrderToUnitArray(units, CMD.SELFD, {}, 0)
end

function widget:GameOver()
	-- Only auto-exit games ended by /suicide, never regular ones.
	if not armed then
		return
	end
	quitAt = os.clock() + QUIT_AFTER_GAMEOVER_SECONDS
	Spring.Echo(('[suicide] game over, exiting to lobby in %d seconds'):format(QUIT_AFTER_GAMEOVER_SECONDS))
end

function widget:Update()
	if not quitAt or os.clock() < quitAt then
		return
	end
	quitAt = nil
	armed = false
	if Spring.GetMenuName and string.find(string.lower(Spring.GetMenuName()), 'chobby') then
		Spring.SendCommands('ReloadForce') -- exit to the lobby, same as the top bar quit button
	else
		Spring.Echo('[suicide] no lobby loaded, staying in game')
	end
end
