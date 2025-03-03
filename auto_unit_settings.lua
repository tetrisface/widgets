function widget:GetInfo()
  return {
    desc = '',
    author = 'tetrisface',
    version = '',
    date = 'May, 2024',
    name = 'Auto Unit Settings',
    license = '',
    layer = -99990,
    enabled = true
  }
end

VFS.Include('luaui/Widgets/misc/helpers.lua')
VFS.Include('luaui/Headers/keysym.h.lua')

local antis = {
  [UnitDefNames['armamd'].id] = true,
  [UnitDefNames['armscab'].id] = true,
  [UnitDefNames['corfmd'].id] = true,
  [UnitDefNames['cormabm'].id] = true
}
if UnitDefNames['legabm'] then
  antis[UnitDefNames['legabm'].id] = true
end
local lraa = {
  [UnitDefNames['corscreamer'].id] = true,
  [UnitDefNames['armmercury'].id] = true
}

local myTeamId = Spring.GetMyTeamID()
local isFactoryDefIds = {}
local reclaimerDefIds = {}
local resurrectorDefIds = {}
local areaReclaimParams = {}
local waitReclaimUnits = {}

local function isFriendlyFiringDef(def)
  return not (def.name == 'armthor' or def.name == 'armassimilator' or def.name:find 'corkarganeth' or
    def.name:find 'legpede' or
    def.name:find 'legkeres')
end

local function isReclaimerUnit(def)
  local isReclaimer =
    (def.canResurrect or def.canReclaim) and
    not (def.name:match '^armcom.*' or def.name:match '^corcom.*' or def.name:match '^legcom.*' or def.name == 'armthor' or
      (def.customParams and def.customParams.iscommander)) and
    not (def.buildOptions and def.buildOptions[1] ~= nil)

  -- if isReclaimer then
  --   log(
  --     def.translatedHumanName,
  --     'reclaimer',
  --     isReclaimer,
  --     not (def.buildOptions and #def.buildOptions > 0),
  --     def.buildOptions
  --   )
  -- end
  return isReclaimer
end

function widget:Initialize()
  myTeamId = Spring.GetMyTeamID()
  isFactoryDefIds = {}
  reclaimerDefIds = {}
  resurrectorDefIds = {}
  areaReclaimParams = {}
  waitReclaimUnits = {}

  if Spring.GetSpectatingState() or Spring.IsReplay() then
    widgetHandler:RemoveWidget()
  end

  for unitDefID, unitDef in pairs(UnitDefs) do
    if
      unitDef.isFactory and
        not (unitDef.name:match '^armcom.*' or unitDef.name:match '^corcom.*' or unitDef.name:match '^legcom.*')
     then
      isFactoryDefIds[unitDefID] = true
    -- log('add factory: ', unitDef.translatedHumanName)
    end

    if isReclaimerUnit(unitDef) then
      reclaimerDefIds[unitDefID] = true
      table.insert(resurrectorDefIds, unitDefID)
    -- log('add ressurector: ', unitDef.translatedHumanName)
    end
  end
end

function widget:UnitFromFactory(unitID, unitDefID, unitTeam)
  widget:UnitFinished(unitID, unitDefID, unitTeam)
end

function widget:UnitFinished(unitID, unitDefID, unitTeam)
  if unitTeam ~= myTeamId then
    return
  end

  local def = UnitDefs[unitDefID]

  if not isFriendlyFiringDef(def) then
    Spring.GiveOrderToUnit(unitID, CMD.FIRE_STATE, {2}, 0)
    Spring.GiveOrderToUnit(unitID, CMD.REPEAT, {0}, 0)
  end
end

function widget:UnitCreated(unitID, unitDefID, unitTeam)
  if unitTeam ~= myTeamId then
    return
  end

  -- log('created', UnitIdUnitDef(unitID).translatedHumanName, unitID)

  local def = UnitDefs[unitDefID]

  -- evocom + thor fix
  if def.name == 'armthor' or def.name:find '^armcom.*' or def.name:find '^corcom.*' or def.name:find '^legcom.*' then
    Spring.GiveOrderToUnit(unitID, CMD.REPEAT, {0}, 0)
    return
  end
  if not isFriendlyFiringDef(def) then
    Spring.GiveOrderToUnit(unitID, CMD.FIRE_STATE, {2}, 0)
  end

  if isFactoryDefIds[unitDefID] then
    local cmdTable = {
      {CMD.MOVE_STATE, {0}, {}},
      {CMD.REPEAT, {0}, {}}
    }

    if
      (def.translatedHumanName:lower():find('aircraft', 1, true) or
        def.translatedHumanName:lower():find('gantry', 1, true) or
        def.translatedHumanName:lower():find('experimental', 1, true)) and
        not def.name == 'corapt3'
     then
      table.insert(cmdTable, {CMD.FIRE_STATE, {0}, {}})
    -- log('adding aircraft factory: ', def.translatedHumanName)
    end
    -- log('Repeating 1', def.translatedHumanName)
    Spring.GiveOrderArrayToUnitArray({unitID}, cmdTable)
  elseif reclaimerDefIds[unitDefID] and #areaReclaimParams > 0 and isReclaimerUnit(def) then
    -- log('setting repeat', def.translatedHumanName)
    -- log('Repeating 2', def.translatedHumanName)
    Spring.GiveOrderToUnit(unitID, CMD.REPEAT, {1}, 0)
    waitReclaimUnits[unitID] = 1
  -- elseif vehicleCons[unitDefID] then
  --   Spring.GiveOrderToUnit(unitID, CMD.REPEAT, { 1 }, 0)
  end

  if def.canStockpile and not lraa[unitDefId] and def.isBuilding and unitID ~= nil and type(unitID) == 'number' then
    Spring.GiveOrderToUnit(unitID, CMD.REPEAT, { 1 }, 0)
    Spring.GiveOrderToUnit(unitID, CMD.STOCKPILE, {}, { 'ctrl', 'shift', 'right' })
    Spring.GiveOrderToUnit(unitID, CMD.STOCKPILE, {}, 0)
    if (def.customparams and def.customparams.unitgroup == 'antinuke') or antis[unitDefId] then
      Spring.GiveOrderToUnit(unitID, CMD.STOCKPILE, {}, CMD.OPT_SHIFT)
      Spring.GiveOrderToUnit(unitID, CMD.STOCKPILE, {}, 0)
    end
  end
end

function widget:UnitGiven(unitID, unitDefID, unitTeam, oldTeam)
  widget:UnitCreated(unitID, unitDefID, unitTeam)
end

function widget:UnitTaken(unitID, unitDefID, unitTeam, oldTeam)
  widget:UnitCreated(unitID, unitDefID, unitTeam)
end

function widget:GameFrame(gameFrame)
  -- if gameFrame >= 100 and not isCommanderRepeatChecked then
  -- set commander repeat on
  -- local units = Spring.GetTeamUnits(myTeamId)
  -- for i = 1, #units do
  -- local unitID = units[i]
  -- if unitID and UnitIdDef(unitID).customParams and UnitIdDef(unitID).customParams.iscommander then
  -- Spring.GiveOrderToUnit(unitID, CMD.REPEAT, { 1 }, 0)
  -- end
  -- end
  -- isCommanderRepeatChecked = true
  -- end

  if gameFrame % 30 == 0 then
    if #areaReclaimParams > 1 then
      for unitId, _ in pairs(waitReclaimUnits) do
        if waitReclaimUnits[unitId] ~= 1 then
          -- log('waiting', unitId)
          waitReclaimUnits[unitId] = 2
        else
          if select(5, Spring.GetUnitHealth(unitId)) == 1 then
            Spring.GiveOrderToUnit(unitId, CMD.STOP, {}, 0)
            Spring.GiveOrderToUnit(unitId, CMD.RECLAIM, areaReclaimParams, {}, 0)
            waitReclaimUnits[unitId] = nil
          -- log('Repeating 3', UnitIdUnitDef(unitId).translatedHumanName)
          end
        end
      end

      local idleResurrectors = Spring.GetTeamUnitsByDefs(myTeamId, resurrectorDefIds)
      for i = 1, #idleResurrectors do
        local unitId = idleResurrectors[i]
        local commands = Spring.GetUnitCommands(unitId, 2)
        if
          isReclaimerUnit(UnitDefs[Spring.GetUnitDefID(unitId)]) and
            (#commands == 0 or
              (#commands == 1 and commands[1].id == CMD.MOVE and select(4, Spring.GetUnitVelocity(unitId)) < 0.02))
         then
          -- log('Repeating 4', UnitIdUnitDef(unitId).translatedHumanName)
          Spring.GiveOrderToUnit(unitId, CMD.REPEAT, {1}, 0)
          Spring.GiveOrderToUnit(unitId, CMD.RECLAIM, areaReclaimParams, {})
        -- log('ordering reclaim idle', unitId, areaReclaimParams[1], areaReclaimParams[2], areaReclaimParams[3], areaReclaimParams[4])
        end
      end
    end
  end
end

function widget:KeyPress(key, mods, isRepeat)
  if key == KEYSYMS.E and mods['alt'] and not mods['shift'] and not mods['ctrl'] then
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
