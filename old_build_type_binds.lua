function widget:GetInfo()
  return {
    name = "(old) Build type binds (zxcv)",
    desc = "Nothing is copied from anywhere ʘ‿ʘ",
    author = "his_face",
    date = "mar, 2018",
    license = "GNU GPL, v2 or later",
    layer = 99,
    enabled = false
  }
end

local SendCommands = Spring.SendCommands
local TraceScreenRay = Spring.TraceScreenRay
local GetMouseState = Spring.GetMouseState
local GetCmdDescIndex = Spring.GetCmdDescIndex
local SetActiveCommand = Spring.SetActiveCommand
local GetSelectedUnits = Spring.GetSelectedUnits
local GetUnitDefID = Spring.GetUnitDefID
local log = Spring.Echo
local UnitDefs = UnitDefs

local current_bo_index = 0
local selectedUnits
local buildOptionMap = {}
local udefid_max
local udefid_min
local current_udefid

-- mods -> maps -> unitds -> popularity
local unit_usage = {}
local unit_usage_path = 'build_type_binds_unit_usages.blob'

local terrain_categories = {
  'all',
  'ground',
  'water',
}

local type_categories = {
  'metal',
  'energy',
  'military',
  'construction',
}

local previous_type = type_categories[1]

local keys = {
  [122] = type_categories[1],
  [120] = type_categories[2],
  [99] = type_categories[3],
  [118] = type_categories[4],
}


function save_usage(udefid)
  if not udefid then
    return
  end
  --  unit_usage.all.all[udefid] = unit_usage.all.all[udefid] and unit_usage.all.all[udefid] + 1 or 1
  unit_usage[udefid] = unit_usage[udefid] and unit_usage[udefid] + 1 or 1
--  log(UnitDefs[udefid].humanName, unit_usage[udefid])
  table.save(unit_usage, unit_usage_path)
end

function widget:Initialize()
  --  if Spring.GetSpectatingState() or Spring.IsReplay() then
  --    widgetHandler:RemoveWidget()
  --  end

  unbind()

  load_usages()

  for source_udefid, source_def in pairs(UnitDefs) do
    local build_options = table_unique(source_def.buildOptions)

    udefid_min = math.min(source_udefid, udefid_min or source_udefid)
    udefid_max = math.max(source_udefid, udefid_max or source_udefid)

    table.sort(build_options, function(a, b)
      return (unit_usage[a] or 0) > (unit_usage[b] or 0)
    end)

    --    if source_udefid == 90 then
    --      log(str_table(build_options))
    --      log(str_table(table_unique(build_options)))
    --    end

    for i = 1, #build_options do
      local target_udefid = build_options[i]
      local target_udef = UnitDefs[build_options[i]]
      --      log('bo', i, #bo, target_udef.humanName)

      if (target_udef.metalMake > 0 or
              target_udef.makesMetal > 0 or
              target_udef.metalStorage > 0 or
              getMetalMakingEfficiency(target_udefid) > 0 or
              target_udef.extractsMetal > 0) and target_udef.buildSpeed == 0 and #target_udef.weapons == 0 then
        save_to_build_option_map(source_udefid, type_categories[1], target_udefid, target_udef)
      end
      if (target_udef.energyStorage > 0 or
              target_udef.windGenerator > 0 or
              target_udef.tidalGenerator > 0 or
              target_udef.energyMake > 0) and target_udef.buildSpeed == 0 and #target_udef.weapons == 0 then
        save_to_build_option_map(source_udefid, type_categories[2], target_udefid, target_udef)
      end
      if (target_udef.radarRadius > 0 or
              target_udef.sonarRadius > 0 or
              target_udef.jammerRadius > 0 or
              target_udef.sonarJamRadius > 0 or
              target_udef.stealth or
              target_udef.sonarStealth or
              target_udef.seismicRadius > 0 or
              target_udef.canCloak or
              #target_udef.weapons > 0) and #target_udef.buildOptions == 0 then
        save_to_build_option_map(source_udefid, type_categories[3], target_udefid, target_udef)
      end
      if target_udef.isBuilder or
              target_udef.buildSpeed > 0 or
              #target_udef.buildOptions > 0 then
        save_to_build_option_map(source_udefid, type_categories[4], target_udefid, target_udef)
      end
    end

    --    buildOptionMapSourceIds[#buildOptionMapSourceIds + 1] = source_udefid
    sort_bo_map()
  end
end

function load_usages()
  unit_usage = table.load(unit_usage_path) or {}
end


function sort_metal(a, b)
  return (a.udef.extractsMetal * 100 + getMetalMakingEfficiency(a.id)) > (b.udef.extractsMetal * 100 + getMetalMakingEfficiency(b.id))
end

function sort_energy(a, b)
  return a.udef.energyMake / a.udef.power > b.udef.energyMake / b.udef.power
end

function sort_construction(a, b)
  return a.udef.buildDistance > b.udef.buildDistance
end

function sort_military(a, b)
  -- crashes spring
  --  return (a.udef.weapons[1] == nil and 0 or 100) > (b.udef.weapons[1] == nil and 0 or 100)
  return a.udef.health > b.udef.health
end


function sort_bo_map()
  for _, map in pairs(buildOptionMap) do
    --  for n = 1, #buildOptionMapSourceIds do
    --    local map = buildOptionMap[buildOptionMapSourceIds[n]]
    if map ~= nil then
      for i = 1, #terrain_categories do
--        table.sort(map.metal[terrain_categories[i]], sort_metal)
--        table.sort(map.energy[terrain_categories[i]], sort_energy)
        --        table.sort(map.military[terrain_categories[i]], sort_military)
--        table.sort(map.construction[terrain_categories[i]], sort_construction)
      end
    end
  end
end


function deepcopy(orig)
  local orig_type = type(orig)
  local copy
  if orig_type == 'table' then
    copy = {}
    for orig_key, orig_value in next, orig, nil do
      copy[deepcopy(orig_key)] = deepcopy(orig_value)
    end
    setmetatable(copy, deepcopy(getmetatable(orig)))
  else -- number, string, boolean, etc
    copy = orig
  end
  return copy
end


--function save_to_global_sort(category, target_udefid, target_udef)
--  global_sort[category] = global_sort[category] or {}
--  global_sort[category][target_udefid] = {
--    id = target_udefid,
--    udef = target_udef
--  }
--end

function save_to_build_option_map(source_udefid, category, target_udefid, target_udef)
  local terrain_types = {
    all = {},
    ground = {},
    water = {},
  }
  buildOptionMap[source_udefid] = buildOptionMap[source_udefid] or {
    metal = deepcopy(terrain_types),
    energy = deepcopy(terrain_types),
    military = deepcopy(terrain_types),
    construction = deepcopy(terrain_types),
  }
  local bo = {
    parent_id = source_udefid,
    id = target_udefid,
    udef = target_udef,
    usage_count = unit_usage[target_udefid]
  }
  local all = buildOptionMap[source_udefid][category].all
  all[#all + 1] = bo
  if target_udef.minWaterDepth < 0 then
    local ground = buildOptionMap[source_udefid][category].ground
    ground[#ground + 1] = bo
  end
  if target_udef.minWaterDepth > 0 then
    local water = buildOptionMap[source_udefid][category].water
    water[#water + 1] = bo
  end
end

-- selection changed?
function widget:CommandsChanged()
  reset()
end

function widget:MousePress(x, y, button)
  mouse_action(button)
end

function widget:MouseRelease(x, y, button)
  mouse_action(button)
end

function reset()
  current_bo_index = 0
  current_udefid = nil
end

function mouse_action(button)
  if button == 1 then
    save_usage(current_udefid)
  end
  reset()
end


function widget:KeyPress(key, mods, isRepeat)

  local build_type = keys[key]
  if key == 27 then
    reset()
  elseif build_type ~= nil and not mods['ctrl'] then
    local selected = GetSelectedUnits()

    local currentPower = 0
    local hasCon = false
    local currentUdefId
    local done_udefids = {}

    for i = 1, #selected do
      local udefid = GetUnitDefID(selected[i])

      if not done_udefids[udefid] and buildOptionMap[udefid] then
        local udef = UnitDefs[udefid]
        local power = udef.power

        -- prio moving units, then by power
        if hasCon and udef.speed > 0 and power > currentPower then
          currentUdefId = udefid
          currentPower = power
        elseif not hasCon and power > currentPower then
          currentUdefId = udefid
          currentPower = power
          hasCon = udef.speed > 0
        elseif not hasCon and udef.speed > 0 then
          currentUdefId = udefid
          currentPower = power
          hasCon = true
        end
      end
      done_udefids[udefid] = true
    end
    if currentUdefId ~= nil then
      cycle_bo(currentUdefId, build_type, mods['shift'])
    end
  end
end

function cycle_bo(udefid, type, reverse)
  local elevation = get_elevation()
  local terrain = terrain_categories[1]

  if elevation ~= nil then
    if elevation > 0 then
      terrain = terrain_categories[2]
    else
      terrain = terrain_categories[3]
    end
  end

  local bos = buildOptionMap[udefid][type][terrain]
  if bos == nil or #bos == 0 then
    return
  end

--  log('cycle bo', UnitDefs[udefid].humanName, type, current_bo_index, bos)
  if type ~= previous_type then
    current_bo_index = 1
  else
    current_bo_index = current_bo_index + (reverse and -1 or 1)

    --  log('bos count', type, terrain, #bos)
    if current_bo_index > #bos then
      current_bo_index = 1
    elseif current_bo_index < 1 then
      current_bo_index = #bos
    end
  end
  previous_type = type

  --  log('bos', type, terrain, #bos, current_bo_index)
  --  log('bos', type, terrain, #bos, bos[current_bo_index].udef.humanName)

  --  log('SetActiveCommand', 'bos[i]', bos[current_bo_index].id)
  current_udefid = bos[current_bo_index].id
  --  log('current_bo_index', current_bo_index, current_udefid, GetCmdDescIndex(-current_udefid), bos[current_bo_index].udef.name)
  --  log('buildunit_' .. bos[current_bo_index].udef.name)
  --  Spring.SetActiveCommand('buildunit_' .. bos[current_bo_index].udef.name)
  --  Spring.SetActiveCommand(-bos[current_bo_index].id)
--  log('cycled from', udefid, 'to', current_udefid)
  Spring.SetActiveCommand(GetCmdDescIndex(-current_udefid))
end

function get_elevation()
  local mouseX, mouseY = GetMouseState()
  local desc, coords = TraceScreenRay(mouseX, mouseY, true)

  if desc == nil then
    return nil
  end

  return coords[3]
end

function getMetalMakingEfficiency(unitDefID)
  if not WG.energyConversion then
    log("Widget: build_type_binds.lua needs WG.energyConversion to function properly. Try enabling widget 'Energy Conversion Info'")
    return 0
  end
  if not unitDefID then
    return 0
  end
  local makerDef = WG.energyConversion.convertCapacities[unitDefID]
  if makerDef ~= nil then
    return makerDef.e
  else
    return 0
  end
end

-- for debug
function table.has_value(tab, val)
  for i = 1, #tab do
    if tab[i] == val then
      return true
    end
  end
  return false
end

function table.full_of(tab, val)
  for i = 1, #tab do
    if tab[i] ~= val then
      return false
    end
  end
  return true
end

-- for printing tables
function table.val_to_str(v)
  if "string" == type(v) then
    v = string.gsub(v, "\n", "\\n")
    if string.match(string.gsub(v, "[^'\"]", ""), '^"+$') then
      return "'" .. v .. "'"
    end
    return '"' .. string.gsub(v, '"', '\\"') .. '"'
  else
    return "table" == type(v) and table.tostring(v) or tostring(v)
  end
end

function table.key_to_str(k)
  if "string" == type(k) and string.match(k, "^[_%a][_%a%d]*$") then
    return k
  else
    return "[" .. table.val_to_str(k) .. "]"
  end
end

function table_unique(items)
  local flags = {}
  local newtable = {}
  for i = 1, #items do
    local item = items[i]
    if not flags[item] then
      newtable[#newtable + 1] = item
      flags[item] = true
    end
  end
  return newtable
end

function str_table(tbl)
  return table.tostring(tbl)
end

function table.tostring(tbl)
  local result, done = {}, {}
  if type(elem) ~= 'table' then
    return tbl
  end
  for k, v in ipairs(tbl) do
    table.insert(result, table.val_to_str(v))
    done[k] = true
  end
  for k, v in pairs(tbl) do
    if not done[k] then
      table.insert(result, table.key_to_str(k) .. "=" .. table.val_to_str(v))
    end
  end
  return "{" .. table.concat(result, ",") .. "}"
end




-- serialization

-- declare local variables
--// exportstring( string )
--// returns a "Lua" portable version of the string
local function exportstring(s)
  return string.format("%q", s)
end

--// The Save Function
function table.save(tbl, filename)
  local charS, charE = "   ", "\n"
  local file, err = io.open(filename, "wb")
  if err then return err end

  -- initiate variables for save procedure
  local tables, lookup = { tbl }, { [tbl] = 1 }
  file:write("return {" .. charE)

  for idx, t in ipairs(tables) do
    file:write("-- Table: {" .. idx .. "}" .. charE)
    file:write("{" .. charE)
    local thandled = {}

    for i, v in ipairs(t) do
      thandled[i] = true
      local stype = type(v)
      -- only handle value
      if stype == "table" then
        if not lookup[v] then
          table.insert(tables, v)
          lookup[v] = #tables
        end
        file:write(charS .. "{" .. lookup[v] .. "}," .. charE)
      elseif stype == "string" then
        file:write(charS .. exportstring(v) .. "," .. charE)
      elseif stype == "number" then
        file:write(charS .. tostring(v) .. "," .. charE)
      end
    end

    for i, v in pairs(t) do
      -- escape handled values
      if (not thandled[i]) then

        local str = ""
        local stype = type(i)
        -- handle index
        if stype == "table" then
          if not lookup[i] then
            table.insert(tables, i)
            lookup[i] = #tables
          end
          str = charS .. "[{" .. lookup[i] .. "}]="
        elseif stype == "string" then
          str = charS .. "[" .. exportstring(i) .. "]="
        elseif stype == "number" then
          str = charS .. "[" .. tostring(i) .. "]="
        end

        if str ~= "" then
          stype = type(v)
          -- handle value
          if stype == "table" then
            if not lookup[v] then
              table.insert(tables, v)
              lookup[v] = #tables
            end
            file:write(str .. "{" .. lookup[v] .. "}," .. charE)
          elseif stype == "string" then
            file:write(str .. exportstring(v) .. "," .. charE)
          elseif stype == "number" then
            file:write(str .. tostring(v) .. "," .. charE)
          end
        end
      end
    end
    file:write("}," .. charE)
  end
  file:write("}")
  file:close()
end

--// The Load Function
function table.load(sfile)
  local ftables, err = loadfile(sfile)
  if err then return _, err end
  local tables = ftables()
  if not tables then return nil end
  for idx = 1, #tables do
    local tolinki = {}
    for i, v in pairs(tables[idx]) do
      if type(v) == "table" then
        tables[idx][i] = tables[v[1]]
      end
      if type(i) == "table" and tables[i[1]] then
        table.insert(tolinki, { i, tables[i[1]] })
      end
    end
    -- link indices
    for _, v in ipairs(tolinki) do
      tables[idx][v[2]], tables[idx][v[1]] = tables[idx][v[1]], nil
    end
  end
  return tables[1]
end



local techa_unbinds = {
  -- building hotkeys
  "bind any+b buildspacing inc",
  "bind any+n buildspacing dec",
  "bind any+q controlunit",
  "bind z buildunit_armmex",
  "bind shift+z buildunit_armmex",
  "bind z buildunit_tllmex",
  "bind shift+z buildunit_tllmex",
  "bind z buildunit_armamex",
  "bind shift+z buildunit_armamex",
  "bind z buildunit_cormex",
  "bind shift+z buildunit_cormex",
  "bind z buildunit_corexp",
  "bind shift+z buildunit_corexp",
  "bind z buildunit_armmoho",
  "bind shift+z buildunit_armmoho",
  "bind z buildunit_cormoho",
  "bind shift+z buildunit_cormoho",
  "bind z buildunit_tllamex",
  "bind shift+z buildunit_tllamex",
  "bind z buildunit_cormexp",
  "bind shift+z buildunit_cormexp",
  "bind z buildunit_coruwmex",
  "bind shift+z buildunit_coruwmex",
  "bind z buildunit_armuwmex",
  "bind shift+z buildunit_armuwmex",
  "bind z buildunit_tlluwmex",
  "bind shift+z buildunit_tlluwmex",
  "bind z buildunit_coruwmme",

  "bind shift+z buildunit_coruwmme",
  "bind z buildunit_armuwmme",
  "bind shift+z buildunit_armuwmme",
  "bind z buildunit_tllauwmex",
  "bind shift+z buildunit_tllauwmex",

  "bind x buildunit_armsolar",
  "bind shift+x buildunit_armsolar",
  "bind x buildunit_armwin",
  "bind shift+x buildunit_armwin",
  "bind x buildunit_corsolar",
  "bind shift+x buildunit_corsolar",
  "bind x buildunit_corwin",
  "bind shift+x buildunit_corwin",
  "bind x buildunit_tllwindtrap",
  "bind shift+x buildunit_tllwindtrap",
  "bind x buildunit_tllsolar",
  "bind shift+x buildunit_tllsolar",

  "bind x buildunit_armadvsol",
  "bind shift+x buildunit_armadvsol",
  "bind x buildunit_coradvsol",
  "bind shift+x buildunit_coradvsol",
  "bind x buildunit_tlladvsolar",
  "bind shift+x buildunit_tlladvsolar",

  "bind x buildunit_armfus",
  "bind shift+x buildunit_armfus",
  "bind x buildunit_armmmkr",
  "bind shift+x buildunit_armmmkr",
  "bind x buildunit_corfus",
  "bind shift+x buildunit_corfus",

  "bind x buildunit_cormmkr",
  "bind shift+x buildunit_cormmkr",
  "bind x buildunit_tllmedfusion",
  "bind shift+x buildunit_tllmedfusion",
  "bind x buildunit_tllcoldfus",
  "bind shift+x buildunit_tllcoldfus",

  --Adv eco
  "bind z buildunit_armmex1",
  "bind shift+z buildunit_armmex1",
  "bind z buildunit_cormex1",
  "bind shift+z buildunit_cormex1",
  "bind x buildunit_armgen",
  "bind shift+x buildunit_armgen",
  "bind x buildunit_corgen",
  "bind shift+x buildunit_corgen",

  "bind x buildunit_armamaker",
  "bind shift+x buildunit_armamaker",
  "bind x buildunit_coramaker",
  "bind shift+x buildunit_coramaker",
  "bind x buildunit_armawin",
  "bind shift+x buildunit_armawin",
  "bind x buildunit_corawin",
  "bind shift+x buildunit_corawin",
  "bind x buildunit_armlightfus",
  "bind shift+x buildunit_armlightfus",
  "bind x buildunit_corlightfus",
  "bind shift+x buildunit_corlightfus",
  "bind x buildunit_armatidal",
  "bind shift+x buildunit_armatidal",
  "bind x buildunit_coratidal",
  "bind shift+x buildunit_armatidal",
  "bind x buildunit_armuwlightfus",
  "bind shift+x buildunit_armuwlightfus",
  "bind x buildunit_coruwlightfus",
  "bind shift+x buildunit_coruwlightfus",

  "bind x buildunit_armtide",
  "bind shift+x buildunit_armtide",
  "bind x buildunit_cortide",
  "bind shift+x buildunit_cortide",
  "bind x buildunit_tllatide",
  "bind shift+x buildunit_tllatide",

  "bind x buildunit_armuwfus",
  "bind shift+x buildunit_armuwfus",
  "bind x buildunit_coruwfus",
  "bind shift+x buildunit_coruwfus",
  "bind x buildunit_tlluwfusion",
  "bind shift+x buildunit_tlluwfusion",

  "bind x buildunit_armuwmmm",
  "bind shift+x buildunit_armuwmmm",
  "bind x buildunit_coruwmmm",
  "bind shift+x buildunit_coruwmmm",
  "bind x buildunit_tllwmmohoconv",
  "bind shift+x buildunit_tllwmmohoconv",

  "bind c buildunit_armllt",
  "bind shift+c buildunit_armllt",
  "bind c buildunit_tllweb",
  "bind shift+c buildunit_tllweb",
  "bind c buildunit_tllrad",
  "bind shift+c buildunit_tllrad",
  "bind c buildunit_armrad",
  "bind shift+c buildunit_armrad",
  "bind c buildunit_corllt",
  "bind shift+c buildunit_corllt",
  "bind c buildunit_corrad",
  "bind shift+c buildunit_corrad",

  "bind c buildunit_corrl",
  "bind shift+c buildunit_corrl",
  "bind c buildunit_armrl",
  "bind shift+c buildunit_armrl",
  "bind c buildunit_armrl",
  "bind shift+c buildunit_armrl",
  "bind c buildunit_tlllmt",
  "bind shift+c buildunit_tlllmt",

  "bind c buildunit_armpb",
  "bind shift+c buildunit_armpb",
  "bind c buildunit_armflak",
  "bind shift+c buildunit_armflak",
  "bind c buildunit_corvipe",
  "bind shift+c buildunit_corvipe",
  "bind c buildunit_corflak",
  "bind shift+c buildunit_corflak",
  "bind c buildunit_tllpulaser",
  "bind shift+c buildunit_tllpulaser",
  "bind c buildunit_tllflak",
  "bind shift+c buildunit_tllflak",

  "bind c buildunit_armtl",
  "bind shift+c buildunit_armtl",
  "bind c buildunit_cortl",
  "bind shift+c buildunit_cortl",
  "bind c buildunit_tllshoretorp",
  "bind shift+c buildunit_tllshoretorp",

  "bind c buildunit_armsonar",
  "bind shift+c buildunit_armsonar",
  "bind c buildunit_corsonar",
  "bind shift+c buildunit_corsonar",
  "bind c buildunit_tllsonar",
  "bind shift+c buildunit_tllsonar",

  "bind c buildunit_armfrad",
  "bind shift+c buildunit_armfrad",
  "bind c buildunit_corfrad",
  "bind shift+c buildunit_corfrad",
  "bind c buildunit_tllradarns",
  "bind shift+c buildunit_tllradarns",


  "bind c buildunit_armfrt",
  "bind shift+c buildunit_armfrt",
  "bind c buildunit_corfrt",
  "bind shift+c buildunit_corfrt",
  "bind c buildunit_tlllmtns",
  "bind shift+c buildunit_tlllmtns",


  "bind v buildunit_cornanotc",
  "bind shift+v buildunit_cornanotc",
  "bind v buildunit_armnanotc",
  "bind shift+v buildunit_armnanotc",
  "bind v buildunit_tllnanotc",
  "bind shift+v buildunit_tllnanotc",

  "bind v buildunit_armlab",
  "bind shift+v buildunit_armlab",
  "bind v buildunit_armvp",
  "bind shift+v buildunit_armvp",

  "bind v buildunit_corlab",
  "bind shift+v buildunit_corlab",
  "bind v buildunit_corvp",
  "bind shift+v buildunit_corvp",

  "bind v buildunit_tlllab",
  "bind shift+v buildunit_tlllab",
  "bind v buildunit_tllvp",
  "bind shift+v buildunit_tllvp",

  "bind v buildunit_armsy",
  "bind shift+v buildunit_armsy",
  "bind v buildunit_corsy",
  "bind shift+v buildunit_corsy",
  "bind v buildunit_tllsy",
  "bind shift+v buildunit_tllsy",
}


function unbind()
  for i = 1, #techa_unbinds do
    SendCommands("un" .. techa_unbinds[i])
  end
end
