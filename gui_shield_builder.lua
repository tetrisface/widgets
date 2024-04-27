function widget:GetInfo()
  return {
    desc    = "",
    author  = "tetrisface",
    version = "",
    date    = "apr, 2016",
    name    = "Shield Builder Helper",
    license = "",
    layer   = -99990,
    enabled = true,
  }
end

VFS.Include('luaui/Widgets/helpers.lua')

local GetMyTeamID        = Spring.GetMyTeamID
local GetTeamUnitsByDefs = Spring.GetTeamUnitsByDefs
local GetTimer           = Spring.GetTimer
local UnitDefs           = UnitDefs

local glColorMask        = gl.ColorMask
local glStencilFunc      = gl.StencilFunc
local glStencilOp        = gl.StencilOp
local glStencilTest      = gl.StencilTest
local glStencilMask      = gl.StencilMask
local GL_ALWAYS          = GL.ALWAYS
local GL_NOTEQUAL        = GL.NOTEQUAL
local GL_KEEP            = 0x1E00 --GL.KEEP
local GL_REPLACE         = GL.REPLACE
local GL_TRIANGLE_FAN    = GL.TRIANGLE_FAN


local previousTimer              = GetTimer()
local shieldBuildingsDefIdRadius = {}
local shieldBuildingsDefIds      = {}
local shieldUnitIds              = {}
local shieldUnitPositions        = {}
local nShieldUnitPositions       = 0
local nShieldBuildingsDefIds     = 0
local active                     = false
local activeBuildRadius          = 550
local alpha                      = 0.6
local circleParts                = 100
local shieldsList

local twicePi                    = math.pi * 2

local yellow                     = { 181 / 256, 137 / 256, 0 / 256 }
local red                        = { 220 / 256, 50 / 256, 47 / 256 }
local magenta                    = { 211 / 256, 54 / 256, 130 / 256 }
local cyan                       = { 42 / 256, 161 / 256, 152 / 256 }
local blue                       = { 38 / 256, 139 / 256, 210 / 256 }

function widget:Initialize()
  previousTimer              = Spring.GetTimer()
  shieldBuildingsDefIdRadius = {}
  shieldBuildingsDefIds      = {}
  shieldUnitIds              = {}
  shieldUnitPositions        = {}
  nShieldUnitPositions       = 0
  nShieldBuildingsDefIds     = 0
  active                     = false
  activeBuildRadius          = 550
  shieldsList                = nil
  for unitDefId, unitDef in pairs(UnitDefs) do
    if unitDef.isBuilding and unitDef.hasShield then
      -- for _, weaponDef in pairs(unitDef.weapons) do
      --   if weaponDef.type == 'Shield' then
      --     shieldBuildingsDefIdRadius[unitDefId] = weaponDef.shield.radius
      --     shieldBuildingsDefIds[#shieldBuildingsDefIds + 1] = unitDefId
      --   end
      -- end
      shieldBuildingsDefIdRadius[unitDefId] = 550
      nShieldBuildingsDefIds = nShieldBuildingsDefIds + 1
      shieldBuildingsDefIds[nShieldBuildingsDefIds] = unitDefId
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

local function DrawShieldRanges()
  gl.PushMatrix()
  gl.DepthTest(GL.LEQUAL)
  glStencilTest(true)

  glStencilFunc(GL_ALWAYS, 1, 1)
  glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE)


  for i = 1, nShieldUnitPositions do
    local shieldUnitPosition = shieldUnitPositions[i]
    local x = shieldUnitPosition.x
    local y = shieldUnitPosition.y + 2
    local z = shieldUnitPosition.z

    glColorMask(false, false, false, false) -- disable color drawing
    gl.BeginEnd(GL_TRIANGLE_FAN, doCircle, x, y, z, 530, circleParts)
  end

  glStencilFunc(GL_NOTEQUAL, 1, 1)

  for i = 1, nShieldUnitPositions do
    local shieldUnitPosition = shieldUnitPositions[i]
    local x = shieldUnitPosition.x
    local y = shieldUnitPosition.y + 2
    local z = shieldUnitPosition.z
    gl.Color(cyan[1], cyan[2], cyan[3], alpha)
    glColorMask(true, true, true, true) -- re-enable color drawing
    gl.BeginEnd(GL_TRIANGLE_FAN, doCircle, x, y, z, 556, circleParts)
  end

  glStencilFunc(GL_ALWAYS, 1, 1)
  for i = 1, nShieldUnitPositions do
    local shieldUnitPosition = shieldUnitPositions[i]
    local x = shieldUnitPosition.x
    local y = shieldUnitPosition.y + 2
    local z = shieldUnitPosition.z

    glColorMask(false, false, false, false) -- disable color drawing
    gl.BeginEnd(GL_TRIANGLE_FAN, doCircle, x, y, z, 556, circleParts)
  end

  glStencilFunc(GL_NOTEQUAL, 1, 1)

  for i = 1, nShieldUnitPositions do
    local shieldUnitPosition = shieldUnitPositions[i]
    local x = shieldUnitPosition.x
    local y = shieldUnitPosition.y + 2
    local z = shieldUnitPosition.z
    gl.Color(yellow[1], yellow[2], yellow[3], 0.4)
    glColorMask(true, true, true, true) -- re-enable color drawing
    gl.BeginEnd(GL_TRIANGLE_FAN, doCircle, x, y, z, 920, circleParts)
  end

  gl.PopMatrix()
  glStencilFunc(GL_ALWAYS, 1, 1) -- reset gl stencilfunc too
  glStencilTest(false)
end

function widget:Update()
  if Spring.DiffTimers(GetTimer(), previousTimer) < 0.1 then
    return
  end

  previousTimer = GetTimer()
  local _, buildingDefId = Spring.GetActiveCommand()

  if not buildingDefId or buildingDefId >= 0 then
    if shieldsList ~= nil then
      gl.DeleteList(shieldsList)
      shieldsList = nil
    end
    return
  end

  activeBuildRadius = shieldBuildingsDefIdRadius[-buildingDefId]

  if activeBuildRadius then
    active = true
    shieldsList = gl.CreateList(DrawShieldRanges)
  end
end

function widget:DrawWorld()
  if shieldsList then
    gl.CallList(shieldsList)
  end
end

function widget:GameFrame(gameFrame)
  if not active or gameFrame % 5 ~= 0 then
    return
  end

  shieldUnitPositions = {}
  shieldUnitIds = GetTeamUnitsByDefs(GetMyTeamID(), shieldBuildingsDefIds)

  nShieldUnitPositions = 0
  for i = 1, #shieldUnitIds do
    local x, y, z = Spring.GetUnitPosition(shieldUnitIds[i], true)
    nShieldUnitPositions = nShieldUnitPositions + 1
    shieldUnitPositions[nShieldUnitPositions] = { x = x, y = y, z = z }
  end
end
