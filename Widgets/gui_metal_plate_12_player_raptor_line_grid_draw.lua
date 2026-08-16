function widget:GetInfo()
	return {
		name = 'Raptor Grid Draw 12 players (Full Metal Plate)',
		desc = 'Draws fairly distributed build border for 12 players raptor mode on Full Metal Plate map',
		author = 'Lu5ck',
		date = '31 May 2025',
		layer = 1,
		enabled = true,
	}
end

--[[
Border values
NONE = 0
TOP = 1
RIGHT = 2
BOTTOM = 4
LEFT = 8
Diagonal \ = 16
Diagonal / = 32

For multiple borders in same cell, add the value together
TOP and RIGHT border = 1 + 2 = 3
]]
--

-- stylua: ignore
local mapping = {
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2, 8, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2, 8, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 2, 8, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2, 8, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2, 8, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 2, 8, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2, 8, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2, 8, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 2, 8, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2, 8, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2, 8, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 2, 8, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2, 8, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2, 8, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 2, 8, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{4, 4, 4, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 4, 4, 4, 4},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6,12, 4, 4, 4, 4, 4, 4, 0, 4, 4, 4, 4, 4, 4, 4, 6,12, 4, 4, 4, 4, 4, 4, 4, 0, 4, 4, 4, 4, 4, 4, 6,12, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,16, 4, 4, 4, 4, 4, 0, 4, 4, 4, 4, 4, 4, 4, 6,12, 4, 4, 4, 4, 4, 4, 4, 0, 4, 4, 4, 4, 4,32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 6, 0, 0, 0, 0,16, 4, 4, 4, 4, 0, 4, 4, 4, 4, 4, 4, 4, 6,12, 4, 4, 4, 4, 4, 4, 4, 0, 4, 4, 4, 4,32, 0, 0, 0, 0,12, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4},
	{1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2,16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,32, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2,16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,32, 8, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 8, 8, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 8, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 8, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 8, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 8, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 8, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 8, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{4, 4, 4, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 8, 8, 0, 0, 0, 0, 0, 0, 0, 0, 4, 4, 4, 4, 4},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 8, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 8, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 8, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 6, 6, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,12,12,12, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4},
	{1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 3, 3, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9, 9, 9, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 8, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 8, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 8, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 8, 8, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 8, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 8, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 8, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 8, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 8, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 8, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{4, 4, 4, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 8, 8, 0, 0, 0, 0, 0, 0, 0, 0, 4, 4, 4, 4, 4},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2,32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,16, 8, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2,32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,16, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,12, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4},
	{1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 3, 0, 0, 0, 0,32, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 3, 9, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1,16, 0, 0, 0, 0, 9, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,32, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 3, 9, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1,16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 9, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 3, 9, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 3, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2, 8, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2, 8, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 2, 8, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2, 8, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2, 8, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 2, 8, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2, 8, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2, 8, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 2, 8, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2, 8, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2, 8, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 2, 8, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
	{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2, 8, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2, 8, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 2, 8, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
}

local gridsize = 12 -- 3 is nano, wind etc size. 12 is efus size. This define the cell size for the mapping
local gridsquare = 16 -- The smallest build grid to map size is 16x16

-- BAR ships "Auto mapmark eraser" enabled by default, which wipes every marker
-- eraseTime (default 60) seconds after it was drawn, on every client. So the grid has to
-- be re-sent forever. The margin makes sure a re-sent segment lands *after* the pending
-- erase: the eraser matches a line by its first point within a 100 elmo radius, so an
-- early redraw would only hand it a fresh copy to delete.
local ERASE_SECONDS = 60
local MARGIN_SECONDS = 1
local REDRAW_FRAMES = (ERASE_SECONDS + MARGIN_SECONDS) * 30

-- The grid is a placement aid, so stop maintaining it once the game is past that stage.
-- Whatever is on the map then survives until each client's eraser gets to it.
local STOP_FRAME = 13 * 60 * 30

local NOTICE = "To keep map lines for the whole match disable 'Auto erase map marks' in settings"

local timer = 0
local noticeSent = false

local lines = {} -- every segment of the grid, built once and then re-sent forever
local sendQueue = {} -- indices into lines awaiting transmission (workaround for spring draw spam protection)
local sendHead, sendTail = 1, 0
local pendingIndex, pendingDue = {}, {} -- sent segments awaiting their redraw, ordered by due frame
local pendingHead, pendingTail = 1, 0

local function pushSend(index)
	sendTail = sendTail + 1
	sendQueue[sendTail] = index
end

local function pushPending(index, dueFrame)
	pendingTail = pendingTail + 1
	pendingIndex[pendingTail] = index
	pendingDue[pendingTail] = dueFrame
end

local function drawLine(y, startX, startZ, endX, endZ)
	local maxLength = 24 * gridsquare

	local dx = endX - startX
	local dz = endZ - startZ
	local length = math.sqrt(dx * dx + dz * dz)

	local lengthCount = math.ceil(length / maxLength)

	for i = 0, lengthCount - 1 do
		local t1 = i / lengthCount
		local t2 = (i + 1) / lengthCount

		local sx = startX + dx * t1
		local sz = startZ + dz * t1
		local ex = startX + dx * t2
		local ez = startZ + dz * t2

		lines[#lines + 1] = { startX = sx, startZ = sz, endX = ex, endZ = ez, y = y }
	end
end

local function hasBit(val, bit)
	return math.floor(val / bit) % 2 == 1
end

-- BAR.Utilities is game-side and has been observed missing at Initialize time
-- (crashed with "attempt to index field 'Utilities'"), so fall back to the same
-- team LuaAI scan BAR's Gametype helpers use, which needs only engine API.
local function isPveGame()
	local gametype = BAR and BAR.Utilities and BAR.Utilities.Gametype
	if gametype then
		return gametype.IsRaptors() or gametype.IsScavengers()
	end
	for _, teamID in ipairs(Spring.GetTeamList() or {}) do
		local luaAI = Spring.GetTeamLuaAI(teamID)
		if luaAI and (string.find(luaAI, 'Raptors') or string.find(luaAI, 'Scavengers')) then
			return true
		end
	end
	return false
end

function widget:Initialize()
	if Spring.GetSpectatingState() then
		widgetHandler:RemoveWidget() -- Don't draw when spectating
		return
	end

	if not isPveGame() then
		widgetHandler:RemoveWidget() -- Don't draw when not pve
		return
	end

	-- Substring so future Full Metal Plate revisions keep working. The row/column check
	-- below still rejects any revision whose size no longer matches the mapping.
	if not string.find(string.lower(Game.mapName or ''), 'full metal plate', 1, true) then
		widgetHandler:RemoveWidget() -- Don't draw when not supported map
		return
	end

	local cellsize = gridsize * gridsquare
	local expectedRows = Game.mapSizeZ / cellsize
	local expectedCols = Game.mapSizeX / cellsize
	if #mapping ~= expectedRows then
		Spring.Echo('Error: Mapping has ' .. #mapping .. ' rows, expected ' .. expectedRows)
		widgetHandler:RemoveWidget()
		return
	end

	for row = 1, #mapping do
		if #mapping[row] ~= expectedCols then
			Spring.Echo('Error: Row ' .. row .. ' has ' .. #mapping[row] .. ' columns, expected ' .. expectedCols)
			widgetHandler:RemoveWidget()
			return
		end
	end

	for row = 1, #mapping do
		for col = 1, #mapping[row] do
			local val = mapping[row][col]
			local x = (col - 1) * cellsize
			local z = (row - 1) * cellsize

			if hasBit(val, 1) then
				drawLine(0, x, z, x + cellsize, z) -- Top
			end
			if hasBit(val, 2) then
				drawLine(0, x + cellsize, z, x + cellsize, z + cellsize) -- Right
			end
			if hasBit(val, 4) then
				drawLine(0, x, z + cellsize, x + cellsize, z + cellsize) -- Bottom
			end
			if hasBit(val, 8) then
				drawLine(0, x, z, x, z + cellsize) -- Left
			end
			if hasBit(val, 16) then
				drawLine(0, x, z, x + cellsize, z + cellsize) -- Diagonal \
			end
			if hasBit(val, 32) then
				drawLine(0, x + cellsize, z, x, z + cellsize) -- Diagonal /
			end
		end
	end

	for i = 1, #lines do
		pushSend(i)
	end
end

function widget:Update(dt)
	-- Game frames, not dt, so we stall together with the eraser when the game is paused
	local frame = Spring.GetGameFrame()

	if frame >= STOP_FRAME then
		widgetHandler:RemoveWidget() -- Done redrawing, stop the widget
		return
	end

	-- Due frames are monotonic, so the head is always the next segment to come back
	while pendingHead <= pendingTail and pendingDue[pendingHead] <= frame do
		pushSend(pendingIndex[pendingHead])
		pendingIndex[pendingHead] = nil
		pendingDue[pendingHead] = nil
		pendingHead = pendingHead + 1
	end
	if pendingHead > pendingTail then -- fully drained, rewind so the tables stay flat
		pendingHead, pendingTail = 1, 0
	end

	if sendHead > sendTail then
		return -- nothing due, keep timer where it is so the next redraw goes out at once
	end

	timer = timer + dt
	if timer <= 0.1 then
		return
	end
	timer = 0

	local dueFrame = frame + REDRAW_FRAMES
	for _ = 1, 10 do -- Draw 10 lines at a time, I think max is 12?
		if sendHead > sendTail then
			break
		end
		local line = lines[sendQueue[sendHead]]
		Spring.MarkerAddLine(line.startX, line.y, line.startZ, line.endX, line.y, line.endZ)
		pushPending(sendQueue[sendHead], dueFrame)
		sendQueue[sendHead] = nil
		sendHead = sendHead + 1
	end

	if sendHead > sendTail then
		sendHead, sendTail = 1, 0
		if not noticeSent then -- once per match, the redraws must not repeat it
			noticeSent = true
			Spring.SendCommands('say ' .. NOTICE) -- no prefix, so players and spectators both see it
		end
	end
end
