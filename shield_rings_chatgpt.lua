function widget:GetInfo()
  return {
    desc    = "Draws extra ground rings around both queued and finished shields. Unfinished shields and queued shields has a different color and pulsate.",
    author  = "tetrisface",
    version = "",
    date    = "Apr, 2024",
    name    = "Shield Ground Rings chatgpt",
    license = "GPLv2 or later",
    layer   = -99990,
    enabled = true,
  }
end

VFS.Include('luaui/Widgets/misc/helpers.lua')
local luaShaderDir = "LuaUI/Widgets/Include/"
local LuaShader = VFS.Include(luaShaderDir .. "LuaShader.lua")

local DiffTimers         = Spring.DiffTimers
local GetTeamUnitsByDefs = Spring.GetTeamUnitsByDefs
local GetTimer           = Spring.GetTimer
local GetUnitCommands    = Spring.GetUnitCommands
local GetUnitHealth      = Spring.GetUnitHealth
local GetUnitPosition    = Spring.GetUnitPosition
local GetUnitShieldState = Spring.GetUnitShieldState
local UnitDefs           = UnitDefs
local mathCos            = math.cos
local mathSin            = math.sin
local max                = math.max

local glColorMask        = gl.ColorMask
local glStencilFunc      = gl.StencilFunc
local glStencilTest      = gl.StencilTest
local glColor            = gl.Color
local glBeginEnd         = gl.BeginEnd
local glVertex           = gl.Vertex
local GL_ALWAYS          = GL.ALWAYS
local GL_NOTEQUAL        = GL.NOTEQUAL
local GL_KEEP            = 0x1E00 --GL.KEEP
local GL_REPLACE         = GL.REPLACE
local GL_TRIANGLE_FAN    = GL.TRIANGLE_FAN

local alpha              = 0.6
local nCircleVertices    = 101
local vertexAngle        = math.pi * 2 / (nCircleVertices - 1)
local drawCheckMs        = 1
local shieldsUpdateMs    = 100
local yellow             = { 181 / 255, 137 / 255, 0 / 255 }
local cyan               = { 42 / 255, 161 / 255, 152 / 255 }
local orange             = { 203 / 255, 75 / 255, 22 / 255 }
local ENUM_ONLINE        = 1
local ENUM_OFFLINE       = 2
local ENUM_ALL           = 3

local t0                 = GetTimer()
local drawCheckTimer     = GetTimer()
local shieldsUpdateTimer = GetTimer()
local defIdRadius        = {}
local defIds             = {}
local nDefIds            = 0
local shieldData            = {}
local nShieldData           = 0
local shieldBuilders     = {}
local active             = false
local activeShieldRadius = 550
local glList             = nil


-- Shader Variables and Configurations
local shieldVBO = nil  -- Vertex buffer object to hold shield data
local shieldVAO = nil  -- Vertex array object for drawing shields
local shieldShader = nil  -- Shader to draw shields

-- Data buffers
-- local shieldData = {}  -- Holds shield position and size (x, y, z, radius)
local pulseMs = 0  -- For shield pulsing effect

local vsSrc = [[
#version 420
layout (location = 0) in vec3 position; // Shield position
layout (location = 1) in float radius;  // Shield radius

uniform mat4 cameraViewProj;
uniform float pulseAlpha;  // Pulsing effect

out vec4 v_color;

void main() {
    // Set shield color, applying alpha for pulsating effect
    v_color = vec4(0.0, 0.8, 0.8, pulseAlpha);  // Example cyan color
    vec4 worldPos = vec4(position.xyz, 1.0);
    gl_Position = cameraViewProj * worldPos;  // Project to camera space
}
]]

local fsSrc = [[
#version 420
in vec4 v_color;

out vec4 fragColor;

void main() {
    fragColor = v_color;
}
]]

local pulseAlpha = 0.0
local function UpdateShields()
  if not active or DiffTimers(GetTimer(), shieldsUpdateTimer, true) < shieldsUpdateMs then
    return
  end

  shieldsUpdateTimer = GetTimer()

  shieldData = {}
  nShieldData = 0

  local shieldBuilderCheckUnitIds = Spring.GetSelectedUnits() or {}
  local nShieldBuilderCheckUnitIds = #shieldBuilderCheckUnitIds

  for k, _ in pairs(shieldBuilders) do
    nShieldBuilderCheckUnitIds = nShieldBuilderCheckUnitIds + 1
    shieldBuilderCheckUnitIds[nShieldBuilderCheckUnitIds] = k
  end

  for n = 1, nShieldBuilderCheckUnitIds do
    local shieldBuilderCheckUnitId = shieldBuilderCheckUnitIds[n]
    if shieldBuilderCheckUnitId then

      shieldBuilders[shieldBuilderCheckUnitId] = nil

      local commandQueue = GetUnitCommands(shieldBuilderCheckUnitId, 1000)
      if commandQueue then
        local isShieldBuilder = false
        for i = 1, #commandQueue do
          local command = commandQueue[i]
          if defIdRadius[-command.id] then
            isShieldBuilder = true
            nShieldData = nShieldData + 1
            shieldData[nShieldData] = command.params[1]
            nShieldData = nShieldData + 1
            shieldData[nShieldData] = command.params[2]
            nShieldData = nShieldData + 1
            shieldData[nShieldData] = command.params[3]
            nShieldData = nShieldData + 1
            shieldData[nShieldData] = defIdRadius[-command.id]
          end
        end

        shieldBuilders[shieldBuilderCheckUnitId] = isShieldBuilder and true or nil
      end
    end
  end

  local nTotalShieldUnitIds = 0
  local teamIds = Spring.GetTeamList()
  for j = 1, #teamIds do
    local shieldUnitIds = GetTeamUnitsByDefs(teamIds[j], defIds)
    local nShieldUnitIds = #shieldUnitIds
    nTotalShieldUnitIds = nTotalShieldUnitIds + nShieldUnitIds

    for i = 1, nShieldUnitIds do
      local id = shieldUnitIds[i]
      local x, y, z = GetUnitPosition(id, true)
      nShieldData = nShieldData + 1
      shieldData[nShieldData] = x
      nShieldData = nShieldData + 1
      shieldData[nShieldData] = y
      nShieldData = nShieldData + 1
      shieldData[nShieldData] = z
      nShieldData = nShieldData + 1
      -- online = select(2, GetUnitShieldState(id)) > 400 and select(5, GetUnitHealth(id)) == 1 and ENUM_ONLINE or ENUM_OFFLINE,
      shieldData[nShieldData] = defIdRadius[550]
    end
  end


  drawCheckMs = max(1, nTotalShieldUnitIds/10)
  shieldsUpdateMs = max(100, 100 + nTotalShieldUnitIds*2)
end

local function InitializeShadersAndBuffers()
    -- Initialize shader
    shieldShader = LuaShader({
        vertex = vsSrc,
        fragment = fsSrc,
        uniformFloat = {
            pulseAlpha = pulseAlpha,
        }
    }, "ShieldShader")
    shieldShader:Initialize()

    -- Create VBO for shield data (position and radius)
    log('nShields', nShieldData, nShieldData / 4, table.tostring(shieldData))
    shieldVBO = gl.GetVBO(GL.ARRAY_BUFFER, false)
    shieldVBO:Define(nShieldData / 4 +1, {
        {id = 0, name = "position", size = 3},  -- Position is vec3
        {id = 1, name = "radius", size = 1},    -- Radius is float
    })
    shieldVBO:Upload(shieldData)

    -- Create VAO for drawing
    shieldVAO = gl.GetVAO()
    shieldVAO:AttachVertexBuffer(shieldVBO)
end

function widget:Initialize()
  t0                 = GetTimer()
  drawCheckTimer     = GetTimer()
  defIdRadius        = {}
  defIds             = {}
  nDefIds            = 0
  shieldData            = {}
  nShieldData           = 0
  shieldBuilders     = {}
  active             = false
  activeShieldRadius = 550
  glList             = nil
  for unitDefId, unitDef in pairs(UnitDefs) do
    if unitDef.isBuilding and unitDef.hasShield then
      defIdRadius[unitDefId] = unitDef.customParams and tonumber(unitDef.customParams.shield_radius) or 550
      nDefIds = nDefIds + 1
      defIds[nDefIds] = unitDefId
    end
  end
  UpdateShields()
end


local function doCircle(x, y, z, radius)
  glVertex(x, y, z)
  for i = 1, nCircleVertices do
    local cx = x + (radius * mathCos(i * vertexAngle))
    local cz = z + (radius * mathSin(i * vertexAngle))
    glVertex(cx, y, cz)
  end
end

local function DrawCircles(drawOnOff, radius)
  for i = 1, nShieldData do
    local shieldUnitPosition = shieldData[i]

    if drawOnOff == ENUM_ALL or shieldUnitPosition.online == drawOnOff then
      local x = shieldUnitPosition.x
      local y = shieldUnitPosition.y + 6
      local z = shieldUnitPosition.z

      glBeginEnd(GL_TRIANGLE_FAN, doCircle, x, y, z, radius)
    end
  end
end

local function Interpolate(value, inMin, inMax, outMin, outMax)
  return outMin + ((((value < inMin) and inMin or ((value > inMax) and inMax or value)) - inMin) / (inMax - inMin)) * (outMax - outMin)
end

local function DrawShields()
  pulseMs = (pulseMs + 1) % 1000
  pulseAlpha = pulseMs < 500 and Interpolate(pulseMs, 0, 499, 0.1, 0.35) or Interpolate(pulseMs, 500, 999, 0.35, 0.1)

  gl.DepthTest(GL.LEQUAL)
  gl.Texture(0, "$heightmap")  -- Bind heightmap for ground positioning

  log('nShieldData', nShieldData)
  shieldShader:Activate()
  gl.Uniform(shieldShader:GetUniformLocation("pulseAlpha"), pulseAlpha)

  -- shieldVAO:DrawArrays(GL.TRIANGLE_FAN, 0, nShieldData, )  -- Drawing as points for now (adjust for proper shape)
  shieldVAO:DrawArrays(GL.TRIANGLES, 0, nShieldData/4 +1) -- +1!!!

  shieldShader:Deactivate()
  gl.Texture(0, false)
end

-- local function DrawShieldRanges()
--   gl.PushMatrix()
--   gl.DepthTest(GL.LEQUAL)
--   gl.StencilOp(GL_KEEP, GL_KEEP, GL_REPLACE)
--   glStencilTest(true)
--   glStencilFunc(GL_ALWAYS, 1, 1)

--   local pulseMs = DiffTimers(GetTimer(), t0, true) % 1000
--   local pulseAlpha = pulseMs < 500 and Interpolate(pulseMs, 0, 499, 0.1, 0.35) or Interpolate(pulseMs, 500, 999, 0.35, 0.1)

--   -- mask online shields
--   glColorMask(false, false, false, false) -- disable color drawing
--   DrawCircles(ENUM_ONLINE, 510)

--   -- cyan online borders
--   glStencilFunc(GL_NOTEQUAL, 1, 1)
--   glColor(cyan[1], cyan[2], cyan[3], alpha)
--   glColorMask(true, true, true, true) -- re-enable color drawing
--   DrawCircles(ENUM_ONLINE, 556)

--   -- mask offline shields
--   glColorMask(false, false, false, false)
--   DrawCircles(ENUM_OFFLINE, 510)

--   -- cyan offline borders
--   glStencilFunc(GL_NOTEQUAL, 1, 1)
--   glColor(cyan[1], cyan[2], cyan[3], pulseAlpha)
--   glColorMask(true, true, true, true)
--   DrawCircles(ENUM_OFFLINE, 556)

--   -- mask yellow/orange
--   glStencilFunc(GL_ALWAYS, 1, 1)
--   glColorMask(false, false, false, false)
--   DrawCircles(ENUM_ALL, 556)

--   glStencilFunc(GL_NOTEQUAL, 1, 1)
--   -- yellow
--   glColor(yellow[1], yellow[2], yellow[3], alpha - 0.25)
--   glColorMask(true, true, true, true)
--   DrawCircles(ENUM_ONLINE, 920)
--   -- orange
--   glColor(orange[1], orange[2], orange[3], pulseAlpha)
--   glColorMask(true, true, true, true)
--   DrawCircles(ENUM_OFFLINE, 920)

--   gl.PopMatrix()
--   glStencilFunc(GL_ALWAYS, 1, 1)
--   glStencilTest(false)
-- end


local function DrawCheck()
  if DiffTimers(GetTimer(), drawCheckTimer, true) < drawCheckMs then
    return
  end

  drawCheckTimer = GetTimer()
  local _, command = Spring.GetActiveCommand()

  if not command or command >= 0 then
    return
  end

  activeShieldRadius = defIdRadius[-command]

  if activeShieldRadius then
    active = true
  end
end

function widget:Update()
  UpdateShields()
  DrawCheck()
end

function widget:DrawWorld()
  log('shieldVAO',shieldVAO ,nShieldData, table.tostring(shieldData))
  if shieldVAO then
      DrawShields()
  elseif nShieldData > 0 then
    InitializeShadersAndBuffers()
    DrawShields()
  end
end
