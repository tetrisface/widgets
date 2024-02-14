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
VFS.Include('luaui/Widgets/helpers.lua')


-- dont wait if has queued stuff and leaking
-- local cmdQueue = GetUnitCommands(builderId, 3)
-- if cmdQueue and #cmdQueue > 0 and cmdQueue[1].id == 5 and (isMetalLeaking or isEnergyLeaking) then
--   GiveOrderToUnit(builderId, CMD.REMOVE, { nil }, { "ctrl" })
-- end
local reloadWaitUnits = {}

function widget:KeyPress(key, mods, isRepeat)
  if key == 113 and mods['alt'] then -- q
    local units = Spring.GetSelectedUnits()
    local nUnits = #units
    if nUnits == 0 then
      return
    end

    local weapons = UnitDefs[Spring.GetUnitDefID(units[1])].weapons
    local isStockpiling = Spring.GetUnitStockpile(units[1]) ~= nil
    local maxReloadTime = 0
    local maxReloadWeaponNumber = -1
    for i = 1, #weapons do
      local weaponDef = WeaponDefs[weapons[i].weaponDef]
      local weaponReloadTime = weaponDef.stockpileTime or weaponDef.reloadTime
      if weaponReloadTime > maxReloadTime then
        maxReloadTime = weaponReloadTime
        maxReloadWeaponNumber = i
      end
    end

    local interval = maxReloadTime / nUnits

    local newReloadWaitUnits = {}
    local nNewReloadWaitUnits = 0
    for i = 1, nUnits do
      local unitId = units[i]

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
    local gameFrame = Spring.GetGameFrame()
    for i = 1, #newReloadWaitUnits do
      reloadWaitUnit = newReloadWaitUnits[i]
      reloadWaitUnit.attackAtTime = interval * (i - 1) + gameFrame
      maxWait = math.max(maxWait, gameFrame + reloadWaitUnit.reloadTimeLeft - reloadWaitUnit.attackAtTime)
      log('maxWait', maxWait)
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
local armjuno = UnitDefNames['armjuno'].id
local corjuno = UnitDefNames['corjuno'].id
local function RegisterUnit(unitId, unitDefId, unitTeam)
  if unitTeam ~= myTeamId then
    return
  end
  if unitDefId == armjuno or unitDefId == corjuno then
    Spring.GiveOrderToUnit(unitId, CMD.STOCKPILE, {}, { "ctrl", "shift", "right" })
    Spring.GiveOrderToUnit(unitId, CMD.STOCKPILE, {}, 0)
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
  for i = 1, nReloadWaitUnits do
    local reloadWaitUnit = reloadWaitUnits[i]
    if reloadWaitUnit.attackAtTime <= Spring.GetGameFrame() then
      Spring.GiveOrderToUnit(reloadWaitUnit.unitId, CMD.REPEAT, { 1 }, 0)
      Spring.GiveOrderToUnit(reloadWaitUnit.unitId, CMD.ATTACK, reloadWaitUnit.attackAtPos, 0)
      Spring.GiveOrderToUnit(reloadWaitUnit.unitId, CMD.STOCKPILE, {}, 0)
      removeUntil = i
    else
      local stockpile, queued = Spring.GetUnitStockpile(reloadWaitUnit.unitId)
      if stockpile > 0 and queued > 0 then
        Spring.GiveOrderToUnit(reloadWaitUnit.unitId, CMD.STOCKPILE, {}, { "ctrl", "shift", "right" })
      end
    end
  end
  for i = 1, removeUntil do
    table.remove(reloadWaitUnits, 1)
  end
end
