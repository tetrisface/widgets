-- Tests for phoenix_engine.lua
-- Run this with: lua tests/phoenix_engine_test.lua

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

local pipelinePolicy = dofile('Widgets/phoenix_engine/include/pipeline_policy.lua')
local replacementPolicy = dofile('Widgets/phoenix_engine/include/replacement_policy.lua')

local mockBuilderID = 100

local RECLAIM_SEQUENTIAL_MODE = true
local MAX_CONCURRENT_RECLAIMS = 2

-- The reclaim window is positional over currentlyProcessing: the list only
-- contains incomplete builds (completed ones are removed by the caller), so
-- only its first MAX_CONCURRENT_RECLAIMS entries may reclaim. Builds under
-- construction keep their slot until completion.
local function shouldReclaimForBuild(pipeline, positionInQueue)
  local eligibility = pipelinePolicy.getReclaimEligibility(
    pipeline.currentlyProcessing,
    RECLAIM_SEQUENTIAL_MODE,
    MAX_CONCURRENT_RECLAIMS
  )
  return eligibility[pipeline.currentlyProcessing[positionInQueue]] == true
end

local function makeBuild(order, x, z)
  return {cmdID = -1, params = {x, 0, z}, xsize = 4, zsize = 4, facing = 0, order = order}
end

-- Test 1: Only the first MAX_CONCURRENT_RECLAIMS builds are eligible
print('Test 1: Positional window limits reclaim to first ' .. MAX_CONCURRENT_RECLAIMS .. ' builds')
do
  local pipeline = {
    builderID = mockBuilderID,
    currentlyProcessing = {
      makeBuild(1, 100, 100),
      makeBuild(2, 200, 200),
      makeBuild(3, 300, 300),
      makeBuild(4, 400, 400)
    }
  }

  assertTrue(shouldReclaimForBuild(pipeline, 1), 'Position 1 should pre-reclaim')
  assertTrue(shouldReclaimForBuild(pipeline, 2), 'Position 2 should pre-reclaim')
  assertFalse(shouldReclaimForBuild(pipeline, 3), 'Position 3 should NOT pre-reclaim')
  assertFalse(shouldReclaimForBuild(pipeline, 4), 'Position 4 should NOT pre-reclaim')

  print('  [PASS] Only the first ' .. MAX_CONCURRENT_RECLAIMS .. ' incomplete builds pre-reclaim')
end

-- Test 2: A build under construction still occupies its slot.
-- Issuing the build order does not free reclaim capacity; only completion
-- (removal from currentlyProcessing) advances the window.
print('Test 2: Under-construction build keeps its slot')
do
  local underConstruction = makeBuild(1, 100, 100)
  local pipeline = {
    builderID = mockBuilderID,
    buildingsUnderConstruction = {[1] = {position = {100, 100}, footprint = {16, 16}}},
    currentlyProcessing = {
      underConstruction,
      makeBuild(2, 200, 200),
      makeBuild(3, 300, 300)
    }
  }

  assertTrue(shouldReclaimForBuild(pipeline, 2), 'Position 2 should pre-reclaim')
  assertFalse(shouldReclaimForBuild(pipeline, 3), 'Position 3 should NOT pre-reclaim while position 1 is still under construction')

  print('  [PASS] Build order issuance does not free reclaim capacity')
end

-- Test 3: Completion advances the window
print('Test 3: Completed build removal advances the window')
do
  local pipeline = {
    builderID = mockBuilderID,
    currentlyProcessing = {
      makeBuild(1, 100, 100),
      makeBuild(2, 200, 200),
      makeBuild(3, 300, 300)
    }
  }

  assertFalse(shouldReclaimForBuild(pipeline, 3), 'Position 3 should NOT pre-reclaim initially')

  -- Build 1 completes: the caller removes it from currentlyProcessing
  table.remove(pipeline.currentlyProcessing, 1)

  assertTrue(shouldReclaimForBuild(pipeline, 1), 'Old position 2 should pre-reclaim')
  assertTrue(shouldReclaimForBuild(pipeline, 2), 'Old position 3 should pre-reclaim after a completion')

  print('  [PASS] Window advances only when a build completes')
end

-- Test 4: Sequential mode disabled
print('Test 4: Sequential mode disabled')
do
  RECLAIM_SEQUENTIAL_MODE = false

  local pipeline = {
    builderID = mockBuilderID,
    currentlyProcessing = {
      makeBuild(1, 100, 100),
      makeBuild(2, 200, 200),
      makeBuild(3, 300, 300)
    }
  }

  assertTrue(shouldReclaimForBuild(pipeline, 1), 'Should pre-reclaim with mode off')
  assertTrue(shouldReclaimForBuild(pipeline, 2), 'Should pre-reclaim with mode off')
  assertTrue(shouldReclaimForBuild(pipeline, 3), 'Should pre-reclaim with mode off')

  RECLAIM_SEQUENTIAL_MODE = true -- restore
  print('  [PASS] Sequential mode disabled allows all pre-reclaim')
end

-- Test 5: Evolving economy units keep their yardmap-defined placement rules.
print('Test 5: Evolving families are protected from automatic reclaim')
do
  for _, faction in ipairs({'arm', 'cor', 'leg'}) do
    for _, family in ipairs({'evfus', 'evconv', 'evnano'}) do
      for level = 1, 30 do
        assertTrue(
          replacementPolicy.isProtectedEvolvingUnitName(faction .. family .. level),
          faction .. family .. level .. ' should be protected'
        )
      end
    end
  end

  for _, unitName in ipairs({'armnanotct3', 'armevnano', 'armevnano0', 'scavevnano1', 'armevnano1_scav'}) do
    assertFalse(replacementPolicy.isProtectedEvolvingUnitName(unitName), unitName .. ' should not match the whitelist')
  end
  assertFalse(replacementPolicy.isProtectedEvolvingUnitName(nil), 'nil unit names should not match the whitelist')

  print('  [PASS] All 30 levels of evfus, evconv, and evnano are protected by name')
end

print('\n=== All tests passed! ===')
