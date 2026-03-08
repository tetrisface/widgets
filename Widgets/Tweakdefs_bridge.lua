function widget:GetInfo()
    return {
        name = "Tweakdefs Bridge",
        desc = "A helper Widget to rename unit names and descriptions with prefixes or full names from infolog. Alt+M: Toggle custom names (Triggers UI Reload).",
        author = 'Ambo',
        date = '2026-02-08',
        license = 'GNU GPL, v3 or later',
        layer = -999998,
        version = 5,
        enabled = true,
    }
end

local infolog = "infolog.txt"
local renamesActive = true

local instructions = {}



local function get_start_position(f)
	local line = f:read("*l")
	local latest_start_position = 0
	while (line) do
		if string.find(line,"tweakdefs_rename_get_ready") then
			latest_start_position =f:seek("cur", 0)
		end
		line = f:read("*l")
	end
	return latest_start_position
end

local function extract_instructions()
  local f = assert(io.open(infolog, "rb"))
  local size = f:seek("end")
  local cache = 1000000

  if size < cache then
  	f:seek("set")
  else
  	f:seek("end", -cache)
  end

  local start_position = get_start_position(f)

  f:seek("end", start_position-size)
  local line = f:read("*l")
  local pattern = "/%(([^/]+)/%-([^/]+)/%-([^/]+)/%)"
  instructions = {}
  local temp = {}
  while (line and not string.find(line,"tweakdefs_rename_end")) do
  	for w1, w2, w3 in string.gmatch(line, pattern) do
      if w2 == "rename" or w2 == "prefix" or w2 == "desc_prefix" or w2 == "desc_change" then
  		  table.insert(temp, {w1, w2, w3})
      end
  	end
  	line = f:read("*l")
  end
  instructions = temp
  
end


local function patchNames()
  if not instructions or #instructions == 0 then  
    Spring.Echo("TDB_testing: instructions is empty or nil ".. #instructions)
    return  
  end  
  for i, entry in pairs(instructions) do
    for i2, ud in pairs(UnitDefs) do
      if ud.name == entry[1] then
        if renamesActive then
          if entry[2] == "rename" then
            if not ud._originalHumanName then ud._originalHumanName = ud.translatedHumanName end
             ud.translatedHumanName = entry[3]
          elseif entry[2] == "prefix" then
              if not ud._originalHumanName then ud._originalHumanName = ud.translatedHumanName end
              ud.translatedHumanName = entry[3] .. " " .. ud._originalHumanName
          elseif entry[2] == "desc_change" then
              if not ud._originalTranslatedTooltip then ud._originalTranslatedTooltip = ud.translatedTooltip end
              ud.translatedTooltip = entry[3]
          elseif entry[2] == "desc_prefix" then
              if not ud._originalTranslatedTooltip then ud._originalTranslatedTooltip = ud.translatedTooltip end
              ud.translatedTooltip = entry[3] .. " " .. ud._originalTranslatedTooltip
          end
        else
          if ud._originalHumanName then
            ud.translatedHumanName = ud._originalHumanName
          end
          if ud._originalTranslatedTooltip then
            ud.translatedTooltip = ud._originalTranslatedTooltip
          end
        end
      end
    end
  end
end

local function toggle()
    renamesActive = not renamesActive
    -- Config is saved automatically on reload. 
    -- The reload forces every widget to re-initialize and see the new names.
    Spring.SendCommands("luaui reload")
end

function widget:Initialize()
    extract_instructions()
    patchNames()
end

function widget:LanguageChanged()
    patchNames()
end

function widget:KeyPress(key, mods, isRepeat)
    if not isRepeat and key == 109 and mods.alt then
        toggle()
        return true
    end
    return false
end

function widget:GetConfigData()
    return { renamesActive = renamesActive }
end

function widget:SetConfigData(data)
    if data and data.renamesActive ~= nil then
        renamesActive = data.renamesActive
    end
end