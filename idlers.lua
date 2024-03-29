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
  idle builder selection and sorting
  0. has been abandoned for many gameframes (filtered)
  1. is or will idle (filtered)
  2. distinct def id (grouped)
  3. tech level (descending)
  4. idle timestamp (ascending)
  5. distance to cursor (ascending)
]]

local NewSetList = VFS.Include('common/SetList.lua').NewSetList
VFS.Include('luaui/Headers/keysym.h.lua')
VFS.Include('luaui/Widgets/helpers.lua')

local builders             = {}
local builderUnitIds       = NewSetList()
local distinctIdleBuilders = {}
local anyIdleTargetEtas    = {}

local gameFrame            = 0
local myTeamId             = Spring.GetMyTeamID()

local function BuilderById(id)
  return builders[builderUnitIds.hash[id]]
end

local function makeETA(unitID, unitDefID)
  if unitDefID == nil then
    return nil
  end
  local _, _, _, _, buildProgress = Spring.GetUnitHealth(unitID)
  if buildProgress == nil or buildProgress >= 1 then
    return nil
  end

  return {
    firstSet   = true,
    lastTime   = Spring.GetGameSeconds(),
    lastProg   = buildProgress,
    rate       = nil,
    timeLeft   = nil,
    finishedAt = nil,
  }
end

local function IdleBuilderDefGroups()
  local idleDefIdBuilders = {}
  local idleDefIdBuildersCounts = {}
  for i = 1, builderUnitIds.count do
    local builder = builders[i]
    local commands = Spring.GetUnitCommands(builder.id, 2)
    local nCommands = #commands
    if nCommands > 0 then
      builder.lastActivity = gameFrame
    end

    if gameFrame - builder.lastActivity < 1800 -- abandoned
    then
      -- Is building or repairing as last activity or being built
      local isFinishingUpTarget = nCommands == 1
          and (commands[1].id < 0
            or commands[1].id == CMD.REPAIR
            or select(5, Spring.GetUnitHealth(builder.id)) < 1
          )
      if nCommands == 0 or isFinishingUpTarget then
        local targetId
        if isFinishingUpTarget then
          targetId = commands[1] and commands[1].args[1] or select(5, Spring.GetUnitHealth(builder.id))
          if not anyIdleTargetEtas[targetId] then
            anyIdleTargetEtas[targetId] = makeETA(targetId, Spring.GetUnitDefID(targetId))
          end
        end
        builder.nCommands = nCommands
        builder.commands = commands
        builder.targetId = targetId
        idleDefIdBuildersCounts[builder.def.id] = (idleDefIdBuildersCounts[builder.def.id] or 0) + 1
        idleDefIdBuilders[builder.def.id][idleDefIdBuildersCounts[builder.def.id]] = builder
      end
    end
  end
  return idleDefIdBuilders
end

local function MouseWorldPosition()
  local mx, my = Spring.GetMouseState()
  local _, pos = Spring.TraceScreenRay(mx, my, true, false, true)
  if not pos then
    return
  end

  local x = pos[4]
  x = x < 0 and 0 or x > Game.mapSizeX and Game.mapSizeX or x
  local z = pos[6]
  z = z < 0 and 0 or z > Game.mapSizeZ and Game.mapSizeZ or z
  return x, pos[2], z
end

local function CompareTechLevel(a, b)
  return (a.def.customParams and tonumber(a.def.customParams.techlevel) or 1)
      > (b.def.customParams and tonumber(b.def.customParams.techlevel) or 1)
end

local function CompareCursorDistance(a, b)
  local aX, _, aZ = Spring.GetUnitPosition(a.id)
  local bX, _, bZ = Spring.GetUnitPosition(b.id)

  local mouseWorldPosX, _, mouseWorldPosZ = MouseWorldPosition() -- also done in Update()
  if not mouseWorldPosX then
    return false
  end
  return (aX - mouseWorldPosX) ^ 2 + (aZ - mouseWorldPosZ) ^ 2
      < (bX - mouseWorldPosX) ^ 2 + (bZ - mouseWorldPosZ) ^ 2
end

local function CompareBuilder(a, b)
  return anyIdleTargetEtas[a.target].finishedAt < anyIdleTargetEtas[b.target].finishedAt
      or CompareCursorDistance(a, b)
end

local function DistinctSortedIdleBuilders(idleBuilderDefGroups)
  local idleBuilders = {}
  local nIdleBuilders = 0
  for _, defGroupBuilders in pairs(idleBuilderDefGroups) do
    table.sort(defGroupBuilders, CompareBuilder)
    nIdleBuilders = nIdleBuilders + 1
    idleBuilders[nIdleBuilders] = defGroupBuilders[1]
  end
  return idleBuilders
end

-- MVPs trepan, jK, Floris build eta function stolen from luaui\Widgets\gui_build_eta.lua
local function UpdateTargetsFinishedAt()
  local gameSeconds = Spring.GetGameSeconds()

  local killTable = {}
  local count = 0
  for unitID, bi in pairs(anyIdleTargetEtas) do
    local _, _, _, _, buildProgress = Spring.GetUnitHealth(unitID)
    if not buildProgress or buildProgress >= 1.0 then
      count = count + 1
      killTable[count] = unitID
    else
      local dp = buildProgress - bi.lastProg
      local dt = gameSeconds - bi.lastTime
      if dt > 2 then
        bi.firstSet = true
        bi.rate = nil
        bi.timeLeft = nil
      end

      local rate = dp / dt

      if rate ~= 0 then
        if bi.firstSet then
          if (buildProgress > 0.001) then
            bi.firstSet = false
          end
        else
          local rf = 0.5
          if bi.rate == nil then
            bi.rate = rate
          else
            bi.rate = ((1 - rf) * bi.rate) + (rf * rate)
          end

          local tf = 0.1
          if rate > 0 then
            local newTime = (1 - buildProgress) / rate
            if bi.timeLeft and bi.timeLeft > 0 then
              bi.timeLeft = ((1 - tf) * bi.timeLeft) + (tf * newTime)
            else
              bi.timeLeft = (1 - buildProgress) / rate
            end
          elseif rate < 0 then
            local newTime = buildProgress / rate
            if bi.timeLeft and bi.timeLeft < 0 then
              bi.timeLeft = ((1 - tf) * bi.timeLeft) + (tf * newTime)
            else
              bi.timeLeft = buildProgress / rate
            end
          end
        end
        bi.lastTime   = gameSeconds
        bi.lastProg   = buildProgress
        bi.finishedAt = gameSeconds + bi.timeLeft
      end
    end
  end

  for _, unitID in pairs(killTable) do
    anyIdleTargetEtas[unitID] = nil
  end
end

function widget:GameFrame(_gameFrame)
  gameFrame = _gameFrame

  local idleBuilderDefGroups = IdleBuilderDefGroups()
  UpdateTargetsFinishedAt()
  distinctIdleBuilders = DistinctSortedIdleBuilders(idleBuilderDefGroups)
  table.sort(distinctIdleBuilders, CompareTechLevel)
end

function widget:UnitCreated(unitID, unitDefID, unitTeam)
  if unitTeam == myTeamId then
    local builderDef = UnitDefs[unitDefID]

    if not builderDef.isFactory then
      if builderDef.isBuilder then
        if #builderDef.buildOptions > 0 then
          builderUnitIds:Add(unitID)
          builders[builderUnitIds.count] = {
            id           = unitID,
            def          = builderDef,
            lastActivity = Spring.GetGameFrame(),
          }
        end
      end
    end
  end
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
  if unitTeam == myTeamId then
    local index = builderUnitIds.hash[unitID]
    if index ~= nil then
      builders[index] = nil
    end
    builderUnitIds:Remove(unitID)
    anyIdleTargetEtas[unitID] = nil
  end
end

function widget:UnitGiven(unitID, unitDefID, unitTeam, oldTeam)
  widget:UnitCreated(unitID, unitDefID, unitTeam)
  widget:UnitDestroyed(unitID, unitDefID, oldTeam)
end

function widget:UnitTaken(unitID, unitDefID, unitTeam, newTeam)
  widget:UnitDestroyed(unitID, unitDefID, newTeam)
end

function widget:UnitFinished(unitID, unitDefID, unitTeam)
  anyIdleTargetEtas[unitID] = nil
end

function widget:Initialize()
  if Spring.GetSpectatingState() or Spring.IsReplay() then
    widgetHandler:RemoveWidget()
  end

  local myUnits = Spring.GetTeamUnits(myTeamId)
  for i = 1, #myUnits do
    local unitID = myUnits[i]
    local unitDefID = Spring.GetUnitDefID(unitID)
    widget:UnitCreated(unitID, unitDefID, myTeamId)
  end
end
