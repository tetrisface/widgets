function widget:GetInfo()
  return {
    desc = 'Draws extra ground rings around both queued and finished shields using VBOs/VAOs. Unfinished shields and queued shields has a different color and pulsate.',
    author = 'tetrisface',
    version = '2.0',
    date = 'Apr, 2024',
    name = 'Shield Ground Rings GL4',
    license = 'GPLv2 or later',
    layer = -99990,
    enabled = true,
    depends = {'gl4'}
  }
end

local DiffTimers = Spring.DiffTimers
local GetTeamUnitsByDefs = Spring.GetTeamUnitsByDefs
local GetTimer = Spring.GetTimer
local GetUnitCommands = Spring.GetUnitCommands
local GetUnitDefID = Spring.GetUnitDefID
local GetUnitHealth = Spring.GetUnitHealth
local GetUnitShieldState = Spring.GetUnitShieldState
local GetUnitPosition = Spring.GetUnitPosition
local UnitDefs = UnitDefs

-- GL constants
local GL_KEEP = 0x1E00
local GL_REPLACE = GL.REPLACE
local GL_TRIANGLE_FAN = GL.TRIANGLE_FAN

-- Colors
local yellow = {181/255, 137/255, 0/255, 0.35}
local cyan = {42/255, 161/255, 152/255, 0.6}
local orange = {203/255, 75/255, 22/255, 0.35}

-- Ring config
local nCircleVertices = 64
local drawCheckMs = 1
local shieldsUpdateMs = 100
local ENUM_ONLINE = 1
local ENUM_OFFLINE = 2

-- State
local t0 = GetTimer()
local drawCheckTimer = GetTimer()
local shieldsUpdateTimer = GetTimer()
local defIdRadius = {}
local defIds = {}
local nDefIds = 0
local shields = {}
local nShields = 0
local shieldBuilders = {}
local active = false

-- GL4 objects
local shieldRingVBO = nil
local shieldInstanceVBO = nil
local shieldVAO = nil
local shieldShader = nil

local circleInstanceVBOLayout = {
  {id = 1, name = 'posscale', size = 4}, -- position + radius
  {id = 2, name = 'color', size = 4},    -- color + alpha
  {id = 3, name = 'params', size = 4},   -- online/offline, pulse, etc
}

local luaShaderDir = "LuaUI/Include/"
local LuaShader = VFS.Include(luaShaderDir.."LuaShader.lua")

local vsSrc = [[
#version 420
#line 10000

layout(location = 0) in vec4 position;      // circle vertex positions (unit circle coordinates)
layout(location = 1) in vec4 posscale;        // center pos (x,z) + y and radius in w
layout(location = 2) in vec4 color;           // color + alpha
layout(location = 3) in vec4 params;          // misc parameters

uniform sampler2D heightmapTex;
uniform float gameFrame;

out DataVS {
  vec4 vertexColor;
  vec2 vUnitPos; // pass the unit circle coordinate to the fragment shader
};

//__ENGINEUNIFORMBUFFERDEFS__

float heightAtWorldPos(vec2 w) {
  vec2 uvhm = heightmapUVatWorldPos(w);
  return textureLod(heightmapTex, uvhm, 0.0).x;
}

void main() {
  // Save the original unit circle coordinate (ranges roughly from -1 to 1)
  vUnitPos = position.xy;

  // Calculate world position from unit circle, scale by radius, and add center (using posscale.xz as center)
  vec2 circlePos = position.xy * posscale.w + posscale.xz;
  float height = heightAtWorldPos(circlePos);
  vec4 worldPos = vec4(circlePos.x, height + 2.0, circlePos.y, 1.0);
  gl_Position = cameraViewProj * worldPos;

  // Calculate pulsing alpha for offline shields; otherwise, use given alpha.
  float pulseAlpha = (params.x < 0.5) ? (0.35 + sin(gameFrame * 0.05) * 0.25) : color.a;
  vertexColor = vec4(color.rgb, pulseAlpha);
}
]]

local fsSrc = [[
#version 420

in DataVS {
  vec4 vertexColor;
  vec2 vUnitPos; // unit circle coordinate from vertex shader
};

out vec4 fragColor;

void main() {
  // Compute distance from center in the unit circle space.
  float dist = length(vUnitPos);

  // Define the inner boundary and the outer boundary of the ring.
  float ringInner = 0.9; // inner edge of the ring (adjust for thickness)
  float ringOuter = 1.0; // outer edge (assuming your VBO is built as a unit circle)

  // Use smoothstep to create a smooth transition; or use step for a hard cutoff:
  //float alphaFactor = smoothstep(ringInner, ringOuter, dist);
  // For a crisp edge, you could alternatively use:
  float alphaFactor = step(ringInner, dist);

  // Multiply the original alpha with the mask factor.
  fragColor = vec4(vertexColor.rgb, vertexColor.a * alphaFactor);
}
]]

local function initGL4()
  -- Create circle VBO
  shieldRingVBO = gl.GetVBO(GL.ARRAY_BUFFER, true)

  local vboData = {}
  for i = 0, nCircleVertices-1 do
    local angle = i * 2 * math.pi / (nCircleVertices-1)
    vboData[#vboData+1] = math.cos(angle) -- x
    vboData[#vboData+1] = math.sin(angle) -- y
    vboData[#vboData+1] = 0               -- z
    vboData[#vboData+1] = 1               -- w
  end

  shieldRingVBO:Define(nCircleVertices, {
    {id = 0, name = "position", size = 4}
  })
  shieldRingVBO:Upload(vboData)

  -- Create instancing VBO
  shieldInstanceVBO = gl.GetVBO(GL.ARRAY_BUFFER, true)
  shieldInstanceVBO:Define(1000, circleInstanceVBOLayout) -- Preallocate for 1000 instances

  -- Create VAO
  shieldVAO = gl.GetVAO()
  shieldVAO:AttachVertexBuffer(shieldRingVBO, 0)
  shieldVAO:AttachInstanceBuffer(shieldInstanceVBO)

  -- Create shader
  local engineUniformBufferDefs = LuaShader.GetEngineUniformBufferDefs()
  vsSrc = vsSrc:gsub("//__ENGINEUNIFORMBUFFERDEFS__", engineUniformBufferDefs)

  shieldShader = LuaShader({
    vertex = vsSrc,
    fragment = fsSrc,
    uniformInt = {
      heightmapTex = 0,
    },
    uniformFloat = {
      gameFrame = 0,
    }
  }, "ShieldRingsShader")

  if not shieldShader:Initialize() then
    Spring.Echo("Failed to initialize shield rings shader")
    widgetHandler:RemoveWidget()
    return false
  end

  return true
end

function widget:Initialize()
  -- Reset state
  t0 = GetTimer()
  drawCheckTimer = GetTimer()
  defIdRadius = {}
  defIds = {}
  nDefIds = 0
  shields = {}
  nShields = 0
  shieldBuilders = {}
  active = false

  -- Find shield units
  for unitDefId, unitDef in pairs(UnitDefs) do
    if unitDef.isBuilding and (unitDef.hasShield or
      (unitDef.customparams and unitDef.customparams.shield_radius and
       unitDef.customparams.shield_radius > 0)) then
      defIdRadius[unitDefId] = unitDef.customparams and
        unitDef.customparams.shield_radius or 550
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

  -- Initialize GL4 components
  if not initGL4() then
    return
  end
end

local function updateShieldData()
  if DiffTimers(GetTimer(), shieldsUpdateTimer, true) < shieldsUpdateMs then
    return
  end
  shieldsUpdateTimer = GetTimer()

  -- Clear old data
  shields = {}
  nShields = 0

  -- Check builders
  local selectedUnits = Spring.GetSelectedUnits() or {}
  for _, unitID in ipairs(selectedUnits) do
    local cmds = GetUnitCommands(unitID, 1000)
    if cmds then
      for _, cmd in ipairs(cmds) do
        if defIdRadius[-cmd.id] then
          nShields = nShields + 1
          shields[nShields] = {
            pos = {cmd.params[1], cmd.params[2], cmd.params[3]},
            online = false,
            radius = defIdRadius[-cmd.id]
          }
        end
      end
    end
  end

  -- Check existing shields
  for _, teamID in ipairs(Spring.GetTeamList()) do
    local teamShields = GetTeamUnitsByDefs(teamID, defIds)
    for _, unitID in ipairs(teamShields) do
      local x, y, z = GetUnitPosition(unitID, true)
      local _, shieldState = GetUnitShieldState(unitID)
      local health = select(5, GetUnitHealth(unitID))

      nShields = nShields + 1
      shields[nShields] = {
        pos = {x, y, z},
        online = shieldState > 400 and health == 1,
        radius = defIdRadius[GetUnitDefID(unitID)]
      }
    end
  end

  -- Update instance data
  local instanceData = {}
  for i, shield in ipairs(shields) do
    -- Position + radius
    instanceData[#instanceData+1] = shield.pos[1]
    instanceData[#instanceData+1] = shield.pos[2]
    instanceData[#instanceData+1] = shield.pos[3]
    instanceData[#instanceData+1] = shield.radius

    -- Color
    local color = shield.online and cyan or orange
    instanceData[#instanceData+1] = color[1]
    instanceData[#instanceData+1] = color[2]
    instanceData[#instanceData+1] = color[3]
    instanceData[#instanceData+1] = color[4]

    -- Parameters
    instanceData[#instanceData+1] = shield.online and 1.0 or 0.0
    instanceData[#instanceData+1] = 0.0
    instanceData[#instanceData+1] = 0.0
    instanceData[#instanceData+1] = 0.0
  end

  shieldInstanceVBO:Upload(instanceData)
end

function widget:DrawWorld()
  if nShields == 0 or shieldShader == nil or shieldVAO == nil then return end

  gl.Texture(0, "$heightmap")

  gl.BlendFunc(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA)

  shieldShader:Activate()
  shieldShader:SetUniform("gameFrame", Spring.GetGameFrame())

  shieldVAO:DrawArrays(GL.TRIANGLE_FAN, nCircleVertices, 0, nShields)

  shieldShader:Deactivate()

  gl.BlendEquation(GL.FUNC_ADD)
  gl.Texture(0, false)
end

function widget:Update()
  updateShieldData()
end
