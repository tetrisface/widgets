function widget:GetInfo()
  return {
    desc = 'Raptor Nuke Warning',
    author = 'TetrisCo',
    version = '',
    date = 'feb, 2024',
    name = 'Raptor Nuke Warning',
    license = '',
    layer = -99990,
    enabled = true
  }
end

-- GitHub https://gist.github.com/tetrisface/68a96fd102a642d12812411035fdc860
-- Discord https://discord.com/channels/549281623154229250/1206703169585811456

local vsx, vsy = Spring.GetViewGeometry()
local showNukeWarning = false
local hasAnti = false
local alive = true
local nukeList
local font
local nukes = not Spring.GetModOptions().unit_restrictions_nonukes

if not nukes then
  widgetHandler:RemoveWidget()
  return false
end

local armamdId = UnitDefNames['armamd'].id
local armscabId = UnitDefNames['armscab'].id
local corfmdId = UnitDefNames['corfmd'].id
local cormabmId = UnitDefNames['cormabm'].id
local legabmId = UnitDefNames['legabm'] and UnitDefNames['legabm'].id

function widget:ViewResize()
  vsx, vsy = Spring.GetViewGeometry()
  font = WG['fonts'].getFont('fonts/' .. Spring.GetConfigString('bar_font2', 'Exo2-SemiBold.otf'))
end

local function CreateNukeWarning()
  gl.PushMatrix()
  font:Begin()
  font:SetTextColor(1, 0.3, 0.3, 0.8)
  local warningString = 'NUKE WARNING! ' .. tostring(Spring.GetGameRulesParam('raptorTechAnger')) .. '%'
  local stringLength = font:GetTextWidth(warningString) * 50
  font:Print(warningString, (vsx - stringLength) / 2, vsy / 2, 50)
  font:End()
  gl.PopMatrix()
end

function widget:DrawScreen()
  if showNukeWarning then
    nukeList = gl.CreateList(CreateNukeWarning)
    gl.CallList(nukeList)
  elseif nukeList ~= nil then
    gl.DeleteList(nukeList)
    nukeList = nil
  end
end

function widget:GameFrame(n)
  if not nukes then
    widgetHandler:RemoveWidget()
    return
  end

  if alive then
    if n % 100 == 0 then
      local myTeamId = Spring.GetMyTeamID()
      hasAnti =
          Spring.GetTeamUnitDefCount(myTeamId, armamdId) > 0 or
          Spring.GetTeamUnitDefCount(myTeamId, armscabId) > 0 or
          Spring.GetTeamUnitDefCount(myTeamId, corfmdId) > 0 or
          Spring.GetTeamUnitDefCount(myTeamId, cormabmId) > 0 or
          (legabmId and Spring.GetTeamUnitDefCount(myTeamId, legabmId) > 0)
    end
    if n % 25 == 0 then
      local raptorTechAnger = Spring.GetGameRulesParam('raptorTechAnger')
      showNukeWarning = not hasAnti and n % 50 < 25 and raptorTechAnger ~= nil and raptorTechAnger > 65
    end
  end
end

function widget:TeamDied(teamID)
  if teamID == Spring.GetMyTeamID() then
    alive = false
    showNukeWarning = false
  end
end

function widget:Initialize()
  if Spring.GetSpectatingState() or Spring.IsReplay() or not nukes then
    widgetHandler:RemoveWidget()
  end

  font = WG['fonts'].getFont('fonts/' .. Spring.GetConfigString('bar_font2', 'Exo2-SemiBold.otf'))
end
