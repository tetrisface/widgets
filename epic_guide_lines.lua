function widget:GetInfo()
    return {
        desc    = "Lots of code from gui_build_costs.lua by Milan Satala and also some from ecostats.lua by Jools, iirc",
        author  = "tetrisface",
        version = "",
        date    = "feb, 2016",
        name    = "cons",
        license = "",
        layer   = -99990,
        enabled = true,
    }
end

local NewSetList = VFS.Include('common/SetList.lua').NewSetList
VFS.Include('luaui/Widgets/helpers.lua')
