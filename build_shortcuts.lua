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

VFS.Include('luaui/Widgets/helpers.lua')

local active = false
local keyFactories = {
  [49] = (UnitDefNames['legavp'] or UnitDefNames['coravp']).id,
  [50] = UnitDefNames['armavp'].id,
  [51] = (UnitDefNames['legaap'] or UnitDefNames['coraap']).id,
  [52] = UnitDefNames['armaap'].id,
}
local factoryUnit = {
  [(UnitDefNames['legavp'] or UnitDefNames['coravp']).id] = (UnitDefNames['legacv'] or UnitDefNames['coracv']).id,
  [UnitDefNames['armavp'].id] = UnitDefNames['armacv'].id,
  [(UnitDefNames['legaap'] or UnitDefNames['coraap']).id] = (UnitDefNames['legaca'] or UnitDefNames['coraca']).id,
  [UnitDefNames['armaap'].id] = UnitDefNames['armaca'].id,
}
local buildFactory = nil
local buildCountString = ''
local myTeamId = Spring.GetMyTeamID()

local function UnitIdDef(unitId)
  return UnitDefs[Spring.GetUnitDefID(unitId)]
end

function widget:Initialize()
  active = false
  keyFactories = {
    [49] = (UnitDefNames['legavp'] or UnitDefNames['coravp']).id,
    [50] = UnitDefNames['armavp'].id,
    [51] = (UnitDefNames['legaap'] or UnitDefNames['coraap']).id,
    [52] = UnitDefNames['armaap'].id,
  }
  buildFactory = nil
  buildCountString = ''
  myTeamId = Spring.GetMyTeamID()

  if Spring.GetSpectatingState() or Spring.IsReplay() then
    widgetHandler:RemoveWidget()
  end

  -- for unitDefID, unitDef in pairs(UnitDefs) do
  --   if unitDef.isFactory then
  --     isFactoryDefId[unitDefID] = true
  --   end
  -- end
end

function widget:UnitCreated(unitID, unitDefID, unitTeam)
  if unitTeam ~= myTeamId then
    return
  end
end

function widget:UnitGiven(unitID, unitDefID, unitTeam, oldTeam)
  widget:UnitCreated(unitID, unitDefID, unitTeam)
end

function widget:UnitTaken(unitID, unitDefID, unitTeam, oldTeam)
  widget:UnitCreated(unitID, unitDefID, unitTeam)
end

local function exec()
  log('exec', buildFactory, buildCountString)
  if not buildFactory then
    return
  end

  local factoryId = Spring.GetTeamUnitsByDefs(myTeamId, { buildFactory })[1]

  if not factoryId then
    buildFactory = nil
    buildCountString = ''
    return
  end

  local buildCount = tonumber(buildCountString)

  if buildCount then
    for i = 1, buildCount do
      Spring.GiveOrderToUnit(factoryId, -factoryUnit[buildFactory], {}, {})
    end

    local mouseX, mouseY = Spring.GetMouseState()
    local desc, args = Spring.TraceScreenRay(mouseX, mouseY, true)
    if nil ~= desc then -- off map
      local x = args[1]
      local y = args[2]
      local z = args[3]
      Spring.GiveOrderToUnit(factoryId, CMD.MOVE, args, {})
    end
  else
    local cx, cy, cz = Spring.GetUnitPosition(factoryId)
    Spring.SetCameraTarget(cx, cy, cz, 0)
  end

  buildFactory = nil
  buildCountString = ''
end

function widget:KeyPress(key, mods, isRepeat)
  -- log('key', key)
  if key == 294 then
    active = true
    return true
  end

  if not active then
    return
  end

  if (key < 48 or key > 52) and not buildFactory then
    return
  end

  if isRepeat then
    return
  end

  if not buildFactory and keyFactories[key] then
    buildFactory = keyFactories[key]
    return true
  end

  if key < 47 or key > 57 or not buildFactory then
    return
  end

  buildCountString = buildCountString .. tostring(key - 48)
end

function widget:KeyRelease(key, mods, isRepeat)
  -- log('key release', key, 'mods', mods, 'isRepeat', isRepeat)
  if key == 294 then
    active = false
    exec()
    return true
  end
end
