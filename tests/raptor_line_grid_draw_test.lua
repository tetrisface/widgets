-- Run with: lua tests/raptor_line_grid_draw_test.lua
-- luacheck: globals Spring Game VFS BAR widget widgetHandler

local widgetPath =
	'Widgets/gui_metal_plate_12_player_raptor_line_grid_draw/gui_metal_plate_12_player_raptor_line_grid_draw.lua'

local unpack = unpack or table.unpack -- luacheck: ignore 143

local MAP_X, MAP_Z = 12288, 12288
local MARGIN = 0.1 * MAP_X
local BOX = { 0, 0, 3000, 3000 }

local frame, markers, said

-- engineBox is what Spring.GetAllyTeamStartBox returns, polygonBox (optional) an explicit polygon config.
-- startbox_utilities.lua returns ParseBoxes on older BAR versions and a module holding it on newer ones.
local function loadWidget(engineBox, polygonBox, asModule)
	frame, markers, said = 0, {}, 0
	Game = { mapName = 'Full Metal Plate', mapSizeX = MAP_X, mapSizeZ = MAP_Z }
	VFS = {
		Include = function()
			if not polygonBox then
				error('no startbox_utilities on this BAR version')
			end
			local x0, z0, x1, z1 = unpack(polygonBox)
			local function parseBoxes()
				return { [0] = { boxes = { { { x0, z0 }, { x1, z0 }, { x1, z1 }, { x0, z1 } } } } }, 'modoption_set', true
			end
			return asModule and { ParseBoxes = parseBoxes } or parseBoxes
		end,
	}
	Spring = {
		GetSpectatingState = function() return false end,
		GetTeamList = function() return { 0, 1 } end,
		GetTeamLuaAI = function(teamID) return teamID == 1 and 'RaptorsDefense' or '' end,
		GetMyAllyTeamID = function() return 0 end,
		GetMyPlayerID = function() return 1 end,
		GetAllyTeamStartBox = function() return unpack(engineBox) end,
		GetGameFrame = function() return frame end,
		GetGameSpeed = function() return 1, 1, false end,
		MarkerAddLine = function(x1, _, z1, x2, _, z2)
			markers[#markers + 1] = { x1, z1, x2, z2 }
		end,
		SendCommands = function() said = said + 1 end,
		Echo = print,
	}
	widget = {}
	widgetHandler = { RemoveWidget = function() error('widget removed itself') end }
	dofile(widgetPath)
	widget:Initialize()
end

local function run(seconds, framesPerUpdate)
	for _ = 1, seconds * 10 do
		frame = frame + framesPerUpdate
		widget:Update(0.1)
	end
end

local function boxDistance(x, z, box)
	local dx = math.max(box[1] - x, 0, x - box[3])
	local dz = math.max(box[2] - z, 0, z - box[4])
	return math.sqrt(dx * dx + dz * dz)
end

local function assertAllNear(box, label)
	assert(#markers > 0, label .. ': nothing drawn')
	for _, m in ipairs(markers) do
		local midX, midZ = (m[1] + m[3]) / 2, (m[2] + m[4]) / 2
		assert(boxDistance(midX, midZ, box) <= MARGIN, label .. ': line drawn outside the margin')
	end
end

-- Joining a running game: the sim replays at 10x, nothing may be sent
loadWidget({ 0, 0, MAP_X, MAP_Z })
run(20, 30)
assert(#markers == 0, 'catch-up sent ' .. #markers .. ' lines')
-- Caught up: real time sim, lines go out
run(5, 3)
assert(#markers > 0, 'nothing drawn after catching up')

-- Pregame (frame 0) counts as live
loadWidget({ 0, 0, MAP_X, MAP_Z })
run(60, 0)
local fullGrid = #markers
assert(said == 1, 'hint said ' .. said .. ' times')

-- Another player's widget already posted the hint, in whatever wording
loadWidget({ 0, 0, MAP_X, MAP_Z })
widget:AddConsoleLine('<Lu5ck> Please turn off Auto Erase Map Marks in your Settings')
run(60, 0)
assert(#markers == fullGrid, 'chat hint changed the drawing')
assert(said == 0, 'hint repeated after another player posted it')

-- Another player's widget draws the same grid, we are playerID 1
local fullGridLines = markers
local function drawnBy(playerID)
	for _, m in ipairs(fullGridLines) do
		widget:MapDrawCmd(playerID, 'line', m[1], 0, m[2], m[3], 0, m[4])
	end
end

loadWidget({ 0, 0, MAP_X, MAP_Z })
drawnBy(0)
run(60, 0)
assert(#markers == 0, 'drew ' .. #markers .. ' lines a lower playerID keeps up')
-- They never redraw: their pregame lines are erased at frame 1800, we take over one cycle later
run(150, 3)
assert(#markers == fullGrid, 'took over ' .. #markers .. ' of ' .. fullGrid .. ' lines')

loadWidget({ 0, 0, MAP_X, MAP_Z })
drawnBy(2)
run(60, 0)
assert(#markers == fullGrid, 'yielded to a higher playerID')

loadWidget(BOX)
run(60, 0)
assertAllNear(BOX, 'engine box')
assert(#markers < fullGrid, 'engine box did not clip')

-- Polygon config wins over the engine rectangle, which BAR widens to the polygon bounds
loadWidget({ 0, 0, MAP_X, MAP_Z }, BOX)
run(60, 0)
assertAllNear(BOX, 'polygon box, older BAR')

loadWidget({ 0, 0, MAP_X, MAP_Z }, BOX, true)
run(60, 0)
assertAllNear(BOX, 'polygon box, newer BAR')

print('raptor line grid draw tests passed (' .. fullGrid .. ' lines in the full grid)')
