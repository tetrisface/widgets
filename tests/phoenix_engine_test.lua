-- Tests for phoenix_engine.lua
-- Run this with: lua tests/phoenix_engine_test.lua

local function assertEq(actual, expected, message)
  if actual ~= expected then
    error(
      string.format(
        'Assertion failed: %s\nExpected: %s\nActual: %s',
        message or '',
        tostring(expected),
        tostring(actual)
      )
    )
  end
end

local function assertTrue(condition, message)
  if condition ~= true then
    error(string.format('Assertion failed: %s', message or 'Expected true'))
  end
end

local function assertFalse(condition, message)
  if condition ~= false then
    error(string.format('Assertion failed: %s', message or 'Expected false'))
  end
end

print('Running Phoenix Engine Tests...')

-- Mock data
local mockUnitDefs = {
  [1] = {xsize = 4, zsize = 4}, -- small building
  [2] = {xsize = 4, zsize = 4} -- small building
}

local mockBuilderID = 100

-- Mock findBlockersAtPosition function
local mockBlockers = {}
local function mockFindBlockersAtPosition(x, z, xsize, zsize, facing, builderID, buildingDefID)
  local key = string.format('%d_%d', x, z)
  return mockBlockers[key] or {}
end

-- Copy the function we're testing (simplified version)
local RECLAIM_SEQUENTIAL_MODE = true

local function shouldReclaimForBuild(pipeline, buildOrder, positionInQueue)
  if not RECLAIM_SEQUENTIAL_MODE then
    return true
  end

  -- Count how many builds ahead of this one are blocked (need reclaim)
  local blockedAheadCount = 0
  for i = 1, positionInQueue - 1 do
    local p = pipeline.currentlyProcessing[i]
    if p then
      local bx, bz = p.params[1], p.params[3]
      local buildingDefIDBeingPlaced = -p.cmdID
      local blockers =
        mockFindBlockersAtPosition(bx, bz, p.xsize, p.zsize, p.facing, pipeline.builderID, buildingDefIDBeingPlaced)
      if #blockers > 0 then
        blockedAheadCount = blockedAheadCount + 1
      end
    end
  end

  -- Only reclaim if we're within the first 2 blocked buildings
  return blockedAheadCount < 2
end

-- Test 1: Non-blocked buildings should allow next blocked buildings to pre-reclaim
print('Test 1: Non-blocked building followed by blocked buildings')
do
  mockBlockers = {
    -- Position 1: no blockers (will build immediately)
    ['100_100'] = {},
    -- Position 2: has blockers (blocked)
    ['200_200'] = {1},
    -- Position 3: has blockers (blocked)
    ['300_300'] = {2},
    -- Position 4: has blockers (blocked)
    ['400_400'] = {3}
  }

  local pipeline = {
    builderID = mockBuilderID,
    currentlyProcessing = {
      {cmdID = -1, params = {100, 0, 100}, xsize = 4, zsize = 4, facing = 0, order = 1}, -- not blocked
      {cmdID = -1, params = {200, 0, 200}, xsize = 4, zsize = 4, facing = 0, order = 2}, -- blocked
      {cmdID = -1, params = {300, 0, 300}, xsize = 4, zsize = 4, facing = 0, order = 3}, -- blocked
      {cmdID = -1, params = {400, 0, 400}, xsize = 4, zsize = 4, facing = 0, order = 4} -- blocked
    }
  }

  -- Position 1 (not blocked): should pre-reclaim (0 blocked ahead)
  assertTrue(shouldReclaimForBuild(pipeline, 1, 1), 'Position 1 should pre-reclaim')

  -- Position 2 (blocked): should pre-reclaim (0 blocked ahead)
  assertTrue(shouldReclaimForBuild(pipeline, 2, 2), 'Position 2 should pre-reclaim')

  -- Position 3 (blocked): should pre-reclaim (1 blocked ahead)
  assertTrue(shouldReclaimForBuild(pipeline, 3, 3), 'Position 3 should pre-reclaim')

  -- Position 4 (blocked): should NOT pre-reclaim (2 blocked ahead)
  assertFalse(shouldReclaimForBuild(pipeline, 4, 4), 'Position 4 should NOT pre-reclaim')

  print("  [PASS] Non-blocked buildings don't count toward pre-reclaim limit")
end

-- Test 2: All blocked buildings
print('Test 2: All blocked buildings')
do
  mockBlockers = {
    ['100_100'] = {1},
    ['200_200'] = {2},
    ['300_300'] = {3},
    ['400_400'] = {4}
  }

  local pipeline = {
    builderID = mockBuilderID,
    currentlyProcessing = {
      {cmdID = -1, params = {100, 0, 100}, xsize = 4, zsize = 4, facing = 0, order = 1},
      {cmdID = -1, params = {200, 0, 200}, xsize = 4, zsize = 4, facing = 0, order = 2},
      {cmdID = -1, params = {300, 0, 300}, xsize = 4, zsize = 4, facing = 0, order = 3},
      {cmdID = -1, params = {400, 0, 400}, xsize = 4, zsize = 4, facing = 0, order = 4}
    }
  }

  -- First 2 should pre-reclaim
  assertTrue(shouldReclaimForBuild(pipeline, 1, 1), 'Position 1 should pre-reclaim')
  assertTrue(shouldReclaimForBuild(pipeline, 2, 2), 'Position 2 should pre-reclaim')

  -- Rest should NOT pre-reclaim
  assertFalse(shouldReclaimForBuild(pipeline, 3, 3), 'Position 3 should NOT pre-reclaim')
  assertFalse(shouldReclaimForBuild(pipeline, 4, 4), 'Position 4 should NOT pre-reclaim')

  print('  [PASS] Only first 2 blocked buildings pre-reclaim')
end

-- Test 3: No blocked buildings
print('Test 3: No blocked buildings')
do
  mockBlockers = {
    ['100_100'] = {},
    ['200_200'] = {},
    ['300_300'] = {}
  }

  local pipeline = {
    builderID = mockBuilderID,
    currentlyProcessing = {
      {cmdID = -1, params = {100, 0, 100}, xsize = 4, zsize = 4, facing = 0, order = 1},
      {cmdID = -1, params = {200, 0, 200}, xsize = 4, zsize = 4, facing = 0, order = 2},
      {cmdID = -1, params = {300, 0, 300}, xsize = 4, zsize = 4, facing = 0, order = 3}
    }
  }

  -- All should return true (but won't actually reclaim anything since no blockers)
  assertTrue(shouldReclaimForBuild(pipeline, 1, 1), 'Position 1 should return true')
  assertTrue(shouldReclaimForBuild(pipeline, 2, 2), 'Position 2 should return true')
  assertTrue(shouldReclaimForBuild(pipeline, 3, 3), 'Position 3 should return true')

  print('  [PASS] Non-blocked buildings all allowed')
end

-- Test 4: Mixed pattern
print('Test 4: Mixed blocked/unblocked pattern')
do
  mockBlockers = {
    ['100_100'] = {}, -- not blocked
    ['200_200'] = {}, -- not blocked
    ['300_300'] = {1}, -- blocked
    ['400_400'] = {}, -- not blocked
    ['500_500'] = {2}, -- blocked
    ['600_600'] = {3} -- blocked
  }

  local pipeline = {
    builderID = mockBuilderID,
    currentlyProcessing = {
      {cmdID = -1, params = {100, 0, 100}, xsize = 4, zsize = 4, facing = 0, order = 1},
      {cmdID = -1, params = {200, 0, 200}, xsize = 4, zsize = 4, facing = 0, order = 2},
      {cmdID = -1, params = {300, 0, 300}, xsize = 4, zsize = 4, facing = 0, order = 3},
      {cmdID = -1, params = {400, 0, 400}, xsize = 4, zsize = 4, facing = 0, order = 4},
      {cmdID = -1, params = {500, 0, 500}, xsize = 4, zsize = 4, facing = 0, order = 5},
      {cmdID = -1, params = {600, 0, 600}, xsize = 4, zsize = 4, facing = 0, order = 6}
    }
  }

  assertTrue(shouldReclaimForBuild(pipeline, 1, 1), 'Position 1 (not blocked) should return true')
  assertTrue(shouldReclaimForBuild(pipeline, 2, 2), 'Position 2 (not blocked) should return true')
  assertTrue(shouldReclaimForBuild(pipeline, 3, 3), 'Position 3 (blocked, 0 ahead) should pre-reclaim')
  assertTrue(shouldReclaimForBuild(pipeline, 4, 4), 'Position 4 (not blocked) should return true')
  assertTrue(shouldReclaimForBuild(pipeline, 5, 5), 'Position 5 (blocked, 1 ahead) should pre-reclaim')
  assertFalse(shouldReclaimForBuild(pipeline, 6, 6), 'Position 6 (blocked, 2 ahead) should NOT pre-reclaim')

  print('  [PASS] Mixed pattern correctly counts only blocked buildings')
end

-- Test 5: Sequential mode disabled
print('Test 5: Sequential mode disabled')
do
  RECLAIM_SEQUENTIAL_MODE = false

  local pipeline = {
    builderID = mockBuilderID,
    currentlyProcessing = {
      {cmdID = -1, params = {100, 0, 100}, xsize = 4, zsize = 4, facing = 0, order = 1},
      {cmdID = -1, params = {200, 0, 200}, xsize = 4, zsize = 4, facing = 0, order = 2},
      {cmdID = -1, params = {300, 0, 300}, xsize = 4, zsize = 4, facing = 0, order = 3}
    }
  }

  -- All should pre-reclaim when sequential mode is off
  assertTrue(shouldReclaimForBuild(pipeline, 1, 1), 'Should pre-reclaim with mode off')
  assertTrue(shouldReclaimForBuild(pipeline, 2, 2), 'Should pre-reclaim with mode off')
  assertTrue(shouldReclaimForBuild(pipeline, 3, 3), 'Should pre-reclaim with mode off')

  RECLAIM_SEQUENTIAL_MODE = true -- restore
  print('  [PASS] Sequential mode disabled allows all pre-reclaim')
end

print('\n=== All tests passed! ===')
