function widget:GetInfo()
  return {
    name = 'Debug Explodeas',
    desc = 'Prints explodeas attribute of T3/T4 eco units',
    author = 'Debug',
    version = '1.0',
    date = '2026',
    license = 'GNU GPL v2',
    layer = 0,
    enabled = true,
  }
end

function widget:Initialize()
  local units = {
    'armmmkrt3', 'cormmkrt3', 'legadveconvt3',
    'armafust3', 'corafust3', 'legafust3',
    'armmmkrt3_200', 'cormmkrt3_200', 'legadveconvt3_200',
    'armafust3_200', 'corafust3_200', 'legafust3_200',
  }
  for _, name in ipairs(units) do
    local defID = UnitDefNames[name] and UnitDefNames[name].id
    if defID then
      local def = UnitDefs[defID]
      Spring.Echo('[ExplodeAs] ' .. name .. ' = ' .. tostring(def.deathExplosion))
    else
      Spring.Echo('[ExplodeAs] ' .. name .. ' = NOT FOUND')
    end
  end
end
