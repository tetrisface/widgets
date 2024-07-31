function widget:GetInfo()
  return {
    desc    = "",
    author  = "tetrisface",
    version = "",
    date    = "May, 2024",
    name    = "Auto Unit Settings",
    license = "",
    layer   = -99990,
    enabled = true,
  }
end

VFS.Include('luaui/Widgets/misc/helpers.lua')

local isCommanderRepeatChecked = false
local myTeamId = Spring.GetMyTeamID()
local isFactoryDefIds = {}
local canResurrectDefIds = {}
local resurrectorDefIds = {}
local areaReclaimParams = {}
local waitReclaimUnits = {}
local vehicleCons = {
  [UnitDefNames['legacv'].id] = true,
  [UnitDefNames['armcv'].id] = true,
  [UnitDefNames['coracv'].id] = true,
}

function widget:Initialize()
  isCommanderRepeatChecked = false
  myTeamId = Spring.GetMyTeamID()
  isFactoryDefIds = {}
  canResurrectDefIds = {}
  resurrectorDefIds = {}
  areaReclaimParams = {}
  waitReclaimUnits = {}

  if Spring.GetSpectatingState() or Spring.IsReplay() then
    widgetHandler:RemoveWidget()
  end

  for unitDefID, unitDef in pairs(UnitDefs) do
    if unitDef.isFactory then
      isFactoryDefIds[unitDefID] = true
    end

    if unitDef.canResurrect and not (unitDef.customParams and unitDef.customParams.iscommander) then
      canResurrectDefIds[unitDefID] = true
      table.insert(resurrectorDefIds, unitDefID)
    end
  end
end

local function UnitIdDef(unitId)
  return UnitDefs[Spring.GetUnitDefID(unitId)]
end

function widget:UnitCreated(unitID, unitDefID, unitTeam)
  if unitTeam ~= myTeamId then
    return
  end


  if isFactoryDefIds[unitDefID] then
    local cmdTable = {
      { CMD.MOVE_STATE, { 0 }, {} },
      { CMD.REPEAT,     { 0 }, {} },
    }

    local def = UnitIdDef(unitID)
    if def.translatedHumanName:lower():find('aircraft', 1, true) then
      table.insert(cmdTable, { CMD.FIRE_STATE, { 0 }, {} })
    end

    Spring.GiveOrderArrayToUnitArray({ unitID }, cmdTable)
  elseif canResurrectDefIds[unitDefID] and #areaReclaimParams > 0 then
    Spring.GiveOrderToUnit(unitID, CMD.REPEAT, { 1 }, 0)
    waitReclaimUnits[unitID] = true
  -- elseif vehicleCons[unitDefID] then
  --   Spring.GiveOrderToUnit(unitID, CMD.REPEAT, { 1 }, 0)
  end
end

function widget:UnitGiven(unitID, unitDefID, unitTeam, oldTeam)
  widget:UnitCreated(unitID, unitDefID, unitTeam)
end

function widget:UnitTaken(unitID, unitDefID, unitTeam, oldTeam)
  widget:UnitCreated(unitID, unitDefID, unitTeam)
end

function widget:GameFrame(gameFrame)
  if gameFrame >= 100 and not isCommanderRepeatChecked then
    -- set commander repeat on
    local units = Spring.GetTeamUnits(myTeamId)
    for i = 1, #units do
      local unitID = units[i]
      if unitID and UnitIdDef(unitID).customParams and UnitIdDef(unitID).customParams.iscommander then
        -- Spring.GiveOrderToUnit(unitID, CMD.REPEAT, { 1 }, 0)
      end
    end
    isCommanderRepeatChecked = true
  end

  if gameFrame % 30 == 0 then
    if #areaReclaimParams > 1 then
      for unitId, _ in pairs(waitReclaimUnits) do
        if select(5, Spring.GetUnitHealth(unitId)) == 1 then
          Spring.GiveOrderToUnit(unitId, CMD.STOP, {}, 0)
          Spring.GiveOrderToUnit(unitId, CMD.RECLAIM, areaReclaimParams, {})
          waitReclaimUnits[unitId] = nil
        end
      end

      local idleResurrectors = Spring.GetTeamUnitsByDefs(myTeamId, resurrectorDefIds)
      for i = 1, #idleResurrectors do
        local unitId = idleResurrectors[i]
        local commands = Spring.GetUnitCommands(unitId, 2)
        if #commands == 0 or (#commands == 1 and commands[1].id == CMD.MOVE and select(4, Spring.GetUnitVelocity(unitId)) < 0.1) then
          Spring.GiveOrderToUnit(unitId, CMD.REPEAT, { 1 }, 0)
          Spring.GiveOrderToUnit(unitId, CMD.RECLAIM, areaReclaimParams, {})
        end
      end
    end
  end
end

function widget:KeyPress(key, mods, isRepeat)
  if key == 101 and mods['alt'] then
    local selectedUnitIds = Spring.GetSelectedUnits()
    if not selectedUnitIds or #selectedUnitIds == 0 then
      areaReclaimParams = {}
      return
    end

    local unitId = selectedUnitIds[1]
    local commands = Spring.GetUnitCommands(unitId, 20)
    for i = 1, #commands do
      local cmd = commands[i]
      if cmd.id == CMD.RECLAIM and #cmd.params == 4 then
        areaReclaimParams = cmd.params
      end
    end
  end
end
