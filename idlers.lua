function widget:GetInfo()
  return {
    desc    = "",
    author  = "tetrisface",
    version = "",
    date    = "mar, 2024",
    name    = "idlers",
    license = "",
    layer   = -99990,
    enabled = true,
  }
end

local NewSetList = VFS.Include('common/SetList.lua').NewSetList
VFS.Include('luaui/Widgets/helpers.lua')


local function RegisterUnit(unitID, unitDefID)
  local candidateBuilderDef = UnitDefs[unitDefID]

  if candidateBuilderDef.isBuilder and candidateBuilderDef.canAssist and not candidateBuilderDef.isFactory then
    builderUnitIds:Add(unitID)
    builders[unitID] = {
      id                 = unitID,
      buildSpeed         = candidateBuilderDef.buildSpeed,
      originalBuildSpeed = candidateBuilderDef.buildSpeed,
      def                = candidateBuilderDef,
      defID              = unitDefID,
      targetId           = nil,
      guards             = {},
      previousBuilding   = nil,
      lastOrder          = 0,
    }
  elseif MetalMakingEfficiencyDef(UnitDefs[unitDefID]) > 0 then
    metalMakers:Add(unitID)
  end
end

local function DeregisterUnit(unitID, unitDefID)
  builderUnitIds:Remove(unitID)
  metalMakers:Remove(unitID)
  builders[unitID] = nil
end

function widget:Initialize()
  if Spring.GetSpectatingState() or Spring.IsReplay() then
    widgetHandler:RemoveWidget()
  end

  local myUnits = GetTeamUnits(myTeamId)
  for _, unitID in ipairs(myUnits) do
    local unitDefID = GetUnitDefID(unitID)
    RegisterUnit(unitID, unitDefID)
  end

  for unitDefID, unitDef in pairs(UnitDefs) do
    if not unitDef.isFactory and #unitDef.buildoptions > 0 then
      builders[nBuilders] = {
        id = unitId,
      }
    end
  end
end

function widget:UnitCreated(unitID, unitDefID, unitTeam)
  if unitTeam == myTeamId then
    RegisterUnit(unitID, unitDefID)
  end
end

function widget:UnitGiven(unitID, unitDefID, unitTeam, oldTeam)
  if unitTeam == myTeamId then
    RegisterUnit(unitID, unitDefID)
  end
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
  if unitTeam == myTeamId then
    DeregisterUnit(unitID, unitDefID)
  end
end
