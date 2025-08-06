VFS.Include('luaui/Headers/keysym.h.lua')
local debugUtilities = VFS.Include('common/springUtilities/debug.lua')

function table.echo(tbl)
  debugUtilities.TableEcho(tbl)
end

function table.tostring2(tbl)
  Spring.Debug.TableEcho(tbl)
end

-- use this for debugging:
function table.val_to_str2 ( v )
  if "string" == type( v ) then
    v = string.gsub( v, "\n", "\\n" )
    if string.match( string.gsub(v,"[^'\"]",""), '^"+$' ) then
      return "'" .. v .. "'"
    end
    return '"' .. string.gsub(v,'"', '\\"' ) .. '"'
  else
    return "table" == type( v ) and table.tostring( v ) or
      tostring( v )
  end
end

function table.key_to_str2 ( k )
  if "string" == type( k ) and string.match( k, "^[_%a][_%a%d]*$" ) then
    return k
  else
    return "[" .. table.val_to_str2( k ) .. "]"
  end
end

function table.tostring3( tbl )
  local result, done = {}, {}
  for k, v in ipairs( tbl ) do
    table.insert( result, table.val_to_str2( v ) )
    done[ k ] = true
  end
  for k, v in pairs( tbl ) do
    if not done[ k ] then
      table.insert( result,
        table.key_to_str2( k ) .. "=" .. table.val_to_str2( v ) )
    end
  end
  return "{" .. table.concat( result, "," ) .. "}"
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


-- SECTION OOP
-- SECTION LRU Cache class
LRUCache = {}
LRUCache.__index = LRUCache

-- Constructor
function LRUCache:new(max_size)
    local cache = {
        max_size = max_size or 10, -- Default max size to 10 if not specified
        cache = {},                -- Key-Value store (uID -> value = radius)
        order = {}                 -- To track the order of use (most recent at the end)
    }
    setmetatable(cache, LRUCache)
    return cache
end

-- Get a value by uID
function LRUCache:get(uID)
    local value = self.cache[uID]
    if value then
        -- Move the accessed uID to the end to mark it as most recently used
        self:moveToEnd(uID)
        return value
    else
        return nil -- uID not found
    end
end

-- Put a uID and value into the cache
function LRUCache:put(uID, value)
    if self.cache[uID] then
        -- If uID already exists, just update and mark it as recently used (should never be the case)
        self.cache[uID] = value
        self:moveToEnd(uID)
    else
        -- Add new uID-value pair
        if #self.order >= self.max_size then
            -- Cache is full, remove the least recently used item
            local lru = table.remove(self.order, 1)
            self.cache[lru] = nil
        end
        table.insert(self.order, uID)
        self.cache[uID] = value
    end
end

-- Helper function to move uID to the end of the order list
function LRUCache:moveToEnd(uID)
    for i, id in ipairs(self.order) do
        if id == uID then
            table.remove(self.order, i)
            break
        end
    end
    table.insert(self.order, uID)
end
-- !SECTION LRU Cache
-- !SECTION OOP



-- SECTION OOP
-- SECTION LRU Cache class
LRUCacheTable = {}
LRUCacheTable.__index = LRUCacheTable

-- Helper function to serialize a key (table with 3 elements) into a string
local function serializeKey(key)
    -- Assuming the key is a table with exactly 3 items
    return table.concat(key, "-")
end

-- Constructor
function LRUCacheTable:new(max_size)
    local cache = {
        max_size = max_size or 10, -- Default max size to 10 if not specified
        cache = {},                -- Key-Value store (serialized key -> value)
        order = {}                 -- To track the order of use (most recent at the end)
    }
    setmetatable(cache, LRUCacheTable)
    return cache
end

-- Get a value by key (which is a table with 3 elements)
function LRUCacheTable:get(key)
    local serializedKey = serializeKey(key)
    local value = self.cache[serializedKey]
    if value then
        -- Move the accessed key to the end to mark it as most recently used
        self:moveToEnd(serializedKey)
        return value
    else
        return nil -- Key not found
    end
end

-- Put a key (table with 3 elements) and value into the cache
function LRUCacheTable:put(key, value)
    local serializedKey = serializeKey(key)

    if self.cache[serializedKey] then
        -- If key already exists, just update and mark it as recently used
        self.cache[serializedKey] = value
        self:moveToEnd(serializedKey)
    else
        -- Add new key-value pair
        if #self.order >= self.max_size then
            -- Cache is full, remove the least recently used item
            local lru = table.remove(self.order, 1)
            self.cache[lru] = nil
        end
        table.insert(self.order, serializedKey)
        self.cache[serializedKey] = value
    end
end

-- Helper function to move the serialized key to the end of the order list
function LRUCacheTable:moveToEnd(serializedKey)
    for i, id in ipairs(self.order) do
        if id == serializedKey then
            table.remove(self.order, i)
            break
        end
    end
    table.insert(self.order, serializedKey)
end
-- !SECTION LRU Cache
-- !SECTION OOP
