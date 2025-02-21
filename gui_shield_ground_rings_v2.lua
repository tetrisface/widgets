function widget:GetInfo()
  return {
    desc    = 'Draws extra ground rings around queued and finished shields using VBOs/VAOs. Overlapping ring segments are merged so that collision boundaries show a single layer of color, giving online shields visual priority over offline ones.',
    author  = 'tetrisface',
    version = '2.0',
    date    = 'Apr, 2024',
    name    = 'Shield Ground Rings GL4',
    license = 'GPLv2 or later',
    layer   = -99990,
    enabled = true,
    depends = {'gl4'},
  }
end

local DiffTimers         = Spring.DiffTimers
local GetTeamUnitsByDefs = Spring.GetTeamUnitsByDefs
local GetTimer           = Spring.GetTimer
local GetUnitCommands    = Spring.GetUnitCommands
local GetUnitDefID       = Spring.GetUnitDefID
local GetUnitHealth      = Spring.GetUnitHealth
local GetUnitShieldState = Spring.GetUnitShieldState
local GetUnitPosition    = Spring.GetUnitPosition
local UnitDefs           = UnitDefs

-- GL constants (we assume these are defined by Spring's GL module)
local GL_KEEP             = 0x1E00
local GL_REPLACE          = GL.REPLACE
local GL_ALWAYS           = GL.ALWAYS
local GL_EQUAL            = GL.EQUAL
local GL_NOTEQUAL         = GL.NOTEQUAL
local GL_INCR             = 0x1E02
local GL_TRIANGLE_FAN     = GL.TRIANGLE_FAN

-- Colors
local yellow = {181/255, 137/255,  0/255, 0.35}
local cyan   = { 42/255, 161/255, 152/255, 0.6}
local orange = {203/255,  75/255, 22/255, 0.35}

-- Statics
local nCircleVertices = 64
local shieldsUpdateMs = 100
local drawCheckMs = 1

-- State
local drawCheckTimer      = GetTimer()
local shieldsUpdateTimer  = GetTimer()
local defIdRadius         = {}
local defIds              = {}
local nDefIds             = 0
local shields             = {}
local nShields            = 0
local active              = false

-- GL4 objects
local shieldRingVBO       = nil
local shieldInstanceVBO   = nil
local shieldVAO           = nil
local shieldShader        = nil

-- We split instance data into two groups: online (drawn first) and offline (drawn second).
local nOnline  = 0
local nOffline = 0

local circleInstanceVBOLayout = {
  {id = 1, name = 'posscale', size = 4}, -- position (x,y,z) + radius (w)
  {id = 2, name = 'color',    size = 4}, -- color (r,g,b,a)
  {id = 3, name = 'params',   size = 4}, -- parameters (first component: online flag)
}

local luaShaderDir = "LuaUI/Include/"
local LuaShader = VFS.Include(luaShaderDir.."LuaShader.lua")

-- Vertex Shader: Passes the unit circle coordinate (position.xy) to the fragment shader.
local vsSrc = [[
#version 420
#line 10000

layout(location = 0) in vec4 position;      // unit circle vertex positions
layout(location = 1) in vec4 posscale;      // center (x,z) and radius (w); posscale.y unused here
layout(location = 2) in vec4 color;         // color + alpha
layout(location = 3) in vec4 params;        // parameters (online flag, etc.)

uniform sampler2D heightmapTex;
uniform float gameFrame;

out DataVS {
  vec4 vertexColor;
  vec2 vUnitPos;
};

//__ENGINEUNIFORMBUFFERDEFS__

float heightAtWorldPos(vec2 w) {
  vec2 uvhm = heightmapUVatWorldPos(w);
  return textureLod(heightmapTex, uvhm, 0.0).x;
}

void main() {
  vUnitPos = position.xy;

  // Scale the unit circle by radius and add the center position (from posscale.xz)
  vec2 circlePos = position.xy * posscale.w + posscale.xz;
  float height = heightAtWorldPos(circlePos);
  vec4 worldPos = vec4(circlePos.x, height + 2.0, circlePos.y, 1.0);
  gl_Position = cameraViewProj * worldPos;

  float pulseAlpha = (params.x < 0.5) ? (0.65 + sin(gameFrame * 0.2) * 0.25) : color.a;
  vertexColor = vec4(color.rgb, pulseAlpha);
}
]]

-- Fragment Shader: In "mask mode" we only write to the stencil for fragments in the outer band.
local fsSrc = [[
#version 420

in DataVS {
  vec4 vertexColor;
  vec2 vUnitPos;
};

uniform int maskMode; // 0 = normal ring; 1 = mask mode (outer band only)

out vec4 fragColor;

void main() {
  float dist = length(vUnitPos);
  float ringInner = 0.9; // adjust to control ring thickness


  if (maskMode == 1) {
    // Mask pass: only output fragments in the outer band of the circle.
    if(dist < ringInner ) {
      fragColor = vec4(1.0); // value is arbitrary for stencil writes
    } else {
      discard;
    }
    return;
  }

  // Normal pass: draw only the outer edge.
  float alphaFactor = step(ringInner, dist);
  fragColor = vec4(vertexColor.rgb, vertexColor.a * alphaFactor);
}
]]

local maskModeUniform
local function initGL4()
  -- Create circle VBO for unit circle vertices.
  shieldRingVBO = gl.GetVBO(GL.ARRAY_BUFFER, true)
  local vboData = {}
  for i = 0, nCircleVertices - 1 do
    local angle = i * 2 * math.pi / (nCircleVertices - 1)
    vboData[#vboData + 1] = math.cos(angle)  -- x
    vboData[#vboData + 1] = math.sin(angle)  -- y
    vboData[#vboData + 1] = 0                -- z
    vboData[#vboData + 1] = 1                -- w
  end
  shieldRingVBO:Define(nCircleVertices, {
    {id = 0, name = "position", size = 4}
  })
  shieldRingVBO:Upload(vboData)

  -- Create instancing VBO (preallocate for 1000 instances)
  shieldInstanceVBO = gl.GetVBO(GL.ARRAY_BUFFER, true)
  shieldInstanceVBO:Define(1000, circleInstanceVBOLayout)

  -- Create VAO and attach vertex and instance buffers.
  shieldVAO = gl.GetVAO()
  shieldVAO:AttachVertexBuffer(shieldRingVBO, 0)
  shieldVAO:AttachInstanceBuffer(shieldInstanceVBO)

  -- Create shader.
  local engineUniformBufferDefs = LuaShader.GetEngineUniformBufferDefs()
  vsSrc = vsSrc:gsub("//__ENGINEUNIFORMBUFFERDEFS__", engineUniformBufferDefs)

  shieldShader = LuaShader({
    vertex   = vsSrc,
    fragment = fsSrc,
    uniformInt = {
      heightmapTex = 0,
      maskMode     = 0,
    },
    uniformFloat = {
      gameFrame = 0,
    }
  }, "ShieldRingsShader")

  if (not shieldShader:Initialize()) then
    Spring.Echo("Failed to initialize shield rings shader")
    widgetHandler:RemoveWidget()
    return false
  end

  maskModeUniform = gl.GetUniformLocation(shieldShader.shaderObj, "maskMode")

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
  active = false

  -- Identify shield units.
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

  if not initGL4() then
    return
  end
end

-- updateShieldData splits instance data into online and offline groups.
local function updateShieldData()
  if DiffTimers(GetTimer(), shieldsUpdateTimer, true) < shieldsUpdateMs then
    return
  end
  shieldsUpdateTimer = GetTimer()

  shields = {}
  nShields = 0

  -- Check shield-building commands from selected units.
  local selectedUnits = Spring.GetSelectedUnits() or {}
  for _, unitID in ipairs(selectedUnits) do
    local cmds = GetUnitCommands(unitID, 1000)
    if cmds then
      for _, cmd in ipairs(cmds) do
        if defIdRadius[-cmd.id] then
          nShields = nShields + 1
          shields[nShields] = {
            pos    = {cmd.params[1], cmd.params[2], cmd.params[3]},
            online = false,
            radius = defIdRadius[-cmd.id]
          }
        end
      end
    end
  end

  -- Check existing shield units.
  for _, teamID in ipairs(Spring.GetTeamList()) do
    local teamShields = GetTeamUnitsByDefs(teamID, defIds)
    for _, unitID in ipairs(teamShields) do
      local x, y, z = GetUnitPosition(unitID, true)
      local _, shieldState = GetUnitShieldState(unitID)
      local health = select(5, GetUnitHealth(unitID))

      nShields = nShields + 1
      shields[nShields] = {
        pos    = {x, y, z},
        online = (shieldState > 400 and health == 1),
        radius = defIdRadius[GetUnitDefID(unitID)]
      }
    end
  end

  -- Split instance data: online instances first, then offline.
  local onlineInstances = {}
  local offlineInstances = {}

  for i, shield in ipairs(shields) do
    local instanceEntry = {
      shield.pos[1], shield.pos[2], shield.pos[3], shield.radius,
      (shield.online and cyan or orange)[1],
      (shield.online and cyan or orange)[2],
      (shield.online and cyan or orange)[3],
      (shield.online and cyan or orange)[4],
      shield.online and 1.0 or 0.0, 0.0, 0.0, 0.0,
    }
    if shield.online then
      table.insert(onlineInstances, instanceEntry)
    else
      table.insert(offlineInstances, instanceEntry)
    end
  end

  nOnline  = #onlineInstances
  nOffline = #offlineInstances

  if nOnline == 0 and nOffline == 0 then
    return
  end

  local combinedInstances = {}
  for i = 1, nOnline do
    for j = 1, #onlineInstances[i] do
      combinedInstances[#combinedInstances + 1] = onlineInstances[i][j]
    end
  end
  for i = 1, nOffline do
    for j = 1, #offlineInstances[i] do
      combinedInstances[#combinedInstances + 1] = offlineInstances[i][j]
    end
  end

  if shieldInstanceVBO then
    shieldInstanceVBO:Upload(combinedInstances)
  end
end

function widget:DrawWorld()
  if nShields == 0
    or not shieldShader
    or not shieldVAO
    or (nOnline == 0 and nOffline == 0)
    or not active then
    return
  end

  gl.Texture(0, "$heightmap")
  gl.StencilTest(true)
  gl.Clear(GL.STENCIL_BUFFER_BIT)

  shieldShader:Activate()
  shieldShader:SetUniform("gameFrame", Spring.GetGameFrame())

  -- Draw online shields
  if nOnline > 0 then
    gl.ColorMask(false, false, false, false)
    gl.UniformInt(maskModeUniform, 1)
    gl.StencilFunc(GL_ALWAYS, 1, 1)
    gl.StencilOp(GL_KEEP, GL_KEEP, GL_REPLACE)
    shieldVAO:DrawArrays(GL_TRIANGLE_FAN,nCircleVertices, 0,  nOnline)

    gl.ColorMask(true, true, true, true)
    gl.UniformInt(maskModeUniform, 0)
    gl.StencilFunc(GL_NOTEQUAL, 1, 1)
    shieldVAO:DrawArrays(GL_TRIANGLE_FAN,nCircleVertices, 0,  nOnline)
  end

  -- Draw offline shields
  if nOffline > 0 then
    gl.ColorMask(false, false, false, false)
    gl.UniformInt(maskModeUniform, 1)
    gl.StencilFunc(GL_ALWAYS, 1, 1)
    gl.StencilOp(GL_KEEP, GL_KEEP, GL_REPLACE)
    shieldVAO:DrawArrays(GL_TRIANGLE_FAN,nCircleVertices, 0,  nOffline, nOnline)

    gl.ColorMask(true, true, true, true)
    gl.UniformInt(maskModeUniform, 0)
    gl.StencilFunc(GL_NOTEQUAL, 1, 1)
    shieldVAO:DrawArrays(GL_TRIANGLE_FAN,nCircleVertices, 0,  nOffline, nOnline)
  end

  shieldShader:Deactivate()
  gl.StencilTest(false)
  gl.Texture(0, false)
end


local function DrawCheck()
  if active and DiffTimers(GetTimer(), drawCheckTimer, true) < drawCheckMs then
    return
  end

  drawCheckTimer = GetTimer()
  local _, command = Spring.GetActiveCommand()

  if not command or command >= 0 then
    active = false
    return
  end

  if defIdRadius[-command] then
    active = true
  end
end

function widget:Update()
  updateShieldData()
  DrawCheck()
end
