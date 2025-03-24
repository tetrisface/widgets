function widget:GetInfo()
  return {
    name = "CMD Build Spacing",
    desc = "",
    author = "-",
    date = "jul, 2024",
    license = "GNU GPL, v3 or later",
    layer = 99,
    enabled = true
  }
end

VFS.Include('luaui/Widgets/.noload/misc/helpers.lua')
VFS.Include('luaui/Headers/keysym.h.lua')

local decrease = KEYSYMS.A
local increase = KEYSYMS.S

function widget:Initialize()
  if Spring.GetSpectatingState() or Spring.IsReplay() then
    widgetHandler:RemoveWidget()
  end
end

local n = 0
function widget:KeyPress(key, mods, isRepeat)
  -- n = n + 1
  -- log('key', key, 'isRepeat', isRepeat, 'n', n)
  if (key == decrease or key == increase) and mods['alt'] then -- 'd' shift from queue
    -- active command
    local _, buildingDefId = Spring.GetActiveCommand()

    if not buildingDefId or buildingDefId >= 0 then
      return
    end

    local unitDef = UnitDefs[-buildingDefId]

    local size = math.min(unitDef.xsize, unitDef.zsize) / 2

    local spacing = Spring.GetBuildSpacing()
    local change = key == decrease and -1 or 1
    spacing = spacing + change * size
    spacing = math.floor(spacing / size + 0.5) * size
    Spring.SetBuildSpacing(spacing)
  end
end
