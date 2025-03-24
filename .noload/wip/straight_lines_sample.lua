function widget:GetInfo()
  return {
    desc = 'Ability to draw straight lines.',
    author  = 'tetrisface',
    version = '',
    date    = '2024-02-23',
    name    = 'Straight Lines sample',
    license = 'GPLv2 or later',
    layer   = -99990,
    enabled = true,
    depends = {'gl4'},
  }
end


VFS.Include('luaui/Headers/keysym.h.lua')

local isActiveFirst   = false
local isActiveShift   = false

function widget:Initialize()
  isActiveFirst     = false
  isActiveShift     = false
end

function widget:KeyPress(key, mods, isRepeat)
  if isRepeat then
    return
  end
  Spring.Echo('KeyPress',key, mods['shift'], mods['ctrl'], mods['alt'])
  if key == KEYSYMS.FIRST then
    isActiveFirst = true
  end
  if key == KEYSYMS.LSHIFT or mods['shift'] then
    isActiveShift = true
  end
end
function widget:KeyRelease(key, mods, releasedFromString)
  Spring.Echo('KeyRelease', key, mods['shift'], mods['ctrl'], mods['alt'], releasedFromString)
  if key == KEYSYMS.FIRST then
    isActiveFirst = false
  end
  if key == KEYSYMS.LSHIFT then
    isActiveShift = false
  end
  return true
end

function widget:MousePress(x, y, button)
  Spring.Echo('draw?', isActiveFirst, isActiveShift)
end
