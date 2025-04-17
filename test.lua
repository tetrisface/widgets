function widget:GetInfo()
	return {
		desc = 'Debug Shader Health Bar',
		author = 'TetrisCo',
		version = '1.0',
		date = '2025-04-17',
		name = 'Debug Shader Health Bar',
		license = 'GPLv2 or later',
		layer = -345345345,
		enabled = true,
		depends = { 'gl4' },
	}
end

-- Configuration
local posX = 100
local posY = 100
local width = 300
local height = 30
local health = 0.75 -- Initial health value

-- Debug
local debugInfo = 'Debug info will appear here'
local useShader = false
local frameCount = 0
local shaderErrors = ''

-- GL objects
local testVAO
local testVBO
local testShader

local luaShaderDir = 'LuaUI/Include/'
local LuaShader = VFS.Include(luaShaderDir .. 'LuaShader.lua')

local vsSrc = [[
#version 330 core

layout(location = 0) in vec2 position;

uniform int posX;
uniform int posY;
uniform int width;
uniform int height;
uniform int screenWidth;
uniform int screenHeight;
uniform float healthValue;

void main() {
    // Map quad to health bar size and position
    vec2 size = vec2(width * healthValue, height);
    vec2 screenPos = vec2(posX, posY) + position * size;

    // Convert to NDC
    vec2 ndc = (screenPos / vec2(screenWidth, screenHeight)) * 2.0 - 1.0;
    ndc.y = -ndc.y;  // Y inversion

    gl_Position = vec4(ndc, 0.0, 1.0);
}
]]

local fsSrc = [[
#version 330 core

uniform float healthValue;
out vec4 fragColor;

void main() {
    // Red to green based on health
    vec3 color = mix(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), healthValue);
    fragColor = vec4(color, 1.0);
}
]]

-- Linear interpolation between two colors
local function lerpColor(color1, color2, t)
	return {
		color1[1] + (color2[1] - color1[1]) * t,
		color1[2] + (color2[2] - color1[2]) * t,
		color1[3] + (color2[3] - color1[3]) * t,
		color1[4] or 1.0,
	}
end

-- Draw health bar with basic GL
local function drawBasicHealthBar()
	-- Background (empty health bar)
	gl.Color(0.3, 0.3, 0.3, 0.7)
	gl.Rect(posX, posY, posX + width, posY + height)

	-- Health color (lerp between red and green)
	local color = lerpColor({ 1.0, 0.0, 0.0, 0.9 }, { 0.0, 1.0, 0.0, 0.9 }, health)
	gl.Color(color[1], color[2], color[3], color[4])

	-- Health bar (filled portion)
	gl.Rect(posX, posY, posX + width * health, posY + height)

	-- Border
	gl.Color(1.0, 1.0, 1.0, 0.8)
	gl.LineWidth(2.0)
	gl.Shape(GL.LINE_LOOP, {
		{ v = { posX, posY } },
		{ v = { posX + width, posY } },
		{ v = { posX + width, posY + height } },
		{ v = { posX, posY + height } },
	})
end

-- Draw health bar with shader
local function drawShaderHealthBar()
	local vsx, vsy = Spring.GetViewGeometry()

	testShader:Activate()
	gl.Uniform(testShader:GetUniformLocation('posX'), posX)
	gl.Uniform(testShader:GetUniformLocation('posY'), posY)
	gl.Uniform(testShader:GetUniformLocation('width'), width)
	gl.Uniform(testShader:GetUniformLocation('height'), height)
	gl.Uniform(testShader:GetUniformLocation('screenWidth'), vsx)
	gl.Uniform(testShader:GetUniformLocation('screenHeight'), vsy)
	gl.Uniform(testShader:GetUniformLocation('healthValue'), health)

	gl.Culling(false)
	gl.DepthTest(false)
	gl.DepthMask(false)
	gl.Blending(true)

	testVAO:DrawArrays(GL.TRIANGLE_STRIP, 0, 4)

	testShader:Deactivate()
	gl.Blending(false)
end

function widget:Initialize()
	-- Create basic quad VBO for unit square
	testVBO = gl.GetVBO(GL.ARRAY_BUFFER, false)
	if not testVBO then
		shaderErrors = shaderErrors .. 'Failed to create VBO. '
		return false
	end

	-- Define VBO layout
	local success = pcall(function()
		testVBO:Define(4, {
			{ id = 0, name = 'position', size = 2 },
		})
	end)

	if not success then
		shaderErrors = shaderErrors .. 'Failed to define VBO. '
		return false
	end

	-- Upload data
	success = pcall(function()
		testVBO:Upload({
			0.0,
			0.0, -- Bottom-left
			1.0,
			0.0, -- Bottom-right
			0.0,
			1.0, -- Top-left
			1.0,
			1.0, -- Top-right
		})
	end)

	if not success then
		shaderErrors = shaderErrors .. 'Failed to upload VBO data. '
		return false
	end

	-- Create VAO
	testVAO = gl.GetVAO()
	if not testVAO then
		shaderErrors = shaderErrors .. 'Failed to create VAO. '
		return false
	end

	-- Attach VBO
	success = pcall(function()
		testVAO:AttachVertexBuffer(testVBO)
	end)

	if not success then
		shaderErrors = shaderErrors .. 'Failed to attach vertex buffer. '
		return false
	end

	-- Create and initialize shader
	testShader = LuaShader({
		vertex = vsSrc,
		fragment = fsSrc,
		uniformInt = {
			posX = posX,
			posY = posY,
			width = width,
			height = height,
			screenWidth = 1,
			screenHeight = 1,
		},
		uniformFloat = {
			healthValue = health,
		},
	}, 'TestHealthBarShader')

	if not testShader then
		shaderErrors = shaderErrors .. 'Failed to create shader. '
		return false
	end

	local shaderInitialized = pcall(function()
		return testShader:Initialize()
	end)

	if not shaderInitialized then
		shaderErrors = shaderErrors .. 'Failed to initialize shader. '
		return false
	end

	debugInfo = 'Initialization complete'
	return true
end

function widget:DrawScreen()
	-- Animate health for testing
	health = 0.5 + 0.5 * math.sin(Spring.GetGameFrame() / 30)

	-- Draw health bar using appropriate method
	if useShader and testVAO and testShader then
		local success, err = pcall(drawShaderHealthBar)
		if not success then
			drawBasicHealthBar()
			debugInfo = 'Shader draw failed: ' .. tostring(err)
		else
			debugInfo = 'Using shader'
		end
	else
		drawBasicHealthBar()
		if shaderErrors ~= '' then
			debugInfo = 'Using basic GL - ' .. shaderErrors
		else
			debugInfo = 'Using basic GL'
		end
	end

	-- Draw debug text
	gl.Color(1.0, 1.0, 1.0, 1.0)
	gl.Text('Health: ' .. string.format('%.2f', health), posX + 10, posY + height / 2 - 5, 14)
	gl.Text(debugInfo, posX, posY + height + 10, 14)
	gl.Text('Press Alt+S to toggle shader', posX, posY + height + 30, 14)

	-- Reset color
	gl.Color(1.0, 1.0, 1.0, 1.0)
end

function widget:KeyPress(key, mods, isRepeat)
	if key == 115 and mods.alt then -- Alt+S
		useShader = not useShader
		return true
	end
	return false
end

function widget:GameFrame(frameNum)
	frameCount = frameNum
end

function widget:Shutdown()
	if testVAO then
		testVAO:Delete()
	end

	if testVBO then
		testVBO:Delete()
	end

	if testShader then
		testShader:Finalize()
	end
end
