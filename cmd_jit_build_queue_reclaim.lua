function widget:GetInfo()
  return {
    name = 'CMD JIT Build Queue Reclaim',
    desc = 'Just-in-time build queue reclaiming',
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
local unitBuildQueues = {} -- unitID -> {buildCmds = {}, nextSequence = 0}
local reclaimQueue = {} -- Queue of reclaim operations to execute
local processedCommands = {} -- Prevent duplicate command processing: "unitID_x_z_buildDefID" -> timestamp
local globalSequenceCounter = 0 -- Global sequence counter for build order preservation
local builderCurrentBuild = {} -- builderID -> current build index (0-based, matches Spring queue positions)
local builderBuildIndex = {} -- builderID -> next index to assign to new builds
local builderLastSpringBuildCount = {} -- builderID -> last known Spring build queue count

-- Timing and performance  
local RECLAIM_AHEAD_DISTANCE = 600 -- Start reclaiming this far ahead (nano turrets can have 500+ build distance)
local MAX_RECLAIM_OPERATIONS = 8 -- Max simultaneous reclaim operations (increased for more builders)
local debugMode = true

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

-- Check if we should reclaim for this build (current + next only)
local function shouldReclaimForBuild(builderID, buildIndex)
  local currentBuild = builderCurrentBuild[builderID] or 0
  local maxLookahead = 1 -- Only current + next build
  
  -- Reclaim if this is the current build or the next build
  local shouldReclaim = (buildIndex >= currentBuild) and (buildIndex <= currentBuild + maxLookahead)
  
  if debugMode then
    Log('  Build reclaim check: builder %d, build index %d, current %d, should reclaim: %s', 
        builderID, buildIndex, currentBuild, tostring(shouldReclaim))
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
    if queue.buildCmds then
      local commandsToExecute = {}

      -- Check each build command in this builder's queue
      for i, buildCmd in ipairs(queue.buildCmds) do
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
            Log('  Unit %d was blocking build command for builder %d (%d -> %d blockers)', 
                destroyedUnitID, builderID, originalBlockerCount, #newBlockingUnits)
                
            -- If no more blocking units, this command can be executed
            if #buildCmd.blockingUnits == 0 then
              Log('  Build command for builder %d is now FULLY UNBLOCKED: %s at (%.1f, %.1f) [seq: %d]',
                  builderID, UnitDefs[-buildCmd.id].name, buildCmd.params[1], buildCmd.params[3], buildCmd.sequence or 0)
              table.insert(commandsToExecute, {index = i, cmd = buildCmd})
              foundBlockedBuilds = true
            else
              Log('  Build command for builder %d still has %d remaining blockers', builderID, #newBlockingUnits)
              foundBlockedBuilds = true
            end
          end
        end
      end

      -- Sort commands by sequence to preserve original order
      table.sort(commandsToExecute, function(a, b) 
        return (a.cmd.sequence or 0) < (b.cmd.sequence or 0)
      end)
      
      -- Execute unblocked commands in sequence order
      for _, cmdInfo in ipairs(commandsToExecute) do
        local buildCmd = cmdInfo.cmd

        Log('Executing build command for builder %d: %s at (%.1f, %.1f, %.1f, %i) [seq: %d]', 
            builderID, UnitDefs[-buildCmd.id].name, buildCmd.params[1], buildCmd.params[2], 
            buildCmd.params[3], buildCmd.params[4] or 0, buildCmd.sequence or 0)
        
        -- Calculate options from the stored options
        local opt = 0
        if buildCmd.options then
          if buildCmd.options.alt then opt = opt + CMD.OPT_ALT end
          if buildCmd.options.ctrl then opt = opt + CMD.OPT_CTRL end
          if buildCmd.options.shift then opt = opt + CMD.OPT_SHIFT end
          if buildCmd.options.right then opt = opt + CMD.OPT_RIGHT end
        end
        
        -- For shift-queued commands, always append to end to preserve original sequence
        local insertPos = 0  -- Default to front for immediate execution
        
        if buildCmd.options and buildCmd.options.shift then
          -- Insert at end of current queue to preserve sequence order
          local currentCommands = Spring.GetUnitCommands(builderID, -1) or {}
          insertPos = #currentCommands  -- Insert at very end
          Log('  Inserting at end of queue (pos: %d) due to shift queue [seq: %d]', insertPos, buildCmd.sequence or 0)
        else
          Log('  Inserting at front of queue for immediate execution [seq: %d]', buildCmd.sequence or 0)
        end
        
        Spring.GiveOrderToUnit(builderID, CMD.INSERT, {insertPos, buildCmd.id, opt, unpack(buildCmd.params)}, {})
      end
      
      -- Remove executed commands from queue (in reverse order to maintain indices)
      table.sort(commandsToExecute, function(a, b) return a.index > b.index end)
      for _, cmdInfo in ipairs(commandsToExecute) do
        table.remove(queue.buildCmds, cmdInfo.index)
      end

      -- Clean up empty queues
      if #queue.buildCmds == 0 then
        unitBuildQueues[builderID] = nil
        Log('Cleared empty build queue for builder %d', builderID)
      end
    end
  end

  Log('EXECUTE BLOCKED BUILDS SUMMARY: Unit %d processed %d total commands, found blocked builds: %s', 
      destroyedUnitID, totalCommandsProcessed, tostring(foundBlockedBuilds))
      
  if not foundBlockedBuilds then
    Log('Unit %d was not blocking any builds', destroyedUnitID)
  end
end

-- Execute any unblocked builds in queue (for non-blocked builds or builds that become unblocked)
local function executeUnblockedBuilds()
  for builderID, queue in pairs(unitBuildQueues) do
    if queue.buildCmds then
      local commandsToExecute = {}

      -- Find commands with no blocking units
      for i, buildCmd in ipairs(queue.buildCmds) do
        if buildCmd.blockingUnits and #buildCmd.blockingUnits == 0 then
          Log('Found unblocked build command for builder %d: %s', builderID, UnitDefs[-buildCmd.id].name)
          table.insert(commandsToExecute, {index = i, cmd = buildCmd})
        end
      end

      -- Sort commands by sequence to preserve original order
      table.sort(commandsToExecute, function(a, b) 
        return (a.cmd.sequence or 0) < (b.cmd.sequence or 0)
      end)
      
      -- Execute unblocked commands in sequence order
      for _, cmdInfo in ipairs(commandsToExecute) do
        local buildCmd = cmdInfo.cmd

        Log('Executing unblocked build command for builder %d: %s at (%.1f, %.1f, %.1f, %i) [seq: %d]', 
            builderID, UnitDefs[-buildCmd.id].name, buildCmd.params[1], buildCmd.params[2], 
            buildCmd.params[3], buildCmd.params[4] or 0, buildCmd.sequence or 0)
        
        -- Calculate options from the stored options
        local opt = 0
        if buildCmd.options then
          if buildCmd.options.alt then opt = opt + CMD.OPT_ALT end
          if buildCmd.options.ctrl then opt = opt + CMD.OPT_CTRL end
          if buildCmd.options.shift then opt = opt + CMD.OPT_SHIFT end
          if buildCmd.options.right then opt = opt + CMD.OPT_RIGHT end
        end
        
        -- Get current unit commands to find proper insertion position
        local currentCommands = Spring.GetUnitCommands(builderID, -1) or {}
        local insertPos = 0  -- Default to front for immediate execution
        
        -- If this was a shift-queued command, insert at end
        if buildCmd.options and buildCmd.options.shift then
          insertPos = #currentCommands  -- Insert at end of queue
          Log('  Inserting at end of queue (pos: %d) due to shift queue', insertPos)
        else
          Log('  Inserting at front of queue for immediate execution')
        end
        
        Spring.GiveOrderToUnit(builderID, CMD.INSERT, {insertPos, buildCmd.id, opt, unpack(buildCmd.params)}, {})
      end
      
      -- Remove executed commands from queue (in reverse order to maintain indices)  
      table.sort(commandsToExecute, function(a, b) return a.index > b.index end)
      for _, cmdInfo in ipairs(commandsToExecute) do
        table.remove(queue.buildCmds, cmdInfo.index)
      end

      -- Clean up empty queues
      if #queue.buildCmds == 0 then
        unitBuildQueues[builderID] = nil
        Log('Cleared empty build queue for builder %d', builderID)
      end
    end
  end
end

-- Find units that would block a build in the footprint area
local function findBlockingUnitsInFootprint(unitDefID, x, z, facing)
  local unitDef = UnitDefs[unitDefID]
  if not unitDef then return {} end

  -- Get the footprint dimensions
  local xsize = unitDef.xsize * 8  -- Convert to game units (8 units per square)
  local zsize = unitDef.zsize * 8

  -- Create a search rectangle slightly larger than the footprint
  local searchMargin = 16  -- Extra margin for safety
  local searchX1 = x - (xsize/2) - searchMargin
  local searchZ1 = z - (zsize/2) - searchMargin
  local searchX2 = x + (xsize/2) + searchMargin
  local searchZ2 = z + (zsize/2) + searchMargin

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
            table.insert(blockingUnits, {
              unitID = unitID,
              position = {ux, 0, uz},
              distance = math.sqrt((ux - x)^2 + (uz - z)^2)
            })
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
      local distance = math.sqrt((bx - x)^2 + (bz - z)^2)

      -- Allow both mobile and immobile builders to reclaim
      table.insert(builders, {
        unitID = unitID,
        distance = distance,
        buildRange = unitDef.buildDistance or 0
      })

      Log('  Added builder: %s (ID: %d, distance: %.1f, range: %.1f, mobile: %s)',
          unitDef.name or "unknown", unitID, distance, unitDef.buildDistance or 0,
          tostring(unitDef.canMove or false))
    end
  end

  -- Sort by distance (closest first)
  table.sort(builders, function(a, b) return a.distance < b.distance end)

  return builders
end

-- Queue a reclaim operation for an obstruction
local function queueReclaimOperation(obstructionType, obstructionID, position, unitID)
  if #reclaimQueue >= MAX_RECLAIM_OPERATIONS then
    Log('Reclaim queue full, skipping reclamation of %s %d', obstructionType, obstructionID)
    return false
  end

  Log('Searching for builders within %.1f units of position (%.1f, %.1f)', RECLAIM_AHEAD_DISTANCE, position[1], position[3])
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
  for i, builder in ipairs(builders) do
    local builderDefID = Spring.GetUnitDefID(builder.unitID)
    local builderDef = UnitDefs[builderDefID]
    local builderName = builderDef and builderDef.name or "unknown"
    Log('  Found builder %d: %s (ID: %d, distance: %.1f, range: %.1f)',
        i, builderName, builder.unitID, builder.distance, builder.buildRange)
  end

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
  if #reclaimQueue == 0 then return end

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
        Log('  Commanding builder %d to reclaim %s %d (separation: %.1f, effective range: %.1f)', 
            builder.unitID, operation.type, operation.id, separation, effectiveRange)
      else
        Log('  Builder %d too far (separation: %.1f > effective range: %.1f) - skipping', 
            builder.unitID, separation, effectiveRange)
      end
    end

    if #builderUnitIDs > 0 then
      -- Issue reclaim command using the same format as cmd_reclaim_selected.lua
      local reclaimCommand = {0, CMD.RECLAIM, CMD.OPT_SHIFT, targetID}
      Spring.GiveOrderToUnitArray(builderUnitIDs, CMD.INSERT, reclaimCommand, {'alt'})

      Log('Issued immediate reclaim command to %d builders for %s %d (IDs: %s)',
           #builderUnitIDs, operation.type, operation.id, table.concat(builderUnitIDs, ", "))
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

-- Update builder's current build position and trigger reclaiming for newly eligible builds
local function updateBuilderPosition(builderID)
  local commands = Spring.GetUnitCommands(builderID, -1) or {}
  local oldPosition = builderCurrentBuild[builderID] or 0

  -- Simple approach: count build commands remaining in Spring's queue
  -- The current build index is how many builds we've completed
  local springBuildCount = 0
  for _, cmd in ipairs(commands) do
    if cmd.id < 0 then -- Build command
      springBuildCount = springBuildCount + 1
    end
  end

  -- If we have fewer builds in queue than before, we've advanced
  local lastBuildCount = builderLastSpringBuildCount[builderID] or 0
  builderLastSpringBuildCount[builderID] = springBuildCount
  
  -- Only advance position if build count actually decreased (builds completed)
  if springBuildCount < lastBuildCount then
    local buildsCompleted = lastBuildCount - springBuildCount
    local newPosition = oldPosition + buildsCompleted
    builderCurrentBuild[builderID] = newPosition
    
    Log('Builder %d advanced from position %d to %d (%d builds completed, %d remaining in queue)',
        builderID, oldPosition, newPosition, buildsCompleted, springBuildCount)

    -- Check if we need to start reclaiming for newly eligible builds
    if unitBuildQueues[builderID] and unitBuildQueues[builderID].buildCmds then
      local newlyEligibleBuilds = {}
      
      for _, buildCmd in ipairs(unitBuildQueues[builderID].buildCmds) do
        -- Only trigger reclaim for builds that:
        -- 1. Are newly eligible (within current+next range)
        -- 2. Have blocking units
        -- 3. Haven't already been marked for reclaim
        if shouldReclaimForBuild(builderID, buildCmd.buildIndex) 
           and buildCmd.blockingUnits and #buildCmd.blockingUnits > 0 
           and not buildCmd.needsReclaim then
          
          Log('Triggering delayed reclaim for newly eligible build at index %d', buildCmd.buildIndex)
          buildCmd.needsReclaim = true -- Mark as now needing reclaim
          table.insert(newlyEligibleBuilds, buildCmd)
        end
      end
      
      -- Queue reclaim operations for newly eligible builds
      for _, buildCmd in ipairs(newlyEligibleBuilds) do
        for _, blockingUnitID in ipairs(buildCmd.blockingUnits) do
          local ux, _, uz = Spring.GetUnitPosition(blockingUnitID)
          if ux and uz then
            queueReclaimOperation('unit', blockingUnitID, {ux, 0, uz}, builderID)
          end
        end
      end
      
      if #newlyEligibleBuilds > 0 then
        Log('Executing delayed reclaim operations for %d newly eligible builds', #newlyEligibleBuilds)
        executeReclaimOperations()
      end
    end
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
          return true  -- Block duplicate
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
                unitBuildQueues[selectedUnitID] = {buildCmds = {}}
                builderCurrentBuild[selectedUnitID] = 0
                builderBuildIndex[selectedUnitID] = 0
                builderLastSpringBuildCount[selectedUnitID] = 0
              end

              -- Create the build command with sequence tracking
              globalSequenceCounter = globalSequenceCounter + 1
              local buildIndex = builderBuildIndex[selectedUnitID]
              builderBuildIndex[selectedUnitID] = buildIndex + 1
              
              local buildCmd = {
                id = id,
                params = params,
                options = options,
                timestamp = Spring.GetGameSeconds(),
                blockingUnits = {}, -- Will be populated below
                sequence = globalSequenceCounter, -- For order preservation
                buildIndex = buildIndex -- Position in builder's queue
              }

              -- Add blocking units to this specific build command
              for _, blockingUnit in ipairs(detectedBlockingUnits) do
                addBlockingUnit(buildCmd, blockingUnit.unitID)
              end

              -- Add to the queue
              table.insert(unitBuildQueues[selectedUnitID].buildCmds, buildCmd)
              
              -- Only reclaim if this is current or next build
              if shouldReclaimForBuild(selectedUnitID, buildIndex) then
                Log('  IMMEDIATE RECLAIM: Build at index %d needs reclaiming', buildIndex)
                buildCmd.needsReclaim = true -- Mark for immediate reclaim
                
                -- Actually queue reclaim operations for immediate builds only
                for _, blockingUnit in ipairs(detectedBlockingUnits) do
                  local ux, _, uz = Spring.GetUnitPosition(blockingUnit.unitID)
                  if ux and uz then
                    if queueReclaimOperation('unit', blockingUnit.unitID, {ux, 0, uz}, selectedUnitID) then
                      Log('  Immediate reclaim operation queued for blocking unit %d', blockingUnit.unitID)
                    end
                  end
                end
              else
                Log('  DEFERRED RECLAIM: Build at index %d is too far ahead, deferring reclaim (current: %d)', 
                    buildIndex, builderCurrentBuild[selectedUnitID] or 0)
                buildCmd.needsReclaim = false -- Mark as deferred
                -- NO reclaim operations queued - truly deferred!
              end

              Log('  Queued BLOCKED build command for unit %d: index %d (total: %d commands, %d blockers)',
                  selectedUnitID, buildIndex, #unitBuildQueues[selectedUnitID].buildCmds, #buildCmd.blockingUnits)
              buildQueued = true
            end

            if buildQueued then
              -- Only execute reclaim operations if any immediate builds were queued
              local hasImmediateReclaims = false
              for _, selectedUnitID in ipairs(selectedUnits) do
                if unitBuildQueues[selectedUnitID] and unitBuildQueues[selectedUnitID].buildCmds then
                  for _, cmd in ipairs(unitBuildQueues[selectedUnitID].buildCmds) do
                    if cmd.needsReclaim then
                      hasImmediateReclaims = true
                      break
                    end
                  end
                end
                if hasImmediateReclaims then break end
              end
              
              if hasImmediateReclaims then
                Log('Executing reclaim operations for immediate builds only')
                executeReclaimOperations()
              else
                Log('All builds deferred - no immediate reclaim operations executed')
              end

              -- Block the original command so we can handle it ourselves
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
            local hasActiveBlockedBuilds = false

            -- Check if any selected unit has blocked builds in queue
            for _, selectedUnitID in ipairs(selectedUnits) do
              if unitBuildQueues[selectedUnitID] and unitBuildQueues[selectedUnitID].buildCmds and #unitBuildQueues[selectedUnitID].buildCmds > 0 then
                hasActiveBlockedBuilds = true
                break
              end
            end

            if hasActiveBlockedBuilds then
              Log('  Non-blocked build queued because other builds are blocked for same units')

              -- Queue this non-blocked build too so it executes in proper order
              for _, selectedUnitID in ipairs(selectedUnits) do
                if unitBuildQueues[selectedUnitID] then
                  globalSequenceCounter = globalSequenceCounter + 1
                  local buildIndex = builderBuildIndex[selectedUnitID]
                  builderBuildIndex[selectedUnitID] = buildIndex + 1
                  
                  local buildCmd = {
                    id = id,
                    params = params,
                    options = options,
                    timestamp = Spring.GetGameSeconds(),
                    blockingUnits = {}, -- No blocking units
                    sequence = globalSequenceCounter, -- For order preservation
                    buildIndex = buildIndex -- Position in builder's queue
                  }

                  table.insert(unitBuildQueues[selectedUnitID].buildCmds, buildCmd)
                  Log('  Queued NON-BLOCKED build command for unit %d: index %d (total: %d commands)', 
                      selectedUnitID, buildIndex, #unitBuildQueues[selectedUnitID].buildCmds)
                end
              end

              -- Execute any unblocked builds immediately
              executeUnblockedBuilds()

              -- Block this command too so we can manage the sequence
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
    builderCurrentBuild = {}
    builderBuildIndex = {}
    builderLastSpringBuildCount = {}
    reclaimQueue = {}
    processedCommands = {}
    globalSequenceCounter = 0
    Log('=== ALL STATE CLEARED ===')
    Log('Cleared build queues, position tracking, and reclaim operations')
    return true
  end
  return false
end


function widget:GameFrame(gameFrame)
  -- Update builder positions every 10 frames (~1/3 second) to check for advancement
  if gameFrame % 10 == 0 then
    for builderID, _ in pairs(unitBuildQueues) do
      if Spring.ValidUnitID(builderID) then
        updateBuilderPosition(builderID)
      end
    end
  end
  
  -- Clean up old processed commands every 30 seconds to prevent memory leaks
  if gameFrame % 900 == 0 then  -- 30 seconds at 30fps
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
  Log('=== UNIT DESTROYED: %d (DefID: %s, Team: %d) ===', unitID, unitDefID and UnitDefs[unitDefID].name or "unknown", unitTeam)

  -- Debug: Show current build queues with blocking info
  Log('Current build queues before processing:')
  local totalQueuedBuilds = 0
  for builderID, queue in pairs(unitBuildQueues) do
    local commandCount = queue.buildCmds and #queue.buildCmds or 0
    totalQueuedBuilds = totalQueuedBuilds + commandCount
    if commandCount > 0 then
      Log('  Builder %d has %d commands queued', builderID, commandCount)
      if queue.buildCmds then
        for i, cmd in ipairs(queue.buildCmds) do
          local blockerCount = cmd.blockingUnits and #cmd.blockingUnits or 0
          local blockerList = cmd.blockingUnits and table.concat(cmd.blockingUnits, ', ') or 'none'
          Log('    Command %d (seq: %d): %s, blocked by %d units (%s)', 
              i, cmd.sequence or 0, UnitDefs[-cmd.id].name, blockerCount, blockerList)
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
    local queueSize = unitBuildQueues[unitID].buildCmds and #unitBuildQueues[unitID].buildCmds or 0
    Log('Cleaning up build queue for destroyed unit %d (had %d commands)', unitID, queueSize)
    unitBuildQueues[unitID] = nil
  end
  
  -- Clean up position tracking
  builderCurrentBuild[unitID] = nil
  builderBuildIndex[unitID] = nil
  builderLastSpringBuildCount[unitID] = nil
  builderLastSpringBuildCount[unitID] = nil

  Log('=== END UNIT DESTROYED ===')
end

function widget:UnitGiven(unitID, unitDefID, unitTeam, oldTeam)
  -- Clean up when unit changes ownership
  if unitBuildQueues[unitID] then
    Log('Cleaning up build queue for transferred unit %d', unitID)
    unitBuildQueues[unitID] = nil
  end
  builderCurrentBuild[unitID] = nil
  builderBuildIndex[unitID] = nil
  builderLastSpringBuildCount[unitID] = nil
end

function widget:UnitTaken(unitID, unitDefID, unitTeam, newTeam)
  -- Clean up when unit is taken
  if unitBuildQueues[unitID] then
    Log('Cleaning up build queue for taken unit %d', unitID)
    unitBuildQueues[unitID] = nil
  end
  builderCurrentBuild[unitID] = nil
  builderBuildIndex[unitID] = nil
  builderLastSpringBuildCount[unitID] = nil
end

function widget:Initialize()
  Log('=== JIT Build Queue Reclaim Widget Initialized ===')
  Log('This widget uses efficient just-ahead-of-time reclaiming:')
  Log('- Only reclaims for current + next build to maximize early production speed')
  Log('- Defers reclaiming distant builds until needed')
  Log('- Automatically advances as builds complete')
  Log('Press F14 to toggle JIT reclaiming')
  Log('Press F15 to clear all widget state')
end

function widget:Shutdown()
  Log('JIT Build Queue Reclaim Widget shutting down')
end

