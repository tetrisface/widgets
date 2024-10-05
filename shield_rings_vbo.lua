function widget:GetInfo()
    return {
        desc = "Draws extra ground rings around both queued and finished shields. Unfinished shields and queued shields have a different color and pulsate.",
        author = "tetrisface",
        version = "1.0",
        date = "Apr, 2024",
        name = "Shield Ground Rings VBO",
        license = "GPLv2 or later",
        layer = -99990,
        enabled = true,
    }
end

local shader
local vbo
local vao
local nVBOData = 0
local activeShieldRadius = 550
local vertexData = {}

-- Shader code
local vsSrc = [[
#version 420
layout(location = 0) in vec3 position;
layout(location = 1) in float alpha;
out float fragAlpha;

uniform mat4 viewProjMatrix;

void main() {
    gl_Position = viewProjMatrix * vec4(position, 1.0);
    fragAlpha = alpha;
}
]]

local fsSrc = [[
#version 420
in float fragAlpha;
out vec4 outColor;

void main() {
    outColor = vec4(0.5, 0.1, 0.8, fragAlpha); // Example color, change as needed
}
]]

-- local function initShader()
--     shader = gl.CreateShaderProgram(vsSrc, fsSrc)
-- end

function initShader()
    local engineUniformBufferDefs = LuaShader.GetEngineUniformBufferDefs() -- all the camera and other lovely stuff
    vsSrc = vsSrc:gsub("//__ENGINEUNIFORMBUFFERDEFS__", engineUniformBufferDefs)
    fsSrc = fsSrc:gsub("//__ENGINEUNIFORMBUFFERDEFS__", engineUniformBufferDefs)
    gridShader = LuaShader({
        vertex = vsSrc:gsub("//__DEFINES__", LuaShader.CreateShaderDefinesString(shaderConfig)),
        fragment = fsSrc:gsub("//__DEFINES__", LuaShader.CreateShaderDefinesString(shaderConfig)),
        uniformInt = {
            heightmapTex = 0, -- the index of the texture uniform sampler2D
            waterSurfaceMode = 0,
        },
        uniformFloat = {
            waterLevel = waterLevel,
            mousePos = { 0.0, 0.0, 0.0 },
        }
    }, "gridShader")
    local shaderCompiled = gridShader:Initialize()
    if not shaderCompiled then
        goodbye("Failed to compile gridshader GL4 ")
        return
    end

    mousePosUniform = gl.GetUniformLocation(gridShader.shaderObj, "mousePos")
    waterSurfaceModeUniform = gl.GetUniformLocation(gridShader.shaderObj, "waterSurfaceMode")
end

local function setupCircleVertices(radius, segments)
    vertexData = {}
    for i = 0, segments do
        local angle = (i / segments) * (2 * math.pi)
        local x = math.cos(angle) * radius
        local z = math.sin(angle) * radius
        table.insert(vertexData, x)
        table.insert(vertexData, 0) -- Ground level
        table.insert(vertexData, z)
        table.insert(vertexData, alpha) -- Opacity
    end
    nVBOData = #vertexData / 4 -- Number of vertices
end

function widget:Initialize()
    initShader()
    vbo = gl.CreateVBO(GL.ARRAY_BUFFER, vertexData)
    vao = gl.GetVAO()
    vao:AttachVertexBuffer(vbo)
    setupCircleVertices(activeShieldRadius, 100) -- Initial setup
end

function widget:Update()
    -- Call your ShieldsUpdate function to fill in vertex data as needed.
    -- Here, update the vertex data if necessary based on the game mechanics.
end

function widget:DrawWorld()
    gl.UseShader(shader)

    -- Update the viewProjMatrix uniform as needed
    local viewProjMatrix = gl.GetViewMatrices()
    gl.UniformMatrix(gl.GetUniformLocation(shader, "viewProjMatrix"), viewProjMatrix)

    -- Draw the filled rings using the VAO
    vao:DrawArrays(GL.TRIANGLE_FAN, 0, nVBOData)

    gl.UseShader(0)
end

function widget:Shutdown()
    if vbo then gl.DeleteVBO(vbo) end
    if vao then vao:Delete() end
    if shader then gl.DeleteShader(shader) end
end
