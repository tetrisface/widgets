std = {
  globals = { -- std extensions
    "math.round", "math.bit_or", "math.diag", "math.cross_product", "math.triangulate",
    "table.ifind", "table.show", "table.save", "table.echo", "table.print",
    -- Spring
    "Spring", "VFS", "gl", "GL", "Game",
    "UnitDefs", "UnitDefNames", "FeatureDefs", "FeatureDefNames",
    "WeaponDefs", "WeaponDefNames", "LOG", "KEYSYMS", "CMD", "Script",
    "SendToUnsynced", "Platform", "Engine", "include", "COB",
    -- GL
    "GL_TEXTURE_2D", "GL_HINT_BIT",
    -- Gadgets
    "GG", "gadgetHandler", "gadget",
    -- Widgets
    "WG", "widgetHandler", "widget", "LUAUI_DIRNAME", "self",
    -- Chili
    "Chili", "Checkbox", "Control", "ComboBox", "Button", "Label",
    "Line", "EditBox", "Font", "Window", "ScrollPanel", "LayoutPanel",
    "Panel", "StackPanel", "Grid", "TextBox", "Image", "TreeView", "Trackbar",
    "DetachableTabPanel", "screen0", "Progressbar",
    -- Libs
    -- "LCS", "Path", "Table", "Log", "String", "Shaders", "Time", "Array", "StartScript",

    "CMDTYPE", "COBSCALE", "CallAsTeam", "SYNCED", "loadlib",
    'log',
    'string',
    'table',
    'tostring',
    'tonumber',
    'ipairs',
    'pairs',
    'select',
    'math'
  },                -- these globals can be set and accessed.
  read_globals = {} -- these globals can only be accessed.
}
max_line_length = 333
