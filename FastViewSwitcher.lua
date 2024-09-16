function widget:GetInfo()
  return {
    name      = "FastViewSwitcher",
    desc      = "Save Views and switch to Points of Interest",
    author    = "Ramthis",
    date      = "April 03, 2024",
	version   = "1.0",
    license   = "GNU GPL, v3 or later",
    layer     = 0,
    enabled   = true,  --  loaded by default?

  }
end

VFS.Include('luaui/Headers/keysym.h.lua')

KeycodeForwardView=KEYSYMS.F14
KeycodeBackwardView=KEYSYMS.F14
Debugmode=false
Index=1


local GetCameraState  = Spring.GetCameraState
local SetCameraState  = Spring.SetCameraState
local GetConfigInt    = Spring.GetConfigInt
local SendCommands    = Spring.SendCommands
local Switch=false
local SwitchKey=KEYSYMS.CAPSLOCK


local cameraAnchors = {}


function widget:Initialize()
	widgetHandler:AddAction("focuscameraanchor", FocusCameraAnchor, nil, 'p')
end

function Log(Message)
	if Debugmode==true then
		Spring.Echo(Message)
	end
end

function widget:MousePress(mx, my, button)
if Switch == true then
	if button==1 then
		SetCameraAnchor()
		Log(table.getn(cameraAnchors).." Set Camera Anchor")
	end
	if button==2 then
		cameraAnchors={}
	end
	if button==3 then
		table.remove(cameraAnchors,Index)
	end

end

end

function widget:MouseWheel(up, value)

	if Switch == true then
		if up==true then
			if table.getn(cameraAnchors)>Index then
				Index=Index+1
			elseif table.getn(cameraAnchors)==Index then
				Index=1
			end
			FocusCameraAnchorIntern()
		else
			if 1<Index then
				Index=Index-1
			elseif 1==Index then
				Index=table.getn(cameraAnchors)
			end
			FocusCameraAnchorIntern()
		end
	end


end
function widget:KeyRelease(key)
Log("Release Key="..key)
	if key == SwitchKey      then
		Switch=false
		Log(Switch)
	end
end

function widget:KeyPress(key, mods, isRepeat)

Log("Key="..key)
	if key == SwitchKey      then
		if  Switch==false then
		Switch=true
		Spring.SelectUnitArray({})
		Log(Switch)
		end

end
	if key == KeycodeForwardView    and mods.shift  then

			SetCameraAnchor()


			Log(table.getn(cameraAnchors).." Set Camera Anchor")

	elseif key == KeycodeBackwardView  and mods.shift  then
		table.remove(cameraAnchors,Index)

	elseif key == KeycodeBackwardView  and mods.ctrl  then
		cameraAnchors={}
	Index=1




	-- save View
	elseif key == KeycodeForwardView  then

		if table.getn(cameraAnchors)>Index then
			Index=Index+1
		elseif table.getn(cameraAnchors)==Index then
			Index=1
		end
		FocusCameraAnchorIntern()



		Log(Index.." Focus")

	elseif key == KeycodeBackwardView   then

		if 1<Index then
			Index=Index-1
		elseif 1==Index then
			Index=table.getn(cameraAnchors)
		end
		FocusCameraAnchorIntern()



		Log(Index.." Focus")
	end




end




function SetCameraAnchor()
	--local anchorId = table.getn(cameraAnchors)+1
	local cameraState = GetCameraState()

	table.insert(cameraAnchors,cameraState)

	Spring.Echo("Camera anchor set: " .. table.getn(cameraAnchors))

	return true
end

function FocusCameraAnchorIntern()
	Log(Index.."Focus")
	local anchorId = Index
	local cameraState = cameraAnchors[anchorId]

	if not cameraState then return end

	-- make sure if last camera state minimized minimap to unminimize it
	-- overview camera hides minimap
	if GetConfigInt("MinimapMinimize", 0) == 0 then
		SendCommands("minimap minimize 0")
	end

	SetCameraState(cameraState, 0)

	return true
end

function FocusCameraAnchor(_, _, args)
	Index=tonumber(args[1])
	Log(Index.." Keybind")
	FocusCameraAnchorIntern()


	return true
end
