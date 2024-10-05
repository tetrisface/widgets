  if Spring.GetSpectatingState() or Spring.IsReplay() then
    return {}
  end
  function widget:GetInfo()
  return {
    name    = "CMD target time spread",
    desc    = "",
    author  = "tetrisface",
    version = "",
    date    = "feb, 2024",
    license = "",
    layer   = -99990,
    enabled = true,
  }
end

local NewSetList = VFS.Include('common/SetList.lua').NewSetList
VFS.Include('luaui/Widgets/misc/helpers.lua')
VFS.Include('luaui/Headers/keysym.h.lua')


-- dont wait if has queued stuff and leaking
-- local cmdQueue = GetUnitCommands(builderId, 3)
-- if cmdQueue and #cmdQueue > 0 and cmdQueue[1].id == 5 and (isMetalLeaking or isEnergyLeaking) then
--   GiveOrderToUnit(builderId, CMD.REMOVE, { nil }, { "ctrl" })
-- end
local reloadWaitUnits = {}
local hardcoded = {}

local antis = {
  [UnitDefNames['armamd'].id] = true,
  [UnitDefNames['armscab'].id] = true,
  [UnitDefNames['corfmd'].id] = true,
  [UnitDefNames['cormabm'].id] = true,
}

function widget:KeyPress(key, mods, isRepeat)
  if key == KEYSYMS.Q and mods['alt'] and not mods['shift'] and not mods['ctrl'] then -- q
    local units = Spring.GetSelectedUnits()
    local nUnits = #units
    if nUnits < 1 then
      return
    end
    local unitDefId = Spring.GetUnitDefID(units[1])
    local isStockpiling
    local maxReloadTime = 0
    local maxReloadWeaponNumber = -1
    if hardcoded[unitDefId] then
      maxReloadTime = hardcoded[unitDefId]
      isStockpiling = true
    else
    local weapons = UnitDefs[unitDefId].weapons
    isStockpiling = Spring.GetUnitStockpile(units[1]) ~= nil
      for i = 1, #weapons do
        local weaponDef = WeaponDefs[weapons[i].weaponDef]
        -- local weaponReloadTime = weaponDef.stockpileTime * (weaponDef.reload == 2 and 1 or 10)
        local weaponReloadTime = isStockpiling and (weaponDef.stockpileTime + (weaponDef.weaponTimer or 0))/30 or weaponDef.reloadTime
        if weaponReloadTime > maxReloadTime then
          maxReloadTime = weaponReloadTime
          maxReloadWeaponNumber = i
        end
      end
    end

    local interval = maxReloadTime / nUnits
    -- log('maxReloadTime', maxReloadTime, 'nUnits', nUnits, 'interval', interval)
    local newReloadWaitUnits = {}
    local nNewReloadWaitUnits = 0
    for i = 1, nUnits do
      local unitId = units[i]

      Spring.GiveOrderToUnit(unitId, CMD.REPEAT, { 1 }, 0)

      local reloadTimeLeft = maxReloadTime
      if isStockpiling then
        local _, _, reloadPercent = Spring.GetUnitStockpile(units[i])
        reloadTimeLeft = (1 - reloadPercent) * maxReloadTime
      end
      nNewReloadWaitUnits = nNewReloadWaitUnits + 1
      newReloadWaitUnits[nNewReloadWaitUnits] = {
        reloadTimeLeft = reloadTimeLeft,
        unitId = unitId,
      }
    end

    table.sort(newReloadWaitUnits, function(a, b)
      return a.reloadTimeLeft < b.reloadTimeLeft
    end)

    local reloadWaitUnit
    local maxWait = 0
    local gameFrameSecond = Spring.GetGameFrame()/30
    for i = 1, #newReloadWaitUnits do
      reloadWaitUnit = newReloadWaitUnits[i]
      reloadWaitUnit.attackAtTime = interval * (i - 1) + gameFrameSecond
      maxWait = math.max(maxWait, gameFrameSecond + reloadWaitUnit.reloadTimeLeft - reloadWaitUnit.attackAtTime)
      -- log('maxWait', maxWait, 'rel left', reloadWaitUnit.reloadTimeLeft, 'attack at', reloadWaitUnit.attackAtTime, 'gf', gameFrameSecond, 'interval', interval)
    end

    local nReloadWaitUnits = #reloadWaitUnits
    for i = 1, #newReloadWaitUnits do
      reloadWaitUnit = newReloadWaitUnits[i]
      local shouldBe2, isUserTarget, pos = Spring.GetUnitWeaponTarget(reloadWaitUnit.unitId, maxReloadWeaponNumber)
      if pos and #pos == 3 then
        local cmdQueue = Spring.GetUnitCommands(reloadWaitUnit.unitId, 1)
        local cmd = cmdQueue and cmdQueue[1]
        if cmd then
          Spring.GiveOrderToUnit(reloadWaitUnit.unitId, CMD.REMOVE, { cmd.tag }, { "ctrl" })
        end
        reloadWaitUnit.attackAtTime = reloadWaitUnit.attackAtTime + maxWait
        reloadWaitUnit.attackAtPos = pos
        reloadWaitUnit.isUserTarget = isUserTarget
        nReloadWaitUnits = nReloadWaitUnits + 1
        reloadWaitUnits[nReloadWaitUnits] = reloadWaitUnit
      end
    end
  end
end

local myTeamId = Spring.GetMyTeamID()

local function RegisterUnit(unitId, unitDefId, unitTeam)
  if unitTeam ~= myTeamId then
    return
  end

  local def = UnitDefs[unitDefId]

  if def.canStockpile then
    Spring.GiveOrderToUnit(unitId, CMD.REPEAT, { 1 }, 0)
    Spring.GiveOrderToUnit(unitId, CMD.STOCKPILE, {}, { "ctrl", "shift", "right" })
    Spring.GiveOrderToUnit(unitId, CMD.STOCKPILE, {}, 0)
    if (def.customparams and def.customparams.unitgroup == 'antinuke') or antis[unitDefId] then
      Spring.GiveOrderToUnit(unitId, CMD.STOCKPILE, {}, CMD.OPT_SHIFT)
      Spring.GiveOrderToUnit(unitId, CMD.STOCKPILE, {}, 0)
    end
  end
end

function widget:UnitCreated(unitId, unitDefId, unitTeam)
  RegisterUnit(unitId, unitDefId, unitTeam)
end

function widget:UnitGiven(unitId, unitDefId, unitTeam, oldTeam)
  RegisterUnit(unitId, unitDefId, unitTeam)
end

function widget:GameFrame(n)
  local nReloadWaitUnits = #reloadWaitUnits
  if nReloadWaitUnits == 0 then
    return
  end
  local removeUntil = 0
  local gameFrameSecond = n / 30
  for i = 1, nReloadWaitUnits do
    local reloadWaitUnit = reloadWaitUnits[i]
    if reloadWaitUnit.attackAtTime <= gameFrameSecond then
      Spring.GiveOrderToUnit(reloadWaitUnit.unitId, CMD.ATTACK, reloadWaitUnit.attackAtPos, 0)
      Spring.GiveOrderToUnit(reloadWaitUnit.unitId, CMD.STOCKPILE, {}, 0)
      removeUntil = i
    else
      local stockpile, queued = Spring.GetUnitStockpile(reloadWaitUnit.unitId)
      if stockpile and queued and stockpile > 0 and queued > 0 then
        Spring.GiveOrderToUnit(reloadWaitUnit.unitId, CMD.STOCKPILE, {}, { "ctrl", "shift", "right" })
      end
    end
  end
  for i = 1, removeUntil do
    table.remove(reloadWaitUnits, 1)
  end
end
