if not RmlUi then
    return
end

local widget = widget ---@type Widget
local WIDGET_NAME = "Strategic Construction Tracker"
local MODEL_NAME = "strategic_construction_tracker"
local RML_PATH = "luaui/rmlwidgets/strategic_construction_tracker/strategic_construction_tracker.rml"
local UPDATE_FREQUENCY = 30

function widget:GetInfo()
    return {
        name      = WIDGET_NAME,
        desc      = "Tracks important building construction",
        author    = "H7",
        date      = "2025",
        license   = "GNU GPL, v2 or later",
        layer     = 5,
        enabled   = true,
        handler   = true,
        api       = true,
        allyTeam  = -1,  -- Receive callbacks for all teams to track data regardless of spectator view
    }
end

-- Build categories
local BUILDCAT_ECONOMY = Spring.I18N and Spring.I18N("ui.buildMenu.category_econ") or "Economy"
local BUILDCAT_COMBAT = Spring.I18N and Spring.I18N("ui.buildMenu.category_combat") or "Combat"
local BUILDCAT_UTILITY = Spring.I18N and Spring.I18N("ui.buildMenu.category_utility") or "Utility"
local BUILDCAT_PRODUCTION = Spring.I18N and Spring.I18N("ui.buildMenu.category_production") or "Build"

-- Category icons
local CATEGORY_ICONS = {
	economy = "LuaUI/Images/groupicons/energy.png",
	combat = "LuaUI/Images/groupicons/weapon.png",
	utility = "LuaUI/Images/groupicons/util.png",
	build = "LuaUI/Images/groupicons/builder.png",
}

-- Base list of important buildings/units to track (T2 and strategic units)
local t2TrackedBuildings = {
    -- === FUSION PLANTS ===
    "armfus", "corfus", "legfus",
    "armafus", "corafus", "legafus",
    "armckfus", -- Cloakable Fusion Reactor
    "armuwfus", -- Naval Fusion Reactor

    -- === T2 LABORATORIES ===
    "armalab", "coralab", "legalab",
    "armavp", "coravp", "legavp",
    "armaap", "coraap", "legaap",
    "armasy", "corasy", "legasy",
    "armhalab", "corhalab", "leghalab",
    "armsalab", "corsalab", "legsalab",

    -- === LONG RANGE PLASMA CANNONS ===
    "armlrpc", "corlrpc", "leglrpc",

    -- === NUCLEAR MISSILE SILOS ===
    "armsilo", "corsilo", "legsilo",

    -- === EXPERIMENTAL GANTRIES ===
    "armshltx", "corshltx", "legshltx",
    "armshltxuw", "corshltxuw", "legshltxuw",
    "corgant", -- Cortex Experimental Gantry

    -- === HEAVY ARTILLERY ===
    "armbrtha", "corint", "legbrtha",
    "armvulc", "corbuzz", "legvulc",

    -- === STRATEGIC DEFENSE ===
    "armamd", "corfmd", "legamd",
    "armanni", "cordoom", "leganni",
    "cormabm", -- Mobile Anti-Nuke

    -- === EXPERIMENTAL UNITS ===
    "armthor", "corkrog", "legthor",
    "armstar", "corshw", "legstar",
    "armvang", -- Armada Vanguard
    "corjugg", -- Behemoth

    -- === TACTICAL MISSILE LAUNCHERS ===
    "armemp", "cortron", "legemp",

    -- === RADAR JAMMERS & STEALTH ===
    "legjamt",

    -- === ADVANCED ENERGY CONVERSION ===
    "armmmkr", "cormmkr", "legmmkr",
    "coruwmmm", -- Naval Advanced Energy Converter

    -- === SEAPLANE PLATFORMS ===
    "armplat", "corplat", "legplat",

    -- === AMPHIBIOUS COMPLEXES ===
    "armasp", "corasp", "legasp",

    -- === SPECIAL LEGION UNITS ===
    "leghive", "legaegis", "leganomaly",

    -- === OTHER STRATEGIC BUILDINGS ===
    "armgate", "corgate", "leggate",
    "cortarg", -- Pinpointer

    -- === STRATEGIC AIRCRAFT ===
    "armliche", -- Liche Atomic Bomber
    "corcrw", -- Cortex Dragon

    -- === TRANSPORTS ===
    "armadtlas", -- Stork
    "armhvytrans", -- Osprey
    "corvalk", -- Hercules
    "corhvytrans", -- Hephaestus

    -- === ADDITIONAL STRATEGIC UNITS ===
    "armbanth", "corkarg", "armraz", "corsb",
}

-- Function to dynamically identify T3/T4 units and other strategic units
local function BuildComprehensiveTrackedList()
    local trackedUnits = {}
    
    -- Start with the base T2 list
    for _, unitName in ipairs(t2TrackedBuildings) do
        trackedUnits[unitName] = true
    end
    
    -- Scan all UnitDefs to find T3/T4 units and other strategic units
    for unitDefID, unitDef in pairs(UnitDefs) do
        if unitDef and unitDef.name then
            local shouldTrack = false
            
            -- Check for T3/T4 units based on various criteria
            if unitDef.customParams then
                local unitgroup = unitDef.customParams.unitgroup or ""
                local techlevel = unitDef.customParams.techlevel or ""
                local description = unitDef.customParams.description or ""
                
                -- T3/T4 units typically have techlevel 3 or 4
                if techlevel == "3" or techlevel == "4" then
                    shouldTrack = true
                end
                
                -- Experimental units (often T3/T4)
                if unitgroup:match("experimental") or unitgroup:match("t3") or unitgroup:match("t4") then
                    shouldTrack = true
                end
                
                -- Strategic units based on unitgroup patterns
                if unitgroup:match("nuke") or unitgroup:match("silo") or unitgroup:match("gantry") or 
                   unitgroup:match("fusion") or unitgroup:match("plasma") or unitgroup:match("artillery") or
                   unitgroup:match("anti") or unitgroup:match("shield") or unitgroup:match("jammer") then
                    shouldTrack = true
                end
            end
            
            -- Additional criteria for strategic units
            if not shouldTrack then
                -- High cost units (typically strategic)
                if unitDef.metalCost and unitDef.metalCost > 5000 then
                    shouldTrack = true
                end
                
                -- High energy cost units
                if unitDef.energyCost and unitDef.energyCost > 50000 then
                    shouldTrack = true
                end
                
                -- Long build time units (typically strategic)
                if unitDef.buildTime and unitDef.buildTime > 3000 then
                    shouldTrack = true
                end
                
                -- Units with special abilities
                if unitDef.customParams and (
                    unitDef.customParams.teleporter or 
                    unitDef.customParams.teleport or
                    unitDef.customParams.cloak or
                    unitDef.customParams.stealth or
                    unitDef.customParams.shield
                ) then
                    shouldTrack = true
                end
            end
            
            if shouldTrack then
                trackedUnits[unitDef.name] = true
            end
        end
    end
    
    return trackedUnits
end

-- This will be populated during initialization with the comprehensive list
local TRACKED_BUILDINGS = {}

-- Dynamically build unitgroup to category mapping from UnitDefs
local UNITGROUP_TO_CATEGORY = {}
local function BuildCategoryMappings()
	UNITGROUP_TO_CATEGORY = {}

	for unitDefID, unitDef in pairs(UnitDefs) do
		if unitDef.customParams and unitDef.customParams.unitgroup then
			local unitgroup = unitDef.customParams.unitgroup

			-- Skip if already categorized
			if not UNITGROUP_TO_CATEGORY[unitgroup] then
				-- Determine category based on unit characteristics
				local category = nil

				-- Economy: energy production, metal extraction, converters
				if unitDef.energyMake and unitDef.energyMake > 0 then
					category = "economy"
				elseif unitDef.extractsMetal and unitDef.extractsMetal > 0 then
					category = "economy"
				elseif unitgroup:match("energy") or unitgroup:match("metal") or unitgroup:match("converter") then
					category = "economy"

				-- Combat: weapons, defense
				elseif #unitDef.weapons > 0 or unitgroup:match("weapon") or unitgroup:match("defense") or unitgroup:match("nuke") or unitgroup:match("aa") then
					category = "combat"

				-- Build: factories, builders
				elseif unitDef.isBuilder or unitgroup:match("builder") or unitgroup:match("factory") then
					category = "build"

				-- Utility: everything else (radar, jammers, etc)
				else
					category = "utility"
				end

				if category then
					UNITGROUP_TO_CATEGORY[unitgroup] = category
				end
			end
		end
	end
end

-- Spring API shortcuts
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitPosition = Spring.GetUnitPosition
local spIsUnitAllied = Spring.IsUnitAllied
local spGetSpectatingState = Spring.GetSpectatingState
local spGetMyTeamID = Spring.GetMyTeamID
local spGetPlayerInfo = Spring.GetPlayerInfo
local spGetAllUnits = Spring.GetAllUnits

local function IsCommander(unitDefID)
    local unitDef = UnitDefs[unitDefID]
    if not unitDef then return false end
    return unitDef.customParams and unitDef.customParams.iscommander == "1"
end

-- Load iconTypes
local iconTypes = VFS.Include("gamedata/icontypes.lua")

-- Widget state
local isSpectator = false
local fullView = false
local myTeamID = 0
local frameCounter = 0
local gameStarted = false
local lastUIHiddenState = false
local completedConstructionsHistory = {}
local trackedConstructions = {}  -- [unitID] = {unitID, unitDefID, team, buildProgress}
local trackedCommanders = {}     -- [teamID] = {unitID, unitDefID}


-- Position state
local widgetPosX = 50
local widgetPosY = 100

-- RMLui variables
local document
local dm_handle
local collapsed = false
local dataDirty = false

-- Category filter state
local activeCategories = {
	economy = true,
	combat = true,
	utility = true,
	build = true,
}

-- Selection visualization state
local selectedUnitsToHighlight = {}

-- Hover menu scroll position tracking
local hoverMenuScrollPositions = {}

local function LoadPosition()
    local configString = Spring.GetConfigString("StrategicConstructionTracker_Position", "")
    if configString and configString ~= "" then
        local x, y = configString:match("^(%d+),(%d+)$")
        if x and y then
            widgetPosX = tonumber(x)
            widgetPosY = tonumber(y)
        end
    end
end

local function SavePosition()
    local configString = widgetPosX .. "," .. widgetPosY
    Spring.SetConfigString("StrategicConstructionTracker_Position", configString)
end

local function LoadCollapsedState()
    local configString = Spring.GetConfigString("StrategicConstructionTracker_Collapsed", "false")
    collapsed = (configString == "true")
end

local function SaveCollapsedState()
    Spring.SetConfigString("StrategicConstructionTracker_Collapsed", tostring(collapsed))
end

local function LoadCategoryFilters()
    local configString = Spring.GetConfigString("StrategicConstructionTracker_Filters", "economy,combat,utility,build")
    activeCategories = {economy = false, combat = false, utility = false, build = false}
    for category in configString:gmatch("[^,]+") do
        activeCategories[category] = true
    end
end

local function SaveCategoryFilters()
    local filters = {}
    for category, active in pairs(activeCategories) do
        if active then
            table.insert(filters, category)
        end
    end
    Spring.SetConfigString("StrategicConstructionTracker_Filters", table.concat(filters, ","))
end

local function UpdateDocumentPosition()
    if document then
        local panel = document:GetElementById("strategic-panel")
        if panel then
            local currentLeft = panel.style.left
            local currentTop = panel.style.top

            if not currentLeft or currentLeft == "" or not currentTop or currentTop == "" then
                panel.style.left = widgetPosX .. "px"
                panel.style.top = widgetPosY .. "px"
            end
        end
    end
end

local function BuildCategoriesArray(includeProgress)
    local categories = {
        {id = "economy", name = BUILDCAT_ECONOMY, icon = CATEGORY_ICONS.economy, active = activeCategories.economy, count = 0, progress = 0},
        {id = "combat", name = BUILDCAT_COMBAT, icon = CATEGORY_ICONS.combat, active = activeCategories.combat, count = 0, progress = 0},
        {id = "utility", name = BUILDCAT_UTILITY, icon = CATEGORY_ICONS.utility, active = activeCategories.utility, count = 0, progress = 0},
        {id = "build", name = BUILDCAT_PRODUCTION, icon = CATEGORY_ICONS.build, active = activeCategories.build, count = 0, progress = 0},
    }

    if includeProgress then
        for i, cat in ipairs(categories) do
            cat.count = includeProgress[cat.id].count or 0
            cat.progress = includeProgress[cat.id].progress or 0
        end
    end

    return categories
end

local function InitializeTrackingTables()
    trackedConstructions = {}
    trackedCommanders = {}

    local allUnits = spGetAllUnits()
    for _, unitID in ipairs(allUnits) do
        local unitDefID = spGetUnitDefID(unitID)
        if unitDefID then
            local unitDef = UnitDefs[unitDefID]
            local unitTeam = spGetUnitTeam(unitID)

            if ShouldTrackUnit(unitID, unitTeam) then
                if unitDef and TRACKED_BUILDINGS[unitDef.name] then
                    trackedConstructions[unitID] = {
                        unitID = unitID,
                        unitDefID = unitDefID,
                        team = unitTeam,
                        buildProgress = 0
                    }
                end

                if IsCommander(unitDefID) then
                    trackedCommanders[unitTeam] = {
                        unitID = unitID,
                        unitDefID = unitDefID
                    }
                end
            end
        end
    end
end

local function RebuildTrackingTables()
    InitializeTrackingTables()
end


function widget:Initialize()
    Spring.Echo(WIDGET_NAME .. ": Initializing widget...")

    -- Build comprehensive tracked buildings list (T2 + T3 + T4 + strategic units)
    TRACKED_BUILDINGS = BuildComprehensiveTrackedList()

    BuildCategoryMappings()
    local count = 0
    for _ in pairs(UNITGROUP_TO_CATEGORY) do count = count + 1 end
    Spring.Echo(WIDGET_NAME .. ": Mapped " .. count .. " unitgroups to categories")

    LoadPosition()
    LoadCollapsedState()
    LoadCategoryFilters()

    myTeamID = Spring.GetMyTeamID()
    local spec, fullV = Spring.GetSpectatingState()
    isSpectator = spec
    fullView = fullV

    widget.forceGameFrame = true

    widget.rmlContext = RmlUi.GetContext("shared")
    if not widget.rmlContext then
        Spring.Echo(WIDGET_NAME .. ": ERROR - Failed to get RML context")
        return false
    end

    local initialModel = {
        collapsed = collapsed,
        collapse_symbol = collapsed and "+" or "−",
        teams = {},
        constructions = {size = 0},
        categories = BuildCategoriesArray()
    }

    dm_handle = widget.rmlContext:OpenDataModel(MODEL_NAME, initialModel)
    if not dm_handle then
        Spring.Echo(WIDGET_NAME .. ": ERROR - Failed to create data model '" .. MODEL_NAME .. "'")
        return false
    end

    Spring.Echo(WIDGET_NAME .. ": Data model created successfully")

    document = widget.rmlContext:LoadDocument(RML_PATH, widget)
    if not document then
        Spring.Echo(WIDGET_NAME .. ": ERROR - Failed to load document: " .. RML_PATH)
        widget:Shutdown()
        return false
    end

    document:ReloadStyleSheet()

    local gameFrame = Spring.GetGameFrame()
    if gameFrame and gameFrame > 0 then
        gameStarted = true
        if not Spring.IsGUIHidden() then
            document:Show()
        end
    end

    UpdateDocumentPosition()
    InitializeTrackingTables()

    Spring.Echo(WIDGET_NAME .. ": Widget initialized successfully")

    return true
end

function widget:GameStart()
    gameStarted = true
    if document and not Spring.IsGUIHidden() then
        document:Show()
    end
end

function widget:Update()
    if not document or not gameStarted then
        return
    end

    local isHidden = Spring.IsGUIHidden()
    local isInMenu = false
    if WG then
        isInMenu = (WG.PauseScreen and WG.PauseScreen.IsActive and WG.PauseScreen.IsActive())
            or (WG.Chili and WG.Chili.Screen0 and WG.Chili.Screen0.focusedControl)
    end

    local shouldHide = isHidden or isInMenu

    if shouldHide ~= lastUIHiddenState then
        lastUIHiddenState = shouldHide
        if shouldHide then
            document:Hide()
        else
            document:Show()
        end
    end
end

function widget:OnDragEnd(event)
    if document then
        local panel = document:GetElementById("strategic-panel")
        if panel then
            local absLeft = panel.absolute_left
            local absTop = panel.absolute_top

            if absLeft and absTop then
                widgetPosX = math.floor(absLeft)
                widgetPosY = math.floor(absTop)
                SavePosition()
            end
        end
    end
end

function widget:ToggleCollapsed(event)
    collapsed = not collapsed
    if dm_handle then
        dm_handle.collapsed = collapsed
        dm_handle.collapse_symbol = collapsed and "+" or "-"
    end
    SaveCollapsedState()
    return true
end

function widget:ToggleCategoryFilter(event)
    local element = event.current_element
    if not element then
        return false
    end

    local categoryId = element:GetAttribute("data-category")
    if not categoryId then
        return false
    end

    activeCategories[categoryId] = not activeCategories[categoryId]

    SaveCategoryFilters()
    UpdateRMLuiData()
    return true
end

local function GetUnitDisplayName(unitDefID)
    local unitDef = UnitDefs[unitDefID]
    if not unitDef then
        return "Unknown"
    end

    if unitDef.name then
        local displayName = Spring.I18N and Spring.I18N('units.names.' .. unitDef.name)
        if displayName and displayName ~= "" and displayName ~= ('units.names.' .. unitDef.name) then
            return displayName
        end
    end

    return unitDef.humanName or unitDef.name or "Unknown"
end

local function GetUnitCategory(unitDefID)
    local unitDef = UnitDefs[unitDefID]
    if not unitDef or not unitDef.customParams then
        return nil
    end

    local unitgroup = unitDef.customParams.unitgroup
    if not unitgroup then
        return nil
    end

    return UNITGROUP_TO_CATEGORY[unitgroup]
end

function widget:SelectConstruction(event)
    local element = event.current_element
    if not element then
        return false
    end

    -- Get hidden span elements by class name - NOTE: Lua arrays are 1-indexed!
    local unitIDSpan = element:GetElementsByClassName("unit-id")[1]
    local unitDefIDSpan = element:GetElementsByClassName("unit-def-id")[1]
    local teamIDSpan = element:GetElementsByClassName("team-id")[1]
    local isCompletedSpan = element:GetElementsByClassName("is-completed")[1]

    local unitID = unitIDSpan and tonumber(unitIDSpan.inner_rml) or nil
    local unitDefID = unitDefIDSpan and tonumber(unitDefIDSpan.inner_rml) or nil
    local teamID = teamIDSpan and tonumber(teamIDSpan.inner_rml) or nil
    local isCompletedText = isCompletedSpan and isCompletedSpan.inner_rml or "false"
    local isCompleted = isCompletedText == "true"

    if isCompleted and not unitID then
        -- Completed construction - select all units of this type
        if unitDefID and teamID then
            selectedUnitsToHighlight = {}
            local validUnitIDs = {}
            local sumX, sumY, sumZ = 0, 0, 0
            local count = 0
            local allUnits = spGetAllUnits()
            for _, checkUnitID in ipairs(allUnits) do
                if completedConstructionsHistory[checkUnitID] then
                    local checkUnitDefID = spGetUnitDefID(checkUnitID)
                    local checkUnitTeam = spGetUnitTeam(checkUnitID)

                    if checkUnitDefID == unitDefID and checkUnitTeam == teamID and Spring.ValidUnitID(checkUnitID) then
                        table.insert(validUnitIDs, checkUnitID)
                        local x, y, z = Spring.GetUnitPosition(checkUnitID)
                        if x then
                            local unitDef = UnitDefs[unitDefID]
                            local r, g, b = Spring.GetTeamColor(teamID)

                            selectedUnitsToHighlight[checkUnitID] = {
                                x = x,
                                y = y,
                                z = z,
                                radius = unitDef and unitDef.radius or 50,
                                teamColor = {r, g, b},
                                unitName = GetUnitDisplayName(unitDefID) or "Unknown"
                            }

                            sumX, sumY, sumZ = sumX + x, sumY + y, sumZ + z
                            count = count + 1
                        end
                    end
                end
            end

            if count > 0 then
                local centerX, centerY, centerZ = sumX / count, sumY / count, sumZ / count
                Spring.SelectUnitArray(validUnitIDs)
                Spring.SetCameraTarget(centerX, centerY, centerZ, 1)
                return true
            end
        end
    elseif unitID and Spring.ValidUnitID(unitID) then
        local x, y, z = Spring.GetUnitPosition(unitID)
        Spring.SelectUnitArray({unitID})
        if x then
            Spring.SetCameraTarget(x, y, z, 1)
        end
        return true
    end

    return false
end


function GetCommanderInfo()
    local commanders = {}

    for teamID, data in pairs(trackedCommanders) do
        if Spring.ValidUnitID(data.unitID) then
            local health, maxHealth = spGetUnitHealth(data.unitID)

            if health and maxHealth and maxHealth > 0 then
                commanders[teamID] = {
                    unitID = data.unitID,
                    unitDefID = data.unitDefID,
                    health = health / maxHealth
                }
            end
        end
    end

    return commanders
end

function GetCurrentConstructions()
    local activeConstructions = {}
    local completedConstructions = {}

    for unitID, data in pairs(trackedConstructions) do
        if Spring.ValidUnitID(unitID) then
            local _, _, _, _, buildProgress = spGetUnitHealth(unitID)

            if buildProgress then
                data.buildProgress = buildProgress

                local constructionData = {
                    unitID = data.unitID,
                    unitDefID = data.unitDefID,
                    team = data.team,
                    buildProgress = buildProgress
                }

                if buildProgress < 1.0 then
                    table.insert(activeConstructions, constructionData)
                else
                    if not completedConstructionsHistory[unitID] then
                        completedConstructionsHistory[unitID] = Spring.GetGameSeconds()
                    end
                    table.insert(completedConstructions, constructionData)
                end
            end
        end
    end

    return activeConstructions, completedConstructions
end

function ShouldTrackUnit(unitID, unitTeam)
    if isSpectator and fullView then
        return true
    else
        return spIsUnitAllied(unitID)
    end
end

function GetTeamDisplayName(teamID)
    local playerList = Spring.GetPlayerList()
    for _, playerID in ipairs(playerList) do
        local playerName, _, isSpec, playerTeam = spGetPlayerInfo(playerID)
        if playerTeam == teamID and playerName and not isSpec then
            return playerName
        end
    end
    return "Team " .. teamID
end


local function GetTeamColorString(teamID)
    local r, g, b = Spring.GetTeamColor(teamID)
    return string.format("rgb(%d,%d,%d)", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end

local function SaveHoverMenuScrollPositions()
    if not document then return end

    if dm_handle and dm_handle.teams then
        for _, team in ipairs(dm_handle.teams) do
            local hoverMenu = document:GetElementById("hover-menu-" .. team.id)
            if hoverMenu then
                hoverMenuScrollPositions[team.id] = hoverMenu.scroll_top
            end
        end
    end
end

local function RestoreHoverMenuScrollPositions()
    if not document then return end

    for teamID, scrollTop in pairs(hoverMenuScrollPositions) do
        local hoverMenu = document:GetElementById("hover-menu-" .. teamID)
        if hoverMenu then
            hoverMenu.scroll_top = scrollTop
        end
    end
end

local function CreateTeamGroup(teamID)
    local teamColor = GetTeamColorString(teamID)
    return {
        id = teamID,
        name = GetTeamDisplayName(teamID),
        accent_color = teamColor,
        active_constructions = {},
        completed_constructions = {},
        total_count = 0,
        avg_progress = 0,
        total_progress = 0
    }
end

function UpdateRMLuiData()
    if not dm_handle then return end

    SaveHoverMenuScrollPositions()

    dm_handle.collapsed = collapsed
    dm_handle.collapse_symbol = collapsed and "+" or "−"

    local activeConstructions, completedConstructions = GetCurrentConstructions()

    local commanders = GetCommanderInfo()

    local categoryCounts = {
        economy = 0,
        combat = 0,
        utility = 0,
        build = 0,
    }

    local categoryProgress = {
        economy = {total = 0, count = 0},
        combat = {total = 0, count = 0},
        utility = {total = 0, count = 0},
        build = {total = 0, count = 0},
    }

    for _, data in ipairs(activeConstructions) do
        local unitCategory = GetUnitCategory(data.unitDefID)
        if unitCategory and categoryCounts[unitCategory] then
            categoryCounts[unitCategory] = categoryCounts[unitCategory] + 1
            categoryProgress[unitCategory].total = categoryProgress[unitCategory].total + (data.buildProgress or 0)
            categoryProgress[unitCategory].count = categoryProgress[unitCategory].count + 1
        end
    end

    local categoryData = {}
    for category, stats in pairs(categoryProgress) do
        categoryData[category] = {
            count = categoryCounts[category],
            progress = stats.count > 0 and (stats.total / stats.count) or 0
        }
    end

    dm_handle.categories = BuildCategoriesArray(categoryData)

    local teamGroups = {}
    local totalConstructions = 0

    for _, data in ipairs(activeConstructions) do
        local unitCategory = GetUnitCategory(data.unitDefID)
        if not unitCategory or activeCategories[unitCategory] then
            totalConstructions = totalConstructions + 1

            local unitDef = UnitDefs[data.unitDefID]
            local unitName = GetUnitDisplayName(data.unitDefID)
            local iconTypeName = unitDef and unitDef.iconType or ""
            local iconData = iconTypes and iconTypes[iconTypeName]
            local iconPath = iconData and iconData.bitmap or ""
            local progressPercent = math.floor(data.buildProgress * 100)
            local progressSquares = {}
            local filledSquares = math.floor(progressPercent / 10)
            for i = 1, filledSquares do
                table.insert(progressSquares, {is_filled = true})
            end

            local constructionData = {
                unit_id = data.unitID or 0,
                unit_name = unitName or "Unknown",
                unit_def_id = data.unitDefID or 0,
                icon_path = iconPath or "",
                progress_percent = progressPercent or 0,
                progress_squares = progressSquares or {},
                is_completed = false
            }

            if not teamGroups[data.team] then
                teamGroups[data.team] = CreateTeamGroup(data.team)
            end

            table.insert(teamGroups[data.team].active_constructions, constructionData)
            teamGroups[data.team].total_progress = teamGroups[data.team].total_progress + data.buildProgress
        end
    end

    for _, data in ipairs(completedConstructions) do
        if not teamGroups[data.team] then
            teamGroups[data.team] = CreateTeamGroup(data.team)
        end

        local unitDef = UnitDefs[data.unitDefID]
        local unitName = GetUnitDisplayName(data.unitDefID)
        local completionTime = completedConstructionsHistory[data.unitID] or 0

        table.insert(teamGroups[data.team].completed_constructions, {
            unit_id = data.unitID or 0,
            unit_name = unitName or "Unknown",
            unit_def_id = data.unitDefID or 0,
            completion_time = completionTime or 0
        })
    end

    for teamID, teamData in pairs(teamGroups) do
        local activeCount = #teamData.active_constructions
        local completedCount = #teamData.completed_constructions

        teamData.total_count = activeCount
        teamData.completed_count = completedCount
        teamData.has_active = activeCount > 0
        teamData.has_completed = completedCount > 0

        local commanderInfo = commanders[teamID]
        if commanderInfo then
            teamData.has_commander = true
            teamData.commander_id = commanderInfo.unitID
            teamData.commander_def_id = commanderInfo.unitDefID
            teamData.commander_health = commanderInfo.health
        else
            teamData.has_commander = false
            teamData.commander_id = 0
            teamData.commander_def_id = 0
            teamData.commander_health = 0
        end

        if activeCount > 0 then
            teamData.avg_progress = teamData.total_progress / activeCount
            teamData.avg_progress_percent = math.floor(teamData.avg_progress * 100)
        else
            teamData.avg_progress = 0
            teamData.avg_progress_percent = 0
        end

        teamData.avg_progress_squares = {}
        local filledSquares = math.floor(teamData.avg_progress_percent / 10)
        for i = 1, filledSquares do
            table.insert(teamData.avg_progress_squares, {is_filled = true})
        end

        local iconMap = {}
        for _, construction in ipairs(teamData.active_constructions) do
            local key = construction.unit_def_id or 0
            if key ~= 0 and not iconMap[key] then
                iconMap[key] = {
                    unit_def_id = construction.unit_def_id or 0,
                    icon_path = construction.icon_path or "",
                    count = 0
                }
            end
            if key ~= 0 then
                iconMap[key].count = iconMap[key].count + 1
            end
        end

        teamData.aggregated_icons = {}
        for _, iconData in pairs(iconMap) do
            table.insert(teamData.aggregated_icons, iconData)
        end
        table.sort(teamData.aggregated_icons, function(a, b)
            if a.count == b.count then
                return a.unit_def_id < b.unit_def_id
            end
            return a.count > b.count
        end)

        table.sort(teamData.active_constructions, function(a, b)
            return a.progress_percent < b.progress_percent
        end)

        table.sort(teamData.completed_constructions, function(a, b)
            return a.completion_time > b.completion_time
        end)

        local uniqueCompletedMap = {}
        for _, completed in ipairs(teamData.completed_constructions) do
            local key = completed.unit_def_id or 0
            if key ~= 0 and not uniqueCompletedMap[key] then
                uniqueCompletedMap[key] = {
                    unit_def_id = completed.unit_def_id or 0,
                    unit_name = completed.unit_name or "Unknown",
                    count = 0
                }
            end
            if key ~= 0 then
                uniqueCompletedMap[key].count = uniqueCompletedMap[key].count + 1
            end
        end

        teamData.unique_completed = {}
        for _, uniqueCompleted in pairs(uniqueCompletedMap) do
            table.insert(teamData.unique_completed, uniqueCompleted)
        end
        table.sort(teamData.unique_completed, function(a, b)
            return a.unit_name < b.unit_name
        end)
    end

    local teamsArray = {}
    for teamID, teamData in pairs(teamGroups) do
        if teamData.has_active or teamData.has_completed then
            table.insert(teamsArray, teamData)
        end
    end

    table.sort(teamsArray, function(a, b)
        return a.id < b.id
    end)

    dm_handle.teams = teamsArray
    dm_handle.constructions = {size = totalConstructions}

    RestoreHoverMenuScrollPositions()
end

function widget:PlayerChanged(playerID)
    local spec, fullV = spGetSpectatingState()
    isSpectator = spec
    fullView = fullV
    myTeamID = spGetMyTeamID()

    RebuildTrackingTables()

    dataDirty = true
end

function widget:UnitCreated(unitID, unitDefID, unitTeam, builderID)
    local unitDef = UnitDefs[unitDefID]

    if unitDef and TRACKED_BUILDINGS[unitDef.name] then
        if ShouldTrackUnit(unitID, unitTeam) then
            trackedConstructions[unitID] = {
                unitID = unitID,
                unitDefID = unitDefID,
                team = unitTeam,
                buildProgress = 0
            }
            dataDirty = true
        end
    end

    if IsCommander(unitDefID) then
        if ShouldTrackUnit(unitID, unitTeam) then
            trackedCommanders[unitTeam] = {
                unitID = unitID,
                unitDefID = unitDefID
            }
            dataDirty = true
        end
    end
end

function widget:UnitFinished(unitID, unitDefID, unitTeam)
    if trackedConstructions[unitID] then
        dataDirty = true
    end
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
    if trackedConstructions[unitID] then
        trackedConstructions[unitID] = nil
        dataDirty = true
    end

    if trackedCommanders[unitTeam] and trackedCommanders[unitTeam].unitID == unitID then
        trackedCommanders[unitTeam] = nil
        dataDirty = true
    end

    if completedConstructionsHistory[unitID] then
        completedConstructionsHistory[unitID] = nil
    end

    if selectedUnitsToHighlight[unitID] then
        selectedUnitsToHighlight[unitID] = nil
    end

    dataDirty = true
end

function widget:GameFrame()
    if dataDirty then
        UpdateRMLuiData()
        dataDirty = false
    end

    if next(selectedUnitsToHighlight) ~= nil then
        local currentSelection = Spring.GetSelectedUnits()
        local selectionSet = {}
        for _, unitID in ipairs(currentSelection) do
            selectionSet[unitID] = true
        end

        local stillSelected = false
        for unitID in pairs(selectedUnitsToHighlight) do
            if selectionSet[unitID] then
                stillSelected = true
                break
            end
        end

        if not stillSelected then
            selectedUnitsToHighlight = {}
        end
    end

    frameCounter = frameCounter + 1
    if frameCounter >= UPDATE_FREQUENCY then
        frameCounter = 0
        dataDirty = true
    end
end

function widget:DrawScreen()
    if Spring.IsGUIHidden() or next(selectedUnitsToHighlight) == nil then
        return
    end

    local teamColor = nil
    local unitName = ""
    local unitCount = 0
    local units = {}
    local screenPositions = {}

    for unitID, highlight in pairs(selectedUnitsToHighlight) do
        if Spring.ValidUnitID(unitID) then
            local x, y, z = Spring.GetUnitPosition(unitID)
            if x then
                teamColor = highlight.teamColor
                unitName = highlight.unitName
                unitCount = unitCount + 1

                local sx, sy, sz = Spring.WorldToScreenCoords(x, y, z)
                if sz and sz < 1 then
                    table.insert(units, {x = x, y = y, z = z, sx = sx, sy = sy})
                    table.insert(screenPositions, {sx = sx, sy = sy})
                end
            end
        end
    end

    if teamColor and unitCount > 0 and #screenPositions > 0 then
        local avgSx, avgSy = 0, 0
        for _, pos in ipairs(screenPositions) do
            avgSx = avgSx + pos.sx
            avgSy = avgSy + pos.sy
        end
        avgSx = avgSx / #screenPositions
        avgSy = avgSy / #screenPositions

        local billboardOffsetY = 200
        avgSy = avgSy + billboardOffsetY

        gl.LineWidth(2)
        gl.Color(teamColor[1], teamColor[2], teamColor[3], 0.5)
        for _, unit in ipairs(units) do
            gl.BeginEnd(GL.LINES, function()
                gl.Vertex(avgSx, avgSy)
                gl.Vertex(unit.sx, unit.sy)
            end)
        end

        gl.LineWidth(2)
        gl.Color(teamColor[1], teamColor[2], teamColor[3], 0.8)
        for _, unit in ipairs(units) do
            local radius = 8
            gl.BeginEnd(GL.LINE_LOOP, function()
                for i = 0, 15 do
                    local angle = (i / 16) * math.pi * 2
                    gl.Vertex(unit.sx + math.cos(angle) * radius, unit.sy + math.sin(angle) * radius)
                end
            end)
        end

        local fontSize = 18
        local quantityText = tostring(unitCount)
        local padding = 30

        local nameWidth = #unitName * fontSize * 0.6
        local qtyWidth = #quantityText * (fontSize + 4) * 0.6
        local panelWidth = math.max(nameWidth, qtyWidth) + padding * 2
        panelWidth = math.max(panelWidth, 180)
        local panelHeight = 95

        local px = avgSx - panelWidth/2
        local py = avgSy - panelHeight/2

        gl.Color(0.0, 0.0, 0.0, 0.9)
        gl.Rect(px, py, px + panelWidth, py + panelHeight)

        local borderWidth = 4
        gl.Color(teamColor[1], teamColor[2], teamColor[3], 0.95)
        gl.Rect(px, py, px + borderWidth, py + panelHeight)

        gl.Color(1, 1, 1, 1)
        gl.Text(unitName, avgSx, avgSy + 18, fontSize, "cvO")

        local qtySize = fontSize + 6
        gl.Color(teamColor[1] * 1.2, teamColor[2] * 1.2, teamColor[3] * 1.2, 1.0)
        gl.Text(quantityText, avgSx, avgSy - 20, qtySize, "cvO")

        gl.LineWidth(1)
    end
end


function widget:Shutdown()
    Spring.Echo(WIDGET_NAME .. ": Shutting down widget...")


    -- Clean up data model
    if widget.rmlContext and dm_handle then
        widget.rmlContext:RemoveDataModel(MODEL_NAME)
        dm_handle = nil
    end

    -- Close document
    if document then
        document:Close()
        document = nil
    end

    widget.rmlContext = nil
    completedConstructionsHistory = {}

    Spring.Echo(WIDGET_NAME .. ": Shutdown complete")
end
