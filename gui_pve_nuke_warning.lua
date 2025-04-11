function widget:GetInfo()
	return {
		desc = 'PVE Nuke Warning',
		author = 'TetrisCo',
		version = '',
		date = 'feb, 2024',
		name = 'PVE Nuke Warning',
		license = '',
		layer = -99990,
		enabled = true,
	}
end

-- GitHub https://gist.github.com/tetrisface/68a96fd102a642d12812411035fdc860
-- Discord https://discord.com/channels/549281623154229250/1206703169585811456

local nukes = not Spring.GetModOptions().unit_restrictions_nonukes
local font

local nukeList

local vsx, vsy = Spring.GetViewGeometry()
local showNukeWarning = false
local hasAnti = false
local alive = true
local techAnger = 0

if not nukes then
	widgetHandler:RemoveWidget()
	return false
end

local nukeNames = { 'armamd', 'armscab', 'corfmd', 'cormabm', 'legabm' }

local nukeIDs = {}
for _, name in ipairs(nukeNames) do
	if UnitDefNames[name] then
		nukeIDs[UnitDefNames[name].id] = true
	end
	if UnitDefNames[name .. '_scav'] then
		nukeIDs[UnitDefNames[name .. '_scav'].id] = true
	end
end

function widget:ViewResize()
	vsx, vsy = Spring.GetViewGeometry()
	font = WG['fonts'].getFont('fonts/' .. Spring.GetConfigString('bar_font2', 'Exo2-SemiBold.otf'))
end

local function CreateNukeWarning()
	gl.PushMatrix()
	font:Begin()
	font:SetTextColor(1, 0.3, 0.3, 0.8)
	local warningString = 'NUKE WARNING! ' .. tostring(techAnger) .. '%'
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
		local myTeamId = Spring.GetMyTeamID()
		if n % 100 == 0 then
			hasAnti = false
			for id, _ in pairs(nukeIDs) do
				if Spring.GetTeamUnitDefCount(myTeamId, id) > 0 then
					hasAnti = true
					break
				end
			end
		end
		if n % 25 == 0 then
			techAnger = math.max(Spring.GetGameRulesParam('raptorTechAnger') or 0, Spring.GetGameRulesParam('scavTechAnger') or 0)
			showNukeWarning = not hasAnti
				and n % 50 < 25
				and techAnger ~= nil
				and techAnger > 65
				and techAnger < 90
				and select(4, Spring.GetTeamResources(myTeamId, 'energy')) > 1000
				and Spring.GetTeamUnitCount(myTeamId) > 3
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
