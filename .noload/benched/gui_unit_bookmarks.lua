function widget:GetInfo()
	return {
		desc = 'Draws health bar for commander, and perhaps more',
		author = 'TetrisCo',
		version = '',
		date = '2025-04-17',
		name = 'Unit Bookmarks (Commander Health Bar)',
		license = 'GPLv2 or later',
		layer = -99990,
		enabled = true,
		depends = { 'gl4' },
	}
end

-- stylua: ignore start
local DiffTimers            = Spring.DiffTimers
local GetTeamUnitsByDefs    = Spring.GetTeamUnitsByDefs
local GetTimer              = Spring.GetTimer
local GetUnitDefID          = Spring.GetUnitDefID
local GetUnitHealth         = Spring.GetUnitHealth
local UnitDefs              = UnitDefs
local GL_KEEP               = 0x1E00

-- Static
local red                   = { 1.0, 0.0, 0.0 }  -- Color for low health
local green                 = { 0.0, 1.0, 0.0 }  -- Color for full health

-- Dynamic
local drawCheckTimer        = GetTimer()
local bookmarksUpdateTimer  = GetTimer()
local bookmarks             = {}
local nBookmarks            = 0
local commanderDefIDs       = {}
local updateCommandersMs    = 100  -- Initial update rate in ms

local windowPositionX = 100
local windowPositionY = 100
local windowWidth = 300
local windowHeight = 40

-- stylua: ignore end

-- GL4 objects
local bookmarksVBOInstances
local bookmarksVAO
local bookmarksShader
local windowPositionXUniform
local windowPositionYUniform
local windowWidthUniform
local windowHeightUniform
local color0Uniform
local color1Uniform
local viewportSizeXUniform
local viewportSizeYUniform

local vsSrc = [[
#version 420


// per vertex attributes
layout (location = 0) in vec4 xyuv; // each vertex of the rectVBO, range [0,1]
layout (location = 1) in vec4 tilingvector; // TODO: binary vector of tiling factors?

// per instance attributes, hmm, 32 floats per instance....

// ---- Inputs ----
layout(location = 0) in vec3  position;     // quad position
layout(location = 1) in float health;       // unit health ratio [0..1]
layout(location = 2) in float activity;     // activity indicator

// ---- Uniforms ----
uniform int windowPositionX;         // bar origin in screen space (x)
uniform int windowPositionY;         // bar origin (y)
uniform int windowWidth;             // full width of the bar when health == 1
uniform int windowHeight;            // height of the bar
uniform int viewportSizeX;           // screen width
uniform int viewportSizeY;           // screen height
uniform vec3 color0;                 // color at health=0.0
uniform vec3 color1;                 // color at health=1.0

// ---- Outputs ----
flat out vec3 vColor;                // flat: same color for all fragments of the bar

//__ENGINEUNIFORMBUFFERDEFS__

// ---- Ramp function ----
vec3 ramp(float h) {
    // simple two stop linear ramp; clamp to [0,1]
    return mix(color0, color1, clamp(h, 0.0, 1.0));
}

void main() {
    // Map quad vertices to screen space (in pixels)
    vec2 screenPos = vec2(windowPositionX, windowPositionY)
                   + position.xy * vec2(windowWidth * health, windowHeight);

    // Convert to normalized device coordinates (NDC: [-1,1])
    vec2 resolution = vec2(viewportSizeX, viewportSizeY);
    vec2 ndc = (screenPos / resolution) * 2.0 - 1.0;
    ndc.y = -ndc.y; // Flip Y because screen Y goes down, NDC Y goes up

    gl_Position = vec4(ndc, 0.0, 1.0);

    vColor = ramp(health);
}
]]

local fsSrc = [[
#version 420

flat in vec3 vColor;
out vec4 fragColor;

void main() {
    fragColor = vec4(vColor, 1.0);
}
]]

local function initGL4()
	-- Create geometry VBO for the quad
	local geometryVBO = gl.GetVBO(GL.ARRAY_BUFFER, false)
	geometryVBO:Define(4, {
		{ id = 0, name = 'position', size = 3 },
	})
	geometryVBO:Upload({
		0.0,
		0.0,
		0.0, -- Bottom-left
		1.0,
		0.0,
		0.0, -- Bottom-right
		0.0,
		1.0,
		0.0, -- Top-left
		1.0,
		1.0,
		0.0, -- Top-right
	})

	-- Create instance VBO for health and activity data
	bookmarksVBOInstances = gl.GetVBO(GL.ARRAY_BUFFER, true)
	bookmarksVBOInstances:Define(1000, {
		{ id = 1, name = 'health', size = 1 },
		{ id = 2, name = 'activity', size = 1 },
	})

	-- Create VAO and attach buffers
	bookmarksVAO = gl.GetVAO()
	bookmarksVAO:AttachVertexBuffer(geometryVBO)
	bookmarksVAO:AttachInstanceBuffer(bookmarksVBOInstances)

	-- Initialize shader
	local engineUniformBufferDefs = gl.LuaShader.GetEngineUniformBufferDefs()
	vsSrc = vsSrc:gsub('//__ENGINEUNIFORMBUFFERDEFS__', engineUniformBufferDefs)

	bookmarksShader = gl.LuaShader({
		vertex = vsSrc:gsub('//__DEFINES__', gl.LuaShader.CreateShaderDefinesString(shaderConfig)),
		fragment = fsSrc:gsub('//__DEFINES__', gl.LuaShader.CreateShaderDefinesString(shaderConfig)),
		uniformInt = {
			windowPositionX = windowPositionX,
			windowPositionY = windowPositionY,
			windowWidth = windowWidth,
			windowHeight = windowHeight,
			viewportSizeX = 1, -- Will be updated in Draw()
			viewportSizeY = 1, -- Will be updated in Draw()
		},
		uniformFloat = {
			color0 = red,
			color1 = green,
		},
	}, 'BookmarksShader')

	if not bookmarksShader:Initialize() then
		Spring.Echo('Failed to initialize bookmarks shader')
		widgetHandler:RemoveWidget()
		return false
	end

	-- Get uniform locations for dynamic updates
	windowPositionXUniform = gl.GetUniformLocation(bookmarksShader.shaderObj, 'windowPositionX')
	windowPositionYUniform = gl.GetUniformLocation(bookmarksShader.shaderObj, 'windowPositionY')
	windowWidthUniform = gl.GetUniformLocation(bookmarksShader.shaderObj, 'windowWidth')
	windowHeightUniform = gl.GetUniformLocation(bookmarksShader.shaderObj, 'windowHeight')
	color0Uniform = gl.GetUniformLocation(bookmarksShader.shaderObj, 'color0')
	color1Uniform = gl.GetUniformLocation(bookmarksShader.shaderObj, 'color1')
	viewportSizeXUniform = gl.GetUniformLocation(bookmarksShader.shaderObj, 'viewportSizeX')
	viewportSizeYUniform = gl.GetUniformLocation(bookmarksShader.shaderObj, 'viewportSizeY')

	return true
end

local function unitData(unitID)
	local health, maxHealth = Spring.GetUnitHealth(unitID)
	if not health or not maxHealth or maxHealth == 0 then
		return {
			health = 1.0,
			activity = 1.0,
		}
	end
	return {
		health = health / maxHealth,
		activity = 1.0,
	}
end

function widget:Initialize()
	bookmarksUpdateTimer = GetTimer()
	bookmarks = {}
	nBookmarks = 0

	-- Find all commander defIDs
	for id, unitDef in pairs(UnitDefs) do
		if unitDef.customParams and unitDef.customParams.iscommander then
			table.insert(commanderDefIDs, id)
		end
	end

	-- If no commanders found, add a test entry
	if #commanderDefIDs == 0 then
		bookmarks[1] = {
			health = 0.75,
			activity = 1.0,
		}
		nBookmarks = 1
	else
		-- Get all commanders for the player's team
		local commanderIDs = GetTeamUnitsByDefs(Spring.GetMyTeamID(), commanderDefIDs)
		if commanderIDs then
			for i = 1, #commanderIDs do
				local commanderID = commanderIDs[i]
				bookmarks[i] = unitData(commanderID)
				nBookmarks = nBookmarks + 1
			end
		end
	end

	-- If still no bookmarks, add a test entry
	if nBookmarks == 0 then
		bookmarks[1] = {
			health = 0.5,
			activity = 1.0,
		}
		nBookmarks = 1
	end

	return initGL4()
end

local function UpdateBookmarks()
	if DiffTimers(GetTimer(), bookmarksUpdateTimer, true) < updateCommandersMs then
		return
	end
	bookmarksUpdateTimer = GetTimer()

	-- Update commander health data
	if #commanderDefIDs > 0 then
		local commanderIDs = GetTeamUnitsByDefs(Spring.GetMyTeamID(), commanderDefIDs)
		bookmarks = {}
		nBookmarks = 0

		if commanderIDs then
			for i = 1, #commanderIDs do
				local commanderID = commanderIDs[i]
				bookmarks[i] = unitData(commanderID)
				nBookmarks = nBookmarks + 1
			end
		end
	end

	-- If no bookmarks, add test data
	if nBookmarks == 0 then
		bookmarks[1] = {
			health = math.abs(math.sin(Spring.GetGameFrame() / 300)), -- Animate health for testing
			activity = 1.0,
		}
		nBookmarks = 1
	end

	-- Prepare VBO data
	local vboData = {}
	for i, bookmark in pairs(bookmarks) do
		vboData[#vboData + 1] = bookmark.health
		vboData[#vboData + 1] = bookmark.activity
	end

	-- Upload data to GPU
	if bookmarksVBOInstances and nBookmarks > 0 and #vboData > 0 then
		bookmarksVBOInstances:Upload(vboData)
	end

	-- Adjust update rate based on the number of bookmarks
	updateCommandersMs = math.max(100, 100 + nBookmarks * 2)
end

function widget:Draw()
	UpdateBookmarks()
	if nBookmarks == 0 or not bookmarksShader or not bookmarksVAO then
		return
	end

	-- Get current viewport size
	local vsx, vsy = Spring.GetViewSizes()

	-- Activate shader
	bookmarksShader:Activate()

	-- Set rendering state
	gl.Culling(false)
	gl.DepthTest(false)
	gl.DepthMask(false)
	gl.Blending(true)

	-- Update uniforms
	gl.UniformInt(windowPositionXUniform, windowPositionX)
	gl.UniformInt(windowPositionYUniform, windowPositionY)
	gl.UniformInt(windowWidthUniform, windowWidth)
	gl.UniformInt(windowHeightUniform, windowHeight)
	gl.UniformInt(viewportSizeXUniform, vsx)
	gl.UniformInt(viewportSizeYUniform, vsy)
	gl.UniformFloat(color0Uniform, red[1], red[2], red[3])
	gl.UniformFloat(color1Uniform, green[1], green[2], green[3])

	-- Draw the health bars
	bookmarksVAO:DrawArrays(GL.TRIANGLE_STRIP, 0, 4, nBookmarks, 0)

	-- Deactivate shader
	bookmarksShader:Deactivate()

	-- Reset state
	gl.Blending(false)
end

function widget:Shutdown()
	if bookmarksVAO then
		bookmarksVAO:Delete()
	end

	if bookmarksVBOInstances then
		bookmarksVBOInstances:Delete()
	end

	if bookmarksShader then
		bookmarksShader:Finalize()
	end
end
