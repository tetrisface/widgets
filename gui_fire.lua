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


local weaponFunc = {}
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

function widget:Initialize()
  Spring.Echo("Remember to not stand in fire")
  --Script.SetWatchProjectile(1, true)
  weaponFunc[WeaponDefNames['armart_tawf113_weapon'].id] = findArtilleryGroundIntersection

  weaponFunc[WeaponDefNames['armmerl_armtruck_rocket'].id] = findRocketGroundIntersection
  weaponFunc[WeaponDefNames['armmh_armmh_weapon'].id] = findRocketGroundIntersection
  weaponFunc[WeaponDefNames['armmship_rocket'].id] = findRocketGroundIntersection
  weaponFunc[WeaponDefNames['armmship_rocket_split'].id] = findArtilleryGroundIntersection

  weaponFunc[WeaponDefNames['corwolv_corwolv_gun'].id] = findArtilleryGroundIntersection

  weaponFunc[WeaponDefNames['corhrk_corhrk_rocket'].id] = findRocketGroundIntersection
  weaponFunc[WeaponDefNames['corvroc_cortruck_rocket'].id] = findRocketGroundIntersection
  --weaponFunc[WeaponDefNames['corshiva_shiva_rocket'].id] = findRocketGroundIntersection

  weaponFunc[WeaponDefNames['cormart_cor_artillery'].id] = findArtilleryGroundIntersection
  weaponFunc[WeaponDefNames['cortrem_tremor_focus_fire'].id] = findArtilleryGroundIntersection
end

function drawSplash(x,y,z, srange)
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

function findArtilleryGroundIntersection(p)
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
    if height > y then
      return x,height,z
    end
  end
  return nil
end

function findRocketGroundIntersection(p)
  local targtype, targ = Spring_GetProjectileTarget(p)
  if targtype == string.byte('g') then
    -- ground
    return targ[1],targ[2],targ[3]
  elseif targtype == string.byte('u') then
    --return findArtilleryGroundIntersection(p)
    --return Spring_GetUnitPosition(targ)
  elseif targtype == string.byte('f') then
    return Spring_GetFeaturePosition(targ)
  end
  return nil
end

function showProjectileSplash(p)
  local res = projectiles[p]
  if res then
    drawSplash(res.ix, res.iy, res.iz, res.srange)
  end
end

function calculateImpact(p, frame)
  if projectiles[p] and projectiles[p].frame + 30 > frame then
    -- already calculated the impact, and the frametime is recent
    projectiles[p].frame = frame
    drawList[drawListIndex] = p
    drawListIndex = drawListIndex + 1
    return
  end
  local did = Spring_GetProjectileDefID(p)
  if not weaponFunc[did] then
    return
  end
  local ix,iy,iz = weaponFunc[did](p)
  if not ix then
    projectiles[p] = {ix=0,iy=0,iz=0,srange=0, frame=frame}
    return
  end

  local srange = 45
  local wd = WeaponDefs[did]
  if wd then
    srange = wd["damageAreaOfEffect"]
  end
  projectiles[p] = {ix=ix, iy=iy, iz=iz, srange=srange, frame=frame}
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
