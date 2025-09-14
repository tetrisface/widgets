function widget:GetInfo()
  return {
    name = 'CMD JAOT Build Queue Reclaim',
    desc = 'Just-Ahead-Of-Time build queue reclaiming',
    author = 'tetrisface',
    date = '2025-09-13',
    license = 'GNU GPL, v2 or later',
    layer = 0,
    enabled = true
  }
end

VFS.Include('LuaUI/Widgets/helpers.lua')

local logEntries = {}
local maxLogEntries = 30

-- JIT Reclaim System Configuration
local JIT_RECLAIM_ENABLED = true

-- JIT Reclaim System State
local unitBuildQueues = {} -- unitID -> {buildCmds = {buildID -> buildCmd}, orderedBuilds = {buildID1, buildID2, ...}}
local reclaimQueue = {} -- Queue of reclaim operations to execute
local processedCommands = {} -- Prevent duplicate command processing: "unitID_x_z_buildDefID" -> timestamp
local globalSequenceCounter = 0 -- Global sequence counter for build order preservation
local builderCurrentBuildID = {} -- builderID -> current build ID (hash)
local buildIDCounter = 0 -- Simple counter for generating unique build IDs

-- Timing and performance
local RECLAIM_AHEAD_DISTANCE = 5000
local MAX_RECLAIM_OPERATIONS = 8 -- Max simultaneous reclaim operations (increased for more builders)
local debugMode = false

-- Simplified logging function
local function Log(message, ...)
  if not debugMode then
    return
  end
  local timestamp = string.format('%.2f', Spring.GetGameSeconds())
  local fullMessage = string.format('[%s] %s', timestamp, string.format(message, ...))

  -- Add to log entries for on-screen display
  table.insert(logEntries, {message = fullMessage, time = Spring.GetGameSeconds()})
  if #logEntries > maxLogEntries then
    table.remove(logEntries, 1)
  end

  -- Always echo to console
  Spring.Echo(fullMessage)
end

-- JIT Reclaim System Functions

-- Generate a unique build ID
local function generateBuildID(builderID)
  buildIDCounter = buildIDCounter + 1
  return string.format('build_%d_%d', builderID, buildIDCounter)
end

-- Get the current build and next build IDs for a builder
local function getCurrentAndNextBuildIDs(builderID)
  local queue = unitBuildQueues[builderID]
  if not queue or not queue.orderedBuilds or #queue.orderedBuilds == 0 then
    return nil, nil
  end

  local currentBuildID = builderCurrentBuildID[builderID]
  local currentIndex = nil

  -- Find current build position in the ordered list
  if currentBuildID then
    for i, buildID in ipairs(queue.orderedBuilds) do
      if buildID == currentBuildID then
        currentIndex = i
        break
      end
    end
  end

  -- If no current build or not found, assume we're at the beginning
  if not currentIndex then
    currentIndex = 1
    currentBuildID = queue.orderedBuilds[1]
  end

  local nextBuildID = queue.orderedBuilds[currentIndex + 1]
  return currentBuildID, nextBuildID
end

-- Check if we should reclaim for this build (current + next only)
local function shouldReclaimForBuild(builderID, buildID)
  local currentBuildID, nextBuildID = getCurrentAndNextBuildIDs(builderID)

  local shouldReclaim = (buildID == currentBuildID) or (buildID == nextBuildID)

  if debugMode then
    Log(
      '  Build reclaim check: builder %d, build %s, current: %s, next: %s, should reclaim: %s',
      builderID,
      buildID or 'nil',
      currentBuildID or 'nil',
      nextBuildID or 'nil',
      tostring(shouldReclaim)
    )
  end

  return shouldReclaim
end

-- Simple approach: just store blocking units directly in the build command
local function addBlockingUnit(buildCmd, blockingUnitID)
  if not buildCmd.blockingUnits then
    buildCmd.blockingUnits = {}
  end

  -- Check if already tracked
  for _, unitID in ipairs(buildCmd.blockingUnits) do
    if unitID == blockingUnitID then
      return -- Already tracked
    end
  end

  table.insert(buildCmd.blockingUnits, blockingUnitID)
  Log('Build command blocked by unit %d (total blockers: %d)', blockingUnitID, #buildCmd.blockingUnits)
end

-- Execute build commands that are no longer blocked by a specific unit
local function executeBlockedBuilds(destroyedUnitID)
  Log('EXECUTING BLOCKED BUILDS: Processing destroyed unit %d', destroyedUnitID)

  local foundBlockedBuilds = false
  local totalCommandsProcessed = 0

  -- Go through all builders and their queued commands
  for builderID, queue in pairs(unitBuildQueues) do
    if queue.buildCmds and queue.orderedBuilds then
      local buildsToExecute = {}

      -- Check each build command by ID
      for _, buildID in ipairs(queue.orderedBuilds) do
        local buildCmd = queue.buildCmds[buildID]
        if buildCmd then
          totalCommandsProcessed = totalCommandsProcessed + 1
          if buildCmd.blockingUnits then
            local originalBlockerCount = #buildCmd.blockingUnits

            -- Remove the destroyed unit from this command's blocking list
            local newBlockingUnits = {}
            local wasBlocking = false
            for _, blockingUnitID in ipairs(buildCmd.blockingUnits) do
              if blockingUnitID ~= destroyedUnitID then
                table.insert(newBlockingUnits, blockingUnitID)
              else
                wasBlocking = true
              end
            end
            buildCmd.blockingUnits = newBlockingUnits

            if wasBlocking then
              Log(
                '  Unit %d was blocking build %s for builder %d (%d -> %d blockers)',
                destroyedUnitID,
                buildID,
                builderID,
                originalBlockerCount,
                #newBlockingUnits
              )

              -- If no more blocking units, this command can be executed
              if #buildCmd.blockingUnits == 0 then
                Log(
                  '  Build %s for builder %d is now FULLY UNBLOCKED: %s at (%.1f, %.1f) [seq: %d]',
                  buildID,
                  builderID,
                  UnitDefs[-buildCmd.id].name,
                  buildCmd.params[1],
                  buildCmd.params[3],
                  buildCmd.sequence or 0
                )
                table.insert(buildsToExecute, {buildID = buildID, cmd = buildCmd})
                foundBlockedBuilds = true
              else
                Log('  Build %s for builder %d still has %d remaining blockers', buildID, builderID, #newBlockingUnits)
                foundBlockedBuilds = true
              end
            end
          end
        end
      end

      -- Sort builds by sequence to preserve original order
      table.sort(
        buildsToExecute,
        function(a, b)
          return (a.cmd.sequence or 0) < (b.cmd.sequence or 0)
        end
      )

      -- Execute unblocked commands in sequence order
      for _, buildInfo in ipairs(buildsToExecute) do
        local buildID = buildInfo.buildID
        local buildCmd = buildInfo.cmd

        Log(
          'Executing build %s for builder %d: %s at (%.1f, %.1f, %.1f, %i) [seq: %d]',
          buildID,
          builderID,
          UnitDefs[-buildCmd.id].name,
          buildCmd.params[1],
          buildCmd.params[2],
          buildCmd.params[3],
          buildCmd.params[4] or 0,
          buildCmd.sequence or 0
        )

        -- Calculate options from the stored options
        local opt = 0
        if buildCmd.options then
          if buildCmd.options.alt then
            opt = opt + CMD.OPT_ALT
          end
          if buildCmd.options.ctrl then
            opt = opt + CMD.OPT_CTRL
          end
          if buildCmd.options.shift then
            opt = opt + CMD.OPT_SHIFT
          end
          if buildCmd.options.right then
            opt = opt + CMD.OPT_RIGHT
          end
        end

        -- Always insert at end of queue to maintain order
        local currentCommands = Spring.GetUnitCommands(builderID, -1) or {}
        local insertPos = #currentCommands

        Log('  Inserting at end of queue (pos: %d) to maintain order', insertPos)

        Spring.GiveOrderToUnit(builderID, CMD.INSERT, {insertPos, buildCmd.id, opt, unpack(buildCmd.params)}, {'alt'})

        -- Remove from both hash table and ordered list
        queue.buildCmds[buildID] = nil
        for i, orderedBuildID in ipairs(queue.orderedBuilds) do
          if orderedBuildID == buildID then
            table.remove(queue.orderedBuilds, i)
            break
          end
        end
      end

      -- Clean up empty queues
      if #queue.orderedBuilds == 0 then
        unitBuildQueues[builderID] = nil
        builderCurrentBuildID[builderID] = nil
        Log('Cleared empty build queue for builder %d', builderID)
      end
    end
  end

  Log(
    'EXECUTE BLOCKED BUILDS SUMMARY: Unit %d processed %d total commands, found blocked builds: %s',
    destroyedUnitID,
    totalCommandsProcessed,
    tostring(foundBlockedBuilds)
  )

  if not foundBlockedBuilds then
    Log('Unit %d was not blocking any builds', destroyedUnitID)
  end
end

-- Execute any unblocked builds in queue (for non-blocked builds or builds that become unblocked)
local function executeUnblockedBuilds()
  for builderID, queue in pairs(unitBuildQueues) do
    if queue.buildCmds and queue.orderedBuilds then
      local buildsToExecute = {}

      -- Find builds with no blocking units (originally unblocked OR became unblocked)
      for _, buildID in ipairs(queue.orderedBuilds) do
        local buildCmd = queue.buildCmds[buildID]
        if buildCmd and buildCmd.blockingUnits and #buildCmd.blockingUnits == 0 then
          Log('Found unblocked build %s for builder %d: %s (temporal order preserved)', buildID, builderID, UnitDefs[-buildCmd.id].name)
          table.insert(buildsToExecute, {buildID = buildID, cmd = buildCmd})
        end
      end

      -- Sort builds by sequence to preserve original order
      table.sort(
        buildsToExecute,
        function(a, b)
          return (a.cmd.sequence or 0) < (b.cmd.sequence or 0)
        end
      )

      -- Execute unblocked commands in sequence order
      for _, buildInfo in ipairs(buildsToExecute) do
        local buildID = buildInfo.buildID
        local buildCmd = buildInfo.cmd

        Log(
          'Executing unblocked build %s for builder %d: %s at (%.1f, %.1f, %.1f, %i) [seq: %d]',
          buildID,
          builderID,
          UnitDefs[-buildCmd.id].name,
          buildCmd.params[1],
          buildCmd.params[2],
          buildCmd.params[3],
          buildCmd.params[4] or 0,
          buildCmd.sequence or 0
        )

        -- Calculate options from the stored options
        local opt = 0
        if buildCmd.options then
          if buildCmd.options.alt then
            opt = opt + CMD.OPT_ALT
          end
          if buildCmd.options.ctrl then
            opt = opt + CMD.OPT_CTRL
          end
          if buildCmd.options.shift then
            opt = opt + CMD.OPT_SHIFT
          end
          if buildCmd.options.right then
            opt = opt + CMD.OPT_RIGHT
          end
        end

        -- Always insert at end of queue to maintain order
        local currentCommands = Spring.GetUnitCommands(builderID, -1) or {}
        local insertPos = #currentCommands

        Log('  Inserting at end of queue (pos: %d) to maintain order', insertPos)

        Spring.GiveOrderToUnit(builderID, CMD.INSERT, {insertPos, buildCmd.id, opt, unpack(buildCmd.params)}, {'alt'})

        -- Remove from both hash table and ordered list
        queue.buildCmds[buildID] = nil
        for i, orderedBuildID in ipairs(queue.orderedBuilds) do
          if orderedBuildID == buildID then
            table.remove(queue.orderedBuilds, i)
            break
          end
        end
      end

      -- Clean up empty queues
      if #queue.orderedBuilds == 0 then
        unitBuildQueues[builderID] = nil
        builderCurrentBuildID[builderID] = nil
        Log('Cleared empty build queue for builder %d', builderID)
      end
    end
  end
end

-- Find units that would block a build in the footprint area
local function findBlockingUnitsInFootprint(unitDefID, x, z, facing)
  local unitDef = UnitDefs[unitDefID]
  if not unitDef then
    return {}
  end

  -- Get the footprint dimensions
  local xsize = unitDef.xsize * 8 -- Convert to game units (8 units per square)
  local zsize = unitDef.zsize * 8

  -- Create a search rectangle slightly larger than the footprint
  local searchMargin = 16 -- Extra margin for safety
  local searchX1 = x - (xsize / 2) - searchMargin
  local searchZ1 = z - (zsize / 2) - searchMargin
  local searchX2 = x + (xsize / 2) + searchMargin
  local searchZ2 = z + (zsize / 2) + searchMargin

  -- Find all units in the search rectangle
  local units = Spring.GetUnitsInRectangle(searchX1, searchZ1, searchX2, searchZ2, Spring.GetMyTeamID())
  local blockingUnits = {}

  for _, unitID in ipairs(units) do
    -- Skip our own selected units
    local isSelected = false
    for _, selectedUnit in ipairs(Spring.GetSelectedUnits()) do
      if unitID == selectedUnit then
        isSelected = true
        break
      end
    end

    if not isSelected then
      -- Check if this unit overlaps with the build footprint
      local ux, _, uz = Spring.GetUnitPosition(unitID)
      if ux and uz then
        local unitDefID = Spring.GetUnitDefID(unitID)
        local unitDef = UnitDefs[unitDefID]

        if unitDef then
          local unitXSize = unitDef.xsize * 8 / 2
          local unitZSize = unitDef.zsize * 8 / 2

          -- Check for overlap with build footprint
          local buildHalfX = xsize / 2
          local buildHalfZ = zsize / 2

          local overlapX = math.abs(ux - x) < (unitXSize + buildHalfX)
          local overlapZ = math.abs(uz - z) < (unitZSize + buildHalfZ)

          if overlapX and overlapZ then
            table.insert(
              blockingUnits,
              {
                unitID = unitID,
                position = {ux, 0, uz},
                distance = math.sqrt((ux - x) ^ 2 + (uz - z) ^ 2)
              }
            )
          end
        end
      end
    end
  end

  return blockingUnits
end

-- Find builders near a position (similar to cmd_reclaim_selected.lua)
local function findBuildersNearPosition(x, z, maxDistance)
  -- Search in a circular area because builder ranges are circular
  local units = Spring.GetUnitsInCylinder(x, z, maxDistance, Spring.GetMyTeamID())
  local builders = {}

  for _, unitID in ipairs(units) do
    local unitDefID = Spring.GetUnitDefID(unitID)
    local unitDef = UnitDefs[unitDefID]

    if unitDef and unitDef.isBuilder then
      local bx, _, bz = Spring.GetUnitPosition(unitID)
      local distance = math.sqrt((bx - x) ^ 2 + (bz - z) ^ 2)

      -- Allow both mobile and immobile builders to reclaim
      table.insert(
        builders,
        {
          unitID = unitID,
          distance = distance,
          buildRange = unitDef.buildDistance or 0
        }
      )

      -- Log(
      --   '  Added builder: %s (ID: %d, distance: %.1f, range: %.1f, mobile: %s)',
      --   unitDef.name or 'unknown',
      --   unitID,
      --   distance,
      --   unitDef.buildDistance or 0,
      --   tostring(unitDef.canMove or false)
      -- )
    end
  end

  -- Sort by distance (closest first)
  table.sort(
    builders,
    function(a, b)
      return a.distance < b.distance
    end
  )

  return builders
end

-- Queue a reclaim operation for an obstruction
local function queueReclaimOperation(obstructionType, obstructionID, position, unitID)
  if #reclaimQueue >= MAX_RECLAIM_OPERATIONS then
    Log('Reclaim queue full, skipping reclamation of %s %d', obstructionType, obstructionID)
    return false
  end

  Log(
    'Searching for builders within %.1f units of position (%.1f, %.1f)',
    RECLAIM_AHEAD_DISTANCE,
    position[1],
    position[3]
  )
  local builders = findBuildersNearPosition(position[1], position[3], RECLAIM_AHEAD_DISTANCE)

  -- Remove the blocking unit from the builder list (can't reclaim itself!)
  local filteredBuilders = {}
  for _, builder in ipairs(builders) do
    if builder.unitID ~= obstructionID then
      table.insert(filteredBuilders, builder)
    else
      Log('  Excluding blocking unit %d from builder list (cannot reclaim itself)', obstructionID)
    end
  end
  builders = filteredBuilders

  if #builders == 0 then
    Log('No other builders available for reclamation at (%.1f, %.1f)', position[1], position[3])
    Log('The blocking unit is the only builder in range - build will timeout and proceed')
    return false
  end

  Log('Found %d total builders for reclaim operation', #builders)

  -- Log details about found builders
  -- for i, builder in ipairs(builders) do
    -- local builderDefID = Spring.GetUnitDefID(builder.unitID)
    -- local builderDef = UnitDefs[builderDefID]
    -- local builderName = builderDef and builderDef.name or 'unknown'
    -- Log(
    --   '  Found builder %d: %s (ID: %d, distance: %.1f, range: %.1f)',
    --   i,
    --   builderName,
    --   builder.unitID,
    --   builder.distance,
    --   builder.buildRange
    -- )
  -- end

  local reclaimOp = {
    type = obstructionType,
    id = obstructionID,
    position = position,
    builders = builders,
    unitID = unitID, -- Track which unit this is for
    timestamp = Spring.GetGameSeconds()
  }

  table.insert(reclaimQueue, reclaimOp)

  -- Track this operation for the unit
  if not unitBuildQueues[unitID] then
    unitBuildQueues[unitID] = {}
  end
  if not unitBuildQueues[unitID].reclaimOps then
    unitBuildQueues[unitID].reclaimOps = {}
  end
  table.insert(unitBuildQueues[unitID].reclaimOps, reclaimOp)

  Log('Queued reclaim operation for unit %d: %s %d with %d builders', unitID, obstructionType, obstructionID, #builders)
  return true
end

-- Execute reclaim operations immediately (not queued)
local function executeReclaimOperations()
  if #reclaimQueue == 0 then
    return
  end

  local operationsToRemove = {}

  for i, operation in ipairs(reclaimQueue) do
    local builders = operation.builders
    local targetID = (operation.type == 'feature') and (Spring.GetGameMaxUnits() + operation.id) or operation.id

    -- Issue immediate reclaim commands to all builders in range
    local builderUnitIDs = {}
    for _, builder in ipairs(builders) do
      -- Use the more accurate IsInBuildRange function from helpers.lua
      local inRange = IsInBuildRange(builder.unitID, operation.id)

      -- Get range info for logging (with safety checks)
      local effectiveRange = Spring.GetUnitEffectiveBuildRange(builder.unitID, Spring.GetUnitDefID(operation.id)) or 0
      local separation = Spring.GetUnitSeparation(operation.id, builder.unitID, false, false) or 0

      if inRange then
        table.insert(builderUnitIDs, builder.unitID)
        Log(
          '  Commanding builder %d to reclaim %s %d (separation: %.1f, effective range: %.1f)',
          builder.unitID,
          operation.type,
          operation.id,
          separation,
          effectiveRange
        )
      else
        -- Log(
        --   '  Builder %d too far (separation: %.1f > effective range: %.1f) - skipping',
        --   builder.unitID,
        --   separation,
        --   effectiveRange
        -- )
      end
    end

    if #builderUnitIDs > 0 then
      -- Issue reclaim command using the same format as cmd_reclaim_selected.lua
      local reclaimCommand = {0, CMD.RECLAIM, CMD.OPT_SHIFT, targetID}
      Spring.GiveOrderToUnitArray(builderUnitIDs, CMD.INSERT, reclaimCommand, {'alt'})

      Log(
        'Issued immediate reclaim command to %d builders for %s %d (IDs: %s)',
        #builderUnitIDs,
        operation.type,
        operation.id,
        table.concat(builderUnitIDs, ', ')
      )
    else
      Log('No builders in range to execute reclaim for %s %d', operation.type, operation.id)
    end

    -- Remove operation after issuing commands (execute once)
    operationsToRemove[#operationsToRemove + 1] = i
  end

  -- Remove completed operations
  for i = #operationsToRemove, 1, -1 do
    table.remove(reclaimQueue, operationsToRemove[i])
  end
end

-- Legacy timeout-based processing removed - now using event-driven system

function widget:CommandNotify(id, params, options)
  Log('=== COMMAND NOTIFY ===')
  Log('Command ID: %d', id)

  if params then
    Log('Params: %s', table.concat(params, ', '))
  end

  if options then
    Log(
      'Options: alt=%s, ctrl=%s, shift=%s, right=%s',
      tostring(options.alt),
      tostring(options.ctrl),
      tostring(options.shift),
      tostring(options.right)
    )
  end

  -- Check if this is a build command
  if id < 0 then
    local unitDefID = -id
    local unitDef = UnitDefs[unitDefID]

    if unitDef and params and #params >= 3 then
      local x, y, z = params[1], params[2], params[3]

      -- Create deduplication key for this build command
      local selectedUnits = Spring.GetSelectedUnits()
      for _, selectedUnitID in ipairs(selectedUnits) do
        local commandKey = string.format('%d_%.1f_%.1f_%d', selectedUnitID, x, z, unitDefID)
        local currentTime = Spring.GetGameSeconds()

        -- Check if we've processed this exact command recently (within 1 second)
        if processedCommands[commandKey] and (currentTime - processedCommands[commandKey]) < 1.0 then
          Log('  DUPLICATE COMMAND DETECTED - Ignoring: %s', commandKey)
          Log('=== END COMMAND NOTIFY ===')
          return true -- Block duplicate
        end

        -- Mark this command as processed
        processedCommands[commandKey] = currentTime
      end
    end

    -- Continue with normal processing
    if unitDef then
      if params and #params >= 3 then
        local x, y, z = params[1], params[2], params[3]
        local facing = params[4] or 0

        -- Check for obstructions at the actual build position using Spring.TestBuildOrder
        local canBuild, blockingFeatureID, blockingUnitID = Spring.TestBuildOrder(unitDefID, x, y, z, facing or 0)

        if canBuild == 0 then
          -- Build is blocked
          Log('  *** BUILD WILL BE BLOCKED ***')
          Log('  Blocking feature ID: %s, blocking unit ID: %s', tostring(blockingFeatureID), tostring(blockingUnitID))

          -- Manually detect blocking units in the build footprint
          local detectedBlockingUnits = findBlockingUnitsInFootprint(unitDefID, x, z, facing or 0)
          Log('  Manually detected %d blocking units', #detectedBlockingUnits)

          if JIT_RECLAIM_ENABLED then
            -- Get selected units and queue command for each
            local selectedUnits = Spring.GetSelectedUnits()
            local buildQueued = false

            for _, selectedUnitID in ipairs(selectedUnits) do
              -- Initialize builder state
              if not unitBuildQueues[selectedUnitID] then
                unitBuildQueues[selectedUnitID] = {buildCmds = {}, orderedBuilds = {}}
                builderCurrentBuildID[selectedUnitID] = nil -- Will be set to first build
              end

              -- Generate unique build ID
              local buildID = generateBuildID(selectedUnitID)
              globalSequenceCounter = globalSequenceCounter + 1

              Log('  Queuing blocked build %s - reclaim will be handled by updateBuilderProgress', buildID)

              local buildCmd = {
                id = id,
                params = params,
                options = options,
                timestamp = Spring.GetGameSeconds(),
                blockingUnits = {}, -- Will be populated below
                sequence = globalSequenceCounter, -- For order preservation
                buildID = buildID -- Unique identifier
              }

              -- Add blocking units to this specific build command
              for _, blockingUnit in ipairs(detectedBlockingUnits) do
                addBlockingUnit(buildCmd, blockingUnit.unitID)
              end

              -- Add to both hash table and ordered list
              unitBuildQueues[selectedUnitID].buildCmds[buildID] = buildCmd
              table.insert(unitBuildQueues[selectedUnitID].orderedBuilds, buildID)

              -- NO IMMEDIATE RECLAIMING! Let updateBuilderProgress handle it based on actual build state
              Log('  DEFERRED RECLAIM: Build %s will be handled by updateBuilderProgress when builder reaches it', buildID)

              Log(
                '  Queued BLOCKED build %s for unit %d (total: %d commands, %d blockers)',
                buildID,
                selectedUnitID,
                #unitBuildQueues[selectedUnitID].orderedBuilds,
                #buildCmd.blockingUnits
              )
              buildQueued = true
            end

            if buildQueued then
              -- Block the original command so we can handle it ourselves
              -- No immediate reclaim execution - let updateBuilderProgress handle it
              return true
            end
          else
            Log('  JIT reclaim disabled - build would be canceled')
          end
        elseif canBuild == 2 then
          Log('  *** BUILD WILL NOT BE BLOCKED ***')

          if JIT_RECLAIM_ENABLED then
            -- Even for non-blocked builds, we need to queue them if we're managing build sequences
            local selectedUnits = Spring.GetSelectedUnits()
            local hasActiveQueuedBuilds = false

            -- Check if any selected unit has ANY builds in queue (blocked OR unblocked)
            for _, selectedUnitID in ipairs(selectedUnits) do
              if
                unitBuildQueues[selectedUnitID] and unitBuildQueues[selectedUnitID].orderedBuilds and
                  #unitBuildQueues[selectedUnitID].orderedBuilds > 0
               then
                hasActiveQueuedBuilds = true
                break
              end
            end

            if hasActiveQueuedBuilds then
              Log('  Non-blocked build queued to preserve temporal order with existing queued builds')

              -- Queue this non-blocked build too so it executes in proper order
              for _, selectedUnitID in ipairs(selectedUnits) do
                if unitBuildQueues[selectedUnitID] then
                  -- Generate unique build ID for non-blocked builds too
                  local buildID = generateBuildID(selectedUnitID)
                  globalSequenceCounter = globalSequenceCounter + 1
                  
                  Log('  Queuing non-blocked build %s for sequence preservation', buildID)

                  local buildCmd = {
                    id = id,
                    params = params,
                    options = options,
                    timestamp = Spring.GetGameSeconds(),
                    blockingUnits = {}, -- No blocking units
                    sequence = globalSequenceCounter, -- For order preservation
                    buildID = buildID -- Unique identifier
                  }

                  -- Add to both hash table and ordered list
                  unitBuildQueues[selectedUnitID].buildCmds[buildID] = buildCmd
                  table.insert(unitBuildQueues[selectedUnitID].orderedBuilds, buildID)

                  Log(
                    '  Queued NON-BLOCKED build %s for unit %d (total: %d commands)',
                    buildID,
                    selectedUnitID,
                    #unitBuildQueues[selectedUnitID].orderedBuilds
                  )
                end
              end

              -- Do NOT execute unblocked builds immediately - let updateBuilderProgress handle sequencing
              -- Block this command so we can manage the temporal sequence
              return true
            end
          end
        else
          Log('  Build area is clear')
        end
      else
        Log('  No position parameters found')
      end
    else
      Log('  Unknown unit definition for ID: %d', unitDefID)
    end
  end

  Log('=== END COMMAND NOTIFY ===')

  -- Return false to allow the command to proceed normally
  -- Return true to block the command
  return false
end

function widget:KeyPress(key, mods, isRepeat)
  if key == KEYSYMS.F14 then
    JIT_RECLAIM_ENABLED = not JIT_RECLAIM_ENABLED
    Log('JIT Reclaim %s', JIT_RECLAIM_ENABLED and 'ENABLED' or 'DISABLED')
    return true
  elseif key == KEYSYMS.F15 then
    -- Clear all widget state
    unitBuildQueues = {}
    reclaimQueue = {}
    processedCommands = {}
    globalSequenceCounter = 0
    builderCurrentBuildID = {}
    buildIDCounter = 0
    Log('=== ALL STATE CLEARED ===')
    return true
  end
  return false
end

-- Update builder's current build progress and trigger reclaiming for newly eligible builds
local function updateBuilderProgress(builderID)
  local queue = unitBuildQueues[builderID]
  if not queue or not queue.orderedBuilds or #queue.orderedBuilds == 0 then
    return
  end

  local commands = Spring.GetUnitCommands(builderID, -1) or {}

  -- Count build commands still in Spring queue
  local springBuildCount = 0
  for _, cmd in ipairs(commands) do
    if cmd.id < 0 then -- Build command
      springBuildCount = springBuildCount + 1
    end
  end

  local oldCurrentBuildID = builderCurrentBuildID[builderID]
  local newCurrentBuildID = nil

  -- Calculate total builds (Spring queue + widget managed builds)
  local totalWidgetBuilds = #queue.orderedBuilds
  local totalBuilds = springBuildCount + totalWidgetBuilds

  -- Calculate completed builds based on the difference
  local completedBuilds = math.max(0, totalBuilds - springBuildCount - totalWidgetBuilds)

  -- If spring has builds, those are earlier in the sequence
  -- Widget builds start after all spring builds are done
  if springBuildCount > 0 then
    -- Builder is still working on Spring builds, no widget build is current yet
    newCurrentBuildID = nil
  else
    -- Builder has finished all Spring builds, now working on widget builds
    -- Current widget build is the first one in our queue
    if totalWidgetBuilds > 0 then
      newCurrentBuildID = queue.orderedBuilds[1]
    end
  end

  -- Update current build ID if it changed
  if newCurrentBuildID ~= oldCurrentBuildID then
    builderCurrentBuildID[builderID] = newCurrentBuildID
    Log(
      'Builder %d progress: %s -> %s (spring queue: %d, widget queue: %d)',
      builderID,
      oldCurrentBuildID or 'nil',
      newCurrentBuildID or 'nil',
      springBuildCount,
      totalWidgetBuilds
    )

    -- Check if we need to execute current build or start reclaiming for blocked builds
    if newCurrentBuildID then
      local currentBuildID, nextBuildID = getCurrentAndNextBuildIDs(builderID)
      
      -- Handle current build
      if currentBuildID then
        local currentBuildCmd = queue.buildCmds[currentBuildID]
        if currentBuildCmd then
          -- Check if current build is blocked or unblocked
          if currentBuildCmd.blockingUnits and #currentBuildCmd.blockingUnits > 0 then
            -- Current build is blocked - trigger reclaim
            Log('Triggering reclaim for current build %s (blocked)', currentBuildID)
            for _, blockingUnitID in ipairs(currentBuildCmd.blockingUnits) do
              local ux, _, uz = Spring.GetUnitPosition(blockingUnitID)
              if ux and uz then
                queueReclaimOperation('unit', blockingUnitID, {ux, 0, uz}, builderID)
              end
            end
          else
            -- Current build is unblocked - execute it immediately (temporal order preserved)
            Log('Executing unblocked build %s in temporal order', currentBuildID)

            -- Calculate options from the stored options
            local opt = 0
            if currentBuildCmd.options then
              if currentBuildCmd.options.alt then opt = opt + CMD.OPT_ALT end
              if currentBuildCmd.options.ctrl then opt = opt + CMD.OPT_CTRL end
              if currentBuildCmd.options.shift then opt = opt + CMD.OPT_SHIFT end
              if currentBuildCmd.options.right then opt = opt + CMD.OPT_RIGHT end
            end

            -- Insert at end of Spring queue
            local currentCommands = Spring.GetUnitCommands(builderID, -1) or {}
            local insertPos = #currentCommands
            Log('  Inserting unblocked build at position %d in temporal sequence', insertPos)

            Spring.GiveOrderToUnit(builderID, CMD.INSERT, {insertPos, currentBuildCmd.id, opt, unpack(currentBuildCmd.params)}, {'alt'})

            -- Remove from both hash table and ordered list
            queue.buildCmds[currentBuildID] = nil
            for i, orderedBuildID in ipairs(queue.orderedBuilds) do
              if orderedBuildID == currentBuildID then
                table.remove(queue.orderedBuilds, i)
                break
              end
            end

            -- Update current build ID to next build or clean up empty queue
            if #queue.orderedBuilds > 0 then
              builderCurrentBuildID[builderID] = queue.orderedBuilds[1]
            else
              builderCurrentBuildID[builderID] = nil
              unitBuildQueues[builderID] = nil
              Log('Cleared empty build queue for builder %d after executing unblocked build', builderID)
            end
          end
        end
      end

      -- Reclaim for next build if blocked
      if nextBuildID then
        local nextBuildCmd = queue.buildCmds[nextBuildID]
        if nextBuildCmd and nextBuildCmd.blockingUnits and #nextBuildCmd.blockingUnits > 0 then
          Log('Triggering reclaim for next build %s (blocked)', nextBuildID)
          for _, blockingUnitID in ipairs(nextBuildCmd.blockingUnits) do
            local ux, _, uz = Spring.GetUnitPosition(blockingUnitID)
            if ux and uz then
              queueReclaimOperation('unit', blockingUnitID, {ux, 0, uz}, builderID)
            end
          end
        end
      end
      
      -- Execute all queued reclaim operations
      executeReclaimOperations()
    end
  end
end

function widget:GameFrame(gameFrame)
  -- Update builder progress every 10 frames (~1/3 second) to check for advancement
  if gameFrame % 10 == 0 then
    for builderID, _ in pairs(unitBuildQueues) do
      if Spring.ValidUnitID(builderID) then
        updateBuilderProgress(builderID)
      end
    end
  end

  -- Clean up old processed commands every 30 seconds to prevent memory leaks
  if gameFrame % 900 == 0 then -- 30 seconds at 30fps
    local currentTime = Spring.GetGameSeconds()
    local keysToRemove = {}

    for commandKey, timestamp in pairs(processedCommands) do
      if (currentTime - timestamp) > 30.0 then
        table.insert(keysToRemove, commandKey)
      end
    end

    for _, key in ipairs(keysToRemove) do
      processedCommands[key] = nil
    end

    if #keysToRemove > 0 then
      Log('Cleaned up %d old processed command entries', #keysToRemove)
    end
  end
end

-- Unit lifecycle management
function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
  Log(
    '=== UNIT DESTROYED: %d (DefID: %s, Team: %d) ===',
    unitID,
    unitDefID and UnitDefs[unitDefID].name or 'unknown',
    unitTeam
  )

  -- Debug: Show current build queues with blocking info
  Log('Current build queues before processing:')
  local totalQueuedBuilds = 0
  for builderID, queue in pairs(unitBuildQueues) do
    local commandCount = queue.orderedBuilds and #queue.orderedBuilds or 0
    totalQueuedBuilds = totalQueuedBuilds + commandCount
    if commandCount > 0 then
      Log(
        '  Builder %d has %d builds queued (current: %s)',
        builderID,
        commandCount,
        builderCurrentBuildID[builderID] or 'nil'
      )
      if queue.buildCmds and queue.orderedBuilds then
        for i, buildID in ipairs(queue.orderedBuilds) do
          local cmd = queue.buildCmds[buildID]
          if cmd then
            local blockerCount = cmd.blockingUnits and #cmd.blockingUnits or 0
            local blockerList = cmd.blockingUnits and table.concat(cmd.blockingUnits, ', ') or 'none'
            Log(
              '    Build %d: %s (seq: %d): %s, blocked by %d units (%s)',
              i,
              buildID,
              cmd.sequence or 0,
              UnitDefs[-cmd.id].name,
              blockerCount,
              blockerList
            )
          end
        end
      end
    end
  end
  Log('Total queued builds across all builders: %d', totalQueuedBuilds)

  -- Check if this was a blocking unit that others were waiting for
  Log('Checking if unit %d was blocking any builds...', unitID)
  executeBlockedBuilds(unitID)

  -- Clean up unit's build queue when destroyed
  if unitBuildQueues[unitID] then
    local queueSize = unitBuildQueues[unitID].orderedBuilds and #unitBuildQueues[unitID].orderedBuilds or 0
    Log('Cleaning up build queue for destroyed unit %d (had %d builds)', unitID, queueSize)
    unitBuildQueues[unitID] = nil
  end

  -- Clean up current build tracking
  if builderCurrentBuildID[unitID] then
    builderCurrentBuildID[unitID] = nil
  end
  

  Log('=== END UNIT DESTROYED ===')
end

function widget:UnitGiven(unitID, unitDefID, unitTeam, oldTeam)
  -- Clean up when unit changes ownership
  if unitBuildQueues[unitID] then
    Log('Cleaning up build queue for transferred unit %d', unitID)
    unitBuildQueues[unitID] = nil
  end
  builderCurrentBuildID[unitID] = nil
end

function widget:UnitTaken(unitID, unitDefID, unitTeam, newTeam)
  -- Clean up when unit is taken
  if unitBuildQueues[unitID] then
    Log('Cleaning up build queue for taken unit %d', unitID)
    unitBuildQueues[unitID] = nil
  end
  builderCurrentBuildID[unitID] = nil
end

function widget:Initialize()
  -- Clear any existing state on initialization
  unitBuildQueues = {}
  reclaimQueue = {}
  processedCommands = {}
  globalSequenceCounter = 0
  builderCurrentBuildID = {}
  buildIDCounter = 0

  Log('=== JIT Build Queue Reclaim Widget Initialized (v3.2 Sequential Execution) ===')
  Log('This widget uses hash-based just-ahead-of-time reclaiming with sequential execution:')
  Log('- Preserves perfect temporal build order - builds execute in exact queued sequence')
  Log('- updateBuilderProgress executes builds sequentially: blocked (after reclaim) or unblocked (immediate)')
  Log('- Only reclaims for current and next builds when builder actually reaches them')
  Log('- No more queue reversal - unblocked builds wait their turn in the sequence')
  Log('Press F14 to toggle JIT reclaiming, F15 to clear all state')
end

function widget:Shutdown()
  Log('JIT Build Queue Reclaim Widget shutting down')
end
