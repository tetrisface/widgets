function widget:GetInfo()
  return {
    desc    = "",
    author  = "tetrisface",
    version = "",
    date    = "mar, 2024",
    name    = "Idle Builders Cursor",
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
local color                = {
  yellow  = { 181 / 256, 137 / 256, 0 },
  blue    = { 38 / 256, 139 / 256, 210 / 256 },
  magenta = { 211 / 256, 54 / 256, 130 / 256 },
  violet  = { 108 / 256, 113 / 256, 196 / 256 },
  cyan    = { 42 / 256, 161 / 256, 152 / 256 },
  red     = { 220 / 256, 50 / 256, 47 / 256 },
  orange  = { 203 / 256, 75 / 256, 22 / 256 },
  green   = { 133, 153, 0 }
}

local fontSize             = 20
local gameFrame            = 0
local lastEtaUpdate        = 0
local myTeamId             = Spring.GetMyTeamID()
local shortcutsActive      = false
local updateEtas           = false
local yellowTime           = 14
local redTime              = 5

local list
local font

-- local function BuilderById(id)
--   return builders[builderUnitIds.hash[id]]
-- end

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

local function AddTargetEta(targetId)
  if not anyIdleTargetEtas[targetId] then
    anyIdleTargetEtas[targetId] = makeETA(targetId, Spring.GetUnitDefID(targetId))
    updateEtas = true
  end
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

    if gameFrame - builder.lastActivity < 1800 then -- not abandoned
      local isFinishingUpTarget = nCommands == 1
          and (commands[1].id < 0
            or commands[1].id == CMD.REPAIR
            or select(5, Spring.GetUnitHealth(builder.id)) < 1
          ) -- Is building or repairing as last activity or being built

      if nCommands == 0 or isFinishingUpTarget then
        if isFinishingUpTarget then
          builder.targetId = Spring.GetUnitIsBuilding(builder.id) or select(5, Spring.GetUnitHealth(builder.id))
          AddTargetEta(builder.targetId)
        end
        idleDefIdBuildersCounts[builder.def.id] = (idleDefIdBuildersCounts[builder.def.id] or 0) + 1
        if not idleDefIdBuilders[builder.def.id] then
          idleDefIdBuilders[builder.def.id] = {}
        end
        idleDefIdBuilders[builder.def.id][idleDefIdBuildersCounts[builder.def.id]] = builder
      end
    end
  end
  return idleDefIdBuilders
end

-- MVPs trepan, jK, Floris build eta function stolen from luaui\Widgets\gui_build_eta.lua
local function UpdateTargetsFinishedAt()
  local gameSeconds = Spring.GetGameSeconds()

  if gameSeconds == lastEtaUpdate and not updateEtas then
    return
  end
  lastEtaUpdate = gameSeconds
  updateEtas = false

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
          bi.finishedAt = gameSeconds + bi.timeLeft
          redraw = true
        end
        bi.lastTime = gameSeconds
        bi.lastProg = buildProgress
      end
    end
  end

  for _, unitID in pairs(killTable) do
    anyIdleTargetEtas[unitID] = nil
  end
end

local function MouseWorldPosition()
  local mx, my = Spring.GetMouseState()
  local _, pos = Spring.TraceScreenRay(mx, my, true, false, true)
  if not pos then
    return
  end

  local x = pos[1]
  x = x < 0 and 0 or x > Game.mapSizeX and Game.mapSizeX or x
  local z = pos[3]
  z = z < 0 and 0 or z > Game.mapSizeZ and Game.mapSizeZ or z
  return x, pos[2], z
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
  local aTarget = anyIdleTargetEtas[a.target]
  local bTarget = anyIdleTargetEtas[b.target]
  return aTarget ~= nil and bTarget == nil
      or aTarget and bTarget and aTarget.finishedAt < bTarget.finishedAt
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

local function CompareTechLevel(a, b)
  return (a.def.customParams and tonumber(a.def.customParams.techlevel) or 1)
      > (b.def.customParams and tonumber(b.def.customParams.techlevel) or 1)
end

function widget:GameFrame(_gameFrame)
  gameFrame = _gameFrame

  local idleBuilderDefGroups = IdleBuilderDefGroups()
  UpdateTargetsFinishedAt()
  distinctIdleBuilders = DistinctSortedIdleBuilders(idleBuilderDefGroups)
  table.sort(distinctIdleBuilders, CompareTechLevel)
  redrawList = true
end

function widget:UnitCreated(unitId, unitDefID, unitTeam)
  if unitTeam == myTeamId then
    local builderDef = UnitDefs[unitDefID]

    if builderDef.isBuilder and not builderDef.isFactory and #builderDef.buildOptions > 0 then
      local isBeingBuilt = select(5, Spring.GetUnitHealth(unitId)) < 1
      builderUnitIds:Add(unitId)
      builders[builderUnitIds.count] = {
        id           = unitId,
        def          = builderDef,
        lastActivity = Spring.GetGameFrame(),
        targetId     = unitId,
      }
      if isBeingBuilt then
        AddTargetEta(unitId)
      end
    end
  end
end

local function Deregister(unitId, _, unitTeam, asTarget)
  if unitTeam == myTeamId then
    local index = builderUnitIds.hash[unitId]
    if index ~= nil then
      builders[index] = nil
    end
    builderUnitIds:Remove(unitId)
  end
  if asTarget then
    anyIdleTargetEtas[unitId] = nil
  end
end
function widget:UnitDestroyed(unitID, unitDefId, unitTeam)
  Deregister(unitID, unitDefId, unitTeam, true)
end

function widget:UnitGiven(unitID, unitDefId, unitTeam, oldTeam)
  widget:UnitCreated(unitID, unitDefId, unitTeam)
  Deregister(unitID, unitDefId, oldTeam, false)
end

function widget:UnitTaken(unitID, unitDefId, unitTeam)
  Deregister(unitID, unitDefId, unitTeam, false)
end

function widget:UnitFinished(unitId)
  anyIdleTargetEtas[unitId] = nil
end

function widget:Initialize()
  if Spring.GetSpectatingState() or Spring.IsReplay() then
    widgetHandler:RemoveWidget()
  end

  widget:ViewResize()

  local myUnits = Spring.GetTeamUnits(myTeamId)
  for i = 1, #myUnits do
    local unitID = myUnits[i]
    local unitDefID = Spring.GetUnitDefID(unitID)
    widget:UnitCreated(unitID, unitDefID, myTeamId)
  end
end

local function Interpolate(value, inMin, inMax, outMin, outMax)
  -- Ensure the value is within the specified range
  -- Calculate the interpolation
  return outMin + ((((value < inMin) and inMin or ((value > inMax) and inMax or value)) - inMin) / (inMax - inMin)) * (outMax - outMin)
end

local function CreateIdleBuilderList()
  local gameSeconds = Spring.GetGameSeconds()

  local mouseX, mouseY = Spring.GetMouseState()

  font:Begin()
  for i = 1, #distinctIdleBuilders do
    local builder        = distinctIdleBuilders[i]
    local target         = anyIdleTargetEtas[builder.targetId]

    -- log('builder.targetId', builder.targetId, 'target', target)
    -- table.echo(target)

    -- log('draw builder', builder.def.translatedHumanName, 'targetId', builder.targetId, 'target', target)

    local timeLeftString = ''
    local lineColor      = { 1, 1, 1 }
    if target then
      local secondsLeft = target.finishedAt and target.finishedAt - gameSeconds or false
      if not secondsLeft then
        timeLeftString = ''
      elseif secondsLeft >= 99.5 then
        timeLeftString = string.format(' %dm', math.floor(0.5 + secondsLeft / 60))
      else
        timeLeftString = string.format(' %ds', math.floor(0.5 + secondsLeft))
        if secondsLeft < redTime then
          lineColor = {
            Interpolate(secondsLeft, 0, redTime, color.red[1], color.yellow[1]),
            Interpolate(secondsLeft, 0, redTime, color.red[2], color.yellow[2]),
            Interpolate(secondsLeft, 0, redTime, color.red[3], color.yellow[3]),
          }
        elseif secondsLeft < yellowTime then
          lineColor = {
            Interpolate(secondsLeft, 3, yellowTime, color.yellow[1], 1),
            Interpolate(secondsLeft, 3, yellowTime, color.yellow[2], 1),
            Interpolate(secondsLeft, 3, yellowTime, color.yellow[3], 1),
          }
        end
      end
    end

    font:SetAutoOutlineColor(true)
    font:SetTextColor(lineColor[1], lineColor[2], lineColor[3])
    local builderString = string.format(
      '%d. %s %s %s',
      i,
      builder.def.name:sub(1, 3):gsub("^%l", string.upper),
      builder.def.translatedHumanName,
      timeLeftString
    )
    -- font:Print(builderString, mouseX + 80, mouseY - (i - 1) * 20, fontSize, 'o')
    font:Print(builderString, mouseX + 80, mouseY - (i - 1) * 20 - 8, fontSize, 'o')
  end

  font:End()
end

function widget:DrawScreen()
  gl.CallList(gl.CreateList(CreateIdleBuilderList))
end

function widget:ViewResize()
  local viewSizeX, viewSizeY = gl.GetViewSizes()

  fontSize = Interpolate((viewSizeX + viewSizeY) / 2, 600, 8000, 10, 50)
  -- font = WG['fonts'].getFont(nil, 33, 0.19, 1.75)
  font = WG['fonts'].getFont(nil, nil, 0.3, 7)
  redraw = true
end

function widget:KeyPress(key, mods, isRepeat, label)
  log('Spring.GetActiveCommand()', Spring.GetActiveCommand())
  if Spring.GetActiveCommand() ~= 0 then
    return
  end

  log('press', key, mods['shift'], key == KEYSYMS.LSHIFT)
  if key == KEYSYMS.CAPSLOCK then
    log('caps')
    return true
  end
  if key == KEYSYMS.LSHIFT then
    shortcutsActive = true
  end
end

function widget:KeyRelease(key, mods, label)
  -- if key == KEYSYMS.CAPSLOCK then
  if key == KEYSYMS.LSHIFT then
    shortcutsActive = false
  end
end

function widget:Shutdown()
  if list then
    gl.DeleteList(list);
    list = nil
  end
end
