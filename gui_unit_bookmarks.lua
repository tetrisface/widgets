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
local GetTimer              = Spring.GetTimer
local UnitDefs              = UnitDefs
local GL_KEEP               = 0x1E00

-- Static
local cyan                  = { 42 / 255, 161 / 255, 152 / 255, 152 / 255 }
local orange                = { 203 / 255, 75 / 255, 22 / 255, 22 / 255 }

-- Dynamic
local drawCheckTimer        = GetTimer()
local bookmarksUpdateTimer = GetTimer()
local bookmarks             = {}
local nBookmarks            = 0
local commanderDefIDs       = {}
local updateCommandersMs    = 0

local windowPositionX = 500
local windowPositionY = 200
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

local luaShaderDir = 'LuaUI/Include/'
local LuaShader = VFS.Include(luaShaderDir .. 'LuaShader.lua')

local vsSrc = [[
#version 420

// ---- Inputs ----
layout(location = 0) in vec3  unitPosition;  // unit space (x,y,z), e.g. (0,0)-(1,1)
layout(location = 1) in float health;        // unit health ratio [0..1]
layout(location = 2) in float activity;

// ---- Uniforms ----
uniform int windowPositionX;           // bar origin in NDC or screen space (x)
uniform int windowPositionY;           // bar origin (y)
uniform int windowWidth;          // full width of the bar when health == 1
uniform int windowHeight;         // height of the bar

// Color stops (extend to more stops as needed)
uniform vec3 color0;             // color at health=0.0
uniform vec3 color1;             // color at health=1.0

// ---- Outputs ----
flat out vec3 vColor;            // flat: same color for all fragments of the bar

//__ENGINEUNIFORMBUFFERDEFS__

// ---- Ramp function ----
vec3 ramp( float h ) {
    // simple two stop linear ramp; clamp to [0,1]
    return mix(color0, color1, clamp(h, 0.0, 1.0));
}
int guViewSizeX = 800;
int guViewSizeY = 800;
void main() {
    // Map quad vertices to screen space (in pixels)
    vec2 screenPos = vec2(windowPositionX, windowPositionY)
                   + unitPosition.xy * vec2(windowWidth, windowHeight);

    // Convert to normalized device coordinates (NDC: [-1,1])
    vec2 resolution = vec2(guViewSizeX, guViewSizeY); // Engine provides this
    vec2 ndc = (screenPos / resolution) * 2.0 - 1.0;
    ndc.y = -ndc.y; // Flip Y because screen Y goes down, NDC Y goes up

    gl_Position = vec4(ndc, 0.0, 1.0);

    //vColor = ramp(health);
		vColor = vec3(1.0, 0.0, 1.0); // hot pink
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

local healthStripVBOSize = 5

local function initGL4()
	local geometryVBO = gl.GetVBO(GL.ARRAY_BUFFER, false)
	geometryVBO:Define(4, {
		{ id = 0, name = 'unitPosition', size = 3 },
	})
	geometryVBO:Upload({ -0.5, -0.5, 0.0, 0.5, -0.5, 0.0, -0.5, 0.5, 0.0, 0.5, 0.5, 0.0 })

	bookmarksVBOInstances = gl.GetVBO(GL.ARRAY_BUFFER, true)

	local bookmarksInstanceVBOLayout = {
		-- { id = 0, name = 'unitPosition', size = 3 }, -- position (x,y,z)
		{ id = 1, name = 'health', size = 1 },
		{ id = 2, name = 'activity', size = 1 },
	}

	bookmarksVBOInstances:Define(1000, bookmarksInstanceVBOLayout)

	bookmarksVAO = gl.GetVAO()
	bookmarksVAO:AttachVertexBuffer(geometryVBO)
	bookmarksVAO:AttachInstanceBuffer(bookmarksVBOInstances)

	local engineUniformBufferDefs = LuaShader.GetEngineUniformBufferDefs()
	vsSrc = vsSrc:gsub('//__ENGINEUNIFORMBUFFERDEFS__', engineUniformBufferDefs)

	bookmarksShader = LuaShader({
		vertex = vsSrc,
		fragment = fsSrc,
		uniformInt = {
			windowPositionX = 0,
			windowPositionY = 0,
		},
	}, 'BookmarksShader')

	if not bookmarksShader:Initialize() then
		Spring.Echo('Failed to initialize bookmarks shader')
		widgetHandler:RemoveWidget()
		return false
	end

	windowPositionXUniform = gl.GetUniformLocation(bookmarksShader.shaderObj, 'windowPositionX')
	windowPositionYUniform = gl.GetUniformLocation(bookmarksShader.shaderObj, 'windowPositionY')
	windowWidthUniform = gl.GetUniformLocation(bookmarksShader.shaderObj, 'windowWidth')
	windowHeightUniform = gl.GetUniformLocation(bookmarksShader.shaderObj, 'windowHeight')

	return true
end

local function unitData(unitID)
	local health, maxHealth = Spring.GetUnitHealth(unitID)
	return {
		unitPosition = { Spring.GetUnitPosition(unitID, true) },
		health = health / maxHealth,
	}
end

function widget:Initialize()
	bookmarksUpdateTimer = GetTimer()
	bookmarks = {}
	nBookmarks = 0
	bookmarks = {}

	for id, unitDef in pairs(UnitDefs) do
		if unitDef.customParams.iscommander then
			table.insert(commanderDefIDs, id)
		end
	end

	local commanderIDs = Spring.GetTeamUnitsByDefs(Spring.GetMyTeamID(), commanderDefIDs)
	Spring.Echo('commanderIDs', commanderIDs)
	for i = 1, #commanderIDs do
		local commanderID = commanderIDs[i]
		bookmarks[commanderID] = unitData(commanderID)
		nBookmarks = nBookmarks + 1
	end

	Spring.Echo('bookmarks', bookmarks)

	return initGL4()
end

local function UpdateBookmarks()
	if DiffTimers(GetTimer(), bookmarksUpdateTimer, true) < updateCommandersMs then
		return
	end
	bookmarksUpdateTimer = GetTimer()

	for bookmarkUnitID, bookmark in pairs(bookmarks) do
		bookmark = unitData(bookmarkUnitID)
	end

	Spring.Echo('bookmarks vbo', bookmarks)
	local vbo = {}
	local i = 0
	for _, bookmark in pairs(bookmarks) do
		i = i + 1
		local vboOffset = (i - 1) * healthStripVBOSize
		vbo[vboOffset + 1] = bookmark.unitPosition[1]
		vbo[vboOffset + 2] = bookmark.unitPosition[2]
		vbo[vboOffset + 3] = bookmark.unitPosition[3]
		vbo[vboOffset + 4] = bookmark.health
		vbo[vboOffset + 5] = 1234.1234
	end

	Spring.Echo('vbo', vbo)
	if bookmarksVBOInstances and nBookmarks > 0 and #vbo > 0 then
		bookmarksVBOInstances:Upload(vbo)
	end

	updateCommandersMs = math.max(100, 100 + nBookmarks * 2)
end

function widget:Draw()
	UpdateBookmarks()
	if nBookmarks == 0 or not bookmarksShader or not bookmarksVAO then
		return
	end

	bookmarksShader:Activate()

	gl.Culling(false)
	gl.DepthTest(false)
	gl.DepthMask(false)

	gl.UniformInt(windowPositionXUniform, windowPositionX)
	gl.UniformInt(windowPositionYUniform, windowPositionY)
	gl.UniformInt(windowWidthUniform, windowWidth)
	gl.UniformInt(windowHeightUniform, windowHeight)

	bookmarksVAO:DrawArrays(GL.TRIANGLE_STRIP, 0, 4, nBookmarks, 0)

	bookmarksShader:Deactivate()
end

function widget:Shutdown()
	if bookmarksVBOInstances and bookmarksVBOInstances.VAO then
		bookmarksVBOInstances.VAO:Delete()
	end

	if bookmarksShader then
		bookmarksShader:Finalize()
	end
end
