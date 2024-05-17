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

VFS.Include('luaui/Widgets/helpers.lua')

local isFactoryDefId = {}
local isCommanderRepeatChecked = false

local myTeamId = Spring.GetMyTeamID()

local function UnitIdDef(unitId)
  return UnitDefs[Spring.GetUnitDefID(unitId)]
end

function widget:Initialize()
  isCommanderRepeatChecked = false
  myTeamId = Spring.GetMyTeamID()
  if Spring.GetSpectatingState() or Spring.IsReplay() then
    widgetHandler:RemoveWidget()
  end

  for unitDefID, unitDef in pairs(UnitDefs) do
    if unitDef.isFactory then
      isFactoryDefId[unitDefID] = true
    end
  end
end

function widget:UnitCreated(unitID, unitDefID, unitTeam)
  if unitTeam ~= myTeamId then
    return
  end
  if isFactoryDefId[unitDefID] then
    Spring.GiveOrderArrayToUnitArray({ unitID }, {
      { CMD.FIRE_STATE, { 0 }, {} },
      { CMD.MOVE_STATE, { 0 }, {} },
      { CMD.REPEAT,     { 0 }, {} },
    })
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
        Spring.GiveOrderToUnit(unitID, CMD.REPEAT, { 1 }, 0)
      end
    end
    isCommanderRepeatChecked = true
  end
end
