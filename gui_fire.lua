function widget:GetInfo()
    return {
        name      = "Dont Stand in Fire",
        desc      = "Shows projectile ground splash so that you can avoid standing in the fire",
        author    = "lov",
        date      = "July 2023",
        version   = "1.1",
        license   = "GNU GPL, v2 or later",
        layer     = 9999,
        enabled   = false,
        handler   = true,
    }
end

VFS.Include('luaui/Widgets/misc/helpers.lua')

local projectiles = {}
local drawListIndex = 1
local drawList = {}
local alpha = 0.15

local glColor = gl.Color
local glLineWidth = gl.LineWidth
local glDrawGroundCircle = gl.DrawGroundCircle
local glPopMatrix = gl.PopMatrix
local glPushMatrix = gl.PushMatrix
local Spring_GetProjectilePosition = Spring.GetProjectilePosition
local Spring_GetProjectileVelocity = Spring.GetProjectileVelocity
local Spring_GetProjectileGravity = Spring.GetProjectileGravity
local Spring_GetGroundHeight = Spring.GetGroundHeight
local Spring_GetProjectileTarget = Spring.GetProjectileTarget
local Spring_GetUnitPosition = Spring.GetUnitPosition
local Spring_GetFeaturePosition = Spring.GetFeaturePosition
local Spring_GetProjectileDefID = Spring.GetProjectileDefID
local Spring_GetProjectilesInRectangle = Spring.GetProjectilesInRectangle

local ARTILLERY_TYPE = 1
local ROCKET_TYPE = 2

local weaponNameTypes = {
  ['armart_tawf113_weapon'] = ARTILLERY_TYPE,

  ['armmerl_armtruck_rocket'] = ROCKET_TYPE,
  ['armmh_armmh_weapon'] = ROCKET_TYPE,
  ['armmship_rocket'] = ROCKET_TYPE,
  ['armmship_rocket_split'] = ARTILLERY_TYPE,

  ['corwolv_corwolv_gun'] = ARTILLERY_TYPE,

  ['corhrk_corhrk_rocket'] = ROCKET_TYPE,
  ['corvroc_cortruck_rocket'] = ROCKET_TYPE,
  --['corshiva_shiva_rocket'] = ROCKET_TYPE,

  ['cormart_cor_artillery'] = ARTILLERY_TYPE,
  ['cortrem_tremor_focus_fire'] = ARTILLERY_TYPE,

  ['raptor_allterrain_arty_basic_t2_v1_goolauncher'] = ARTILLERY_TYPE,
  ['raptor_allterrain_arty_basic_t4_v1_goolauncher'] = ARTILLERY_TYPE,
  ['raptorartillery_goolauncher'] = ARTILLERY_TYPE,

  ['raptor_hive_antiground'] = ARTILLERY_TYPE,
  ['raptor_turret_acid_t2_v1_acidspit'] = ARTILLERY_TYPE,
  ['raptor_turret_acid_t3_v1_acidspit'] = ARTILLERY_TYPE,
  ['raptor_turret_acid_t4_v1_acidspit'] = ARTILLERY_TYPE,
  ['raptor_turret_basic_t2_v1_weapon'] = ARTILLERY_TYPE,
  ['raptor_turret_basic_t3_v1_weapon'] = ARTILLERY_TYPE,
  ['raptor_turret_basic_t4_v1_weapon'] = ARTILLERY_TYPE,
  ['raptor_turret_burrow_t2_v1_weapon'] = ARTILLERY_TYPE,
  ['raptor_turret_emp_t2_v1_raptorparalyzersmall'] = ARTILLERY_TYPE,
  ['raptor_turret_emp_t3_v1_raptorparalyzerbig'] = ARTILLERY_TYPE,
  ['raptor_turret_emp_t4_v1_raptorparalyzerbig'] = ARTILLERY_TYPE,
  ['raptor_worm_green_acidspit'] = ARTILLERY_TYPE,

}

local weaponIdTypes = {}

for weaponName, type in pairs(weaponNameTypes) do
  if WeaponDefNames[weaponName] then
    weaponIdTypes[WeaponDefNames[weaponName].id] = type
  end
end

function widget:Initialize()
  -- Spring.Echo("Remember to not stand in fire")
  -- Script.SetWatchProjectile(1, true)
  -- weaponFunc[WeaponDefNames['armart_tawf113_weapon'].id] = findArtilleryGroundIntersection

  -- weaponFunc[WeaponDefNames['armmerl_armtruck_rocket'].id] = findRocketGroundIntersection
  -- weaponFunc[WeaponDefNames['armmh_armmh_weapon'].id] = findRocketGroundIntersection
  -- weaponFunc[WeaponDefNames['armmship_rocket'].id] = findRocketGroundIntersection
  -- weaponFunc[WeaponDefNames['armmship_rocket_split'].id] = findArtilleryGroundIntersection

  -- weaponFunc[WeaponDefNames['corwolv_corwolv_gun'].id] = findArtilleryGroundIntersection

  -- weaponFunc[WeaponDefNames['corhrk_corhrk_rocket'].id] = findRocketGroundIntersection
  -- weaponFunc[WeaponDefNames['corvroc_cortruck_rocket'].id] = findRocketGroundIntersection
  -- --weaponFunc[WeaponDefNames['corshiva_shiva_rocket'].id] = findRocketGroundIntersection

  -- weaponFunc[WeaponDefNames['cormart_cor_artillery'].id] = findArtilleryGroundIntersection
  -- weaponFunc[WeaponDefNames['cortrem_tremor_focus_fire'].id] = findArtilleryGroundIntersection
end

local function drawSplash(x,y,z, srange)
  glPushMatrix()

  local cColor = {1, 255, 1, 0.5}
  glColor(cColor[1], cColor[2], cColor[3], alpha * 2)
  glLineWidth(3)
  glDrawGroundCircle(x, y+16, z, srange*1.1, 32)

  glPopMatrix()
end

--function widget:ProjectileCreated(proID, proOwnerID, weaponDefID)
--  Spring.Echo(proID)
--end

local function findArtilleryGroundIntersection(p)
  local x,y,z = Spring_GetProjectilePosition(p)
  local vx,vy,vz = Spring_GetProjectileVelocity(p)
  local grav = Spring_GetProjectileGravity(p)
  local step = .6
  local maxSteps = 10000
  for i=1, maxSteps do
    x = x+vx*step
    z = z+vz*step
    vy = vy+(grav*step)
    y = y+vy*step
    local height = Spring_GetGroundHeight(x,z)
    -- log('height',height, y, 'x ' .. x .. ' y ' .. y .. ' z ' .. z)
    if height > y then
      return {x=x,y=height,z=z}
    end
  end
  return nil
end

local function findRocketGroundIntersection(p)
  local targtype, targ = Spring_GetProjectileTarget(p)
  if targtype == string.byte('g') then
    -- ground
    return {x=targ[1],y=targ[2],z=targ[3]}
  elseif targtype == string.byte('u') then
    --return findArtilleryGroundIntersection(p)
    --return Spring_GetUnitPosition(targ)
  elseif targtype == string.byte('f') then
    local pos = Spring_GetFeaturePosition(targ)
    return {x=pos[1],y=pos[2],z=pos[3]}
  end
  return nil
end

local function showProjectileSplash(p)
  local res = projectiles[p]
  if res then
    drawSplash(res.ix, res.iy, res.iz, res.srange)
  end
end

local function calculateImpact(p, frame)
  if projectiles[p] and projectiles[p].frame + 30 > frame then
    -- already calculated the impact, and the frametime is recent
    projectiles[p].frame = frame
    drawList[drawListIndex] = p
    drawListIndex = drawListIndex + 1
    return
  end
  local did = Spring_GetProjectileDefID(p)
  if not weaponIdTypes[did] then
    return
  end
  -- local ix,iy,iz = weaponIdTypes[did] == ARTILLERY_TYPE and findArtilleryGroundIntersection(p) or findRocketGroundIntersection(p)
  local result = weaponIdTypes[did] == ARTILLERY_TYPE and findArtilleryGroundIntersection(p) or findRocketGroundIntersection(p)
  if not result then
    projectiles[p] = {ix=0,iy=0,iz=0,srange=0, frame=frame}
    return
  end

  local srange = 45
  local wd = WeaponDefs[did]
  if wd then
    srange = wd["damageAreaOfEffect"]
  end
  projectiles[p] = {ix=result.x, iy=result.y, iz=result.z, srange=srange, frame=frame}
  drawList[drawListIndex] = p
  drawListIndex = drawListIndex + 1
end

function widget:GameFrame(frame)
  if frame % 15 == 0 then
    local pros = Spring_GetProjectilesInRectangle(0,0,10000,10000,false,true)
    drawList = {}
    drawListIndex = 1
    for pi=1,#pros do
      local p = pros[pi]
      calculateImpact(p, frame)
    end
  end
end

function widget:DrawWorldPreUnit()
  for i=1,#drawList do
    showProjectileSplash(drawList[i])
  end
end
