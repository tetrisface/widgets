function widget:GetInfo()
  return {
    desc    = "",
    author  = "tetrisface",
    version = "",
    date    = "May, 2024",
    name    = "History",
    license = "",
    layer   = -99990,
    enabled = true,
  }
end

VFS.Include('luaui/Widgets/.noload/misc/helpers.lua')

local updateMs = 100
local updateTimer = Spring.GetTimer()
local myTeamId = Spring.GetMyTeamID()
local mouseBusy = false

local historicUnits = {}
local unitHistory = {}


-- Concatenate the list of integers into a single string
local function concatenate_list(int_list)
  local str = ""
  for _, num in ipairs(int_list) do
    str = str .. tostring(num)
  end
  return str
end

-- Manual left shift operation
local function left_shift(value, shift)
  return value * (2 ^ shift)
end

-- Manual bitwise OR operation
local function bitwise_or(a, b)
  local result = 0
  local bitval = 1
  while a > 0 or b > 0 do
    if (a % 2 == 1) or (b % 2 == 1) then
      result = result + bitval
    end
    a = math.floor(a / 2)
    b = math.floor(b / 2)
    bitval = bitval * 2
  end
  return result
end

-- A simple hash function (djb2 algorithm with manual bitwise operations)
local function Hash(str)
  local hash = 5381
  for i = 1, #str do
    local char = string.byte(str, i)
    hash = bitwise_or(left_shift(hash, 5), hash) + char -- hash * 33 + char
  end
  return hash
end


function widget:Initialize()
  myTeamId = Spring.GetMyTeamID()

  -- if Spring.GetSpectatingState() or Spring.IsReplay() then
  --   widgetHandler:RemoveWidget()
  -- end
end

-- function widget:UnitCreated(unitID, unitDefID, unitTeam)
--   if unitTeam ~= myTeamId then
--     return
--   end
-- end

-- function widget:UnitGiven(unitID, unitDefID, unitTeam, oldTeam)
--   widget:UnitCreated(unitID, unitDefID, unitTeam)
-- end

-- function widget:UnitTaken(unitID, unitDefID, unitTeam, oldTeam)
--   widget:UnitCreated(unitID, unitDefID, unitTeam)
-- end

local function storeCheckSelection()
  local selectedUnits = Spring.GetSelectedUnits()
  if #selectedUnits > 0 then
    local hash = Hash(concatenate_list(selectedUnits))
    if historicUnits[hash] then
      historicUnits[hash] = selectedUnits
      table.insert(unitHistory, {
        time = Spring.GetTimer(),
        units = selectedUnits,
        hash = hash

      })
    end
  end
end

local function storeCheckCamera()
  local camX, camY, camZ = Spring.GetCameraPosition()
end

function widget:Update()
  if mouseBusy or Spring.DiffTimers(Spring.GetTimer(), updateTimer, true) < updateMs or Spring.GetActiveCommand() == 0 then
    return
  end

  updateTimer = Spring.GetTimer()

  storeCheckSelection()
  storeCheckCamera()
end

-- function widget:KeyPress(key, mods, isRepeat)
--   log('key', key)
-- if key == 294 then
--   active = true
--   return true
-- end

-- if not active then
--   return
-- end

-- if (key < 48 or key > 52) and not buildFactory then
--   return
-- end

-- if isRepeat then
--   return
-- end

-- if not buildFactory and keyFactories[key] then
--   buildFactory = keyFactories[key]
--   return true
-- end

-- if key < 47 or key > 57 or not buildFactory then
--   return
-- end

-- buildCountString = buildCountString .. tostring(key - 48)
-- end

-- function widget:KeyRelease(key, mods, isRepeat)
-- log('key release', key, 'mods', mods, 'isRepeat', isRepeat)
-- end

-- function widget:MousePress()
--   mouseBusy = true
--   return true
-- end

-- function widget:MouseMove(x, y, dx, dy, button)
--   log('mouse move', x, y, dx, dy, button)
-- end

-- function widget:MouseRelease()
--   log('mouse release')
--   mouseBusy = false
-- end

-- function widget:MouseRelease(x, y, button)
--   moving = nil
-- end
