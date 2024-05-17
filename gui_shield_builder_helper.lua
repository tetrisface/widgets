function widget:GetInfo()
  return {
    desc    = "Draws ground circles around shields, unfinished shields and queued shields with different visuals",
    author  = "tetrisface",
    version = "",
    date    = "Apr, 2024",
    name    = "Shield Builder Helper",
    license = "",
    layer   = -99990,
    enabled = true,
  }
end

local DiffTimers         = Spring.DiffTimers
local GetTimer           = Spring.GetTimer
local GetUnitCommands    = Spring.GetUnitCommands
local GetUnitHealth      = Spring.GetUnitHealth
local GetUnitPosition    = Spring.GetUnitPosition
local GetUnitShieldState = Spring.GetUnitShieldState
local UnitDefs           = UnitDefs
local mathCos            = math.cos
local mathSin            = math.sin

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

local alpha              = 0.6
local nCircleVertices    = 101
local vertexAngle        = math.pi * 2 / (nCircleVertices - 1)
local drawCheckMs        = 1
local shieldsUpdateMs    = 100
local yellow             = { 181 / 255, 137 / 255, 0 / 255 }
local cyan               = { 42 / 255, 161 / 255, 152 / 255 }
local orange             = { 203 / 255, 75 / 255, 22 / 255 }

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
      -- for _, weaponDef in pairs(unitDef.weapons) do
      --   if weaponDef.type == 'Shield' then
      --     defIdRadius[unitDefId] = weaponDef.shield.radius
      --     shieldBuildingsDefIds[#shieldBuildingsDefIds + 1] = unitDefId
      --   end
      -- end
      defIdRadius[unitDefId] = 550
      nDefIds = nDefIds + 1
      defIds[nDefIds] = unitDefId
    end
  end
  -- local weapons = UnitDefs[Spring.GetUnitDefID(units[1])].weapons
  -- for i = 1, #weapons do
  --   local weaponDef = WeaponDefs[weapons[i].weaponDef]
  -- for key, value in pairs(WeaponDefs[UnitDefNames['armgate'].weapons[1].weaponDef]) do
  --   log(value())
  -- end
  -- log('UnitDefNames[].weapons[1].weaponDef', UnitDefNames['armgate'].weapons[1].weaponDef)
  -- table.echo(WeaponDefs[UnitDefNames['armgate'].weapons[1].weaponDef])
  -- log(table.tostring(WeaponDefs[UnitDefNames['armgate'].weapons[1].weaponDef]))
  -- table.echo(UnitDefNames['armgate'])
  -- log(table.tostring(UnitDefNames['armgate'].weapons[1]))
  -- defIdRadius[UnitDefNames['armgate'].id] = WeaponDefs[UnitDefNames['armgate'].weapons[1].weaponDef].shield.range
  -- defIdRadius[UnitDefNames['armfgate'].id] = WeaponDefs[UnitDefNames['armfgate'].weapons[1].weaponDef].shield.range
  -- defIdRadius[UnitDefNames['corgate'].id] = WeaponDefs[UnitDefNames['corgate'].weapons[1].weaponDef].shield.range
  -- defIdRadius[UnitDefNames['corfgate'].id] = WeaponDefs[UnitDefNames['corfgate'].weapons[1].weaponDef].shield.range
end

local function doCircle(x, y, z, radius)
  glVertex(x, y, z)
  for i = 1, nCircleVertices do
    local cx = x + (radius * mathCos(i * vertexAngle))
    local cz = z + (radius * mathSin(i * vertexAngle))
    glVertex(cx, y, cz)
  end
end

local function DrawCircles(online, radius)
  for i = 1, nShields do
    local shieldUnitPosition = shields[i]

    if online == nil or shieldUnitPosition.online == online then
      local x = shieldUnitPosition.x
      local y = shieldUnitPosition.y + 2
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

  local pulseMs = DiffTimers(GetTimer(), t0, true)
  local pulseAlpha = pulseMs % 1000 < 500 and Interpolate(pulseMs % 1000, 0, 499, 0.1, 0.35) or Interpolate(pulseMs % 1000, 500, 999, 0.35, 0.1)

  -- mask online shields
  glColorMask(false, false, false, false) -- disable color drawing
  DrawCircles(true, 510)

  -- cyan online borders
  glStencilFunc(GL_NOTEQUAL, 1, 1)
  glColor(cyan[1], cyan[2], cyan[3], alpha)
  glColorMask(true, true, true, true) -- re-enable color drawing
  DrawCircles(true, 556)

  -- mask offline shields
  glColorMask(false, false, false, false)
  DrawCircles(false, 510)

  -- cyan offline borders
  glStencilFunc(GL_NOTEQUAL, 1, 1)
  glColor(cyan[1], cyan[2], cyan[3], pulseAlpha)
  glColorMask(true, true, true, true)
  DrawCircles(false, 556)

  -- mask yellow/orange
  glStencilFunc(GL_ALWAYS, 1, 1)
  glColorMask(false, false, false, false)
  DrawCircles(nil, 556)

  glStencilFunc(GL_NOTEQUAL, 1, 1)
  -- yellow
  glColor(yellow[1], yellow[2], yellow[3], alpha - 0.25)
  glColorMask(true, true, true, true)
  DrawCircles(true, 920)
  -- orange
  glColor(orange[1], orange[2], orange[3], pulseAlpha)
  glColorMask(true, true, true, true)
  DrawCircles(false, 920)

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
              online = false,
            }
          end
        end
        shieldBuilders[shieldBuilderCheckUnitId] = isShieldBuilder and true or nil
      else
        shieldBuilders[shieldBuilderCheckUnitId] = nil
      end
    end
  end

  local shieldUnitIds = Spring.GetTeamUnitsByDefs(Spring.GetMyTeamID(), defIds)
  local nShieldUnitIds = #shieldUnitIds

  for i = 1, nShieldUnitIds do
    local id = shieldUnitIds[i]
    local x, y, z = GetUnitPosition(id, true)
    nShields = nShields + 1
    shields[nShields] = {
      x = x,
      y = y,
      z = z,
      online = select(2, GetUnitShieldState(id)) > 400 and select(5, GetUnitHealth(id)) == 1,
    }
  end
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
