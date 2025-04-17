function widget:GetInfo()
	return {
		desc = 'Extremely Basic Drawing Test',
		author = 'TetrisCo',
		version = '1.0',
		date = '2025-04-17',
		name = 'Basic Drawing Test',
		license = 'GPLv2 or later',
		layer = -1341341340, -- Very high layer to make sure it's on top
		enabled = true,
	}
end

-- Constants
local posX = 200
local posY = 200
local width = 300
local height = 40

function widget:DrawScreen()
	-- Draw a red rectangle
	gl.Color(1.0, 0.0, 0.0, 1.0)
	gl.Rect(posX, posY, posX + width, posY + height)

	-- Draw outline
	gl.Color(1.0, 1.0, 1.0, 1.0)
	gl.LineWidth(2.0)
	gl.Shape(GL.LINE_LOOP, {
		{ v = { posX, posY } },
		{ v = { posX + width, posY } },
		{ v = { posX + width, posY + height } },
		{ v = { posX, posY + height } },
	})

	-- Draw text
	gl.Text('Test Rectangle', posX + 10, posY + height / 2, 14)

	-- Reset color
	gl.Color(1.0, 1.0, 1.0, 1.0)
end
function widget:Initialize()
	local asdf = 1242345
end
