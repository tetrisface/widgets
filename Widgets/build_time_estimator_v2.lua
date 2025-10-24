Spring.Echo("BTEv2: File loading started...")

--------------------------------------------------------------------------------
-- Build Time Estimator v2 Widget for Beyond All Reason
--------------------------------------------------------------------------------
-- Copyright (C) 2024 Pyrem
--
-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation; either version 2 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
-- GNU General Public License for more details.
--------------------------------------------------------------------------------

function widget:GetInfo()
    return {
        name = "⏱️ Build Timer v2 (Pyrem)",
        desc = [[
🎯 Advanced build time calculation system for Beyond All Reason with economy-aware predictions.

CORE FEATURES:
• Real-time build time estimates based on available builders and nano turrets
• Economy-aware predictions accounting for metal/energy constraints  
• Smart unit detection: builders in range, selected, or guarding
• Performance-optimized with caching and frame-based updates
• Works seamlessly in both player and spectator modes

🔧 IDLE BUILDER MODE - Press backtick (`) to toggle:
  - Shows ALL idle builders AND turrets (in range or guarding)
  - Auto-commands idle units to GUARD selected builder when placing buildings
  - Idle = not actively building (GUARD alone doesn't make unit busy)
  - Works with T1/T2 compatibility (guard copies valid commands)
  - 2-second cooldown per unit to prevent command spam
  - Consistent color scheme across all modes (economy-based)
  - Command feedback shows units commanded

👁️ SPECTATOR SUPPORT:
• Auto-switches to show build power of selected units' team
• Hover over any unit for 1 second to auto-switch to their team
• Manual team overrides persist until new units are selected
• Shows correct BP/s, usage rates, and build times for each player

📊 DISPLAY INFORMATION:
• Hover over units under construction to see completion time
• Color-coded indicators: Green (affordable), Yellow (60-99%), Red (stalled), White (good economy)
• Shows total build power (BP/s) in both build and hover modes
• Clean builder/turret counts with consistent bracket formatting
• Displays usage rates (M/s, E/s) AND remaining/required resources (M, E)
• Shows current storage levels for metal and energy
• Optimized text-background alignment for improved readability

🔧 SMART UNIT DETECTION:
• Mobile builders: Not building + not moving + (no commands OR only GUARD)
• Nano turrets: Not building + (no work commands OR only GUARD/FIGHT)
• Units actively building are NEVER idle (even if guarding)
• Includes builders in range, selected builders, and units guarding selected builders

🏗️ TECHNICAL FEATURES:
• DRY architecture with 17+ utility functions for maintainability
• Optimized unit type validation with pre-built lookup tables
• Frame-based calculation throttling for consistent performance
• Centralized resource formatting and economy status management
• Intelligent caching system for unit data and calculations

See CHANGELOG.md for version history and detailed changes.
]],
        author = "Pyrem",
        version = "2.7.5",
        date = "2025",
        license = "GNU GPL, v2 or later",
        layer = -999,
        enabled = true
    }
end

Spring.Echo("BTEv2: GetInfo() function declared successfully")

-- 🔧 Debug System (Set to true to enable debug logging)
local DEBUG_MODE = false
local function debugLog(stage, msg) if DEBUG_MODE then Spring.Echo("BTEv2 [" .. stage .. "]: " .. msg) end end
local function debugError(func, err) if DEBUG_MODE then Spring.Echo("BTEv2 ERROR [" .. func .. "]: " .. tostring(err)) end end

-- Early debug to see if widget loads at all
Spring.Echo("BTEv2: Debug system declared")
debugLog("LOAD", "Widget file loading, starting variable declarations...")

-- 🎯 Player identification and spectator support
local myPlayerID = nil
local myTeamID = nil
local targetPlayerID = nil  -- Which player's units to track (for spectator mode)
local targetTeamID = nil
local isSpectator = false
local lastPlayerCheck = 0

-- ⚡ Performance tuning constants
local UPDATE_FREQUENCY = 15 -- Update every 15 frames (0.5s at 30 fps)
local HOVER_CHECK_FREQUENCY = 6 -- Check hover every 6 frames (0.2s at 30 fps)
local PLAYER_CHECK_FREQUENCY = 90 -- Check player status every 90 frames (3s)
local HOVER_TEAM_SWITCH_DELAY = 30 -- Delay before switching teams on hover (1s at 30 fps)
local frameCounter = 0
local lastHoverUpdate = 0
local lastHoverCheck = 0

-- 🎯 Hover-based team switching for spectators
local hoveredTeamID = nil
local hoveredTeamStartFrame = 0
local lastHoverTeamSwitch = 0
local manualTeamOverride = nil  -- Stores manually selected team (via hover)
local hasManualOverride = false  -- Flag to prevent auto-reset

--------------------------------------------------------------------------------
-- ⚡ Performance & Caching Systems
--------------------------------------------------------------------------------

-- 🚀 Performance caching system
local unitCache = {}  -- Cache unit properties that don't change often
local lastCacheUpdate = 0
local CACHE_UPDATE_FREQUENCY = 45 -- Update cache every 45 frames (1.5s)

-- 💾 Cached calculation results
local cachedResults = {
    isActive = false,
    timeText = "",
    builderCount = 0,
    turretCount = 0,
    showingIdle = false,
    ecoStatus = nil,
    metalPerSecond = 0,
    energyPerSecond = 0,
    playerName = "" -- Track which player's units we're showing
}

-- 🔨 Cached hover results for construction info
local hoveredResults = {
    isActive = false,
    unitID = nil,
    buildProgress = 0,
    timeText = "",
    buildPowerPerSecond = 0,
    ecoStatus = nil,
    metalPerSecond = 0,
    energyPerSecond = 0
}

-- Idle builder toggle state
local showIdleOnly = false
local BACKTICK_KEY_1 = 96   -- ASCII backtick
local BACKTICK_KEY_2 = 192  -- SDL backtick/tilde key

-- Import required modules
local gl = gl
local CMD = CMD

-- Command IDs for clarity
local CMD_MOVE = CMD.MOVE
local CMD_PATROL = CMD.PATROL
local CMD_FIGHT = CMD.FIGHT
local CMD_GUARD = CMD.GUARD
local CMD_REPAIR = CMD.REPAIR
local CMD_RECLAIM = CMD.RECLAIM
local CMD_RESURRECT = CMD.RESURRECT
local CMD_WAIT = CMD.WAIT
local CMD_STOP = CMD.STOP

-- 🎯 Idle builder auto-command system
local idleBuildersCommanded = {}  -- Track cooldown per builder {[unitID] = frameExpiry}
local lastCommandFeedback = ""
local commandFeedbackTime = 0
local COMMAND_COOLDOWN = 60  -- 2 seconds at 30fps
local FEEDBACK_DURATION = 60  -- Show feedback for 2 seconds
local cachedIdleBuilders = {}  -- Cache idle builders for command system
local cachedIdleTurrets = {}  -- Cache idle turrets separately

-- BAR-style color constants
local ECO_GREEN = "\255\120\235\120"  -- Positive/affordable
local ECO_RED = "\255\240\125\125"    -- Negative/unaffordable  
local ECO_YELLOW = "\255\255\255\150" -- Warning (60-99%)
local ECO_WHITE = "\255\255\255\255"  -- Neutral
local ECO_GRAY = "\255\200\200\200"   -- Default

--------------------------------------------------------------------------------
-- 📐 UI Layout Configuration & Rendering System  
--------------------------------------------------------------------------------

-- Distance from mouse cursor
local HOVER_DISTANCE_FROM_CURSOR = 50    -- Hover display distance
local BUILD_DISTANCE_FROM_CURSOR = 60    -- Build placement distance

-- Background dimensions  
local BACKGROUND_WIDTH = 240             -- Both modes use same width

-- Background padding (top/bottom spacing)
local HOVER_BACKGROUND_PADDING = 8       -- Hover display padding per side
local BUILD_BACKGROUND_PADDING = 8       -- Build placement padding per side

-- Extra spacing adjustments for fine-tuning
local TOP_PADDING_ADJUSTMENT = 0         -- Reduce bottom padding by adjusting this
local BOTTOM_PADDING_ADJUSTMENT = -4     -- Add/remove bottom padding directly
local BOTTOM_BUILD_TEXT_ADJUSTMENT = -2

-- 🎯 Font-size-based LineRenderer System
-- Font-size-based spacing calculation functions
local function calculateLineHeight(fontSize)
    return math.floor(fontSize * 1.3)  -- 130% of font size for proper line spacing
end

local function calculateFontGap(fontSize)
    return math.floor(fontSize * 0.2)  -- 20% font gap for visual breathing room  
end

-- 📐 Unified Line Positioning System
local LineRenderer = {
    lines = {},
    startY = 0,
    currentY = 0,
    screenX = 0
}

function LineRenderer:reset(startY, screenX)
    self.lines = {}
    self.startY = startY
    self.currentY = startY
    self.screenX = screenX
end

function LineRenderer:addLine(text, fontSize, color, extraSpacing)
    local lineHeight = calculateLineHeight(fontSize) 
    local fontGap = calculateFontGap(fontSize)
    local totalSpacing = lineHeight + fontGap + (extraSpacing or 0)
    
    table.insert(self.lines, {
        text = text,
        fontSize = fontSize, 
        color = color,
        y = self.currentY
    })
    
    self.currentY = self.currentY - totalSpacing
end

-- 🎨 Color conversion for GL rendering
local function colorStringToGL(colorString)
    -- Convert BAR color strings like "\255\120\235\120" to GL RGB values
    if colorString == ECO_GREEN then
        return {120/255, 235/255, 120/255, 1}  -- Green
    elseif colorString == ECO_RED then
        return {240/255, 125/255, 125/255, 1}  -- Red
    elseif colorString == ECO_YELLOW then
        return {255/255, 255/255, 150/255, 1}  -- Yellow
    elseif colorString == ECO_WHITE then
        return {1, 1, 1, 1}  -- White
    elseif colorString == ECO_GRAY then
        return {200/255, 200/255, 200/255, 1}  -- Gray
    else
        return {0.8, 0.8, 0.8, 1}  -- Default light gray
    end
end

function LineRenderer:renderAll()
    if font then
        font:Begin()
        font:SetOutlineColor(0, 0, 0, 0.3)  -- Consistent outline
        
        for _, line in ipairs(self.lines) do
            font:Print(line.color .. line.text, self.screenX, line.y, line.fontSize, "tc")
        end
        
        font:End()
    else
        -- GL fallback rendering with proper colors
        for _, line in ipairs(self.lines) do
            local glColor = colorStringToGL(line.color)
            gl.Color(glColor[1], glColor[2], glColor[3], glColor[4])
            gl.Text(line.text, self.screenX, line.y, line.fontSize, "tc")
        end
    end
end

function LineRenderer:getTotalHeight()
    if #self.lines == 0 then return 0 end
    
    -- Calculate from startY to actual bottom of text content
    local lastLine = self.lines[#self.lines]
    
    -- Remove the unnecessary font gap that was added for the last line
    -- since there's no next line below it (font gap is 20% of font size)
    local lastLineFontGap = calculateFontGap(lastLine.fontSize)
    
    -- self.startY - self.currentY already includes all line heights + gaps
    -- Subtract the unnecessary gap for the last line to get actual content height
    return self.startY - self.currentY - lastLineFontGap
end

function LineRenderer:getBackgroundBounds(bgWidth, topPadding, bottomPadding)
    local totalHeight = self:getTotalHeight()
    local topPad = topPadding or 10  -- Default 10px top
    local bottomPad = (bottomPadding or topPad) + BOTTOM_PADDING_ADJUSTMENT  -- Apply adjustment to padding value
    
    local bgHeight = totalHeight + topPad + bottomPad
    local bgX = self.screenX - bgWidth/2
    
    -- Calculate font alignment offset for "tc" (top-center) mode
    local alignmentOffset = 0
    if #self.lines > 0 then
        local firstLineHeight = calculateLineHeight(self.lines[1].fontSize)
        -- "tc" alignment renders text with its top edge at the Y coordinate
        -- Smaller offset needed since we fixed the height calculation
        alignmentOffset = firstLineHeight * 0.05  -- Minimal offset for "tc" alignment
    end
    
    -- Background Y position calculation (removed BOTTOM_PADDING_ADJUSTMENT since it's now in bottomPad)
    local bgY = self.startY - totalHeight - topPad - bottomPad + alignmentOffset + TOP_PADDING_ADJUSTMENT
    
    return bgX, bgY, bgWidth, bgHeight
end

-- Font system
local font

--------------------------------------------------------------------------------
-- 🎯 Player & Team Management Functions
--------------------------------------------------------------------------------

-- Extract player name from team ID (centralized logic) - MUST BE BEFORE updatePlayerInfo
local function getPlayerNameFromTeam(teamID)
    if not teamID then return "Unknown" end
    
    local _, leader = Spring.GetTeamInfo(teamID)
    if leader and leader >= 0 then
        return Spring.GetPlayerInfo(leader) or "Team " .. teamID
    else
        return "Team " .. teamID
    end
end

-- 🔍 Detect which team spectator should track based on selected units
local function detectSpectatorTargetTeam()
    if not isSpectator then
        return myTeamID
    end
    
    -- Check if spectator has full view
    local spec, fullView, fullSelect = Spring.GetSpectatingState()
    if not fullView then
        return myTeamID  -- Limited spectator, use own team
    end
    
    -- PRIORITY 1: Use manual override if set (from hover switching)
    if hasManualOverride and manualTeamOverride then
        return manualTeamOverride
    end
    
    -- PRIORITY 2: Check selected units to determine which team to track
    local selectedUnits = Spring.GetSelectedUnits()
    if selectedUnits and #selectedUnits > 0 then
        -- Use the team of the first selected unit
        local unitTeam = Spring.GetUnitTeam(selectedUnits[1])
        if unitTeam then
            return unitTeam
        end
    end
    
    -- PRIORITY 3: No units selected, try to find first valid team with units
    local teamList = Spring.GetTeamList()
    if teamList then
        for _, teamID in ipairs(teamList) do
            local teamUnits = Spring.GetTeamUnits(teamID)
            if teamUnits and #teamUnits > 0 then
                -- Check if this is a real player team (not Gaia)
                local _, leader = Spring.GetTeamInfo(teamID)
                if leader and leader >= 0 then
                    return teamID
                end
            end
        end
    end
    
    -- Fallback to own team
    return myTeamID
end

-- 👤 Player identification functions
local function updatePlayerInfo()
    myPlayerID = Spring.GetMyPlayerID()
    local _, _, spec, teamID = Spring.GetPlayerInfo(myPlayerID)
    myTeamID = teamID
    isSpectator = spec
    
    -- Detect which team to track
    if isSpectator then
        targetTeamID = detectSpectatorTargetTeam()
        -- Find the player ID for this team
        local _, leader = Spring.GetTeamInfo(targetTeamID)
        targetPlayerID = leader or myPlayerID
    else
        targetPlayerID = myPlayerID  
        targetTeamID = myTeamID
    end
    
    -- Get player name for display using centralized logic
    cachedResults.playerName = getPlayerNameFromTeam(targetTeamID)
end

-- 🎯 Get units belonging to specific player/team
local function getPlayerUnits(forceRefresh)
    if not targetTeamID then return {} end
    
    -- For critical calculations, always get fresh data
    if forceRefresh then
        return Spring.GetTeamUnits(targetTeamID) or {}
    end
    
    -- Use cached units only for non-critical operations
    local currentFrame = Spring.GetGameFrame()
    if unitCache.units and unitCache.teamID == targetTeamID and 
       (currentFrame - lastCacheUpdate) < CACHE_UPDATE_FREQUENCY then
        return unitCache.units
    end
    
    -- Refresh unit cache
    local teamUnits = Spring.GetTeamUnits(targetTeamID) or {}
    unitCache.units = teamUnits
    unitCache.teamID = targetTeamID
    lastCacheUpdate = currentFrame
    
    return teamUnits
end

-- Helper function for 2D distance
local function getDistance2D(x1, z1, x2, z2)
    local dx, dz = x1 - x2, z1 - z2
    return math.sqrt(dx*dx + dz*dz)
end

-- 🎨 Helper function to draw rounded rectangle background
local function drawRoundedRect(x, y, width, height, radius, color)
    -- Set color with transparency
    gl.Color(color[1], color[2], color[3], color[4])
    
    -- For now, just draw a simple rectangle to avoid overlap issues
    -- The radius parameter is kept for future enhancement
    gl.Rect(x, y, x + width, y + height)
    
    -- Reset color
    gl.Color(1, 1, 1, 1)
end

-- Helper function to format numbers with k suffix
local function formatNumber(num)
    if num >= 1000 then
        return string.format("%.1fk", num / 1000)
    else
        return string.format("%.0f", num)
    end
end

--------------------------------------------------------------------------------
-- 🔧 Unit Analysis & Validation Functions  
--------------------------------------------------------------------------------

-- Centralized cache invalidation
local function invalidatePlayerCaches()
    unitCache = {}
    lastCacheUpdate = 0
    cachedResults.isActive = false
    hoveredResults.isActive = false
end

-- Get timer color based on economy status and mode
local function getTimerColor(ecoStatus, isIdleMode)
    debugLog("COLOR", "getTimerColor: idle=" .. tostring(isIdleMode) .. ", eco=" .. tostring(ecoStatus ~= nil))
    if not ecoStatus or not ecoStatus.canAfford then
        return ECO_RED
    elseif ecoStatus.metalPercent < 100 or ecoStatus.energyPercent < 100 then
        return ECO_YELLOW
    else
        return ECO_WHITE  -- Default good economy color for distinction
    end
end

-- Update team target with proper cleanup and feedback
local function updateTeamTarget(newTeamID, reason)
    targetTeamID = newTeamID
    manualTeamOverride = newTeamID
    hasManualOverride = true
    
    -- Find the player ID for this team
    local _, leader = Spring.GetTeamInfo(targetTeamID)
    targetPlayerID = leader or targetPlayerID
    
    -- Update player name
    cachedResults.playerName = getPlayerNameFromTeam(targetTeamID)
    
    -- Clear caches for fresh data
    invalidatePlayerCaches()
    
    -- Provide feedback
    local reasonText = reason and (" (" .. reason .. ")") or ""
    Spring.Echo("Build Timer v2: Hover-switched to " .. cachedResults.playerName .. reasonText)
end

-- Handle hover-based team switching for spectators
local function handleHoverTeamSwitch(unitID, currentFrame)
    if not isSpectator or not unitID or not Spring.ValidUnitID(unitID) then
        return false  -- No switch occurred
    end
    
    local unitTeam = Spring.GetUnitTeam(unitID)
    if not unitTeam or unitTeam == targetTeamID then
        -- Reset hover tracking if hovering over same team
        hoveredTeamID = targetTeamID
        hoveredTeamStartFrame = currentFrame
        return false
    end
    
    -- Track if we're hovering over a new team
    if unitTeam ~= hoveredTeamID then
        hoveredTeamID = unitTeam
        hoveredTeamStartFrame = currentFrame
        return false  -- Just started hovering, no switch yet
    end
    
    -- Check if we should switch teams after delay
    local hoverTime = currentFrame - hoveredTeamStartFrame
    local cooldownSinceLastSwitch = currentFrame - lastHoverTeamSwitch
    
    if hoverTime >= HOVER_TEAM_SWITCH_DELAY and cooldownSinceLastSwitch >= (HOVER_TEAM_SWITCH_DELAY * 2) then
        updateTeamTarget(unitTeam, "locked")
        lastHoverTeamSwitch = currentFrame
        return true  -- Switch occurred
    end
    
    return false  -- No switch yet
end

-- 🎨 Resource Display Formatting Functions

-- Format resource usage rates (M/s, E/s)
local function formatResourceUsage(metalPerSecond, energyPerSecond)
    return "Usage • " .. formatNumber(metalPerSecond) .. " M/s • " .. formatNumber(energyPerSecond) .. " E/s"
end

-- Format resource requirements (M, E)
local function formatResourceRequired(metalCost, energyCost)
    return "Required • " .. formatNumber(metalCost) .. " M • " .. formatNumber(energyCost) .. " E"
end

-- Format resource remaining (M, E)  
local function formatResourceRemaining(metalRemaining, energyRemaining)
    return "Remaining • " .. formatNumber(metalRemaining) .. " M • " .. formatNumber(energyRemaining) .. " E"
end

-- Format storage display with economy-based colors
local function formatResourceStorage(metalStored, energyStored, ecoStatus, isIdleMode)
    local metalStorageColor = ECO_GRAY
    local energyStorageColor = ECO_GRAY
    
    if ecoStatus then
        metalStorageColor = ecoStatus.hasMetalStorage and ECO_GREEN or ECO_RED
        energyStorageColor = ecoStatus.hasEnergyStorage and ECO_GREEN or ECO_RED
    end
    
    return "Storage " .. 
           metalStorageColor .. "• " .. formatNumber(metalStored) .. " M " ..
           energyStorageColor .. "• " .. formatNumber(energyStored) .. " E"
end

-- Generate hover indicator for team switching
local function generateHoverIndicator(hoveredTeamID, targetTeamID, currentFrame)
    if not hoveredTeamID or hoveredTeamID == targetTeamID then
        return ""
    end
    
    local hoverTime = currentFrame - hoveredTeamStartFrame
    if hoverTime < HOVER_TEAM_SWITCH_DELAY then
        local progress = math.floor((hoverTime / HOVER_TEAM_SWITCH_DELAY) * 100)
        local hoveredPlayerName = getPlayerNameFromTeam(hoveredTeamID)
        return " → " .. hoveredPlayerName .. " (" .. progress .. "%)"
    end
    
    return ""
end

-- Render player info line with hover indicator  
local function renderPlayerInfo(lineRenderer, playerName, fontSize, isSpectator, extraSpacing)
    if not isSpectator or not playerName then
        return
    end
    
    local currentFrame = Spring.GetGameFrame()
    local hoverIndicator = generateHoverIndicator(hoveredTeamID, targetTeamID, currentFrame)
    
    lineRenderer:addLine("👤 " .. playerName .. hoverIndicator, fontSize, ECO_GRAY, extraSpacing or 5)
end

-- Format build time consistently (handles infinite, seconds, minutes+seconds)
local function formatBuildTime(buildTime, totalBuildPower)
    debugLog("FORMAT", "formatBuildTime: time=" .. tostring(buildTime) .. ", power=" .. tostring(totalBuildPower))
    if buildTime == math.huge or totalBuildPower == 0 then
        return "∞"
    elseif buildTime < 60 then
        return string.format("%.0fs", buildTime)
    else
        local minutes = math.floor(buildTime / 60)
        local seconds = buildTime % 60
        return string.format("%dm %.0fs", minutes, seconds)
    end
end

-- Generate builder count text for different display modes
local function generateBuilderCountText(builderCount, turretCount, guardingBuilderCount, guardingTurretCount, isIdleMode)
    if isIdleMode then
        -- Idle mode: show ready idle units
        local idleParts = {}
        if builderCount > 0 then
            table.insert(idleParts, builderCount .. " builders")
        end
        if turretCount > 0 then
            table.insert(idleParts, turretCount .. " turrets")
        end
        
        if #idleParts > 0 then
            return "(" .. table.concat(idleParts, " + ") .. " idle)"
        else
            return "No idle builders or turrets in range"
        end
    else
        -- Normal mode: show counts
        local parts = {}
        if builderCount > 0 then
            local builderStr = builderCount .. " builders"
            table.insert(parts, builderStr)
        end
        if turretCount > 0 then
            local turretStr = turretCount .. " turrets"
            table.insert(parts, turretStr)
        end
        return "(" .. table.concat(parts, ", ") .. ")"
    end
end

-- Create default economy status object (for error handling and safe defaults)
local function createDefaultEconomyStatus()
    return {
        canAfford = true,
        metalOk = true,
        energyOk = true,
        metalPercent = 100,
        energyPercent = 100,
        hasMetalStorage = true,
        hasEnergyStorage = true,
        metalStored = 0,
        energyStored = 0,
        metalDeficit = 0,
        energyDeficit = 0
    }
end

-- Nano turret definitions (must be defined before validation functions)
local TURRET_NAMES = {
    "armnanotc", "armnanotcplat", "armnanotct2", "armnanotc2plat", "armrespawn",
    "cornanotc", "cornanotcplat", "cornanotct2", "cornanotc2plat", "correspawn",
    "legnanotc", "legnanotcplat", "legnanotct2", "legnanotct2plat", "legnanotcbase",
    "armnanotct3", "cornanotct3", "legnanotct3",
}

-- Convert names to UnitDefIDs for fast lookup
local TURRET_DEF_IDS = {}

-- 🔧 Unit Type Validation Functions

-- Check if unit is a builder (but not a factory)
local function isBuilderUnit(unitDefID)
    if not unitDefID then debugLog("UNIT", "isBuilderUnit: nil unitDefID"); return false end
    local unitDef = UnitDefs[unitDefID]
    local result = unitDef and unitDef.isBuilder and not unitDef.isFactory
    debugLog("UNIT", "isBuilderUnit(" .. unitDefID .. "): " .. tostring(result))
    return result
end

-- Check if unit is a factory
local function isFactoryUnit(unitDefID)
    if not unitDefID then return false end
    local unitDef = UnitDefs[unitDefID]
    return unitDef and unitDef.isFactory
end

-- Check if unit is a nano turret
local function isTurretUnit(unitDefID)
    if not unitDefID then return false end
    return TURRET_DEF_IDS[unitDefID] == true
end

-- Check if unit is any type of builder (including factories)
local function isAnyBuilderUnit(unitDefID)
    if not unitDefID then return false end
    local unitDef = UnitDefs[unitDefID]
    return unitDef and unitDef.isBuilder
end

debugLog("LOAD", "All utility functions declared successfully")

-- Helper function to check if a MOBILE builder is idle
-- Mobile builders: Building or actively working = busy, GUARD alone = idle
local function isBuilderIdle(unitID)
    -- MOST IMPORTANT: Check if actively building something
    local buildingID = Spring.GetUnitIsBuilding(unitID)
    if buildingID then
        return false  -- Actively building = NOT idle
    end
    
    -- Check if unit is moving (velocity check - mobile builders only)
    local vx, vy, vz = Spring.GetUnitVelocity(unitID)
    if vx and (math.abs(vx) > 0.01 or math.abs(vz) > 0.01) then
        return false  -- Moving = NOT idle
    end
    
    -- No commands = definitely idle
    local commands = Spring.GetUnitCommands(unitID, 1)
    if not commands or #commands == 0 then
        return true  -- No commands = IDLE
    end
    
    -- Has commands - check if it's ONLY guard (guard alone = idle)
    if #commands == 1 and commands[1].id == CMD_GUARD then
        return true  -- Only guarding, not building = IDLE
    end
    
    -- Has other commands = busy
    return false
end

-- Helper function to check if unit is guarding any selected builder
local function isGuardingSelectedBuilder(unitID, selectedBuilders)
    if not selectedBuilders or not next(selectedBuilders) then
        return false, nil
    end
    
    local commands = Spring.GetUnitCommands(unitID, 5)
    if commands then
        for _, cmd in ipairs(commands) do
            if cmd.id == CMD_GUARD and cmd.params and cmd.params[1] then
                local targetID = cmd.params[1]
                if selectedBuilders[targetID] then
                    return true, targetID  -- Guarding a selected builder
                end
            end
        end
    end
    return false, nil
end

-- 🔨 Command idle builders and turrets to guard selected builders
local function commandIdleUnitsToGuard()
    if not showIdleOnly then return 0 end  -- Only work in idle mode
    
    local currentFrame = Spring.GetGameFrame()
    local commandedCount = 0
    local turretCount = 0
    local skippedCooldown = 0
    
    -- Get selected units that are builders (these will be doing the actual building)
    local selectedUnits = Spring.GetSelectedUnits()
    if not selectedUnits or #selectedUnits == 0 then
        -- No selected units to guard
        return 0
    end
    
    -- Find the first selected builder to guard
    local targetBuilder = nil
    for _, unitID in ipairs(selectedUnits) do
        local unitDefID = Spring.GetUnitDefID(unitID)
        if isBuilderUnit(unitDefID) then
            targetBuilder = unitID
            break
        end
    end
    
    if not targetBuilder then
        -- No selected builder to guard
        return 0
    end
    
    -- Found target builder to guard
    
    -- Command idle mobile builders to guard (only those in range)
    if cachedIdleBuilders and #cachedIdleBuilders > 0 then
        for _, builder in ipairs(cachedIdleBuilders) do
            if builder.idle and builder.inRange then  -- Only command idle builders in range
                -- Check cooldown
                local cooldownExpiry = idleBuildersCommanded[builder.id]
                if not cooldownExpiry or currentFrame > cooldownExpiry then
                    -- Issue guard command
                    Spring.GiveOrderToUnit(builder.id, CMD_GUARD, {targetBuilder}, {})
                    
                    -- Track cooldown
                    idleBuildersCommanded[builder.id] = currentFrame + COMMAND_COOLDOWN
                    commandedCount = commandedCount + 1
                else
                    skippedCooldown = skippedCooldown + 1
                end
            end
        end
    end
    
    -- Command idle turrets to guard (only those in range)
    if cachedIdleTurrets and #cachedIdleTurrets > 0 then
        for _, turret in ipairs(cachedIdleTurrets) do
            if turret.idle and turret.inRange then  -- Turrets must be in range
                -- Check cooldown
                local cooldownExpiry = idleBuildersCommanded[turret.id]
                if not cooldownExpiry or currentFrame > cooldownExpiry then
                    -- Issue guard command
                    Spring.GiveOrderToUnit(turret.id, CMD_GUARD, {targetBuilder}, {})
                    
                    -- Track cooldown  
                    idleBuildersCommanded[turret.id] = currentFrame + COMMAND_COOLDOWN
                    turretCount = turretCount + 1
                else
                    skippedCooldown = skippedCooldown + 1
                end
            end
        end
    end
    
    -- Clean up expired cooldowns
    for unitID, expiry in pairs(idleBuildersCommanded) do
        if currentFrame > expiry then
            idleBuildersCommanded[unitID] = nil
        end
    end
    
    -- Set feedback message
    local totalCommanded = commandedCount + turretCount
    if totalCommanded > 0 then
        local parts = {}
        if commandedCount > 0 then
            table.insert(parts, commandedCount .. " builders")
        end
        if turretCount > 0 then
            table.insert(parts, turretCount .. " turrets")
        end
        lastCommandFeedback = "✓ Commanded " .. table.concat(parts, " and ") .. " to guard"
        commandFeedbackTime = currentFrame + FEEDBACK_DURATION
    elseif skippedCooldown > 0 then
        lastCommandFeedback = "⏳ " .. skippedCooldown .. " units on cooldown"
        commandFeedbackTime = currentFrame + FEEDBACK_DURATION
    end
    
    return totalCommanded
end

-- Helper function to check if a NANO TURRET is idle
-- Turrets: Building or actively working = busy, GUARD/FIGHT alone = idle
local function isTurretIdle(unitID)
    -- MOST IMPORTANT: Check if actively building/repairing something
    local buildingID = Spring.GetUnitIsBuilding(unitID)
    if buildingID then
        return false  -- Actively building = NOT idle
    end
    
    -- Check commands but IGNORE state commands AND guard
    local commands = Spring.GetUnitCommands(unitID, 5)
    if commands and #commands > 0 then
        -- Check if turret has REAL work commands (NOT including GUARD)
        for _, cmd in ipairs(commands) do
            -- These are actual work commands for turrets
            if cmd.id == CMD_REPAIR or 
               cmd.id == CMD_RECLAIM or
               cmd.id == CMD_RESURRECT or
               cmd.id < 0 then  -- Negative = build commands
                return false  -- Has real work = NOT idle
            end
            -- GUARD, FIGHT, STOP, WAIT are NOT real work - ignore them
        end
    end
    
    -- Not building, no real work commands (guard is OK) = IDLE
    return true
end

--------------------------------------------------------------------------------
-- 💰 Economy & Resource Calculation Engine
--------------------------------------------------------------------------------

-- Get real-time economy data
local function getEconomyInfo()
    if not targetTeamID then return {} end
    
    local metalCurrent, metalStorage, metalPull, metalIncome = Spring.GetTeamResources(targetTeamID, "metal")
    local energyCurrent, energyStorage, energyPull, energyIncome = Spring.GetTeamResources(targetTeamID, "energy")
    
    return {
        metalNet = (metalIncome or 0) - (metalPull or 0),
        energyNet = (energyIncome or 0) - (energyPull or 0),
        metalIncome = metalIncome or 0,
        energyIncome = energyIncome or 0,
        metalStored = metalCurrent or 0,
        energyStored = energyCurrent or 0,
        metalStorage = metalStorage or 0,
        energyStorage = energyStorage or 0
    }
end

-- Calculate resource gathering time
local function calculateResourceTime(metalCost, energyCost, metalPerSecond, energyPerSecond)
    local eco = getEconomyInfo()
    local metalTime = 0
    local energyTime = 0
    
    -- Calculate actual deficit after using stored resources
    local metalNeeded = math.max(0, metalCost - eco.metalStored)
    local energyNeeded = math.max(0, energyCost - eco.energyStored)
    
    -- If we have enough stored resources, no extra time needed
    if metalNeeded == 0 and energyNeeded == 0 then
        return 0
    end
    
    -- Calculate gathering time if income can't support required rate
    if metalPerSecond > 0 and eco.metalNet < metalPerSecond then
        if metalNeeded > 0 then
            if eco.metalIncome > 0 then
                metalTime = metalNeeded / eco.metalIncome
            else
                metalTime = math.huge
            end
        end
    end
    
    if energyPerSecond > 0 and eco.energyNet < energyPerSecond then
        if energyNeeded > 0 then
            if eco.energyIncome > 0 then
                energyTime = energyNeeded / eco.energyIncome
            else
                energyTime = math.huge
            end
        end
    end
    
    return math.max(metalTime, energyTime)
end

-- Check if economy can support the build
local function getEconomyStatus(metalPerSecond, energyPerSecond, metalCost, energyCost)
    local eco = getEconomyInfo()
    
    local metalAvailable = eco.metalNet
    local energyAvailable = eco.energyNet
    
    local metalProductionPercent = metalPerSecond > 0 and ((metalAvailable / metalPerSecond) * 100) or 100
    local energyProductionPercent = energyPerSecond > 0 and ((energyAvailable / energyPerSecond) * 100) or 100
    
    local hasMetalStorage = eco.metalStored >= metalCost
    local hasEnergyStorage = eco.energyStored >= energyCost
    
    local metalAffordable = metalAvailable >= metalPerSecond or hasMetalStorage
    local energyAffordable = energyAvailable >= energyPerSecond or hasEnergyStorage
    
    return {
        canAfford = metalAffordable and energyAffordable,
        metalOk = metalAffordable,
        energyOk = energyAffordable,
        metalPercent = metalProductionPercent,
        energyPercent = energyProductionPercent,
        hasMetalStorage = hasMetalStorage,
        hasEnergyStorage = hasEnergyStorage,
        metalStored = eco.metalStored,
        energyStored = eco.energyStored,
        metalDeficit = (not hasMetalStorage) and math.max(0, metalPerSecond - metalAvailable) or 0,
        energyDeficit = (not hasEnergyStorage) and math.max(0, energyPerSecond - energyAvailable) or 0
    }
end

-- Calculate construction info for a hovered unit
local function calculateConstructionInfo(unitID, buildProgress)
    local unitDefID = Spring.GetUnitDefID(unitID)
    if not unitDefID then return end
    
    local unitDef = UnitDefs[unitDefID]
    if not unitDef then return end
    
    local ux, uy, uz = Spring.GetUnitPosition(unitID)
    if not ux then return end
    
    -- Find builders working on this unit (only from our target player)
    local totalBuildPower = 0
    local playerUnits = getPlayerUnits(true)  -- Force refresh for accurate calculations
    
    for _, builderID in ipairs(playerUnits) do
        local builderDefID = Spring.GetUnitDefID(builderID)
        if isAnyBuilderUnit(builderDefID) then
            local targetID = Spring.GetUnitIsBuilding(builderID)
            
            if targetID == unitID then
                local buildSpeed = UnitDefs[builderDefID].buildSpeed or 100
                totalBuildPower = totalBuildPower + buildSpeed
            end
        end
    end
    
    -- Calculate resource consumption rates
    local metalCost = unitDef.metalCost or 0
    local energyCost = unitDef.energyCost or 0
    local remainingBuildTime = unitDef.buildTime * (1 - buildProgress)
    
    local constructionTime = totalBuildPower > 0 and (remainingBuildTime / totalBuildPower) or math.huge
    local metalPerSecond = constructionTime > 0 and constructionTime < math.huge and (metalCost * (1 - buildProgress) / constructionTime) or 0
    local energyPerSecond = constructionTime > 0 and constructionTime < math.huge and (energyCost * (1 - buildProgress) / constructionTime) or 0
    
    local remainingMetalCost = metalCost * (1 - buildProgress)
    local remainingEnergyCost = energyCost * (1 - buildProgress)
    
    local resourceGatherTime = calculateResourceTime(remainingMetalCost, remainingEnergyCost, metalPerSecond, energyPerSecond)
    local buildTime = math.max(constructionTime, resourceGatherTime)
    
    -- Format time text using centralized function
    local success, timeText = pcall(formatBuildTime, buildTime, totalBuildPower)
    if not success then debugError("calculateConstructionInfo", timeText); timeText = "?" end
    
    -- Get economy status
    local ecoStatus = nil
    local ecoSuccess, ecoResult = pcall(getEconomyStatus, metalPerSecond, energyPerSecond, remainingMetalCost, remainingEnergyCost)
    if ecoSuccess then
        ecoStatus = ecoResult
    else
        Spring.Echo("Build Timer v2 Economy Error: " .. tostring(ecoResult))
        ecoStatus = createDefaultEconomyStatus()
    end
    
    -- Cache results
    hoveredResults.timeText = timeText
    hoveredResults.buildPowerPerSecond = totalBuildPower
    hoveredResults.ecoStatus = ecoStatus
    hoveredResults.metalPerSecond = metalPerSecond
    hoveredResults.energyPerSecond = energyPerSecond
    hoveredResults.remainingMetalCost = remainingMetalCost
    hoveredResults.remainingEnergyCost = remainingEnergyCost
end

--------------------------------------------------------------------------------
-- 🎨 UI Rendering & Display System
--------------------------------------------------------------------------------

-- Display hover info for construction
local function displayHoverInfo()
    local mx, my = Spring.GetMouseState()
    
    local totalHeight = HOVER_DISTANCE_FROM_CURSOR  -- Distance from mouse
    local screenX, screenY = mx, my - totalHeight
    
    -- 🎯 Initialize LineRenderer for hover display
    LineRenderer:reset(screenY, screenX)
    
    -- 📊 Gather display data
    local ecoStatus = hoveredResults.ecoStatus
    local buildProgressPercent = math.floor((hoveredResults.buildProgress or 0) * 100)
    local timeText = hoveredResults.timeText or "?"
    local buildPowerPerSecond = hoveredResults.buildPowerPerSecond or 0
    local metalPerSecond = hoveredResults.metalPerSecond or 0
    local energyPerSecond = hoveredResults.energyPerSecond or 0
    local remainingMetal = hoveredResults.remainingMetalCost or 0
    local remainingEnergy = hoveredResults.remainingEnergyCost or 0
    
    -- ⏱️ Timer with progress percentage (main line)
    local timerColor = getTimerColor(ecoStatus, false)
    LineRenderer:addLine("⏱️ " .. timeText .. " (" .. buildProgressPercent .. "%)", 24, timerColor, 4)
    
    -- 👤 Player name in spectator mode with hover indicator
    if isSpectator then
        renderPlayerInfo(LineRenderer, cachedResults.playerName, 14, isSpectator, 5)
    end
    
    -- 🔨 Build power being applied
    LineRenderer:addLine("Build • " .. formatNumber(buildPowerPerSecond) .. " BP/s", 16, ECO_GRAY, BOTTOM_BUILD_TEXT_ADJUSTMENT)
    
    -- 💰 Usage rates
    LineRenderer:addLine(formatResourceUsage(metalPerSecond, energyPerSecond), 14, ECO_GRAY)
    
    -- 📦 Remaining resources required
    LineRenderer:addLine(formatResourceRemaining(remainingMetal, remainingEnergy), 14, ECO_GRAY)
    
    -- 🏪 Storage availability (if economy status available)
    if ecoStatus then
        local metalStored = ecoStatus.metalStored or 0
        local energyStored = ecoStatus.energyStored or 0
        LineRenderer:addLine(formatResourceStorage(metalStored, energyStored, ecoStatus, false), 14, ECO_GRAY)
    end
    
    -- 🎨 Draw dynamic background based on actual content size
    local bgX, bgY, bgW, bgH = LineRenderer:getBackgroundBounds(BACKGROUND_WIDTH, HOVER_BACKGROUND_PADDING, HOVER_BACKGROUND_PADDING + BOTTOM_PADDING_ADJUSTMENT)
    drawRoundedRect(bgX, bgY, bgW, bgH, 8, {0, 0, 0, 0.6})
    
    -- 🖼️ Render all text lines
    LineRenderer:renderAll()
end

debugLog("LOAD", "All main functions declared, widget ready for initialization")

--------------------------------------------------------------------------------
-- ⚡ Widget Event Handlers & Main Functions
--------------------------------------------------------------------------------

function widget:Initialize()
    debugLog("INIT", "Widget initializing...")
    -- Initialize player info (works in both regular and spectator mode)
    updatePlayerInfo()
    debugLog("INIT", "Player info updated: teamID=" .. tostring(targetTeamID) .. ", spectator=" .. tostring(isSpectator))
    
    -- Initialize UnitDefID lookup tables
    for _, name in ipairs(TURRET_NAMES) do
        local def = UnitDefNames[name]
        if def then TURRET_DEF_IDS[def.id] = true end
    end
    
    -- Use BAR font system
    if WG.fonts then
        font = WG.fonts.getFont(2)
    end
    
    local modeText = isSpectator and "spectator mode" or "player mode"
    Spring.Echo("Build Timer v2: Initialized in " .. modeText .. " tracking " .. (cachedResults.playerName or "unknown player"))
end

function widget:Shutdown()
    Spring.Echo("Build Timer v2: Shutdown")
end

-- Handle player status changes
function widget:PlayerChanged(playerID)
    -- Update our player information when players change
    updatePlayerInfo()
    
    local modeText = isSpectator and "spectator mode" or "player mode"  
    Spring.Echo("Build Timer v2: Player changed, now in " .. modeText .. " tracking " .. (cachedResults.playerName or "unknown player"))
end

-- Handle unit selection changes (for spectator team switching)
function widget:SelectionChanged(selectedUnits)
    if not isSpectator then
        return  -- Only relevant for spectators
    end
    
    -- Check if we have a new team selected
    if selectedUnits and #selectedUnits > 0 then
        local newTeam = Spring.GetUnitTeam(selectedUnits[1])
        if newTeam then
            -- Clear manual override when user explicitly selects units
            hasManualOverride = false
            manualTeamOverride = nil
            
            if newTeam ~= targetTeamID then
                -- Team has changed, update player info
                updatePlayerInfo()
                
                -- Clear caches to force refresh
                invalidatePlayerCaches()
                
                Spring.Echo("Build Timer v2: Selection-switched to " .. (cachedResults.playerName or "unknown player"))
            end
        end
    else
        -- No units selected - keep the current team (either manual or last selected)
        -- Don't clear manual override here, let hover-switching persist
    end
end

-- Key handler for idle builder toggle (press to toggle on/off)
function widget:KeyPress(key, mods, isRepeat)
    if (key == BACKTICK_KEY_1 or key == BACKTICK_KEY_2) and not isRepeat then
        showIdleOnly = not showIdleOnly  -- Toggle the state
        
        -- Clear cached idle units when turning off
        if not showIdleOnly then
            cachedIdleBuilders = {}
            cachedIdleTurrets = {}
        end
        
        return false
    end
end

-- 🎯 Intercept build commands to auto-command idle builders
function widget:CommandNotify(cmdID, cmdParams, cmdOptions)
    -- Check if placing a building (negative cmdID) and idle mode is active
    if showIdleOnly and cmdID < 0 then
        local buildDefID = -cmdID  -- Convert to positive unit def ID
        local unitDef = UnitDefs[buildDefID]
        local unitName = unitDef and unitDef.name or "unknown"
        
        -- Command idle units to guard the selected builder
        local commanded = commandIdleUnitsToGuard()
        
        -- Still let the original command through for any selected builders
        return false
    end
    
    return false  -- Don't block the command
end

-- Optimized calculation loop with player-specific filtering
function widget:GameFrame()
    frameCounter = frameCounter + 1
    
    -- Periodically update player status and check for team changes in spectator mode
    if frameCounter % PLAYER_CHECK_FREQUENCY == 0 then
        -- Only update if we don't have a manual override
        if not hasManualOverride then
            local oldTeamID = targetTeamID
            updatePlayerInfo()
            
            -- If team changed, clear caches
            if oldTeamID ~= targetTeamID then
                invalidatePlayerCaches()
                
                if isSpectator then
                    Spring.Echo("Build Timer v2: Auto-switched to tracking " .. (cachedResults.playerName or "unknown player"))
                end
            end
        else
            -- Just update player info without changing teams
            myPlayerID = Spring.GetMyPlayerID()
            local _, _, spec, teamID = Spring.GetPlayerInfo(myPlayerID)
            myTeamID = teamID
            isSpectator = spec
        end
    end
    
    -- Only process every UPDATE_FREQUENCY frames
    if frameCounter % UPDATE_FREQUENCY ~= 0 then
        return
    end
    
    -- Reset cached results
    cachedResults.isActive = false
    
    -- Check build mode
    local _, activeCommand = Spring.GetActiveCommand()
    if not activeCommand or activeCommand >= 0 then
        return
    end
    
    -- Get mouse position and world coordinates
    local mx, my = Spring.GetMouseState()
    local _, pos = Spring.TraceScreenRay(mx, my, true)
    
    if not pos then
        return
    end
    
    local unitDef = UnitDefs[-activeCommand]
    if not unitDef or not unitDef.buildTime then
        return
    end
    
    -- Get player-specific units - ALWAYS FRESH for accurate range detection
    local playerUnits = getPlayerUnits(true)  -- Force refresh for accurate calculations
    if not playerUnits or #playerUnits == 0 then
        return
    end
    
    -- Smart build time calculation: check player's builders against their ranges
    local builders = {}
    local selectedUnits = Spring.GetSelectedUnits()
    local selectedBuilders = {}
    
    -- Mark selected builders for special handling
    for _, unitID in ipairs(selectedUnits) do
        local unitDefID = Spring.GetUnitDefID(unitID)
        if isBuilderUnit(unitDefID) then
            selectedBuilders[unitID] = true
        end
    end
    
    -- Check player's builders against placement position
    for _, unitID in ipairs(playerUnits) do
        local unitDefID = Spring.GetUnitDefID(unitID)
        -- Count mobile builders (not nano turrets, not factories)
        if isBuilderUnit(unitDefID) and not isTurretUnit(unitDefID) then
            local bx, by, bz = Spring.GetUnitPosition(unitID)
            if bx then
                local buildRange = UnitDefs[unitDefID].buildDistance or 100
                local distance = getDistance2D(bx, bz, pos[1], pos[3])
                local buildSpeed = UnitDefs[unitDefID].buildSpeed or 100
                
                local isSelected = selectedBuilders[unitID] or false
                local inRange = distance <= buildRange
                
                -- Check if guarding a selected builder
                local isGuarding, guardTarget = isGuardingSelectedBuilder(unitID, selectedBuilders)
                
                -- Add builder if in range OR selected OR guarding selected
                if inRange or isSelected or isGuarding then
                    -- Check if builder is idle (includes guard without building)
                    local idle = isBuilderIdle(unitID)
                    
                    -- Only add builder if showing all OR it's idle (when showing idle only)
                    if not showIdleOnly or idle then
                        builders[#builders + 1] = {
                            id = unitID,
                            buildSpeed = buildSpeed,
                            inRange = inRange,
                            selected = isSelected,
                            distance = distance,
                            buildRange = buildRange,
                            idle = idle,
                            guarding = isGuarding,
                            guardTarget = guardTarget
                        }
                    end
                end
            end
        end
    end
    
    -- Calculate totals and count guarding units
    local builderCount = #builders
    local guardingBuilderCount = 0
    local totalBuildPower = 0
    
    for _, builder in ipairs(builders) do
        totalBuildPower = totalBuildPower + builder.buildSpeed
        if builder.guarding and not builder.selected then
            guardingBuilderCount = guardingBuilderCount + 1
        end
    end
    
    -- Check nano turrets in range from player's units
    local turrets = {}
    for _, unitID in ipairs(playerUnits) do
        local unitDefID = Spring.GetUnitDefID(unitID)
        if isTurretUnit(unitDefID) then
            local tx, ty, tz = Spring.GetUnitPosition(unitID)
            if tx then
                local buildRange = UnitDefs[unitDefID].buildDistance or 300
                local distance = getDistance2D(tx, tz, pos[1], pos[3])
                
                local inRange = distance <= buildRange
                
                -- Check if turret is guarding a selected builder
                local isGuarding, guardTarget = isGuardingSelectedBuilder(unitID, selectedBuilders)
                
                -- Include turret if in range OR guarding selected builder
                if inRange or isGuarding then
                    local idle = isTurretIdle(unitID)
                    local buildSpeed = UnitDefs[unitDefID].buildSpeed or 100
                    
                    -- Only add turret if showing all OR it's idle
                    if not showIdleOnly or idle then
                        turrets[#turrets + 1] = {
                            id = unitID,
                            buildSpeed = buildSpeed,
                            inRange = inRange,
                            idle = idle,
                            guarding = isGuarding,
                            guardTarget = guardTarget
                        }
                        totalBuildPower = totalBuildPower + buildSpeed
                    end
                end
            end
        end
    end
    
    -- 📦 Cache idle builders and turrets for command system (when in idle mode)
    if showIdleOnly then
        cachedIdleBuilders = builders  -- Store the filtered builder list
        cachedIdleTurrets = turrets  -- Store the filtered turret list
        local totalIdle = #builders + #turrets
        -- Cached idle units for command system
    else
        cachedIdleBuilders = {}  -- Clear when not in idle mode
        cachedIdleTurrets = {}  -- Clear when not in idle mode
    end
    
    local turretCount = #turrets
    local guardingTurretCount = 0
    
    -- Count guarding turrets
    for _, turret in ipairs(turrets) do
        if turret.guarding then
            guardingTurretCount = guardingTurretCount + 1
        end
    end
    
    -- Calculate resource consumption rates
    local metalCost = unitDef.metalCost or 0
    local energyCost = unitDef.energyCost or 0
    local constructionTime = totalBuildPower > 0 and (unitDef.buildTime / totalBuildPower) or 0
    local metalPerSecond = constructionTime > 0 and (metalCost / constructionTime) or 0
    local energyPerSecond = constructionTime > 0 and (energyCost / constructionTime) or 0
    
    -- Calculate resource gathering time
    local resourceGatherTime = calculateResourceTime(metalCost, energyCost, metalPerSecond, energyPerSecond)
    
    -- Realistic build time is the maximum of construction time and resource gathering time
    local buildTime = math.max(constructionTime, resourceGatherTime)
    
    if totalBuildPower > 0 then
        local success, timeText = pcall(formatBuildTime, buildTime, totalBuildPower)
        if not success then debugError("GameFrame", timeText); timeText = "?" end
        
        -- Get economy status
        local ecoStatus = getEconomyStatus(metalPerSecond, energyPerSecond, metalCost, energyCost)
        
        -- Cache calculation results
        cachedResults.isActive = true
        cachedResults.timeText = timeText
        cachedResults.builderCount = builderCount
        cachedResults.turretCount = turretCount
        cachedResults.guardingBuilderCount = guardingBuilderCount
        cachedResults.guardingTurretCount = guardingTurretCount
        cachedResults.showingIdle = showIdleOnly
        cachedResults.ecoStatus = ecoStatus
        cachedResults.metalPerSecond = metalPerSecond
        cachedResults.energyPerSecond = energyPerSecond
        cachedResults.metalCost = metalCost
        cachedResults.energyCost = energyCost
        cachedResults.totalBuildPower = totalBuildPower
    end
    
    -- 🌐 Share data with other widgets via WG table
    WG.BuildTimeEstimator = WG.BuildTimeEstimator or {}
    WG.BuildTimeEstimator.showingIdleOnly = showIdleOnly
    WG.BuildTimeEstimator.idleBuilders = cachedIdleBuilders
    WG.BuildTimeEstimator.builderCount = cachedResults.builderCount
    WG.BuildTimeEstimator.turretCount = cachedResults.turretCount
end

function widget:DrawScreen()
    -- Wrap everything in error protection
    local success, err = pcall(function()
    
    -- Always check for hover position, but throttle expensive calculations
    if not cachedResults.isActive then
        local mx, my = Spring.GetMouseState()
        local targetType, unitID = Spring.TraceScreenRay(mx, my)
        
        if targetType == 'unit' then
            -- Process the unit directly
            local foundConstruction = false
            
            if unitID and Spring.ValidUnitID(unitID) then
                -- 🎯 Check for hover-based team switching in spectator mode
                handleHoverTeamSwitch(unitID, Spring.GetGameFrame())
                
                local health, maxHealth, paralyze, capture, buildProgress = Spring.GetUnitHealth(unitID)
                
                -- Check if unit is under construction
                if buildProgress and buildProgress < 1 then
                    foundConstruction = true
                    
                    -- Check if we should calculate/recalculate
                    local currentFrame = Spring.GetGameFrame()
                    local shouldCalculate = false
                    
                    if showIdleOnly then
                        -- Instant calculation with backtick key
                        shouldCalculate = hoveredResults.unitID ~= unitID or (currentFrame - lastHoverUpdate) >= UPDATE_FREQUENCY
                    else
                        -- Throttled calculation for default hover
                        local shouldCheckHoverDefault = (currentFrame - lastHoverCheck) >= HOVER_CHECK_FREQUENCY
                        if shouldCheckHoverDefault then
                            shouldCalculate = hoveredResults.unitID ~= unitID or (currentFrame - lastHoverUpdate) >= UPDATE_FREQUENCY
                            lastHoverCheck = currentFrame
                        end
                    end
                    
                    if shouldCalculate then
                        hoveredResults.isActive = true
                        hoveredResults.unitID = unitID
                        hoveredResults.buildProgress = buildProgress
                        lastHoverUpdate = currentFrame
                        
                        -- Initialize safe defaults
                        hoveredResults.timeText = "?"
                        hoveredResults.buildPowerPerSecond = 0
                        hoveredResults.metalPerSecond = 0
                        hoveredResults.energyPerSecond = 0
                        hoveredResults.ecoStatus = createDefaultEconomyStatus()
                        
                        -- Calculate construction info
                        local calcSuccess, calcErr = pcall(calculateConstructionInfo, unitID, buildProgress)
                        if not calcSuccess then
                            Spring.Echo("Build Timer v2 Calc Error: " .. tostring(calcErr))
                        end
                    else
                        -- Keep showing existing hover info
                        hoveredResults.isActive = true
                    end
                end
            end
            
            -- Clear hover if no construction found
            if not foundConstruction then
                hoveredResults.isActive = false
                hoveredResults.unitID = nil
            end
        else
            -- Clear hover if no valid position
            hoveredResults.isActive = false
            hoveredResults.unitID = nil
        end
    end
    
    -- Check for hover info first
    if hoveredResults.isActive then
        local hoverSuccess, hoverErr = pcall(displayHoverInfo)
        if not hoverSuccess then
            Spring.Echo("Build Timer v2 Hover Error: " .. tostring(hoverErr))
            gl.Color(1, 0, 0, 1)
            gl.Text("HOVER ERROR - Check console", 10, 30, 14)
        end
        return
    end
    
    -- Display build placement info if we have cached results
    if cachedResults.isActive then
        local mx, my = Spring.GetMouseState()
        local _, pos = Spring.TraceScreenRay(mx, my, true)
        
        if pos then
            -- 🎯 Check for hover-based team switching in build mode (spectator only)
            if isSpectator then
                local mouseTargetType, mouseUnitID = Spring.TraceScreenRay(mx, my)
                if mouseTargetType == 'unit' and mouseUnitID then
                    handleHoverTeamSwitch(mouseUnitID, Spring.GetGameFrame())
                end
            end
            
            local totalHeight = BUILD_DISTANCE_FROM_CURSOR  -- Distance from mouse
            local screenX, screenY = mx, my - totalHeight
            
            if screenX and screenY then
                local ecoStatus = cachedResults.ecoStatus
                
                -- 🎯 Initialize LineRenderer for build placement display (dynamic background sizing)
                LineRenderer:reset(screenY, screenX)
                
                -- 📊 Timer color based on economy (gray in idle mode)
                local timerColor = getTimerColor(ecoStatus, cachedResults.showingIdle)
                
                -- ⏱️ Main timer (always first)
                LineRenderer:addLine("⏱️ " .. cachedResults.timeText, 24, timerColor, 4)
                
                -- 🎯 Idle mode indicator (below timer)
                if cachedResults.showingIdle then
                    LineRenderer:addLine("🎯 IDLE COMMAND MODE", 16, ECO_GRAY, 5)  -- Moderate spacing below timer
                end
                
                -- 👤 Player name in spectator mode with hover indicator
                if isSpectator then
                    renderPlayerInfo(LineRenderer, cachedResults.playerName, 14, isSpectator, 5)
                end
                
                -- 🔨 Build power being applied
                LineRenderer:addLine("Build • " .. formatNumber(cachedResults.totalBuildPower) .. " BP/s", 16, ECO_GRAY,BOTTOM_BUILD_TEXT_ADJUSTMENT)
                
                -- 🏗️ Builder and turret count
                local success, builderText = pcall(generateBuilderCountText,
                    cachedResults.builderCount, 
                    cachedResults.turretCount, 
                    cachedResults.guardingBuilderCount, 
                    cachedResults.guardingTurretCount, 
                    cachedResults.showingIdle
                )
                if not success then debugError("DrawScreen", builderText); builderText = "Builder count error" end
                LineRenderer:addLine(builderText, 14, ECO_GRAY)
                
                -- 💰 Usage rates
                LineRenderer:addLine(formatResourceUsage(cachedResults.metalPerSecond, cachedResults.energyPerSecond), 14, ECO_GRAY)
                
                -- 📦 Required resources
                LineRenderer:addLine(formatResourceRequired(cachedResults.metalCost, cachedResults.energyCost), 14, ECO_GRAY)
                
                -- 🏪 Storage availability (gray in idle mode)
                LineRenderer:addLine(formatResourceStorage(ecoStatus.metalStored, ecoStatus.energyStored, ecoStatus, cachedResults.showingIdle), 14, ECO_GRAY)
                
                -- 🎯 Command feedback (if present)
                local currentFrame = Spring.GetGameFrame()
                if commandFeedbackTime > currentFrame then
                    LineRenderer:addLine(lastCommandFeedback, 14, ECO_GRAY)
                end
                
                -- 🎨 Draw dynamic background based on actual content size
                local bgX, bgY, bgW, bgH = LineRenderer:getBackgroundBounds(BACKGROUND_WIDTH, BUILD_BACKGROUND_PADDING, BUILD_BACKGROUND_PADDING + BOTTOM_PADDING_ADJUSTMENT)
                drawRoundedRect(bgX, bgY, bgW, bgH, 8, {0, 0, 0, 0.6})
                
                -- 🖼️ Render all text lines
                LineRenderer:renderAll()
            end
        end
    end
    end)
    
    -- Error handling
    if not success then
        Spring.Echo("Build Timer v2 Error: " .. tostring(err))
        gl.Color(1, 0, 0, 1)
        gl.Text("BUILD TIMER V2 ERROR - Check console", 10, 10, 14)
    end
end
