function widget:GetInfo()
  return {
    name    = "(wip) navigator",
    desc    = "",
    author  = "tetrisface",
    version = "",
    date    = "jan, 2024",
    license = "",
    layer   = -99990,
    enabled = false,
  }
end

local GetMouseState = Spring.GetMouseState
local GetScreenGeometry = Spring.GetScreenGeometry
local GetTeamUnits = Spring.GetTeamUnits
local GetUnitDefID = Spring.GetUnitDefID
local GetUnitPosition = Spring.GetUnitPosition
local GetUnitsInRectangle = Spring.GetUnitsInRectangle
local log = Spring.Echo
local myTeamId = Spring.GetMyTeamID()
local SelectUnitArray = Spring.SelectUnitArray
local SetCameraTarget = Spring.SetCameraTarget
local TraceScreenRay = Spring.TraceScreenRay
local GetUnitCommands = Spring.GetUnitCommands
local GetVisibleUnits = Spring.GetVisibleUnits

local teamUnits = {}
local keyPressMouseX, keyPressMouseY = GetMouseState()
local isNavigatorActive = false


local function RegisterUnit(unitID, unitDefID)
  if not unitDefID then
    return
  end

  local unitDef = UnitDefs[unitDefID]
  teamUnits[unitID] = {
    ['unitDef'] = unitDef,
  }
end

function widget:Initialize()
  if Spring.GetSpectatingState() or Spring.IsReplay() then
    widgetHandler:RemoveWidget()
  end

  local myUnitsIds = GetTeamUnits(myTeamId)
  for i = 1, #myUnitsIds do
    local unitID = myUnitsIds[i]
    local unitDefID = GetUnitDefID(unitID)
    RegisterUnit(unitID, unitDefID)
  end
end

function widget:UnitCreated(unitID, unitDefID, unitTeam)
  RegisterUnit(unitID, unitDefID)
end

function widget:UnitGiven(unitID, unitDefID, unitTeam, oldTeam)
  if unitTeam == myTeamId then
    RegisterUnit(unitID, unitDefID)
  end
end

function widget:MouseRelease(x, y, button)
  if button ~= 5 then
    return false
  end
  isNavigatorActive = false
  local moveDirection = getPressMoveDirection(x, y)

  -- check for not selecting
  if not moveDirection then
    return false
  end
  -- log('move ' .. moveDirection)

  local screenWidth, screenHeight = GetScreenGeometry()
  local _, topLeftPos = TraceScreenRay(0, screenHeight - 1, true)
  local _, topRightPos = TraceScreenRay(screenWidth - 1, screenHeight - 1, true)
  local _, bottomLeftPos = TraceScreenRay(0, 0, true)
  local _, bottomRightPos = TraceScreenRay(screenWidth - 1, 0, true)

  topLeftPos = topLeftPos or { 0, 0, 0 }
  topRightPos = topRightPos or { Game.mapSizeX, nil, 0 }
  bottomLeftPos = bottomLeftPos or { 0, nil, Game.mapSizeZ }
  bottomRightPos = bottomRightPos or { Game.mapSizeX, nil, Game.mapSizeZ }

  -- log('topLeftPos ' .. math.floor(topLeftPos[1]) .. ' ' .. math.floor(topLeftPos[3]))
  -- log('topRightPos ' .. math.floor(topRightPos[1]) .. ' ' .. math.floor(topRightPos[3]))
  -- log('bottomLeftPos ' .. math.floor(bottomLeftPos[1]) .. ' ' .. math.floor(bottomLeftPos[3]))
  -- log('bottomRightPos ' .. math.floor(bottomRightPos[1]) .. ' ' .. math.floor(bottomRightPos[3]))

  local units, rectangle
  if moveDirection == 'right' then
    units, rectangle = getUnits(math.min(topRightPos[1], bottomRightPos[1]), 0, Game.mapSizeX, Game.mapSizeZ,
      math.mininteger)
  elseif moveDirection == 'left' then
    units, rectangle = getUnits(0, 0, math.min(topLeftPos[1], bottomLeftPos[1]), Game.mapSizeZ, math.mininteger)
  elseif moveDirection == 'up' then
    units, rectangle = getUnits(0, 0, Game.mapSizeX, math.max(topLeftPos[3], topRightPos[3]), math.mininteger)
  elseif moveDirection == 'down' then
    units, rectangle = getUnits(0, math.min(bottomLeftPos[3], bottomRightPos[3]), Game.mapSizeX, Game.mapSizeZ,
      math.mininteger)
  end

  -- log('found units ' .. (units and #units or 0) .. ' rect ' .. (rectangle and table.tostring(rectangle) or ''))

  if not units or #units == 0 then
    return true
  end

  shuffle(units)

  local unitPositionsX = {}
  local unitPositionsZ = {}
  for i = 1, math.min(#units, 1000) do
    local unitX, _, unitZ = GetUnitPosition(units[i], true)
    table.insert(unitPositionsX, unitX)
    table.insert(unitPositionsZ, unitZ)
  end

  SetCameraTarget(median(unitPositionsX), 0, median(unitPositionsZ), 0)

  SelectUnitArray(units)

  return true
end

function table.min(table_)
  local min = table_[1]
  for i = 1, #table_ do
    min = min < table_[i] and min or table_[i]
  end
  return min
end

function table.max(table_)
  local max = table_[1]
  for i = 1, #table_ do
    max = max < table_[i] and max or table_[i]
  end
  return max
end

function getUnits(xMin, zMin, xMax, zMax, total)
  if table.has_value({ xMin, xMax, zMin, zMax }, nil) then
    -- log('nil params')
    return {}, {}
  end

  local units = GetUnitsInRectangle(xMin, zMin, xMax, zMax, myTeamId)
  -- log('getunits ' ..
  -- xMin ..
  -- ' ' ..
  -- zMin ..
  -- ' ' ..
  -- xMax .. ' ' .. zMax .. ' ' .. table.tostring(units) .. ' #units ' .. #units .. ' total ' .. (total and total or 0))
  if not total then
    total = #units
  elseif #units <= 0.8 * total or #units < 2 then
    return units, { xMin, zMin, xMax, zMax }
  end

  local originX = xMin + (xMax - xMin) / 2
  local originZ = zMin + (zMax - zMin) / 2
  local subRectangles = {
    -- topLeftUnits
    { xMin,    zMin,    originX, originZ },
    -- topRightUnits
    { originX, zMin,    xMax,    originZ },
    -- bottomLeftUnits
    { xMin,    originZ, originX, zMax },
    -- bottomRightUnits
    { originX, originZ, xMax,    zMax },
  }
  for i = 1, 4 do
    local subRect = subRectangles[i]
    -- local subRectangleUnits, subRectangleArgs = getUnits(subRect[1], subRect[2], subRect[3], subRect[4], total)
    local subUnits = GetUnitsInRectangle(subRect[1], subRect[2], subRect[3], subRect[4], myTeamId)
    -- log('#subUnits ' .. #subUnits .. ' total ' .. total .. ' args ' .. table.tostring(subRect))
    if #subUnits >= 0.8 * total then
      return getUnits(subRect[1], subRect[2], subRect[3], subRect[4], total)
    end
  end
  return units, { xMin, zMin, xMax, zMax }
end

function shuffle(tbl)
  for i = #tbl, 2, -1 do
    local j = math.random(i)
    tbl[i], tbl[j] = tbl[j], tbl[i]
  end
  return tbl
end

function median(temp)
  table.sort(temp)

  -- If we have an even number of table elements or odd.
  if math.fmod(#temp, 2) == 0 then
    -- return mean value of middle two elements
    return (temp[#temp / 2] + temp[(#temp / 2) + 1]) / 2
  else
    -- return middle element
    return temp[math.ceil(#temp / 2)]
  end
end

function widget:MousePress(x, y, button)
  if button ~= 5 then
    return false
  end

  -- log('press ' .. x .. ' ' .. y .. ' == ' .. math.floor(pos[1]) .. ' ' .. math.floor(pos[3]))

  isNavigatorActive = true
  keyPressMouseX, keyPressMouseY = GetMouseState()
  local screenWidth, screenHeight = GetScreenGeometry()
  local _, keyPressScreenPos = TraceScreenRay(math.ceil(screenWidth / 2), math.ceil(screenHeight / 2), true)
  if keyPressScreenPos then
    initScreenPos = { ['x'] = keyPressScreenPos[1], ['y'] = keyPressScreenPos[2], ['z'] = keyPressScreenPos[3] }
  end
  return true
end

local function compareConsReverse(a, b)
  if not b or not a then
    return false
  end
  return (not a.hasBuildQueue and b.hasBuildQueue)
      or (a.def.cost < b.def.cost)
end

local function compareCons(a, b)
  if not b or not a then
    return false
  end
  return (not a.hasBuildQueue and b.hasBuildQueue)
      or (a.def.cost > b.def.cost)
end

local function filterSortUnitDefs(toFilterUnits, category, reverse)
  local filtered = {}
  if category == 'cons' then
    for i = 1, #toFilterUnits do
      local temp = toFilterUnits[i]
      local tempDef = temp['def']
      if tempDef.isBuilder and not tempDef.isBuilding and string.find(tempDef.translatedTooltip, 'Commander') == nil then
        temp['cmdQueue'] = GetUnitCommands(temp['id'], 10)
        temp['hasBuildQueue'] = false
        for j = 1, #temp['cmdQueue'] do
          if temp['cmdQueue'][j].id < 0 then
            temp['hasBuildQueue'] = true
            break
          end
        end
        table.insert(filtered, temp)
      end
    end
    table.sort(filtered, reverse and compareConsReverse or compareCons)
    return filtered
  end
  return toFilterUnits
end

function widget:KeyPress(key, mods, isRepeat)
  -- log('isNavigatorActive ' ..
  --   tostring(isNavigatorActive) ..
  --   ' key ' .. key .. ' mods ' .. table.tostring(mods) .. ' isRepeat ' .. tostring(isRepeat))
  local handledKeys = { 113 }
  if not isNavigatorActive or not table.has_value(handledKeys, key) then
    return false
  end
  -- if isRepeat then
  --   return true
  -- end

  local visibleUnits = unitDefMap(GetVisibleUnits(myTeamId))

  if key == 113 then
    local filteredSorted = filterSortUnitDefs(visibleUnits, 'cons', mods['ctrl'])
    if #filteredSorted > 0 then
      SelectUnitArray({ filteredSorted[1].id })
    end
  end

  return true
end

function unitDefMap(_unitIds)
  local map = {}
  for i = 1, #_unitIds do
    table.insert(map, {
      ['id'] = _unitIds[i],
      ['def'] = UnitDefs[GetUnitDefID(_unitIds[i])]
    })
  end
  return map
end

function getPressMoveDirection(x, y)
  local deltaX = x - keyPressMouseX
  local deltaY = y - keyPressMouseY
  if math.abs(deltaX) > 70 then
    if deltaX > 0 then
      return 'right'
    else
      return 'left'
    end
  elseif math.abs(deltaY) > 50 then
    if deltaY > 0 then
      return 'up'
    else
      return 'down'
    end
  end
  return false
end

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
