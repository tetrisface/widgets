function widget:GetInfo()
  return {
    desc    = 'Bookmarked Units',
    author  = 'tetrisface',
    version = '',
    date    = 'Mar, 2025',
    name    = 'Bookmarked Units',
    license = 'GPLv2 or later',
    layer   = -99990,
    enabled = true,
    depends = { 'gl4' },
  }
end

local DiffTimers              = Spring.DiffTimers
local GetTeamUnitsByDefs      = Spring.GetTeamUnitsByDefs
local GetTimer                = Spring.GetTimer
local GetUnitCommands         = Spring.GetUnitCommands
local GetUnitDefID            = Spring.GetUnitDefID
local GetUnitHealth           = Spring.GetUnitHealth
local GetUnitShieldState      = Spring.GetUnitShieldState
local GetUnitPosition         = Spring.GetUnitPosition
local UnitDefs                = UnitDefs

local GL_KEEP                 = 0x1E00
local GL_REPLACE              = GL.REPLACE
local GL_ALWAYS               = GL.ALWAYS
local GL_NOTEQUAL             = GL.NOTEQUAL
local GL_TRIANGLE_FAN         = GL.TRIANGLE_FAN

-- Colors
-- local cyan                    = { 42 / 255, 161 / 255, 152 / 255, 152 / 255 }
-- local blue                    = { 38 / 255, 139 / 255, 210 / 255 }
-- local magenta                 = { 211 / 255, 54 / 255, 130 / 255 }
-- local violet                  = { 108 / 255, 113 / 255, 196 / 255 }
local green                   = { 133, 153, 0 }
local orange                  = { 203 / 255, 75 / 255, 22 / 255, 22 / 255 }
local yellow                  = { 181 / 255, 137 / 255, 0 }
local red                     = { 220 / 255, 50 / 255, 47 / 255 }

-- Static
local nCircleVertices         = 64

-- State
local t0                      = GetTimer()
local drawCheckTimer          = GetTimer()
local shieldsUpdateTimer      = GetTimer()
local defIdRadius             = {}
local defIds                  = {}
local nDefIds                 = 0
local shields                 = {}
local nShields                = 0
local isActive                = false
local shieldBuilders          = {}
local nOnline                 = 0
local nOffline                = 0
local updateShieldsMs         = 0
local updateActiveMs          = 0

-- GL4 objects
local shieldRingVBO
local shieldInstanceVBO
local shieldVAO
local shieldShader
local maskModeUniform
local pulseAlphaUniform

local circleInstanceVBOLayout = {
  { id = 1, name = 'posscale', size = 4 }, -- position (x,y,z) + radius (w)
  { id = 2, name = 'color',    size = 4 }, -- color (r,g,b,a)
  { id = 3, name = 'params',   size = 4 }, -- parameters (first component: online flag)
}

local luaShaderDir            = "LuaUI/Include/"
local LuaShader               = VFS.Include(luaShaderDir .. "LuaShader.lua")

local vsSrc                   = [[
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
local fsSrc                   = [[
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
  shieldRingVBO = gl.GetVBO(GL.ARRAY_BUFFER, true)
  local vboData = {}
  for i = 0, nCircleVertices - 1 do
    local angle = i * 2 * math.pi / (nCircleVertices - 1)
    vboData[#vboData + 1] = math.cos(angle) -- x
    vboData[#vboData + 1] = math.sin(angle) -- y
    vboData[#vboData + 1] = 0               -- z
    vboData[#vboData + 1] = 1               -- w
  end
  shieldRingVBO:Define(nCircleVertices, {
    { id = 0, name = "position", size = 4 }
  })
  shieldRingVBO:Upload(vboData)

  -- Create instancing VBO (preallocate for 1000 instances)
  shieldInstanceVBO = gl.GetVBO(GL.ARRAY_BUFFER, true)
  shieldInstanceVBO:Define(1000, circleInstanceVBOLayout)

  shieldVAO = gl.GetVAO()
  shieldVAO:AttachVertexBuffer(shieldRingVBO, 0)
  shieldVAO:AttachInstanceBuffer(shieldInstanceVBO)

  local engineUniformBufferDefs = LuaShader.GetEngineUniformBufferDefs()
  vsSrc = vsSrc:gsub("//__ENGINEUNIFORMBUFFERDEFS__", engineUniformBufferDefs)

  shieldShader = LuaShader({
    vertex       = vsSrc,
    fragment     = fsSrc,
    uniformInt   = {
      heightmapTex = 0,
      maskMode     = 0,
    },
    uniformFloat = {
      pulseAlpha = 0,
    }
  }, "ShieldRingsShader")

  if (not shieldShader:Initialize()) then
    Spring.Echo("Failed to initialize shield rings shader")
    widgetHandler:RemoveWidget()
    return false
  end

  maskModeUniform = gl.GetUniformLocation(shieldShader.shaderObj, "maskMode")
  pulseAlphaUniform = gl.GetUniformLocation(shieldShader.shaderObj, "pulseAlpha")

  return true
end

function widget:Initialize()
  t0 = GetTimer()
  shieldsUpdateTimer = GetTimer()
  defIdRadius = {}
  defIds = {}
  nDefIds = 0
  shields = {}
  nShields = 0
  isActive = false
  shieldBuilders = {}

  for unitDefId, unitDef in pairs(UnitDefs) do
    if unitDef.isBuilding and (unitDef.hasShield or
          (unitDef.customparams and unitDef.customparams.shield_radius and unitDef.customparams.shield_radius > 0)) then
      defIdRadius[unitDefId] = (unitDef.customparams and unitDef.customparams.shield_radius) or 550
      nDefIds = nDefIds + 1
      defIds[nDefIds] = unitDefId
    elseif unitDef.name == 'armgatet3' then
      defIdRadius[unitDefId] = 710
      nDefIds = nDefIds + 1
      defIds[nDefIds] = unitDefId
    elseif unitDef.name == 'corgatet3' then
      defIdRadius[unitDefId] = 825
      nDefIds = nDefIds + 1
      defIds[nDefIds] = unitDefId
    end
  end

  local shieldBuilderDefIds = {}
  for _, unitDef in pairs(UnitDefs) do
    if unitDef.buildOptions then
      for _, buildoptionDefID in pairs(unitDef.buildOptions) do
        if defIdRadius[buildoptionDefID] then
          table.insert(shieldBuilderDefIds, unitDef.id)
        end
      end
    end
  end
  local possibleShieldBuilders = Spring.GetTeamUnitsByDefs(Spring.GetMyTeamID(), shieldBuilderDefIds)
  for i = 1, #possibleShieldBuilders do
    shieldBuilders[possibleShieldBuilders[i]] = true
  end

  return initGL4()
end

local function sortShieldsOnlineDesc(a, b)
  return a.online and not b.online
end

local function UpdateShieldData()
  if not isActive or DiffTimers(GetTimer(), shieldsUpdateTimer, true) < updateShieldsMs then
    return
  end
  shieldsUpdateTimer = GetTimer()

  shields = {}
  nShields = 0
  nOnline = 0
  nOffline = 0

  local shieldBuilderCheckUnitIds = Spring.GetSelectedUnits() or {}
  local nShieldBuilderCheckUnitIds = #shieldBuilderCheckUnitIds

  for k, _ in pairs(shieldBuilders) do
    nShieldBuilderCheckUnitIds = nShieldBuilderCheckUnitIds + 1
    shieldBuilderCheckUnitIds[nShieldBuilderCheckUnitIds] = k
  end

  for n = 1, nShieldBuilderCheckUnitIds do
    local shieldBuilderCheckUnitId = shieldBuilderCheckUnitIds[n]
    local cmds = GetUnitCommands(shieldBuilderCheckUnitId, 1000)
    local isShieldBuilder = false
    if cmds then
      for i = 1, #cmds do
        local cmd = cmds[i]
        if defIdRadius[-cmd.id] then
          isShieldBuilder = true
          nShields = nShields + 1
          nOffline = nOffline + 1
          shields[nShields] = {
            pos    = { cmd.params[1], cmd.params[2], cmd.params[3] },
            online = false,
            radius = defIdRadius[-cmd.id]
          }
        end
      end
    end
    shieldBuilders[shieldBuilderCheckUnitId] = isShieldBuilder and true or nil
  end

  for _, teamID in ipairs(Spring.GetTeamList()) do
    local teamShields = GetTeamUnitsByDefs(teamID, defIds)
    for i = 1, #teamShields do
      local unitID = teamShields[i]
      local x, y, z = GetUnitPosition(unitID, true)
      local _, shieldState = GetUnitShieldState(unitID)
      local health = select(5, GetUnitHealth(unitID))
      local isOnline = (shieldState > 400 and health == 1)
      nOnline = isOnline and nOnline + 1 or nOnline
      nShields = nShields + 1
      shields[nShields] = {
        pos    = { x, y, z },
        online = isOnline,
        radius = defIdRadius[GetUnitDefID(unitID)]
      }
    end
  end

  table.sort(shields, sortShieldsOnlineDesc)

  local vbo = {}
  for i = 1, #shields do
    local shield = shields[i]
    local color = shield.online and cyan or orange
    local vboOffset = (i - 1) * 12
    vbo[vboOffset + 1] = shield.pos[1]
    vbo[vboOffset + 2] = shield.pos[2]
    vbo[vboOffset + 3] = shield.pos[3]
    vbo[vboOffset + 4] = shield.radius
    vbo[vboOffset + 5] = color[1]
    vbo[vboOffset + 6] = color[2]
    vbo[vboOffset + 7] = color[3]
    vbo[vboOffset + 8] = color[4]
    vbo[vboOffset + 9] = shield.online and 1.0 or 0.0
    vbo[vboOffset + 10] = 0.0
    vbo[vboOffset + 11] = 0.0
    vbo[vboOffset + 12] = 0.0
  end

  if shieldInstanceVBO and nShields > 0 then
    shieldInstanceVBO:Upload(vbo)
  end

  updateShieldsMs = math.max(100, 100 + nShields * 2)
  updateActiveMs = math.max(60, nShields / 10)
end

local function UpdateIsActive()
  if isActive and DiffTimers(GetTimer(), drawCheckTimer, true) < updateActiveMs then
    return
  end

  drawCheckTimer = GetTimer()
  local _, command = Spring.GetActiveCommand()

  isActive = command and defIdRadius[-command] ~= nil
end

function widget:DrawWorld()
  UpdateIsActive()
  UpdateShieldData()
  if not isActive or nShields == 0 or not shieldShader or not shieldVAO then
    return
  end

  gl.Texture(0, "$heightmap")
  gl.StencilTest(true)
  gl.Clear(GL.STENCIL_BUFFER_BIT)

  shieldShader:Activate()
  local pulseMs = Spring.DiffTimers(GetTimer(), t0, true) % 1000
  gl.UniformFloat(pulseAlphaUniform, pulseMs < 500
    and (0.1 + (0.35 - 0.1) * (pulseMs / 499))
    or (0.35 + (0.1 - 0.35) * ((pulseMs - 500) / 499)))

  -- Draw online shields
  if nOnline > 0 then
    gl.ColorMask(false, false, false, false)
    gl.UniformInt(maskModeUniform, 1)
    gl.StencilFunc(GL_ALWAYS, 1, 1)
    gl.StencilOp(GL_KEEP, GL_KEEP, GL_REPLACE)
    shieldVAO:DrawArrays(GL_TRIANGLE_FAN, nCircleVertices, 0, nOnline)

    gl.ColorMask(true, true, true, true)
    gl.UniformInt(maskModeUniform, 0)
    gl.StencilFunc(GL_NOTEQUAL, 1, 1)
    shieldVAO:DrawArrays(GL_TRIANGLE_FAN, nCircleVertices, 0, nOnline)
  end

  -- Draw offline shields
  if nOffline > 0 then
    gl.ColorMask(false, false, false, false)
    gl.UniformInt(maskModeUniform, 1)
    gl.StencilFunc(GL_ALWAYS, 1, 1)
    gl.StencilOp(GL_KEEP, GL_KEEP, GL_REPLACE)
    shieldVAO:DrawArrays(GL_TRIANGLE_FAN, nCircleVertices, 0, nOffline, nOnline)

    gl.ColorMask(true, true, true, true)
    gl.UniformInt(maskModeUniform, 0)
    gl.StencilFunc(GL_NOTEQUAL, 1, 1)
    shieldVAO:DrawArrays(GL_TRIANGLE_FAN, nCircleVertices, 0, nOffline, nOnline)
  end

  shieldShader:Deactivate()
  gl.StencilTest(false)
  gl.Texture(0, false)
end

function widget:Shutdown()
  if shieldInstanceVBO and shieldInstanceVBO.VAO then
    shieldInstanceVBO.VAO:Delete()
  end

  if shieldShader then
    shieldShader:Finalize()
  end
end
