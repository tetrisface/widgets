function widget:GetInfo()
    return {
        name = "test widget1",
        desc = "",
        author = "",
        date = "",
        license = "GNU GPL, v2 or later",
        layer = -9,
        enabled = true --  loaded by default?
    }
end

local useWaveMsg = VFS.Include('LuaRules/Configs/raptor_spawn_defs.lua').useWaveMsg
local Set        = VFS.Include('common/SetList.lua').NewSetListMin
local fontfile2  = "fonts/" .. Spring.GetConfigString("bar_font2", "Exo2-SemiBold.otf")
local RaptorCommon
if io.open('LuaRules/gadgets/raptors/common.lua', "r") == nil then
    RaptorCommon = {
        EcoValueDef       = EcoValueDef,
        IsValidEcoUnitDef = IsValidEcoUnitDef
    }
else
    RaptorCommon = VFS.Include('LuaRules/gadgets/raptors/common.lua')
end
