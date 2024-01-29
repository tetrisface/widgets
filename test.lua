function widget:GetInfo()
  return {
    name    = "(test)",
    desc    = "",
    author  = "tetrisface",
    version = "",
    date    = "jan, 2024",
    license = "",
    layer   = -99990,
    enabled = false,
  }
end

local GetCameraPosition = Spring.GetCameraPosition
local GetSelectedUnits = Spring.GetSelectedUnits
local GetUnitsInRectangle = Spring.GetUnitsInRectangle
local GetUnitViewPosition = Spring.GetUnitViewPosition
local GetVisibleUnits = Spring.GetVisibleUnits
local GetFeaturesInCylinder = Spring.GetFeaturesInCylinder
local GetFeatureResources = Spring.GetFeatureResources
local GetMouseState = Spring.GetMouseState
local TraceScreenRay = Spring.TraceScreenRay
local GiveOrderToUnit = Spring.GiveOrderToUnit
local log = Spring.Echo
local myTeamId = Spring.GetMyTeamID()
local SetCameraTarget = Spring.SetCameraTarget
local GetSelectedUnits = Spring.GetSelectedUnits
local GetUnitCommands = Spring.GetUnitCommands
local GetUnitStates = Spring.GetUnitStates
local GetUnitDefID = Spring.GetUnitDefID
local UnitDefs = UnitDefs


function widget:MouseRelease(x, y, button)
  -- log('mouse release ' .. x .. " " .. y .. " " .. button)
  -- return false
end

function widget:MousePress(x, y, button)
  -- local cmdQueue = GetUnitCommands(16230, 3)
  -- log(cmdQueue[1].params[1])
  -- local unitDef = UnitDefs[GetUnitDefID(24505)]

  -- log(table.tostring(unitDef.wDefs[1]))
  -- log(unitDef.wDefs[1].projectilespeed)

  -- local desc, args = TraceScreenRay(x, y, true)
  -- if nil == desc then return end -- off map
  -- local worldX = args[1]
  -- local worldY = args[2]
  -- local worldZ = args[3]
  -- log('x ' .. math.floor(worldX) .. ' z ' .. math.floor(worldZ))

  -- log('mouse press ' .. x .. " " .. y .. " " .. button)
  -- return false
  -- local unitStates = GetUnitStates(20448)
  -- log('unitStates')
  -- log(table.tostring(unitStates))
  -- SetUnitTarget(30651, 6298)
  -- GiveOrderToUnit(4281, CMD.FIGHT, 22248, {})
  -- log('Spring.GetGameRulesParam(mmLevel)')
  -- log(Spring.SetTeamRulesParam(myTeamId, 'mmLevel', 0.2))
end

function widget:MouseMove(x, y, dx, dy, button)
  -- log('move1 ' .. x .. ' ' .. y .. " " .. button)
  -- if not keyHold then
  --   return
  -- end
  -- log('move ' .. x .. ' ' .. y)


  -- if math.abs(x-keyPressMouseX) > 50 or math.abs(y-keyPressMouseY) > 50 then
  --   log('moved ' .. x-keyPressMouseX ' and ' .. y-keyPressMouseY)
  -- end
  -- return false
end

-- function getReclaimableFeature(x , z, radius)
--   local wrecksInRange = GetFeaturesInCylinder(x, z, radius)

--   if #wrecksInRange == 0 then
--     return
--   end

--   -- for i=1, #wrecksInRange do
--   --   local metal, _, energy = GetFeatureResources(featureId)
--   --   if metal + energy == 0 then
--   --     goto continue
--   --   end
--   --   local featureId = wrecksInRange[i]
--   --   local featureId = wrecksInRange[i]
--   --   ::continue::
--   -- end
--   local featureId = wrecksInRange[1]
--   local metal, _, energy = GetFeatureResources(featureId)
--   -- log('feature metal ' .. metal, ' energy ' .. energy)
--   return featureId
-- end


-- function widget:KeyPress(key, mods, isRepeat)
--   log(key .. " "..table.tostring(mods))

--   if key ~= 306 and key ~= 9 then
--     return
--   end

--   local mouse_x, mouse_y = GetMouseState ( )
--   -- local mouse_x, mouse_y = GetMouseStartPosition(0)
--   -- local wrecksInRange = GetFeaturesInCylinder(mpx, mpz, builderDef.buildDistance)
--   local desc, args = TraceScreenRay(mouse_x, mouse_y, true)
--   if nil == desc then return end -- off map
--   local x = args[1]
--   local y = args[2]
--   local z = args[3]
--   log('x ' .. x .. ' z ' .. z)

--   local selectedUnits = GetSelectedUnits()
--   local unitId = 26618

--   -- log(table.tostring(selectedUnits))

--   local featureId = getReclaimableFeature(x, z, 123)

--   if not featureId then
--     return
--   end

--   log('featureId ' .. (featureId or ''))

--   local queue = GetUnitCommands(unitId, 1)

--   -- already reclaiming
--   if #queue > 0 and queue[1].id == 90 then
--     return
--   end

--   GiveOrderToUnit(unitId, CMD.INSERT, {0, CMD.RECLAIM, CMD.OPT_SHIFT, Game.maxUnits+featureId}, {'alt'})
--   -- local selectedUnits0 = GetSelectedUnits()

--   -- local camera0 = GetCameraPosition()

--   -- local visibleUnitsArr = GetVisibleUnits(myTeamId, nil, true)
--   -- local visibleUnits = {}
--   -- for i=1, #visibleUnitsArr do
--   --   local unitId = visibleUnitsArr[i]
--   --   visibleUnits[unitId] = GetUnitViewPosition(unitId)
--   -- end

--   -- boundaries =


-- end


-- function getPositionBoundaries(points)
--   local xMin = math.huge
--   local zMin = math.huge
--   local xMax = -math.huge
--   local zMax = -math.huge
--   for i = 1, #points  do
--     local point = points[i]
--     xMin = xMin < point.x and xMin or point.x
--     xMax = xMax > point.x and xMax or point.x
--     zMin = zMin < point.z and zMin or point.z
--     zMax = zMax > point.z and zMax or point.z
--   end
--   return xMin, xMax, yMin, yMax
-- end


-- for printing tables
function table.val_to_str(v)
  if "string" == type(v) then
    v = string.gsub(v, "\n", "\\n")
    if string.match(string.gsub(v, "[^'\"]", ""), '^"+$') then
      return "'" .. v .. "'"
    end
    return '"' .. string.gsub(v, '"', '\\"') .. '"'
  else
    return "table" == type(v) and table.tostring(v) or
        tostring(v)
  end
end

function table.key_to_str(k)
  if "string" == type(k) and string.match(k, "^[_%a][_%a%d]*$") then
    return k
  else
    return "[" .. table.val_to_str(k) .. "]"
  end
end

function table.tostring(tbl)
  local result, done = {}, {}
  for k, v in ipairs(tbl) do
    table.insert(result, table.val_to_str(v))
    done[k] = true
  end
  for k, v in pairs(tbl) do
    if not done[k] then
      table.insert(result,
        table.key_to_str(k) .. "=" .. table.val_to_str(v))
    end
  end
  return "{" .. table.concat(result, ",") .. "}"
end
