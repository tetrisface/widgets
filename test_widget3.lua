function widget:GetInfo()
    return {
        name = "test widget3",
        desc = "",
        author = "",
        date = "",
        license = "GNU GPL, v2 or later",
        layer = -9,
        enabled = true --  loaded by default?
    }
end

function widget:Initialize()
    Spring.Echo("test widget3 initialized")
end
