function widget:GetInfo()
  return {
    name = "Commands",
    desc = "some commands for editing constructor build queue, and automatic geo toggling",
    author = "-",
    date = "dec, 2016",
    license = "GNU GPL, v3 or later",
    layer = 99,
    enabled = true
  }
end

-- todo add builder shortcuts

VFS.Include('luaui/Widgets/misc/helpers.lua')
VFS.Include('luaui/Headers/keysym.h.lua')

local myTeamId = Spring.GetMyTeamID()

local selectSplitKeys = {
  [KEYSYMS.Q] = 2,
  [KEYSYMS.W] = 3,
  [KEYSYMS.E] = 4,
}
local partitionIds = {}
local subsetPartition = 1
local selectedPos = {}


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

local selectPrios = {
  arm = {'armack', 'armaca', 'armacv', 'armca', 'armck', 'armcv', 'corca', 'legca', 'corck', 'legck', 'corcv',},
}

local function KeyUnits(key)
  key = (key == KEYSYMS.D and 'arm') or (key == KEYSYMS.S and 'cor') or 'leg'
  local builders = Spring.GetTeamUnitsByDefs (myTeamId,  key == 'arm' and UnitDefNames['armack'] or key == 'cor' and UnitDefNames['corack'] or UnitDefNames['legack'])

  if not builders or #builders == 0 then
    local builders = Spring.GetTeamUnitsByDefs (myTeamId,  key == 'arm' and UnitDefNames['armaca'] or key == 'cor' and UnitDefNames['coraca'] or UnitDefNames['legaca'])
  end

  if not builders or #builders == 0 then
    local builders = Spring.GetTeamUnitsByDefs (myTeamId,  key == 'arm' and UnitDefNames['armaca'] or key == 'cor' and UnitDefNames['coraca'] or UnitDefNames['legaca'])
  end

  return builders
end
local function median(temp)
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

local function SortBuildPowerDistance(a, b)
  -- Handle nil values more gracefully
  if a == nil then
    return false
  elseif b == nil then
    return true
  end

  -- Calculate squared distances to avoid unnecessary sqrt computation
  local aDistanceToSelected = (a[2][1] - selectedPos[1]) * (a[2][1] - selectedPos[1])
                            + (a[2][3] - selectedPos[2]) * (a[2][3] - selectedPos[2])

  local bDistanceToSelected = (b[2][1] - selectedPos[1]) * (b[2][1] - selectedPos[1])
                            + (b[2][3] - selectedPos[2]) * (b[2][3] - selectedPos[2])

  -- log('a buildPower ' .. (a.buildPower or 0) .. ' ' .. (b.buildPower or 0) .. ' ' .. aDistanceToSelected .. ' ' .. bDistanceToSelected)
  -- Sort by buildPower first, if equal then sort by distance
  if (a.buildPower or 0) > (b.buildPower or 0) then
    return true
  elseif (a.buildPower or 0) < (b.buildPower or 0) then
    return false
  else
    return aDistanceToSelected < bDistanceToSelected
  end
end

function widget:KeyPress(key, mods, isRepeat)
  -- if (key == 114 and mods['ctrl'] and mods['alt']) then
  --   widgetHandler:RemoveWidget()
  --   widgetHandler:
  --   return
  -- end
  local activeCommand = select(2, Spring.GetActiveCommand())
  if activeCommand ~= nil and activeCommand ~= 0 then
    return false
  end
  if (key == KEYSYMS.S or key == KEYSYMS.D) and mods['alt'] and not mods['shift'] and not mods['ctrl'] then -- 'd' shift from queue
    local selected_units = Spring.GetSelectedUnits()
    -- for i, unit_id in ipairs(selected_units) do
    for i = 1, #selected_units do
      local unit_id = selected_units[i]
      local cmd_queue = Spring.GetUnitCommands(unit_id, 100)
      if cmd_queue and #cmd_queue > 1 then
        if key == KEYSYMS.S then
          removeFirstCommand(unit_id)
        elseif key == KEYSYMS.D then
          removeLastCommand(unit_id)
        -- elseif key == KEYSYMS.A and #cmd_queue > 1 then
        --   reverseQueue(unit_id)
        end
        -- does not seem to stop when removing to an empty queue, therefore:
        if #cmd_queue == 2 then
          Spring.GiveOrderToUnit(unit_id, CMD.INSERT, { -1, CMD.STOP, CMD.OPT_SHIFT }, { "alt" })
        end
      end
    end
    if #selected_units == 0 then
      local builders = KeyUnits(key)
    end
  elseif selectSplitKeys[key] and mods['alt'] and not mods['shift'] and mods['ctrl'] then
    local selected_units = Spring.GetSelectedUnits()

    if #selected_units ~= #partitionIds then
      partitionIds = {}
    end

    for i = 1, #selected_units do
      partitionIds[selected_units[i]] = true
    end

    SelectSubset(selected_units, selectSplitKeys[key])

  elseif (key == KEYSYMS.F) and mods['alt'] and not mods['ctrl'] then
    local selectedUnits = Spring.GetSelectedUnits()
    local command_queue = Spring.GetUnitCommands(selectedUnits[1], 1000)
    local selectedUnitsMap = {}
    local xPositions = {}
    local zPositions = {}
    for i = 1, #selectedUnits do
      selectedUnitsMap[selectedUnits[i]] = true
      local x, _, z = Spring.GetUnitPosition(selectedUnits[i])
      table.insert(xPositions, x)
      table.insert(zPositions, z)
    end
    selectedPos = {median(xPositions), median(zPositions)}

    local commands = {}
    local nCommands = 0
    for i = 1, #command_queue do
      local command = command_queue[i]
      if command.id ~= 0 then
        -- log('adding', table.tostring(command_queue[i]), command_queue[i])
        nCommands = nCommands + 1
        commands[nCommands] = {command.id, {command.params[1], command.params[2], command.params[3]}, command.options, buildPower=0}
        commands[nCommands] = {command.id, command.params, command.options, buildPower=0}
        if command.params[1] then
          local adjacentBuilders = Spring.GetUnitsInCylinder(command.params[1], command.params[3], 1000, myTeamId)
          for j = 1, #adjacentBuilders do
            local unitId = adjacentBuilders[j]
            if not selectedUnitsMap[unitId] then
              commands[nCommands].buildPower = commands[nCommands].buildPower + UnitDefs[Spring.GetUnitDefID(unitId)].buildSpeed
            end
          end
        end
      end
    end
    for _, value in ipairs(commands) do
      -- value.buildPower = nil
      -- log(table.tostring(value))
      -- value[3] = {'shift'}
    end
    -- log(table.tostring(newCommands))
    if mods['shift'] then
      if nCommands > 0 then
        table.sort(commands, SortBuildPowerDistance)
      end

      local nSelectedUnits = #selectedUnits

      local nPartitions = (nCommands > nSelectedUnits) and nSelectedUnits or (nCommands / math.ceil(nCommands / nSelectedUnits))

      local partitionUnitCommands = {}

      for i = 1, nCommands do
        local partition = (i-1)%(nPartitions) + 1
        partitionUnitCommands[partition] = partitionUnitCommands[partition] or {}
        partitionUnitCommands[partition].commands = partitionUnitCommands[partition].commands or {}
        table.insert(partitionUnitCommands[partition].commands, commands[i])
      end

      -- log('partitionCommands',table.tostring(partitionUnitCommands))

      for i = 1, nSelectedUnits do
        -- local partition = (nCommands > nSelectedUnits) and ((i)%(nPartitions+1) ) or (i%nPartitions)
        -- nCommands > nSelectedUnits
        local partition =(i-1) % ( nPartitions) + 1
        -- log('unit partition',i, partition)
        partitionUnitCommands[partition].units = partitionUnitCommands[partition].units or {}
        table.insert(partitionUnitCommands[partition].units, selectedUnits[i])
      end

      -- log('partitionUnits',table.tostring(partitionUnitCommands))
      -- log('partitionUnits',table.tostring3(partitionUnitCommands))

      -- log('partition counts:')

      for i = 1, nPartitions do
        -- log('partition',i, partitionUnitCommands[i].commands and #partitionUnitCommands[i].commands, partitionUnitCommands[i].units and #partitionUnitCommands[i].units)
        Spring.GiveOrderToUnitArray(partitionUnitCommands[i].units, CMD.STOP, {}, {})
        Spring.GiveOrderArrayToUnitArray(partitionUnitCommands[i].units, partitionUnitCommands[i].commands)
      end


      -- for i = 1, #selected_units do
      --   Spring.GiveOrderToUnit(selected_units[i], CMD.STOP, {}, {})
      --   if #newCommands > 0 then
      --     -- Spring.GiveOrderToUnitArray(selected_units, newCommands[0])
      --     for j = 1, #newCommands do
      --       Spring.GiveOrderToUnit(selected_units[i], newCommands[j][1], newCommands[j][2], newCommands[j][3])
      --     end
      --   end
      -- end

    elseif mods['ctrl'] then

    else
      if nCommands > 0 then
        table.sort(commands, SortBuildPowerDistance)
      end
      Spring.GiveOrderToUnitArray(selectedUnits, CMD.STOP, {}, {})
      Spring.GiveOrderArrayToUnitArray(selectedUnits, commands)
    end
  end
end

function removeFirstCommand(unit_id)
  local cmd_queue = Spring.GetUnitCommands(unit_id, 4)
  if cmd_queue[2]['id'] == 70 then
    -- remove real command before empty one
    Spring.GiveOrderToUnit(unit_id, CMD.REMOVE, { cmd_queue[2].tag }, { nil })
  end
  Spring.GiveOrderToUnit(unit_id, CMD.REMOVE, { cmd_queue[1].tag }, { nil })
end

function removeLastCommand(unit_id)
  local cmd_queue = Spring.GetUnitCommands(unit_id, 5000)
  local remove_cmd = cmd_queue[#cmd_queue]
  -- empty commands are somehow put between cmds,
  -- but not by the "space/add to start of cmdqueue" widget
  if remove_cmd['id'] == 70 then
    -- remove real command before empty one
    Spring.GiveOrderToUnit(unit_id, CMD.REMOVE, { cmd_queue[#cmd_queue - 1].tag }, { nil })
  end
  -- remove the last command
  Spring.GiveOrderToUnit(unit_id, CMD.REMOVE, { cmd_queue[#cmd_queue].tag }, { nil })
end

-- function updateGeoDefs()
--   geos = {}
--   for _, unitId in ipairs(GetTeamUnits(Spring.GetMyTeamID())) do
--     local unitDefId = Spring.GetUnitDefID(unitId)
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
--   Spring.GiveOrderToUnitMap(geos, CMD.ONOFF, { geos_on and 1 or 0 }, {} )
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
  return UnitDefs[Spring.GetUnitDefID(unitId)]
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
  Spring.GiveOrderToUnit(unit_id, CMD.INSERT, { -1, CMD.STOP, CMD.OPT_SHIFT }, { "alt" })
  --  local build_queue = Spring.GetRealBuildQueue(unit_id)

  -- log(table.tostring(queue))
  if queue then
    -- rm queue
    for k, v in ipairs(queue) do --  in order
      --    Spring.GiveOrderToUnit(unit_id, CMD.INSERT, { -1, CMD.STOP, CMD.OPT_SHIFT }, { "alt" })
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
