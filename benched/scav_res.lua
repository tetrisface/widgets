function widget:GetInfo()
  return {
    name    = "Scavenger Resource Generator",
    desc    = "",
    author  = "tetrisface",
    version = "",
    date    = "jul, 2024",
    license = "",
    layer   = -99990,
    enabled = true,
  }
end
if not (Spring.Utilities.Gametype.IsScavengers() or Spring.Utilities.Gametype.IsRaptors()) or Spring.GetModOptions().unit_restrictions_noair then
  return false
end

VFS.Include('luaui/Widgets/misc/helpers.lua')

local transportTiers = {}
for unitDefName, tier in pairs({armatlas_scav = 1, corvalk_scav = 1, legatrans_scav = 1, armdfly_scav = 2, corseah_scav = 2, legstronghold_scav = 2}) do
  if UnitDefNames[unitDefName] then
    transportTiers[UnitDefNames[unitDefName].id] = tier
  end
end

for unitDefID, unitDef in pairs(UnitDefs) do
  if unitDef.isTransport and not transportTiers[unitDefID] then
    transportTiers[unitDef.name] = tonumber(unitDef.customparams.techlevel)
  end
end

log('transports', table.tostring(transportTiers))

local lootboxTiers = {}

for unitDefName, tier in pairs({lootboxbronze_scav = 1, lootboxsilver_scav  = 1, lootboxgold_scav = 2, lootboxplatinum_scav = 2}) do
  if UnitDefNames[unitDefName] then
    lootboxTiers[UnitDefNames[unitDefName].id] = tier
  end
end

for _, unitDef in pairs(UnitDefs) do
  if unitDef.name:find "lootbox" then
    lootboxTiers[unitDef.name] = tonumber(unitDef.customparams.techlevel)
  end
end

-- local teams = Spring.GetTeamList()
-- for _, teamID in ipairs(teams) do
  --     local teamLuaAI = Spring.GetTeamLuaAI(teamID)
  --     if (teamLuaAI and string.find(teamLuaAI, "Scavengers")) then
    --         scavTeamID = teamID
    --         scavAllyTeamID = select(6, Spring.GetTeamInfo(scavTeamID))
    --         break
    --     end
    -- end

    local aliveLootboxes = {}
    local aliveLootboxesCount = 0

    function gadget:UnitCreated(unitID, unitDefID, unitTeam)
      if lootboxTiers[unitDefID] then
        aliveLootboxes[unitID] = {
          tier=lootboxTiers[unitDefID]
        }
        aliveLootboxesCount = aliveLootboxesCount + 1
      end
    end

    function gadget:UnitDestroyed(unitID, unitDefID, unitTeam)
      if aliveLootboxes[unitID] then
        aliveLootboxes[unitID] = nil
        aliveLootboxesCount = aliveLootboxesCount - 1
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
        -- Spring.GiveOrderToUnit(unitId, CMD.REPEAT, { 1 }, 0)
        -- Spring.GiveOrderToUnit(unitId, CMD.STOCKPILE, {}, { "ctrl", "shift", "right" })
        -- Spring.GiveOrderToUnit(unitId, CMD.STOCKPILE, {}, 0)
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

    function gadget:GameFrame(frame)
      if frame%30 ~= 0 then
        return
      end

      if aliveLootboxesCount > 0 and aliveSpawnersCount > 0 then
        if SetCount(handledLootboxesList) > 0 then
          handledLootboxesList = {}
        end
        if frame-math.ceil(18000/aliveLootboxesCount) > lastTransportSentFrame then -- 10 minutes for 1 lootbox alive
          local targetLootboxID = -1
          local loopCount = 0
          local success = false
          for lootboxID, lootboxTier in pairs(aliveLootboxes) do
            local lootboxPosX, lootboxPosY, lootboxPosZ = Spring.GetUnitPosition(lootboxID)
            if (lootboxPosX) and not GG.IsPosInRaptorScum(lootboxPosX, lootboxPosY, lootboxPosZ) then
              if math.random(0,aliveLootboxesCount) == 0 and not handledLootboxesList[lootboxID] then
                for transportDefID, transportTier in pairs(transportsList) do
                  if math.random(0,SetCount(transportsList)) == 0 and transportTier == lootboxTier and not handledLootboxesList[lootboxID] then
                    for spawnerID, _ in pairs(aliveSpawners) do
                      if math.random(0,SetCount(aliveSpawners)) == 0 and not handledLootboxesList[lootboxID] then
                        targetLootboxID = lootboxID
                        local spawnerPosX, spawnerPosY, spawnerPosZ = Spring.GetUnitPosition(spawnerID)
                        for j = 1,5 do
                          if math.random() <= config.spawnChance then
                            local transportID = Spring.CreateUnit(transportDefID, spawnerPosX+math.random(-1024, 1024), spawnerPosY+100, spawnerPosZ+math.random(-1024, 1024), math.random(0,3), scavTeamID)
                            if transportID then
                              handledLootboxesList[targetLootboxID] = true
                              success = true
                              lastTransportSentFrame = frame
                              Spring.GiveOrderToUnit(transportID, CMD.LOAD_UNITS, {targetLootboxID}, {"shift"})
                              for i = 1,100 do
                                local randomX = math.random(0, Game.mapSizeX)
                                local randomZ = math.random(0, Game.mapSizeZ)
                                local randomY = math.max(0, Spring.GetGroundHeight(randomX, randomZ))
                                if GG.IsPosInRaptorScum(randomX, randomY, randomZ) then
                                  Spring.GiveOrderToUnit(transportID, CMD.UNLOAD_UNITS, {randomX, randomY, randomZ, 1024}, {"shift"})
                                end
                                if i == 100 then
                                  Spring.GiveOrderToUnit(transportID, CMD.MOVE, {randomX+math.random(-256,256), randomY, randomZ+math.random(-256,256)}, {"shift"})
                                end
                              end
                            end
                          end
                        end
                      end
                      if success == true then
                        break
                      end
                    end
                  end
                  if success == true then
                    break
                  end
                end
              end
            end
          end
          end
        end
      end
