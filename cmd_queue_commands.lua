function widget:GetInfo()
  return {
    name = "CMD Queue Commands",
    desc = "some commands for editing constructor build queue, and automatic geo toggling",
    author = "-",
    date = "dec, 2016",
    license = "GNU GPL, v3 or later",
    layer = 99,
    enabled = true
  }
end

-- TODO DOESNT WORK QUEUE CMDS ON FLYING

VFS.Include('luaui/Widgets/misc/helpers.lua')
VFS.Include('luaui/Headers/keysym.h.lua')

local GetSelectedUnits = Spring.GetSelectedUnits
local GetUnitCommands = Spring.GetUnitCommands
local GetUnitDefID = Spring.GetUnitDefID

local GiveOrderToUnit = Spring.GiveOrderToUnit

local selectSplitKeys = {
  [KEYSYMS.Q] = 2,
  [KEYSYMS.W] = 3,
  [KEYSYMS.E] = 4,
}
local partitionIds = {}
local subsetPartition = 1


function widget:Initialize()
  if Spring.GetSpectatingState() or Spring.IsReplay() then
    widgetHandler:RemoveWidget()
  end
end

local function SelectSubset(selected_units, nPartitions)

  if not nPartitions or not selected_units or #selected_units == 0 then
    return
  end

  selected_units = sort(selected_units)

  local nUnits = #selected_units
  local nUnitsPerPartition = math.ceil(nUnits / nPartitions)



end

function widget:KeyPress(key, mods, isRepeat)
  -- if (key == 114 and mods['ctrl'] and mods['alt']) then
  --   widgetHandler:RemoveWidget()
  --   widgetHandler:
  --   return
  -- end
  if (key == KEYSYMS.S or key == KEYSYMS.D) and mods['alt'] and not mods['shift'] and not mods['ctrl'] then -- 'd' shift from queue
    local selected_units = GetSelectedUnits()
    -- for i, unit_id in ipairs(selected_units) do
    for i = 1, #selected_units do
      local unit_id = selected_units[i]
      local cmd_queue = GetUnitCommands(unit_id, 100)
      if cmd_queue and #cmd_queue > 1 then
        if key == 115 then                       -- s
          removeFirstCommand(unit_id)
        elseif key == 100 then                   -- d
          removeLastCommand(unit_id)
        elseif key == 97 and #cmd_queue > 1 then -- a
          reverseQueue(unit_id)
        end
        -- does not seem to stop when removing to an empty queue, therefore:
        if #cmd_queue == 2 then
          GiveOrderToUnit(unit_id, CMD.INSERT, { -1, CMD.STOP, CMD.OPT_SHIFT }, { "alt" })
        end
      end
    end
  elseif selectSplitKeys[key] and mods['alt'] and not mods['shift'] and mods['ctrl'] then
    local selected_units = GetSelectedUnits()

    if #selected_units ~= #partitionIds then
      partitionIds = {}
    end

    for i = 1, #selected_units do
      partitionIds[selected_units[i]] = true
    end

    SelectSubset(selected_units, selectSplitKeys[key])
  end
end

function removeFirstCommand(unit_id)
  local cmd_queue = GetUnitCommands(unit_id, 4)
  if cmd_queue[2]['id'] == 70 then
    -- remove real command before empty one
    GiveOrderToUnit(unit_id, CMD.REMOVE, { cmd_queue[2].tag }, { nil })
  end
  GiveOrderToUnit(unit_id, CMD.REMOVE, { cmd_queue[1].tag }, { nil })
end

function removeLastCommand(unit_id)
  local cmd_queue = GetUnitCommands(unit_id, 5000)
  local remove_cmd = cmd_queue[#cmd_queue]
  -- empty commands are somehow put between cmds,
  -- but not by the "space/add to start of cmdqueue" widget
  if remove_cmd['id'] == 70 then
    -- remove real command before empty one
    GiveOrderToUnit(unit_id, CMD.REMOVE, { cmd_queue[#cmd_queue - 1].tag }, { nil })
  end
  -- remove the last command
  GiveOrderToUnit(unit_id, CMD.REMOVE, { cmd_queue[#cmd_queue].tag }, { nil })
end

-- function updateGeoDefs()
--   geos = {}
--   for _, unitId in ipairs(GetTeamUnits(Spring.GetMyTeamID())) do
--     local unitDefId = GetUnitDefID(unitId)
--     local udef = unitDef(unitId)
--     if udef.name:find('geo') or udef.humanName:find('[Gg]eo') or udef.humanName:match('Resource Fac') then

--       local m = udef.makesMetal - udef.metalUpkeep
--       local e = udef.energyUpkeep
--       local eff = m/e
--       geos[unitId] = {m, e, eff, true}
--     end
--   end
--   table.sort(geos, function(a,b) return a[2] < b[2] end)
-- end

-- local function setGeos()
--   updateGeoDefs()
--   GiveOrderToUnitMap(geos, CMD.ONOFF, { geos_on and 1 or 0 }, {} )
-- end

-- function widget:GameFrame(n)
--   if n % mainIterationModuloLimit == 0 then
--     local mm_level = GetTeamRulesParam(myTeamId, 'mmLevel')
--     local e_curr, e_max, e_pull, e_inc, e_exp = GetTeamResources(myTeamId, 'energy')
--     local energyLevel = e_curr/e_max
--     local isPositiveEnergyDerivative = e_inc > (e_pull+e_exp)/2

--     table.insert(regularizedResourceDerivativesEnergy, 1, isPositiveEnergyDerivative)
--     if #regularizedResourceDerivativesEnergy > 7 then
--       table.remove(regularizedResourceDerivativesEnergy)
--     end

--     regularizedPositiveEnergy = table.full_of(regularizedResourceDerivativesEnergy, true)
--     regularizedNegativeEnergy = table.full_of(regularizedResourceDerivativesEnergy, false)

--     if not geos_on and regularizedPositiveEnergy and energyLevel > mm_level then
--       geos_on = true
--       setGeos()
--     elseif geos_on and energyLevel < mm_level then
--       geos_on = false
--       setGeos()
--     end
--   end
-- end


function unitDef(unitId)
  return UnitDefs[GetUnitDefID(unitId)]
end

-- TODO
function reverseQueue(unit_id)
  --  local states = Spring.GetUnitStates(targetID)

  --  if (states ~= nil) then
  --    Spring.GiveOrderToUnit(unitID, CMD.FIRE_STATE, { states.firestate }, 0)
  --    Spring.GiveOrderToUnit(unitID, CMD.MOVE_STATE, { states.movestate }, 0)
  --    Spring.GiveOrderToUnit(unitID, CMD.REPEAT,     { states['repeat']  and 1 or 0 }, 0)
  --    Spring.GiveOrderToUnit(unitID, CMD.ONOFF,      { states.active     and 1 or 0 }, 0)
  --    Spring.GiveOrderToUnit(unitID, CMD.CLOAK,      { states.cloak      and 1 or 0 }, 0)
  --    Spring.GiveOrderToUnit(unitID, CMD.TRAJECTORY, { states.trajectory and 1 or 0 }, 0)
  --  end

  local queue = Spring.GetCommandQueue(unit_id, 10000);
  GiveOrderToUnit(unit_id, CMD.INSERT, { -1, CMD.STOP, CMD.OPT_SHIFT }, { "alt" })
  --  local build_queue = Spring.GetRealBuildQueue(unit_id)

  -- log(table.tostring(queue))
  if queue then
    -- rm queue
    for k, v in ipairs(queue) do --  in order
      --    GiveOrderToUnit(unit_id, CMD.INSERT, { -1, CMD.STOP, CMD.OPT_SHIFT }, { "alt" })
    end

    --    for int k,v in ipairs(queue) do  --  in order
    --    for k,v in ipairs(queue) do  --  in order
    for i = #queue, 1, -1 do
      local v = queue[i]
      local options = v.options
      if not options.internal then
        local new_options = {}
        if (options.alt) then table.insert(new_options, "alt") end
        if (options.ctrl) then table.insert(new_options, "ctrl") end
        if (options.right) then table.insert(new_options, "right") end
        table.insert(new_options, "shift")
        --        Spring.GiveOrderToUnit(unit_id, v.id, v.params, options.coded)
        --         log(v.id)
        --         log(v.params)
        -- --        table.insert(v.params, 1, 0)
        --         log(v.params)
        --         log(options.coded)
        Spring.GiveOrderToUnit(unit_id, v.id, -1, v.params, options.coded)
      end
    end
  end

  if (build_queue ~= nil) then
    for udid, buildPair in ipairs(build_queue) do
      local udid, count = next(buildPair, nil)
      Spring.AddBuildOrders(unit_id, udid, count)
    end
  end
end
