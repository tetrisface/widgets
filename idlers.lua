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

--[[
  builder sort prio
  0. will idle
  1. has been abandoned for many gameframes (ascending)
  2. has unique def id (descending)
  3. tech level (descending)
  4. time left until idle (ascending)
  5. distance to cursor (ascending)
]]


local NewSetList = VFS.Include('common/SetList.lua').NewSetList
VFS.Include('luaui/Widgets/helpers.lua')

local myTeamId = Spring.GetMyTeamID()
local builderUnitIds = NewSetList()
local builders = {}
local gameFrame = 0

local function BuilderById(id)
  return builders[builderUnitIds.hash[id]]
end

local function BuildTimeLeft(targetId, targetDef)
  local _, _, _, _, build = GetUnitHealth(targetId)
  local currentBuildSpeed = 0
  local idleBuildersTargets = {}
  -- for builderId, _ in pairs(builders) do
  for i = 1, builderUnitIds.count do
    local builder = BuilderById(builderUnitIds.list[i])
    local testTargetId = GetUnitIsBuilding(builder.id)
    if testTargetId == targetId and builder.id ~= targetId then
      currentBuildSpeed = currentBuildSpeed + builder.originalBuildSpeed
    end
  end

  if not targetDef then
    targetDef = UnitDefs[GetUnitDefID(targetId)]
  end

  local buildLeft = (1 - build) * targetDef.buildTime

  local time = buildLeft / currentBuildSpeed

  return time
end

local function DeregisterBuilder(unitID)
  local index = builderUnitIds.hash[unitID]
  if index ~= nil then
    builders[index] = nil
  end
  builderUnitIds:Remove(unitID)
end

local function ToBeIdleBuilders()
  local filteredBuilders = {}
  local nFilteredBuilders = 0
  for i = 1, builderUnitIds.count do
    local builder = builders[i]
    local commands = Spring.GetUnitCommands(builder.id, 2)
    local nCommands = #commands
    if nCommands > 0 then
      builder.lastActivity = gameFrame
    end

    if gameFrame - builder.lastActivity < 1800 and (nCommands == 0 or nCommands == 1 and (commands[1].id < 0 or commands[1].id == CMD.REPAIR)) then
      nFilteredBuilders = nFilteredBuilders + 1
      filteredBuilders[nFilteredBuilders] = builder
    end
  end
  return filteredBuilders
end

local function SortBuilders(a, b)
  local result = asd
  return a.willIdle and not b.willIdle
end


function widget:GameFrame(_gameFrame)
  gameFrame = _gameFrame
  table.sort(ToBeIdleBuilders(), SortBuilders)
end

local function RegisterUnit(unitID, unitDefID)
  local candidateBuilderDef = UnitDefs[unitDefID]

  if candidateBuilderDef.isBuilder and not candidateBuilderDef.isFactory then
    if #candidateBuilderDef.buildOptions > 0 then
      builderUnitIds:Add(unitID)
      builders[builderUnitIds.count] = {
        id           = unitID,
        def          = candidateBuilderDef,
        defID        = unitDefID,
        lastActivity = 0,
      }
    end
  end
end

function widget:Initialize()
  if Spring.GetSpectatingState() or Spring.IsReplay() then
    widgetHandler:RemoveWidget()
  end

  local myUnits = Spring.GetTeamUnits(myTeamId)
  for i = 1, #myUnits do
    local unitID = myUnits[i]
    local unitDefID = Spring.GetUnitDefID(unitID)
    RegisterUnit(unitID, unitDefID)
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
    DeregisterBuilder(unitID, unitDefID)
  end
end
