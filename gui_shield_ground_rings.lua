function widget:GetInfo()
  return {
    desc    = "Draws extra ground rings around both queued and finished shields. Unfinished shields and queued shields has a different color and pulsate.",
    author  = "tetrisface",
    version = "",
    date    = "Apr, 2024",
    name    = "Shield Ground Rings",
    license = "GPLv2 or later",
    layer   = -99990,
    enabled = true,
  }
end

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
local shields            = {}
local nShields           = 0
local shieldBuilders     = {}
local active             = false
local activeShieldRadius = 550
local glList             = nil

function widget:Initialize()
  t0                 = GetTimer()
  drawCheckTimer     = GetTimer()
  defIdRadius        = {}
  defIds             = {}
  nDefIds            = 0
  shields            = {}
  nShields           = 0
  shieldBuilders     = {}
  active             = false
  activeShieldRadius = 550
  glList             = nil
  for unitDefId, unitDef in pairs(UnitDefs) do
    if unitDef.isBuilding and unitDef.hasShield then
      defIdRadius[unitDefId] = unitDef.customParams and unitDef.customParams.shield_radius or 550
      nDefIds = nDefIds + 1
      defIds[nDefIds] = unitDefId
    end
  end
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
  for i = 1, nShields do
    local shieldUnitPosition = shields[i]

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

local function DrawShieldRanges()
  gl.PushMatrix()
  gl.DepthTest(GL.LEQUAL)
  gl.StencilOp(GL_KEEP, GL_KEEP, GL_REPLACE)
  glStencilTest(true)
  glStencilFunc(GL_ALWAYS, 1, 1)

  local pulseMs = DiffTimers(GetTimer(), t0, true) % 1000
  local pulseAlpha = pulseMs < 500 and Interpolate(pulseMs, 0, 499, 0.1, 0.35) or Interpolate(pulseMs, 500, 999, 0.35, 0.1)

  -- mask online shields
  glColorMask(false, false, false, false) -- disable color drawing
  DrawCircles(ENUM_ONLINE, 510)

  -- cyan online borders
  glStencilFunc(GL_NOTEQUAL, 1, 1)
  glColor(cyan[1], cyan[2], cyan[3], alpha)
  glColorMask(true, true, true, true) -- re-enable color drawing
  DrawCircles(ENUM_ONLINE, 556)

  -- mask offline shields
  glColorMask(false, false, false, false)
  DrawCircles(ENUM_OFFLINE, 510)

  -- cyan offline borders
  glStencilFunc(GL_NOTEQUAL, 1, 1)
  glColor(cyan[1], cyan[2], cyan[3], pulseAlpha)
  glColorMask(true, true, true, true)
  DrawCircles(ENUM_OFFLINE, 556)

  -- mask yellow/orange
  glStencilFunc(GL_ALWAYS, 1, 1)
  glColorMask(false, false, false, false)
  DrawCircles(ENUM_ALL, 556)

  glStencilFunc(GL_NOTEQUAL, 1, 1)
  -- yellow
  glColor(yellow[1], yellow[2], yellow[3], alpha - 0.25)
  glColorMask(true, true, true, true)
  DrawCircles(ENUM_ONLINE, 920)
  -- orange
  glColor(orange[1], orange[2], orange[3], pulseAlpha)
  glColorMask(true, true, true, true)
  DrawCircles(ENUM_OFFLINE, 920)

  gl.PopMatrix()
  glStencilFunc(GL_ALWAYS, 1, 1)
  glStencilTest(false)
end

local function ShieldsUpdate()
  if not active or DiffTimers(GetTimer(), shieldsUpdateTimer, true) < shieldsUpdateMs then
    return
  end

  shieldsUpdateTimer = GetTimer()

  shields = {}
  nShields = 0

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
            nShields = nShields + 1
            shields[nShields] = {
              x = command.params[1],
              y = command.params[2],
              z = command.params[3],
              online = ENUM_OFFLINE,
            }
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
      nShields = nShields + 1
      shields[nShields] = {
        x = x,
        y = y,
        z = z,
        online = select(2, GetUnitShieldState(id)) > 400 and select(5, GetUnitHealth(id)) == 1 and ENUM_ONLINE or ENUM_OFFLINE,
      }
    end
  end

  drawCheckMs = max(1, nTotalShieldUnitIds/10)
  shieldsUpdateMs = max(100, 100 + nTotalShieldUnitIds*2)
end

local function DrawCheck()
  if DiffTimers(GetTimer(), drawCheckTimer, true) < drawCheckMs then
    return
  end

  drawCheckTimer = GetTimer()
  local _, command = Spring.GetActiveCommand()

  if not command or command >= 0 then
    if glList ~= nil then
      gl.DeleteList(glList)
      glList = nil
    end
    return
  end

  activeShieldRadius = defIdRadius[-command]

  if activeShieldRadius then
    active = true
    glList = gl.CreateList(DrawShieldRanges)
  end
end

function widget:Update()
  ShieldsUpdate()
  DrawCheck()
end

function widget:DrawWorld()
  if glList then
    gl.CallList(glList)
  end
end
