function widget:GetInfo()
  return {
    desc    = "",
    author  = "tetrisface",
    version = "",
    date    = "May, 2024",
    name    = "Build Shortcuts",
    license = "",
    layer   = -99990,
    enabled = true,
  }
end

VFS.Include('luaui/Widgets/misc/helpers.lua')

local myTeamId = Spring.GetMyTeamID()
local active = false
local keysFactoryDefIds = {
  [49] = (UnitDefNames['legavp'] or UnitDefNames['coravp']).id,
  [50] = UnitDefNames['armavp'].id,
  [51] = (UnitDefNames['legaap'] or UnitDefNames['coraap']).id,
  [52] = UnitDefNames['armaap'].id,
}
local factoryDefIdsConDefIds = {
  [(UnitDefNames['legavp'] or UnitDefNames['coravp']).id] = (UnitDefNames['legacv'] or UnitDefNames['coracv']).id,
  [UnitDefNames['armavp'].id] = UnitDefNames['armacv'].id,
  [(UnitDefNames['legaap'] or UnitDefNames['coraap']).id] = (UnitDefNames['legaca'] or UnitDefNames['coraca']).id,
  [UnitDefNames['armaap'].id] = UnitDefNames['armaca'].id,
}
-- local buildCountString = ''
-- local factoryDefId = nil
local waitingForConDefId = nil
local selectedUnits = {}

function widget:Initialize()
  myTeamId = Spring.GetMyTeamID()
  active = false
  keysFactoryDefIds = {
    [49] = (UnitDefNames['legavp'] or UnitDefNames['coravp']).id,
    [50] = UnitDefNames['armavp'].id,
    [51] = (UnitDefNames['legaap'] or UnitDefNames['coraap']).id,
    [52] = UnitDefNames['armaap'].id,
  }
  factoryDefIdsConDefIds = {
    [(UnitDefNames['legavp'] or UnitDefNames['coravp']).id] = (UnitDefNames['legacv'] or UnitDefNames['coracv']).id,
    [UnitDefNames['armavp'].id] = UnitDefNames['armacv'].id,
    [(UnitDefNames['legaap'] or UnitDefNames['coraap']).id] = (UnitDefNames['legaca'] or UnitDefNames['coraca']).id,
    [UnitDefNames['armaap'].id] = UnitDefNames['armaca'].id,
  }
  --  buildCountString = ''
  -- factoryDefId = nil
  waitingForConDefId = nil
  selectedUnits = {}

  if Spring.GetSpectatingState() or Spring.IsReplay() then
    widgetHandler:RemoveWidget()
  end
end

function widget:UnitCreated(unitID, unitDefID, unitTeam)
  if unitTeam ~= myTeamId or not active or not waitingForConDefId or unitDefID ~= waitingForConDefId then
    return
  end

  local units = Spring.GetSelectedUnits() or {}

  table.insert(units, unitID)

  Spring.SelectUnitArray(units)
end

local function addSelected(other)
  if other then
    selectedUnits[other] = true
  end
  local currentSelectedUnits = Spring.GetSelectedUnits() or {}
  for i = 1, #currentSelectedUnits do
    selectedUnits[currentSelectedUnits[i]] = true
  end
end

local function resetSelected()
  selectedUnits = {}
end
local function exec(factoryDefId, conDefId)
  log('exec', factoryDefId)
  -- local selectedUnits = Spring.GetSelectedUnits() or {}
  -- log('selectedUnits', selectedUnits, '#selectedUnits', #selectedUnits)

  -- if not factoryDefId then
  --   return
  -- end

  local factoryId = Spring.GetTeamUnitsByDefs(myTeamId, { factoryDefId })[1]

  if not factoryId then
    -- factoryDefId = nil
    -- buildCountString = ''
    return
  end

  local inProgressId = Spring.GetUnitIsBuilding(factoryId)

  if inProgressId and Spring.GetUnitDefID(inProgressId) == conDefId then
    addSelected(inProgressId)
  end

  local buildCount = 1

  if buildCount then
    for i = 1, buildCount do
      Spring.GiveOrderToUnit(factoryId, -conDefId, {}, {})
    end


    local mouseX, mouseY = Spring.GetMouseState()
    local desc, args = Spring.TraceScreenRay(mouseX, mouseY, true)
    if nil ~= desc then -- off map
      local x = args[1]
      local y = args[2]
      local z = args[3]
      Spring.GiveOrderToUnit(factoryId, CMD.MOVE, args, {})
    end
    -- Spring.SelectUnitArray(selectedUnits)
  else
    local cx, cy, cz = Spring.GetUnitPosition(factoryId)
    Spring.SetCameraTarget(cx, cy, cz, 0)
  end

  -- factoryDefId = nil
  -- buildCountString = ''
end


function widget:KeyPress(key, mods, isRepeat)
  addSelected()
  -- log('key', key, '#selectedUnits', #Spring.GetSelectedUnits())

  if key == 294 then
    if isRepeat then
      return false
    end
    waitingForConDefId = nil
    active = true
    return true
  end

  if not active then
    return
  end

  -- if (key < 48 or key > 52) and not factoryDefId then
  if (key < 48 or key > 52) then
    return
  end


  -- if not factoryDefId and keysFactoryDefIds[key] then
  -- factoryDefId = keysFactoryDefIds[key]
  waitingForConDefId = factoryDefIdsConDefIds[keysFactoryDefIds[key]]
  exec(keysFactoryDefIds[key], waitingForConDefId)

  Spring.SelectUnitMap(selectedUnits)

  return true
  -- end

  -- if key < 47 or key > 57 or not buildFactory then
  --   return
  -- end

  -- buildCountString = buildCountString .. tostring(key - 48)
end

function widget:KeyRelease(key, mods, isRepeat)
  -- log('key release', key, 'mods', mods, 'isRepeat', isRepeat)
  if key == 294 then
    resetSelected()
    active = false
    return true
  end
end
