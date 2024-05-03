function widget:GetInfo()
  return {
    desc    = "",
    author  = "tetrisface",
    version = "",
    date    = "apr, 2024",
    name    = "Shield Builder Helper",
    license = "",
    layer   = -99990,
    enabled = true,
  }
end

VFS.Include('luaui/Widgets/helpers.lua')

local GetUnitCommands    = Spring.GetUnitCommands
local GetSelectedUnits   = Spring.GetSelectedUnits
local GetMyTeamID        = Spring.GetMyTeamID
local GetTeamUnitsByDefs = Spring.GetTeamUnitsByDefs
local GetTimer           = Spring.GetTimer
local DiffTimers         = Spring.DiffTimers
local UnitDefs           = UnitDefs

local glColorMask        = gl.ColorMask
local glStencilFunc      = gl.StencilFunc
local glStencilOp        = gl.StencilOp
local glStencilTest      = gl.StencilTest
local GL_ALWAYS          = GL.ALWAYS
local GL_NOTEQUAL        = GL.NOTEQUAL
local GL_KEEP            = 0x1E00 --GL.KEEP
local GL_REPLACE         = GL.REPLACE
local GL_TRIANGLE_FAN    = GL.TRIANGLE_FAN

local t0                 = GetTimer()
local previousTimer      = GetTimer()
local defIdRadius        = {}
local defIds             = {}
local nDefIds            = 0
local shields            = {}
local nShields           = 0
local active             = false
local activeBuildRadius  = 550
local glList             = nil

local gameFrame          = 0

local alpha              = 0.6
local circleParts        = 100
local twicePi            = math.pi * 2
local yellow             = { 181 / 255, 137 / 255, 0 / 255 }
local red                = { 220 / 255, 50 / 255, 47 / 255 }
local magenta            = { 211 / 255, 54 / 255, 130 / 255 }
local cyan               = { 42 / 255, 161 / 255, 152 / 255 }
local blue               = { 38 / 255, 139 / 255, 210 / 255 }
local orange             = { 203 / 255, 75 / 255, 22 / 255 }

local function Interpolate(value, inMin, inMax, outMin, outMax)
  return outMin + ((((value < inMin) and inMin or ((value > inMax) and inMax or value)) - inMin) / (inMax - inMin)) * (outMax - outMin)
end

function widget:Initialize()
  t0                = GetTimer()
  previousTimer     = GetTimer()
  defIdRadius       = {}
  defIds            = {}
  nDefIds           = 0
  shields           = {}
  nShields          = 0
  active            = false
  activeBuildRadius = 550
  glList            = nil
  for unitDefId, unitDef in pairs(UnitDefs) do
    if unitDef.isBuilding and unitDef.hasShield then
      -- for _, weaponDef in pairs(unitDef.weapons) do
      --   if weaponDef.type == 'Shield' then
      --     shieldBuildingsDefIdRadius[unitDefId] = weaponDef.shield.radius
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
  -- shieldBuildingsDefIdRadius[UnitDefNames['armgate'].id] = WeaponDefs[UnitDefNames['armgate'].weapons[1].weaponDef].shield.range
  -- shieldBuildingsDefIdRadius[UnitDefNames['armfgate'].id] = WeaponDefs[UnitDefNames['armfgate'].weapons[1].weaponDef].shield.range
  -- shieldBuildingsDefIdRadius[UnitDefNames['corgate'].id] = WeaponDefs[UnitDefNames['corgate'].weapons[1].weaponDef].shield.range
  -- shieldBuildingsDefIdRadius[UnitDefNames['corfgate'].id] = WeaponDefs[UnitDefNames['corfgate'].weapons[1].weaponDef].shield.range
end

local function doCircle(x, y, z, radius, sides)
  local sideAngle = twicePi / sides
  gl.Vertex(x, y, z)
  for i = 1, sides + 1 do
    local cx = x + (radius * math.cos(i * sideAngle))
    local cz = z + (radius * math.sin(i * sideAngle))
    gl.Vertex(cx, y, cz)
  end
end

local function DrawCircles(online, radius)
  for i = 1, nShields do
    local shieldUnitPosition = shields[i]

    if online == nil or shieldUnitPosition.online == online then
      local x = shieldUnitPosition.x
      local y = shieldUnitPosition.y + 2
      local z = shieldUnitPosition.z

      gl.BeginEnd(GL_TRIANGLE_FAN, doCircle, x, y, z, radius, circleParts)
    end
  end
end

local function DrawShieldRanges()
  gl.PushMatrix()
  gl.DepthTest(GL.LEQUAL)
  glStencilTest(true)
  glStencilFunc(GL_ALWAYS, 1, 1)
  glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE)
  local diffTime = DiffTimers(GetTimer(), t0, true)
  local pulseAlpha = diffTime % 1000 < 500 and Interpolate(diffTime % 1000, 0, 500, 0.1, 0.35) or Interpolate(diffTime % 1000, 500, 1000, 0.35, 0.1)

  -- mask online shields
  glColorMask(false, false, false, false) -- disable color drawing
  DrawCircles(true, 510)


  -- cyan online borders
  glStencilFunc(GL_NOTEQUAL, 1, 1)
  gl.Color(cyan[1], cyan[2], cyan[3], alpha)
  glColorMask(true, true, true, true) -- re-enable color drawing
  DrawCircles(true, 556)

  -- mask offline shields
  glColorMask(false, false, false, false)
  DrawCircles(false, 530)

  -- cyan offline borders
  glStencilFunc(GL_NOTEQUAL, 1, 1)
  gl.Color(cyan[1], cyan[2], cyan[3], pulseAlpha)
  glColorMask(true, true, true, true)
  DrawCircles(false, 556)

  -- mask outer
  glStencilFunc(GL_ALWAYS, 1, 1)
  glColorMask(false, false, false, false)
  DrawCircles(nil, 556)

  glStencilFunc(GL_NOTEQUAL, 1, 1)

  -- yellow
  gl.Color(yellow[1], yellow[2], yellow[3], alpha - 0.25)
  glColorMask(true, true, true, true)
  DrawCircles(true, 920)

  -- orange
  gl.Color(orange[1], orange[2], orange[3], pulseAlpha)
  glColorMask(true, true, true, true)
  DrawCircles(false, 920)


  gl.PopMatrix()
  glStencilFunc(GL_ALWAYS, 1, 1) -- reset gl stencilfunc too
  glStencilTest(false)
end

function widget:Update()
  if DiffTimers(GetTimer(), previousTimer) < 0.1 then
    return
  end

  previousTimer = GetTimer()
  local _, cmd = Spring.GetActiveCommand()

  if not cmd or cmd >= 0 then
    if glList ~= nil then
      gl.DeleteList(glList)
      glList = nil
    end
    return
  end

  activeBuildRadius = defIdRadius[-cmd]

  if activeBuildRadius then
    active = true
    glList = gl.CreateList(DrawShieldRanges)
  end
end

function widget:DrawWorld()
  if glList then
    gl.CallList(glList)
  end
end

function widget:GameFrame(_gameFrame)
  gameFrame = _gameFrame
  if not active or gameFrame % 5 ~= 0 then
    return
  end

  shields = {}
  nShields = 0

  local selectedUnitIds = GetSelectedUnits()
  if selectedUnitIds then
    local selectedUnitId = selectedUnitIds[1]
    if selectedUnitId then
      local cmdQueue = GetUnitCommands(selectedUnitId, 100)
      if cmdQueue then
        for i = 1, #cmdQueue do
          local cmd = cmdQueue[i]
          if defIdRadius[-cmd.id] then
            nShields = nShields + 1
            shields[nShields] = {
              x = cmd.params[1],
              y = cmd.params[2],
              z = cmd.params[3],
              online = false,
              queued = true,
            }
          end
        end
      end
    end
  end

  local shieldUnitIds = GetTeamUnitsByDefs(GetMyTeamID(), defIds)
  local nShieldUnitIds = #shieldUnitIds

  for i = 1, nShieldUnitIds do
    local id = shieldUnitIds[i]
    local x, y, z = Spring.GetUnitPosition(id, true)
    nShields = nShields + 1
    shields[nShields] = {
      x = x,
      y = y,
      z = z,
      id = id,
      online = select(2, Spring.GetUnitShieldState(id)) > 400 and select(5, Spring.GetUnitHealth(id)) == 1,
      queued = false,
    }
  end
end
