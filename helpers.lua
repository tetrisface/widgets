VFS.Include('luaui/Headers/keysym.h.lua')
local debugUtilities = VFS.Include('common/springUtilities/debug.lua')

function table.echo(tbl)
  debugUtilities.TableEcho(tbl)
end

local logGameFrame = false
if logGameFrame then
  log = function(a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v) Spring.Echo(Spring.GetGameFrame(), a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v) end
else
  log = Spring.Echo
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

function table.has_value(tab, val)
  for _, value in pairs(tab) do
    if value == val then
      return true
    end
  end
  return false
end

function table.full_of(tab, val)
  for _, value in pairs(tab) do
    if value ~= val then
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
    return "table" == type(v) and table.tostring(v) or
        tostring(v)
  end
end

function table.key_to_str(k)
  if "string" == type(k) and string.match(k, "^[_%a][_%a%d]*$") then
    return k
  else
    return "[" .. table.val_to_str(k) .. "]"
  end
end

function table.tostring(tbl)
  if type(tbl) == "string" then
    return tbl
  elseif type(tbl) ~= "table" then
    return tostring(tbl)
  end
  if not tbl then
    return 'nil'
  end
  local result, done = {}, {}
  for k, v in ipairs(tbl) do
    table.insert(result, table.val_to_str(v))
    done[k] = true
  end
  for k, v in pairs(tbl) do
    if not done[k] then
      table.insert(result,
        table.key_to_str(k) .. "=" .. table.val_to_str(v))
    end
  end
  return "{" .. table.concat(result, ",") .. "}"
end
