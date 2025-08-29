function widget:GetInfo()
	return {
		name = 'Building Grid GL4',
		desc = 'Draw a configurable grid to assist build spacing',
		author = 'Hobo Joe, Beherith, LSR, myriari, tetrisface',
		date = 'June 2023',
		license = 'GNU GPL, v2 or later',
		version = 0.2,
		layer = -1,
		enabled = false
	}
end

local opacity = 0.5

local config = {
	gridSize = 3, -- smallest footprint is size 1 (perimeter camera), size 3 is the size of nanos, winds, etc
	strongLineSpacing = 4, -- which interval produces heavy lines
	strongLineOpacity = 0.60, -- opacity of heavy lines
	weakLineOpacity = 0.18, -- opacity of intermediate lines
	gridRadius = 90, -- how far from the cursor the grid should show. Same units as gridSize
	gridRadiusFalloff = 2.5, -- how sharply the grid should get cut off at max distance
	maxViewDistance = 3000.0, -- distance at which the grid no longer renders
	lineColor = {0.70, 1.0, 0.70} -- color of the lines
}

local waterLevel = Spring.GetModOptions().map_waterlevel

local gridVBO = nil -- the vertex buffer object, an array of vec2 coords
local gridVAO = nil -- the vertex array object, a way of collecting buffer objects for submission to opengl
local gridShader = nil -- the shader itself
local spacing = config.gridSize * 16 -- the repeat rate of the grid

local shaderConfig = {
	-- These will be replaced in the shader using #defines's
	LINECOLOR = 'vec3(' .. config.lineColor[1] .. ', ' .. config.lineColor[2] .. ', ' .. config.lineColor[3] .. ')',
	GRIDRADIUS = config.gridRadius,
	RADIUSFALLOFF = config.gridRadiusFalloff,
	MAXVIEWDIST = config.maxViewDistance
}

local vsSrc =
	[[
#version 420
#extension GL_ARB_uniform_buffer_object : require
#extension GL_ARB_shader_storage_buffer_object : require
#extension GL_ARB_shading_language_420pack: require

layout (location = 0) in vec3 position; // xz world position, 3rd value is opacity

//__ENGINEUNIFORMBUFFERDEFS__
//__DEFINES__

#line 10000

out vec4 v_worldPos;
out vec4 v_color; // this is unused, but you can pass some stuff to fragment shader from here

uniform sampler2D heightmapTex; // the heightmap texture
uniform float waterLevel;
uniform int waterSurfaceMode;

#line 11000
void main(){
	v_worldPos.xz = position.xy;
	float alpha = position.z; // sneaking in an alpha value on the position input
	vec2 uvhm = heightmapUVatWorldPos(v_worldPos.xz); // this function gets the UV coords of the heightmap texture at a world position
	v_worldPos.y = textureLod(heightmapTex, uvhm, 0.0).x;
	if (waterSurfaceMode > 0) {
		v_worldPos.y = max(waterLevel, v_worldPos.y);
	}

	v_color = vec4(LINECOLOR, alpha);
	gl_Position = cameraViewProj * vec4(v_worldPos.xyz, 1.0);  // project it into camera
}
]]

local fsSrc =
	[[
#version 420
#extension GL_ARB_uniform_buffer_object : require
#extension GL_ARB_shading_language_420pack: require
//__ENGINEUNIFORMBUFFERDEFS__
//__DEFINES__

in vec4 v_worldPos;
in vec4 v_color;

out vec4 fragColor; // the output color

uniform vec3 mousePos;

void main(void) {
	float maxDist = MAXVIEWDIST;
	vec3 camPos = cameraViewInv[3].xyz;
    float dist = distance(v_worldPos.xyz, mousePos.xyz);
	// Specifiy the color of the output line
	float fadeDist = GRIDRADIUS * 16.0;
    float alpha = smoothstep(0.0, 1.0, ((fadeDist / (dist / RADIUSFALLOFF))) - RADIUSFALLOFF);
    float camDist = distance(camPos, mousePos.xyz);
    float distAlpha = smoothstep(0.0, 1.0, 1.0 - (maxDist / camDist));
	fragColor.rgba = vec4(v_color.rgb, (alpha - (distAlpha * 1.75)) * (v_color.a));
}
]]

local function goodbye(reason)
	Spring.Echo('Building Grid GL4 widget exiting with reason: ' .. reason)
	widgetHandler:RemoveWidget()
end

local mousePosUniform
local waterSurfaceModeUniform

function initShader()
	local engineUniformBufferDefs = gl.LuaShader.GetEngineUniformBufferDefs() -- all the camera and other lovely stuff
	vsSrc = vsSrc:gsub('//__ENGINEUNIFORMBUFFERDEFS__', engineUniformBufferDefs)
	fsSrc = fsSrc:gsub('//__ENGINEUNIFORMBUFFERDEFS__', engineUniformBufferDefs)
	gridShader =
		gl.LuaShader(
		{
			vertex = vsSrc:gsub('//__DEFINES__', gl.LuaShader.CreateShaderDefinesString(shaderConfig)),
			fragment = fsSrc:gsub('//__DEFINES__', gl.LuaShader.CreateShaderDefinesString(shaderConfig)),
			uniformInt = {
				heightmapTex = 0, -- the index of the texture uniform sampler2D
				waterSurfaceMode = 0
			},
			uniformFloat = {
				waterLevel = waterLevel,
				mousePos = {0.0, 0.0, 0.0}
			}
		},
		'gridShader'
	)
	local shaderCompiled = gridShader:Initialize()
	if not shaderCompiled then
		goodbye('Failed to compile gridshader GL4 ')
		return
	end

	mousePosUniform = gl.GetUniformLocation(gridShader.shaderObj, 'mousePos')
	waterSurfaceModeUniform = gl.GetUniformLocation(gridShader.shaderObj, 'waterSurfaceMode')
end

function widget:Initialize()
	WG['buildinggrid'] = {}
	WG['buildinggrid'].getOpacity = function()
		return opacity
	end
	WG['buildinggrid'].setOpacity = function(value)
		opacity = value
		-- widget needs reloading wholly
	end
	-- WG['buildinggrid'].setForceShow = function(reason, enabled, unitDefID)
	-- 	if enabled then
	-- 		forceShow[reason] = unitDefID
	-- 	else
	-- 		forceShow[reason] = nil
	-- 	end
	-- end

	initShader()

	if gridVBO then
		return
	end

	local VBOData = {} -- the lua array that will be uploaded to the GPU
	for row = 0, Game.mapSizeX, spacing do
		for col = 0, Game.mapSizeZ, spacing do
			if row ~= Game.mapSizeX then -- skip last
				local strength =
					((col / spacing) % config.strongLineSpacing == 0 and config.strongLineOpacity or config.weakLineOpacity) * opacity
				-- vertical lines
				VBOData[#VBOData + 1] = row
				VBOData[#VBOData + 1] = col
				VBOData[#VBOData + 1] = strength
				VBOData[#VBOData + 1] = row + spacing
				VBOData[#VBOData + 1] = col
				VBOData[#VBOData + 1] = strength
			end

			if col ~= Game.mapSizeZ then -- skip last
				local strength =
					((row / spacing) % config.strongLineSpacing == 0 and config.strongLineOpacity or config.weakLineOpacity) * opacity
				-- horizonal lines
				VBOData[#VBOData + 1] = row
				VBOData[#VBOData + 1] = col
				VBOData[#VBOData + 1] = strength
				VBOData[#VBOData + 1] = row
				VBOData[#VBOData + 1] = col + spacing
				VBOData[#VBOData + 1] = strength
			end
		end
	end

	gridVBO = gl.GetVBO(GL.ARRAY_BUFFER, false)
	-- this is 2d position + opacity
	gridVBO:Define(
		#VBOData / 3,
		{
			{
				id = 0,
				name = 'position',
				size = 3
			}
		}
	) -- number of elements (vertices), size is 2 for the vec2 position
	gridVBO:Upload(VBOData)
	gridVAO = gl.GetVAO()
	gridVAO:AttachVertexBuffer(gridVBO)
end

function widget:DrawWorld()
	local mx, my = Spring.GetMouseState()
	local _, pos = Spring.TraceScreenRay(mx, my, true)
	if not pos then
		return
	end

	local gridSize = spacing
	local xStep = gridSize * config.strongLineSpacing
	local radius = 2000
	local fontSize = gridSize * 0.5

	local startX = math.max(0, math.floor((pos[1] - radius) / xStep) * xStep)
	local endX = math.min(Game.mapSizeX, math.ceil((pos[1] + radius) / xStep) * xStep)
	local startZ = math.max(0, math.floor((pos[3] - radius) / xStep) * xStep)
	local endZ = math.min(Game.mapSizeZ, math.ceil((pos[3] + radius) / xStep) * xStep)

	-- Get camera direction for proper label rotation
	local camDirX, _, camDirZ = Spring.GetCameraDirection()
	local camYaw = math.atan2(camDirX, camDirZ) * 180 / math.pi
	-- Snap to 90-degree steps
	local camYawSnapped = math.floor((camYaw + 45) / 90) * 90

	gl.PushMatrix()
	gl.DepthTest(GL.LEQUAL)

	for x = startX, endX - xStep, xStep do
		for z = startZ, endZ - xStep, xStep do
			local y = Spring.GetGroundHeight(x, z)

			-- distance-based fade
			local centerX = x + xStep / 2
			local centerZ = z + xStep / 2
			local dx = centerX - pos[1]
			local dz = centerZ - pos[3]
			local dist = math.sqrt(dx * dx + dz * dz)*0.6
			local fade = math.max(0, 1.0 - (dist / radius))
			local alpha = fade ^ 2 * 0.85

			-- Only show labels in cross pattern (horizontal and vertical lines through mouse position)
			local mouseGridX = math.floor(pos[1] / xStep) * xStep
			local mouseGridZ = math.floor(pos[3] / xStep) * xStep
			local gridX = math.floor(centerX / xStep) * xStep
			local gridZ = math.floor(centerZ / xStep) * xStep

			local inCrossPattern = (gridX == mouseGridX) or (gridZ == mouseGridZ)
			local isUnderCursor = (gridX == mouseGridX) and (gridZ == mouseGridZ)

			-- if alpha >= 0.01 and inCrossPattern and not isUnderCursor then
			-- 	-- Calculate grid number from map edges
			-- 	local gridNumX = math.floor(centerX / xStep) -- grid count from left edge
			-- 	local gridNumZ = math.floor(centerZ / xStep) -- grid count from bottom edge

			-- 	-- Calculate distances to each edge (1-based)
			-- 	local distToLeft = gridNumX + 1
			-- 	local distToRight = math.floor(Game.mapSizeX / xStep) - gridNumX
			-- 	local distToBottom = gridNumZ + 1
			-- 	local distToTop = math.floor(Game.mapSizeZ / xStep) - gridNumZ

			-- 	-- Determine which direction this label is from the cursor
			-- 	local mouseGridNumX = math.floor(pos[1] / xStep)
			-- 	local mouseGridNumZ = math.floor(pos[3] / xStep)

				-- local label
				-- if gridNumX < mouseGridNumX then
				-- 	-- Label is to the left of cursor
				-- 	label = tostring(distToLeft)
				-- elseif gridNumX > mouseGridNumX then
				-- 	-- Label is to the right of cursor
				-- 	label = tostring(distToRight)
				-- elseif gridNumZ < mouseGridNumZ then
				-- 	-- Label is below cursor
				-- 	label = tostring(distToBottom)
				-- else
				-- 	-- Label is above cursor
				-- 	label = tostring(distToTop)
				-- end

				-- draw label
				-- gl.Color(1, 1, 1, alpha)
				-- gl.PushMatrix()
				-- gl.Translate(centerX, y, centerZ)
				-- gl.Rotate(-90, 1, 0, 0) -- lay flat
				-- gl.Rotate(camYawSnapped+180, 0, 0, 1) -- rotate to face camera but always within the plane of the map
				-- gl.Scale(1, 1, 1) -- no mirroring
				-- gl.Text(label, -#label*fontSize/4, -8, fontSize, 'o')
				-- gl.PopMatrix()
			-- end
		end
	end

	gl.PopMatrix()
	gl.DepthTest(false)
end

function widget:DrawWorldPreUnit()
	local waterSurfaceMode = false

	local mx, my, _ = Spring.GetMouseState()
	local _, mousePos = Spring.TraceScreenRay(mx, my, true, false, false, not waterSurfaceMode)

	if not mousePos then
		return
	end

	gl.LineWidth(2.25)
	gl.Culling(GL.BACK) -- not needed really, only for triangles
	gl.DepthTest(GL.ALWAYS) -- so that it wont be drawn behind terrain
	gl.DepthMask(false) -- so that we dont write the depth of the drawn pixels
	gl.Texture(0, '$heightmap') -- bind engine heightmap texture to sampler 0
	if gridShader then
		gridShader:Activate()
		gl.UniformInt(waterSurfaceModeUniform, waterSurfaceMode and 1 or 0)
		gl.Uniform(mousePosUniform, unpack(mousePos, 1, 3))
		if gridVAO then
			gridVAO:DrawArrays(GL.LINES) -- draw the lines
		end
		gridShader:Deactivate()
	end
	gl.Texture(0, false)
	gl.DepthTest(false)
end

function widget:GetConfigData(data)
	return {
		opacity = opacity
	}
end

function widget:SetConfigData(data)
	opacity = data.opacity or opacity
end
