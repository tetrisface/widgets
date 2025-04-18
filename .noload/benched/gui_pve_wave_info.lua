if not (Spring.Utilities.Gametype.IsRaptors() or Spring.Utilities.Gametype.IsScavengers()) then
  return false
end

function widget:GetInfo()
  return {
    name = "GUI PVE Wave Info",
    desc = "",
    author = "tetrisface",
    date = "May, 2024",
    license = "GNU GPL, v3 or later",
    layer = -9123,
    enabled = true
  }
end

VFS.Include('luaui/Widgets/.noload/misc/helpers.lua')

local config               = VFS.Include('LuaRules/Configs/raptor_spawn_defs.lua')

local customScale          = 1
local widgetScale          = customScale
local font, font2
local showMarqueeMessage   = false

local vsx, vsy             = Spring.GetViewGeometry()

local viewSizeX, viewSizeY = 0, 0
local w                    = 300
local h                    = 800
local x1                   = 0
local y1                   = 0
local dragging             = false
local waveSpeed            = 0.1
local waveTime
local spawnDefs            = {}
local nSpawnDefs           = 0
local tech                 = 0
local stageGrace           = 0
local stageMain            = 1
local stageQueen           = 2
local fontSize             = 14

local waveInfoList
local needRedraw           = false
local hasRaptorEvent       = false

local modOptions           = Spring.GetModOptions()

local dedupNames           = {}
local previousTimer        = Spring.GetGameSeconds()

local rules                = {
  -- "raptorDifficulty",
  -- "raptorGracePeriod",
  -- "raptorQueenAnger",
  -- "RaptorQueenAngerGain_Aggression",
  -- "RaptorQueenAngerGain_Base",
  -- "RaptorQueenAngerGain_Eco",
  -- "raptorQueenHealth",
  -- "raptorQueenTime",
  "raptorTechAnger",
}

local function Interpolate(value, inMin, inMax, outMin, outMax)
  -- Ensure the value is within the specified range
  value = (value < inMin) and inMin or ((value > inMax) and inMax or value)

  -- Calculate the interpolation
  local t = (value - inMin) / (inMax - inMin)
  return outMin + t * (outMax - outMin)
end

local function FormatSeconds(seconds)
  if seconds < 0 then
    if Spring.GetGameSeconds() < config.gracePeriod then
      return 'pending'
    end
    return ''
  end
  -- log('seconds', seconds, string.format("%02d:%02d", math.floor(seconds / 60), math.floor(seconds % 60)))
  return string.format("%02d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
end


-- local function RaptorStage(currentTime)
--   local stage = stageGrace
--   if (currentTime and currentTime or Spring.GetGameSeconds()) > config.gracePeriod then
--     if gameInfo.raptorQueenAnger < 100 then
--       stage = stageMain
--     else
--       stage = stageQueen
--     end
--   end
--   return stage
-- end

local function DrawWaveInfo()
  local t = Spring.GetGameSeconds()
  gl.PushMatrix()
  gl.Translate(x1, y1, 0)
  -- gl.Scale(widgetScale, widgetScale, 1)
  font:Begin()

  -- font:SetTextColor(1, 1, 1, 1)
  -- font:SetOutlineColor(0, 0, 0, 1)
  -- font:Print(I18N('ui.raptors.mode', { mode = 'asdf' }), 80, h - 170, panelFontSize)
  font:SetAutoOutlineColor(true)
  for index, spawn in ipairs(spawnDefs) do
    if spawn.spawnAtSeconds then
      if spawn.minTech >= tech or t < config.gracePeriod then
        font:SetTextColor(1, 1, 1, 1)
      else
        font:SetTextColor(1, 1, 1, 0.7)
      end
      local spawnName = spawn.def.translatedHumanName
      local spawnTime = FormatSeconds(spawn.spawnAtSeconds - t)
      local spawnTech = '(' .. spawn.minTech .. '%)'
      local nameWidth = math.floor(0.5 + font:GetTextWidth(spawnName) * fontSize)
      local timeWidth = math.floor(0.5 + font:GetTextWidth(spawnTime) * fontSize)
      local timeWidthColon = math.floor(0.5 + font:GetTextWidth(spawnTime:gsub('(.*):.*$', '%1')) * fontSize)
      font:Print(spawnName, nameWidth / 2, -index * fontSize, fontSize, 'co')
      font:Print(spawnTime, 270 + timeWidthColon / 2, -index * fontSize, fontSize, 'co')
    end
  end
  font:End()

  -- gl.Texture(false)
  gl.PopMatrix()
end

function widget:DrawScreen()
  -- if updateWaveInfo then
  --   if (waveInfoList) then
  --     gl.DeleteList(waveInfoList);
  --     waveInfoList = nil
  --   end
  --   waveInfoList = gl.CreateList(DrawWaveInfo)
  --   -- gl.CallList(waveInfoList)
  --   -- updateWaveInfo = false
  --   updateWaveInfo = false
  -- end

  -- if waveInfoList then
  -- if updateWaveInfo then
  if needRedraw or ((Spring.GetGameSeconds() - previousTimer) > 0.2) then
    if (waveInfoList) then
      gl.DeleteList(waveInfoList);
      waveInfoList = nil
    end
    waveInfoList = nil
    waveInfoList = gl.CreateList(DrawWaveInfo)
    needRedraw = false
    previousTimer = Spring.GetGameSeconds()
  end
  if waveInfoList then
    gl.CallList(waveInfoList)
  end

  if showMarqueeMessage then
    local t = Spring.GetTimer()

    local waveY = viewSizeY - Spring.DiffTimers(t, waveTime) * waveSpeed * viewSizeY
    if waveY > 0 then
      -- if refreshMarqueeMessage or not marqueeMessage then
      -- 	marqueeMessage = getMarqueeMessage(messageArgs)
      -- end

      font2:Begin()
      -- for i, message in ipairs(marqueeMessage) do
      -- 	font2:Print(message, viewSizeX / 2, waveY - (WaveRow(i) * widgetScale), waveFontSize * widgetScale, "co")
      -- end
      font2:End()
    else
      showMarqueeMessage = false
      -- messageArgs = nil
      waveY = viewSizeY
    end
    -- elseif #resistancesTable > 0 then
    -- marqueeMessage = getResistancesMessage()
    -- waveTime = Spring.GetTimer()
    -- showMarqueeMessage = true
  end
end

local function UpdateTimes()
  -- for i = 1, #rules do
  --   local rule = rules[i]
  -- if temp == 0 or temp == nil or temp ~= raptorTechAnger then
  -- updateWaveInfo = true
  -- end
  tech = Spring.GetGameRulesParam('raptorTechAnger') or 0

  -- if updateWaveInfo then
  -- local techAnger = math.max(math.ceil(math.min((t - (config.gracePeriod / modOptions.raptor_graceperiodmult)) / ((config.queenTime / modOptions.raptor_queentimemult) - (config.gracePeriod / modOptions.raptor_graceperiodmult)) * 100), 999), 0)
  local graceSeconds = config.gracePeriod / modOptions.raptor_graceperiodmult
  local queenSeconds = (config.queenTime + config.gracePeriod) / modOptions.raptor_queentimemult
  -- log('tech', tech, 'config.gracePeriod', config.gracePeriod, 'modOptions.raptor_graceperiodmult', modOptions.raptor_graceperiodmult)
  for i = 1, #spawnDefs do
    local spawn = spawnDefs[i]
    -- local tech = (t - (config.gracePeriod / modOptions.raptor_graceperiodmult)) / ((config.queenTime / modOptions.raptor_queentimemult) - (config.gracePeriod / modOptions.raptor_graceperiodmult)) * 100
    -- local tech = (t - graceTimeFraction) / (queenTimeFraction - graceTimeFraction) * 100
    -- log('tech', tech, 'minTech', spawn.minTech, 'seconds', graceSeconds, queenSeconds, 'techdiff', (spawn.minTech - tech) / 100, queenSeconds - graceSeconds)
    -- log('test', math.max(0, math.ceil(0.5 + ((spawn.minTech - tech) / 100) * (queenTimeFraction - graceTimeFraction) + graceTimeFraction)))
    -- end
    -- local timeDiffSeconds = math.max(0, math.ceil(0.5 + ((spawn.minTech - tech) / 100) * (queenTimeFraction - graceTimeFraction) + graceTimeFraction - (config.gracePeriod / modOptions.raptor_graceperiodmult)))
    -- spawn.spawnAtSeconds = math.max(0, math.floor(0.5 + (spawn.minTech / 100) * (queenSeconds - graceSeconds)))
    -- local techAnger = (t - (config.gracePeriod / modOptions.raptor_graceperiodmult)) / ((config.queenTime / modOptions.raptor_queentimemult) - (config.gracePeriod / modOptions.raptor_graceperiodmult)) * 100
    -- local origTest = math.max(math.ceil(math.min((Spring.GetGameSeconds() - (config.gracePeriod / Spring.GetModOptions().raptor_graceperiodmult)) / ((queenSeconds) - (config.gracePeriod / Spring.GetModOptions().raptor_graceperiodmult)) * 100), 999), 0)
    -- local testTech = ((Spring.GetGameSeconds() - graceSeconds) / (queenSeconds - graceSeconds)) * 100
    spawn.spawnAtSeconds = math.floor(0.5 + ((spawn.minTech - 0.5) / 100) * (queenSeconds - graceSeconds) + graceSeconds - 10)
    -- if tech < spawn.minTech then
    --   log('test', testTech, 'invertTest', invertTechSeconds, (queenSeconds - graceSeconds))
    -- end
  end
end
-- end

local function RaptorEvent(raptorEventArgs)
  -- if (raptorEventArgs.type == "firstWave" or raptorEventArgs.type == "wave" or raptorEventArgs.type == "airWave") and gameRulesParams.raptorQueenAnger <= 99 then
  -- waveCount = waveCount + 1
  -- raptorEventArgs.waveCount = waveCount
  -- showMarqueeMessage = true
  -- refreshMarqueeMessage = true
  -- messageArgs = raptorEventArgs
  --   waveTime = Spring.GetTimer()
  -- end
end

local function updatePos(x, y)
  local x0 = (viewSizeX * 0.94) - (w * widgetScale) / 2
  local y0 = (viewSizeY * 0.89) - (h * widgetScale) / 2
  -- x1 = x0 < x and x0 or x
  -- y1 = y0 < y and y0 or y
  x1 = x
  y1 = y
  needRedraw = true
end

function deepcopy(orig)
  local orig_type = type(orig)
  local copy
  if orig_type == 'table' then
    copy = {}
    for orig_key, orig_value in next, orig, nil do
      copy[deepcopy(orig_key)] = deepcopy(orig_value)
    end
    setmetatable(copy, deepcopy(getmetatable(orig)))
  else -- number, string, boolean, etc
    copy = orig
  end
  return copy
end

function trim6(s)
  return s:match '^()%s*$' and '' or s:match '^%s*(.*%S)'
end

local function SortSpawn(a, b)
  if a.minTech == b.minTech then
    return a.name == 'raptor_turret_meteor_t4_v1' or (b.name ~= 'raptor_turret_meteor_t4_v1' and a.def.cost > b.def.cost)
  end
  return a.minTech < b.minTech
end

function widget:Initialize()
  widget:ViewResize()

  widgetHandler:RegisterGlobal("RaptorEvent", RaptorEvent)
  UpdateTimes()
  viewSizeX, viewSizeY = gl.GetViewSizes()
  -- local x = math.abs(math.floor(viewSizeX - 300))
  -- local y = math.abs(math.floor(viewSizeY - 340))
  local x = math.abs(math.floor(viewSizeX - 600))
  local y = math.abs(math.floor(viewSizeY - 100))

  updatePos(x, y)
  -- table.echo(config.squadSpawnOptionsTable, 'config.squadSpawnOptionsTable')
  nSpawnDefs = 0
  for _, spawnTypeDefs in pairs(config.squadSpawnOptionsTable) do
    for _, spawnDef in ipairs(spawnTypeDefs) do
      for _, spawnDefName in ipairs(spawnDef.units) do
        spawnDefName = trim6(spawnDefName:gsub('^%d+%s+', ''))
        local spawnDefCopy = deepcopy(spawnDef)
        spawnDefCopy.units = nil
        spawnDefCopy.weight = nil
        spawnDefCopy.minTech = spawnDefCopy.minAnger
        spawnDefCopy.minAnger = nil
        spawnDefCopy.def = UnitDefNames[spawnDefName]
        spawnDefCopy.name = spawnDefName
        nSpawnDefs = nSpawnDefs + 1
        spawnDefs[nSpawnDefs] = spawnDefCopy
      end
    end
  end

  for defName, spawnDef in pairs(config.raptorTurrets) do
    spawnDef.def = UnitDefNames[defName]
    spawnDef.name = defName
    spawnDef.minTech = spawnDef.minQueenAnger
    spawnDef.minQueenAnger = nil
    nSpawnDefs = nSpawnDefs + 1
    spawnDefs[nSpawnDefs] = spawnDef
  end

  table.sort(spawnDefs, SortSpawn)

  local _spawnDefs = {}

  for _, spawnDef in ipairs(spawnDefs) do
    if not dedupNames[spawnDef.def.translatedHumanName] then
      table.insert(_spawnDefs, spawnDef)
      dedupNames[spawnDef.def.translatedHumanName] = true
    end
  end
  spawnDefs = _spawnDefs
  UpdateTimes()
  needRedraw = true
end

function widget:Shutdown()
  if waveInfoList then
    gl.DeleteList(waveInfoList);
    waveInfoList = nil
  end
  widgetHandler:DeregisterGlobal("RaptorEvent")
end

function widget:GameFrame(n)
  -- if not hasRaptorEvent and n > 1 then
  -- 	Spring.SendCommands({ "luarules HasRaptorEvent 1" })
  -- 	hasRaptorEvent = true
  -- end
  if n == 0 or n % 300 == 0 then
    -- do i even need?
    UpdateTimes()
  end
end

function widget:MouseMove(x, y, dx, dy, button)
  if dragging then
    updatePos(x1 + dx, y1 + dy)
  end
end

function widget:MousePress(x, y, button)
  if x > x1 and x < x1 + (w * widgetScale) and
      y > y1 and y < y1 + (h * widgetScale)
  then
    dragging = true
  end
  return dragging
end

function widget:MouseRelease(x, y, button)
  dragging = false
end

function widget:ViewResize()
  vsx, vsy = Spring.GetViewGeometry()

  font = WG['fonts'].getFont()

  x1 = math.floor(x1 - viewSizeX)
  y1 = math.floor(y1 - viewSizeY)
  viewSizeX, viewSizeY = vsx, vsy
  widgetScale = (0.75 + (viewSizeX * viewSizeY / 10000000)) * customScale
  x1 = viewSizeX + x1 + ((x1 / 2) * (widgetScale - 1))
  y1 = viewSizeY + y1 + ((y1 / 2) * (widgetScale - 1))
end

function widget:LanguageChanged()
  needRedraw = true
end
