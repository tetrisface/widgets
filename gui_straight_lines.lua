function widget:GetInfo()
  return {
    desc = 'Ability to draw straight lines.',
    author  = 'tetrisface',
    version = '',
    date    = '2024-02-23',
    name    = 'Straight Lines',
    license = 'GPLv2 or later',
    layer   = -99990,
    enabled = true,
    depends = {'gl4'},
  }
end

local DiffTimers         = Spring.DiffTimers
local GetTimer           = Spring.GetTimer

local GL_KEEP            = 0x1E00
local GL_REPLACE         = GL.REPLACE
local GL_ALWAYS          = GL.ALWAYS
local GL_NOTEQUAL        = GL.NOTEQUAL
local GL_TRIANGLE_FAN    = GL.TRIANGLE_FAN

VFS.Include('luaui/Headers/keysym.h.lua')

-- Constants
local nCircleVertices    = 100

-- Colors
local cyan               = { 42 / 255, 161 / 255, 152 / 255, 152 / 255 }
local orange             = { 203 / 255, 75 / 255, 22 / 255, 22 / 255 }

-- State
local t0                 = GetTimer()
local linesUpdateTimer   = GetTimer()
local isActiveFirst   = false
local isActiveShift   = false
local isActiveMain      = false
local isActiveDrawing      = false
local isActiveSnapBig      = false
local isActiveSnapSmall      = false
local isActiveDragging      = false
local updateLinesMs    = 0
local worldMouseX             = 0
local WorldMousexZ            = 0
local linesXZData = {}
local nLinesXZData            = 0

-- GL4 objects
local lineVBO
local lineInstanceVBO
local lineVAO
local lineShader
local maskModeUniform
local dragableOffset

local circleInstanceVBOLayout = {
  {id = 1, name = 'posscale', size = 4}, -- position (x,y,z) + radius (w)
  {id = 2, name = 'color',    size = 4}, -- color (r,g,b,a)
  {id = 3, name = 'params',   size = 4}, -- parameters (first component: online flag)
}

local luaShaderDir = "LuaUI/Include/"
local LuaShader = VFS.Include(luaShaderDir.."LuaShader.lua")

local vsSrc = [[
#version 420
#line 10000

layout(location = 0) in vec4 position;      // unit circle vertex positions
layout(location = 1) in vec4 posscale;      // center (x,z) and radius (w); posscale.y unused here
layout(location = 2) in vec4 color;         // color + alpha
layout(location = 3) in vec4 params;        // parameters (online flag, etc.)

uniform sampler2D heightmapTex;
uniform float pulseAlpha;

out DataVS {
  vec4 vertexColor;
  vec2 vUnitPos;
  float radius;
};

//__ENGINEUNIFORMBUFFERDEFS__

float heightAtWorldPos(vec2 w) {
  vec2 uvhm = heightmapUVatWorldPos(w);
  return textureLod(heightmapTex, uvhm, 0.0).x;
}

void main() {
  vUnitPos = position.xy;
  radius = posscale.w;

  // Scale the unit circle by radius and add the center position (from posscale.xz)
  vec2 circlePos = position.xy * posscale.w + posscale.xz;
  vec4 worldPos = vec4(circlePos.x, heightAtWorldPos(circlePos)+2.0, circlePos.y, 1.0);
  gl_Position = cameraViewProj * worldPos;

  float pulseAlpha = (params.x < 0.5) ? pulseAlpha : color.a;
  vertexColor = vec4(color.rgb, pulseAlpha);
}
]]

-- Fragment Shader: In "mask mode" we only write to the stencil for fragments in the outer band.
local fsSrc = [[
#version 420

in DataVS {
  vec4 vertexColor;
  vec2 vUnitPos;
  float radius;
};

uniform int maskMode; // 0 = normal ring; 1 = mask mode (outer band only)

out vec4 fragColor;

void main() {
  float dist = length(vUnitPos);
  float ringWidthFactor = 1 - (54/radius);

  if (maskMode == 1) {
    // Mask pass: only output fragments in the outer band of the circle.
    if(dist < ringWidthFactor ) {
      fragColor = vec4(1.0);
    } else {
      discard;
    }
    return;
  }

  // Normal pass: draw only the outer edge.
  float alphaFactor = step(ringWidthFactor, dist);
  fragColor = vec4(vertexColor.rgb, vertexColor.a * alphaFactor);
}
]]

local function initGL4()
  lineVBO = gl.GetVBO(GL.ARRAY_BUFFER, true)
  local vboData = {}
  for i = 0, nCircleVertices - 1 do
    local angle = i * 2 * math.pi / (nCircleVertices - 1)
    vboData[#vboData + 1] = math.cos(angle)  -- x
    vboData[#vboData + 1] = math.sin(angle)  -- y
    vboData[#vboData + 1] = 0                -- z
    vboData[#vboData + 1] = 1                -- w
  end
  lineVBO:Define(nCircleVertices, {
    {id = 0, name = "position", size = 4}
  })
  lineVBO:Upload(vboData)

  -- Create instancing VBO (preallocate for 1000 instances)
  lineInstanceVBO = gl.GetVBO(GL.ARRAY_BUFFER, true)
  lineInstanceVBO:Define(1000, circleInstanceVBOLayout)

  lineVAO = gl.GetVAO()
  lineVAO:AttachVertexBuffer(lineVBO, 0)
  lineVAO:AttachInstanceBuffer(lineInstanceVBO)

  local engineUniformBufferDefs = LuaShader.GetEngineUniformBufferDefs()
  vsSrc = vsSrc:gsub("//__ENGINEUNIFORMBUFFERDEFS__", engineUniformBufferDefs)

  lineShader = LuaShader({
    vertex   = vsSrc,
    fragment = fsSrc,
    uniformInt = {
      heightmapTex = 0,
      maskMode     = 0,
    },
    uniformFloat = {
      pulseAlpha = 0,
    }
  }, "ShieldRingsShader")

  if (not lineShader:Initialize()) then
    Spring.Echo("Failed to initialize shield rings shader")
    widgetHandler:RemoveWidget()
    return false
  end

  maskModeUniform = gl.GetUniformLocation(lineShader.shaderObj, "maskMode")
  dragableOffset = gl.GetUniformLocation(lineShader.shaderObj, "pulseAlpha")

  return true
end

function widget:Initialize()
  t0                = GetTimer()
  linesUpdateTimer  = GetTimer()
  isActiveFirst     = false
  isActiveShift     = false
  isActiveMain      = false
  isActiveDrawing   = false
  isActiveSnapBig   = false
  isActiveSnapSmall = false
  isActiveDragging  = false
  updateLinesMs     = 0
  worldMouseX       = 0
  WorldMousexZ      = 0
  linesXZData       = {}
  nLinesXZData      = 0

  return initGL4()
end

local function UpdateLinesData()
  if not isActiveMain or DiffTimers(GetTimer(), linesUpdateTimer, true) < updateLinesMs then
    return
  end
  linesUpdateTimer = GetTimer()

  -- local vbo = {}
  -- for i = 1, #shields do
  --   local shield = shields[i]
  --   local color = shield.online and cyan or orange
  --   local vboOffset = (i - 1) * 12
  --   vbo[vboOffset + 1] = shield.pos[1]
  --   vbo[vboOffset + 2] = shield.pos[2]
  --   vbo[vboOffset + 3] = shield.pos[3]
  --   vbo[vboOffset + 4] = shield.radius
  --   vbo[vboOffset + 5] = color[1]
  --   vbo[vboOffset + 6] = color[2]
  --   vbo[vboOffset + 7] = color[3]
  --   vbo[vboOffset + 8] = color[4]
  --   vbo[vboOffset + 9] = shield.online and 1.0 or 0.0
  --   vbo[vboOffset + 10] = 0.0
  --   vbo[vboOffset + 11] = 0.0
  --   vbo[vboOffset + 12] = 0.0
  -- end

  updateLinesMs = math.max(100, 100 + nShields * 2)
  updateActiveMs = math.max(60, nShields / 10)

end

-- local function UpdateIsActive()
--   if isActive and DiffTimers(GetTimer(), drawCheckTimer, true) < updateActiveMs then
--     return
--   end

--   drawCheckTimer = GetTimer()
--   local _, command = Spring.GetActiveCommand()

--   isActive = command and defIdRadius[-command] ~= nil
-- end

function widget:DrawWorld()
  UpdateLinesData()
  if not isActiveMain or not lineShader or not lineVAO then
    return
  end

  gl.Texture(0, "$heightmap")
  -- gl.Clear(GL.STENCIL_BUFFER_BIT)

  lineShader:Activate()
  gl.UniformFloat(dragableOffset, worldMouseX, mouseyZ)

  gl.UniformInt(maskModeUniform, 1)
  gl.DepthTest(GL.LEQUAL)
  lineVAO:DrawArrays(GL.TRIANGLE_STRIP, nCircleVertices, 0, nLines)

  lineShader:Deactivate()
  gl.Texture(0, false)
end

local function UpdateWorldMousePosition(screenMouseX, screenMouseY)
    if not x then
      screenMouseX, screenMouseY  = Spring.GetMouseState()
    end
    local _, pos                     = Spring.TraceScreenRay(screenMouseX, screenMouseY, true, true, false, isOnWater)

    worldMouseX = pos[1]
    WorldMousexZ = pos[3]
end

-- function widget:Update()
--   Spring.Echo('Update', isActiveFirst, isActiveDrawing)
--   if isActiveFirst or isActiveDrawing then

--     UpdateWorldMousePosition()
--     -- snap
--     -- if math.floor(xSize / 16) % 2 > 0 then
--     --   result[1] = math.floor((pos[1]) / BUILD_SQUARE_SIZE) * BUILD_SQUARE_SIZE + SQUARE_SIZE;
--     -- else
--     --   result[1] = math.floor((pos[1] + SQUARE_SIZE) / BUILD_SQUARE_SIZE) * BUILD_SQUARE_SIZE;
--     -- end
--     -- Spring.Echo('mouse', worldMouseX, WorldMousexZ)§
--     if isActiveDrawing then
--       linesXZData[nLinesXZData + 1] = worldMouseX
--       linesXZData[nLinesXZData + 2] = WorldMousexZ
--       Spring.Echo('drawing', worldMouseX, WorldMousexZ)
--     end
--   end
-- end

isActiveFirst = false
isActiveShift = false
isActiveDrawing = false
function widget:KeyPress(key, mods, isRepeat)
  if isRepeat then
    return
  end
  Spring.Echo('KeyPress',key, mods['shift'], mods['ctrl'], mods['alt'])
  if key == KEYSYMS.FIRST then
    isActiveFirst = true
  end
  if key == KEYSYMS.LSHIFT or mods['shift'] then
    isActiveShift = true
  end
end
function widget:KeyRelease(key, mods, releasedFromString)
  Spring.Echo('KeyRelease', key, mods['shift'], mods['ctrl'], mods['alt'], releasedFromString)
  if key == KEYSYMS.FIRST then
    isActiveFirst = false
  end
  if key == KEYSYMS.LSHIFT then
    isActiveShift = false
  end
  if (key == KEYSYMS.LSHIFT and not isActiveFirst) then
    -- isActiveDrawing = false
  end
  return true
end

function widget:MousePress(x, y, button)
  Spring.Echo('draw?', isActiveFirst, isActiveShift)
  if isActiveFirst and isActiveShift then
    isActiveDrawing = true
    UpdateWorldMousePosition(x, y)
    -- nLinesXZData = nLinesXZData + 1
    -- linesXZData[nLinesXZData] = worldMouseX
    -- nLinesXZData = nLinesXZData + 1
    -- linesXZData[nLinesXZData] = WorldMousexZ

    -- nLinesXZData = 2
    -- linesXZData[1] = worldMouseX
    -- linesXZData[2] = WorldMousexZ
  end
end
