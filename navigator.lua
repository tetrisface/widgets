function widget:GetInfo()
  return {
    name      = "navigator",
    desc      = "",
    author    = "tetrisface",
    version   = "",
    date      = "jan, 2024",
    license   = "",
    layer     = -99990,
    enabled   = false,
	}
end

local GetCameraPosition = Spring.GetCameraPosition
local GetSelectedUnits = Spring.GetSelectedUnits
local GetUnitsInRectangle = Spring.GetUnitsInRectangle
local GetUnitViewPosition = Spring.GetUnitViewPosition
local GetVisibleUnits = Spring.GetVisibleUnits
local log = Spring.Echo
local myTeamId = Spring.GetMyTeamID()
local SetCameraTarget = Spring.SetCameraTarget

function widget:KeyPress(key, mods, isRepeat)
  -- log(key .. " "..table.tostring(mods))

  if key ~= 301 and key ~= 9 then
    return
  end

  local wrecksInRange = GetFeaturesInCylinder(mpx, mpz, builderDef.buildDistance)     



  -- local selectedUnits0 = GetSelectedUnits()

  -- local camera0 = GetCameraPosition()

  -- local visibleUnitsArr = GetVisibleUnits(myTeamId, nil, true)
  -- local visibleUnits = {}
  -- for i=1, #visibleUnitsArr do
  --   local unitId = visibleUnitsArr[i]
  --   visibleUnits[unitId] = GetUnitViewPosition(unitId)
  -- end

  -- boundaries = 
  

end


function getPositionBoundaries(points)
  local xMin = math.huge
  local zMin = math.huge
  local xMax = -math.huge
  local zMax = -math.huge
  for i = 1, #points  do
    local point = points[i]
    xMin = xMin < point.x and xMin or point.x
    xMax = xMax > point.x and xMax or point.x
    zMin = zMin < point.z and zMin or point.z 
    zMax = zMax > point.z and zMax or point.z 
  end
  return xMin, xMax, yMin, yMax
end


  -- for printing tables
function table.val_to_str(v)
  if "string" == type(v) then
    v = string.gsub(v, "\n", "\\n" )
    if string.match(string.gsub(v,"[^'\"]",""), '^"+$' ) then
      return "'" .. v .. "'"
    end
    return '"' .. string.gsub(v,'"', '\\"' ) .. '"'
  else
    return "table" == type(v) and table.tostring(v) or
      tostring(v)
  end
end

function table.key_to_str(k)
  if "string" == type(k) and string.match(k, "^[_%a][_%a%d]*$" ) then
    return k
  else
    return "[" .. table.val_to_str(k) .. "]"
  end
end

function table.tostring(tbl)
  local result, done = {}, {}
  for k, v in ipairs(tbl ) do
    table.insert(result, table.val_to_str(v) )
    done[ k ] = true
  end
  for k, v in pairs(tbl) do
    if not done[ k ] then
      table.insert(result,
        table.key_to_str(k) .. "=" .. table.val_to_str(v) )
    end
  end
  return "{" .. table.concat(result, "," ) .. "}"
end
