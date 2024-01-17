function widget:GetInfo()
    return {
        name = "Build Tasks",
        desc = "Shows Current Resource Allocation",
        author = "MasterBel2",
        version = 0,
        date = "Dec 2023",
        license = "GNU GPL, v2 or later",
        layer = 0
    }
end

------------------------------------------------------------------------------------------------------------
-- Imports
------------------------------------------------------------------------------------------------------------

local MasterFramework
local requiredFrameworkVersion = 33
local key

local builderDefIDs = {}
for unitDefID, unitDef in pairs(UnitDefs) do
    if unitDef.buildSpeed > 0 and (not string.find(unitDef.name, 'spy')) and (not (unitDef.name == 'armrectr')) and (not (unitDef.name == 'cornecro')) then
    -- if unitDef.buildSpeed > 0 and not string.find(unitDef.name, 'spy') then
        table.insert(builderDefIDs, unitDefID)
    end
end

local backgroundColor
local contentStack

local buildTaskDisplayCache = {}

local function BuildTaskDisplay(buildTaskID)
    local metalText = MasterFramework:Text("", MasterFramework:Color(1, 1, 1, 1))
    local energyText = MasterFramework:Text("", MasterFramework:Color(1, 1, 0.2, 1))
    local buildPowerText = MasterFramework:Text("", MasterFramework:Color(0.2, 1, 0.2, 1))
    local etaText = MasterFramework:Text("", MasterFramework:Color(0.7, 0.7, 0.7, 1))

    local builderStack = MasterFramework:VerticalStack(
        {},
        MasterFramework:Dimension(8),
        0
    )

    local _buildTask

    local display = MasterFramework:HorizontalStack({
        MasterFramework:Button(
            MasterFramework:Rect(MasterFramework:Dimension(50), MasterFramework:Dimension(50), MasterFramework:Dimension(3), { MasterFramework:Image("#".. Spring.GetUnitDefID(buildTaskID)) }),
            function()
                local alt, ctrl, meta, shift = Spring.GetModKeyState()

                local unitsToSelect = { buildTaskID }

                if alt then
                    if _buildTask then
                        unitsToSelect = table.joinArrays(table.mapToArray(_buildTask.builderIDsByDefs, function(defID, unitIDs) return unitIDs end))
                    else
                        unitsToSelect = {}
                    end
                end
                if ctrl then
                    local selectedUnitsMap = table.imapToTable(Spring.GetSelectedUnits(), function(_, value) return value, true end)
                    for _, unitID in pairs(unitsToSelect) do
                        if selectedUnitsMap[unitID] then
                            selectedUnitsMap[unitID] = nil
                        else
                            selectedUnitsMap[unitID] = true
                        end
                    end

                    Spring.SelectUnitMap(selectedUnitsMap)
                else
                    Spring.SelectUnitArray(unitsToSelect, shift)
                end
            end
        ),
        MasterFramework:VerticalStack({ MasterFramework:HorizontalStack({ metalText, energyText }, MasterFramework:Dimension(8), 0), buildPowerText, etaText }, MasterFramework:Dimension(8), 0),
        builderStack
    }, MasterFramework:Dimension(8), 1)

    function display:Update(buildTask)
        _buildTask = buildTask
        metalText:SetString(string.format("-%d", buildTask.metal))
        energyText:SetString(string.format("-%d", buildTask.energy))
        buildPowerText:SetString(string.format("%d/%d (%d%%)", buildTask.buildPower, buildTask.totalAvailableBuildPower, buildTask.buildPower / buildTask.totalAvailableBuildPower * 100))

        local _, _, _, _, buildProgress = Spring.GetUnitHealth(buildTaskID)

        etaText:SetString(string.format("%.1fs (%d%%)", (1 - buildProgress) * UnitDefs[Spring.GetUnitDefID(buildTaskID)].buildTime / buildTask.buildPower, buildProgress * 100))

        builderStack.members = table.mapToArray(
            buildTask.builderIDsByDefs,
            function(builderDefID, builderIDs)
                local visual = MasterFramework:Rect(MasterFramework:Dimension(30), MasterFramework:Dimension(30), MasterFramework:Dimension(3), { MasterFramework:Image("#".. builderDefID) })

                if #builderIDs > 1 then
                    visual = MasterFramework:StackInPlace({
                        visual,
                        MasterFramework:Text(tostring(#builderIDs))
                    }, 0.975, 0.025)
                end

                return MasterFramework:Button(visual, function()
                    local alt, ctrl, _, shift = Spring.GetModKeyState()

                    local unitsToSelect = builderIDs

                    if alt then
                        unitsToSelect = { unitsToSelect[1] }
                    end
                    if ctrl then
                        local selectedUnitsMap = table.imapToTable(Spring.GetSelectedUnits(), function(_, value) return value, true end)
                        for _, unitID in pairs(unitsToSelect) do
                            if selectedUnitsMap[unitID] then
                                selectedUnitsMap[unitID] = nil
                            else
                                selectedUnitsMap[unitID] = true
                            end
                        end

                        Spring.SelectUnitMap(selectedUnitsMap)
                    else
                        Spring.SelectUnitArray(unitsToSelect, shift)
                    end
                end)
            end
        )
    end

    return display
end

function widget:GameFrame(n)
    contentStack.members = {}

    local buildTasks = {}

    local builderIDs = Spring.GetTeamUnitsByDefs(Spring.GetMyTeamID(), builderDefIDs)

    for _, builderID in ipairs(builderIDs) do
        -- Spring.Echo("builder " .. builderID)
        local buildTaskID = Spring.GetUnitIsBuilding(builderID)
        if buildTaskID then
            -- Spring.Echo("Build task ID: " .. buildTaskID)
            local buildTask = buildTasks[buildTaskID] or { metal = 0, energy = 0, buildPower = 0, totalAvailableBuildPower = 0, builderIDsByDefs = {} }

            local _, metalUse, _, energyUse = Spring.GetUnitResources(builderID)
            local builderDefID = Spring.GetUnitDefID(builderID)

            buildTask.metal = buildTask.metal + metalUse
            buildTask.energy = buildTask.energy + energyUse - UnitDefs[builderDefID].energyUpkeep
            buildTask.buildPower = buildTask.buildPower + Spring.GetUnitCurrentBuildPower(builderID) * UnitDefs[builderDefID].buildSpeed
            buildTask.totalAvailableBuildPower = buildTask.totalAvailableBuildPower + UnitDefs[builderDefID].buildSpeed
            if not buildTask.builderIDsByDefs[builderDefID] then buildTask.builderIDsByDefs[builderDefID] = {} end
            table.insert(buildTask.builderIDsByDefs[builderDefID], builderID)

            buildTasks[buildTaskID] = buildTask
        end
    end

    local displayedBuildTasks = {}
    for buildTaskID, buildTaskData in pairs(buildTasks) do
        displayedBuildTasks[buildTaskID] = buildTaskDisplayCache[buildTaskID] or BuildTaskDisplay(buildTaskID)
        -- Spring.Echo([[testing123]])

        displayedBuildTasks[buildTaskID]:Update(buildTaskData)

        table.insert(
            contentStack.members,
            displayedBuildTasks[buildTaskID]
        )
    end

    buildTaskDisplayCache = displayedBuildTasks

    backgroundColor.a = (#contentStack.members > 0) and 0.7 or 0
end

function widget:DebugInfo()
    return buildTaskDisplayCache
end

function widget:Initialize()
    if MasterFramework then
        MasterFramework = WG.MasterFramework[requiredFrameworkVersion]
    else
        Spring.Echo("[Key Tracker] Error: MasterFramework " .. requiredFrameworkVersion .. " not found! Removing self.")
        widgetHandler:RemoveWidget(self)
        return
    end

    backgroundColor = MasterFramework:Color(0, 0, 0, 0)

    contentStack = MasterFramework:VerticalStack({}, MasterFramework:Dimension(8), 0)

    key = MasterFramework:InsertElement(
        -- MasterFramework:FrameOfReference(
        --     0.5, 0.25,
        MasterFramework:MovableFrame(
            "Build Tasks",
            MasterFramework:PrimaryFrame(
                MasterFramework:MarginAroundRect(
                    contentStack,
                    MasterFramework:Dimension(5),
                    MasterFramework:Dimension(5),
                    MasterFramework:Dimension(5),
                    MasterFramework:Dimension(5),
                    { backgroundColor },
                    MasterFramework:Dimension(5),
                    true
                )
            ),
            1700,
            900
            -- )
        ),
        "Build Tasks",
        MasterFramework.layerRequest.bottom()
    )
end

function widget:Shutdown()
    if WG.MasterStats then WG.MasterStats:Refresh() end
    if MasterFramework then
        MasterFramework:RemoveElement(key)
    end
end