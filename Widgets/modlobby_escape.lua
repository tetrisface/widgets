-- modlobby: Escape opens the lobby.
--
-- Written by modlobby when it launches a game and removed when it exits. It
-- draws nothing and sends nothing but a keypress notification to a loopback
-- port that modlobby is listening on, guarded by a token generated for this
-- run.
--
-- If modlobby is not listening it does nothing at all -- including not
-- consuming the key -- so a game launched from any other lobby behaves
-- exactly as it would without this file.

function widget:GetInfo()
	return {
		name = "modlobby Escape",
		desc = "Escape with nothing selected opens the modlobby window",
		author = "modlobby",
		date = "2026",
		license = "GNU GPL, v2 or later",
		layer = 0,
		enabled = true,
	}
end

local PORT = 63052
local TOKEN = "86dec9f639a426772ee987f2366c3d94"

local socket = socket
local GetSelectedUnitsCount = Spring.GetSelectedUnitsCount

local KEY_ESCAPE = 27
local connection = nil

-- Connecting costs a round trip on loopback, which is nothing, but doing it
-- inside the keypress would still stall a frame if the port were gone. The
-- connection is kept and only rebuilt when it breaks.
local function connect()
	if not socket then
		return nil
	end
	local tcp = socket.tcp()
	if not tcp then
		return nil
	end
	tcp:settimeout(0.05)
	local ok = tcp:connect("127.0.0.1", PORT)
	if not ok then
		tcp:close()
		return nil
	end
	return tcp
end

-- Sends one line and waits briefly for the answer.
--
-- The answer is the point. modlobby replies "ok" only when the game we are in
-- is one it launched and the overlay is switched on; anything else is "no",
-- and the key goes back to the game untouched. Waiting costs a loopback round
-- trip on an Escape press, which is not a frame anyone will notice.
local function ask(verb)
	if not connection then
		connection = connect()
	end
	if not connection then
		return false
	end

	local sent = connection:send(TOKEN .. " " .. verb .. "\n")
	if not sent then
		-- The lobby was restarted under us; one reconnect, then give up.
		connection:close()
		connection = connect()
		if not connection then
			return false
		end
		sent = connection:send(TOKEN .. " " .. verb .. "\n")
		if not sent then
			return false
		end
	end

	local reply = connection:receive("*l")
	if not reply then
		connection:close()
		connection = nil
		return false
	end
	return reply == "ok"
end

function widget:Initialize()
	connection = connect()
	if not connection then
		-- Nothing to talk to. Staying loaded is harmless and lets a lobby
		-- started after the game still be reached on the next press.
		Spring.Echo("modlobby: not running; Escape left alone")
	end
end

function widget:Shutdown()
	if connection then
		connection:close()
		connection = nil
	end
end

function widget:KeyPress(key, mods, isRepeat)
	if key ~= KEY_ESCAPE or isRepeat then
		return false
	end
	-- Escape already means "drop what I am holding". Only when it would
	-- otherwise do nothing does it mean "show me the lobby".
	if GetSelectedUnitsCount() > 0 then
		return false
	end
	if mods and (mods.alt or mods.ctrl or mods.shift or mods.meta) then
		return false
	end
	-- Consumed only if it actually got through, so the game keeps its own
	-- Escape whenever modlobby is not there.
	return ask("raise")
end
