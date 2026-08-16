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

local function assertNil(value, message)
  if value ~= nil then
    error(string.format('Assertion failed: %s', message or 'Expected nil'))
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

-- Test 5: Yardmapped families remain protected from Phoenix reclaim. Nanos are
-- intentionally handled by the directional policy below because they have no yardmap.
print('Test 5: Yardmapped evolving economy families are protected')
do
  for _, faction in ipairs({'arm', 'cor', 'leg'}) do
    for _, family in ipairs({'evfus', 'evconv'}) do
      for level = 1, 30 do
        assertTrue(
          replacementPolicy.isProtectedEvolvingUnitName(faction .. family .. level),
          faction .. family .. level .. ' should be protected'
        )
      end
    end

    for level = 1, 30 do
      assertFalse(
        replacementPolicy.isProtectedEvolvingUnitName(faction .. 'evnano' .. level),
        faction .. 'evnano' .. level .. ' should use directional replacement'
      )
    end
  end

  for _, unitName in ipairs({'armnanotct3', 'armevnano', 'armevnano0', 'scavevnano1', 'armevnano1_scav'}) do
    assertFalse(replacementPolicy.isProtectedEvolvingUnitName(unitName), unitName .. ' should not match the whitelist')
  end
  assertFalse(replacementPolicy.isProtectedEvolvingUnitName(nil), 'nil unit names should not match the whitelist')

  print('  [PASS] Yardmapped families are protected and evnano uses directional replacement')
end

-- Test 6: Every faction pairing follows the same strict evnano level ladder.
print('Test 6: Evolving nanos replace only lower evolving nano levels')
do
  local factions = {'arm', 'cor', 'leg'}
  for _, existingFaction in ipairs(factions) do
    for _, placingFaction in ipairs(factions) do
      for existingLevel = 1, 30 do
        for placingLevel = 1, 30 do
          local existingName = existingFaction .. 'evnano' .. existingLevel
          local placingName = placingFaction .. 'evnano' .. placingLevel
          local actual = replacementPolicy.getEvolvingNanoReplacementDecision(existingName, placingName)
          local expected = placingLevel > existingLevel
          if expected then
            assertTrue(actual, placingName .. ' should replace ' .. existingName)
          else
            assertFalse(actual, placingName .. ' should not replace ' .. existingName)
          end
        end
      end
    end
  end

  assertNil(
    replacementPolicy.getEvolvingNanoReplacementDecision('armevconv1', 'armevnano2'),
    'mixed evolving families should defer to normal Phoenix rules'
  )
  assertNil(
    replacementPolicy.getEvolvingNanoReplacementDecision('armnanotct3', 'armevnano2'),
    'non-evolving nanos should defer to normal Phoenix rules'
  )

  print('  [PASS] Same and descending levels are rejected; ascending levels are allowed cross-faction')
end

-- Test 7: Base Builder is identified by display name and never replaced
print('Test 7: Protected display names')
do
  assertTrue(replacementPolicy.isProtectedHumanName('Base Builder'), 'Base Builder should be protected')
  assertFalse(replacementPolicy.isProtectedHumanName('Construction Turret'), 'Ordinary nanos should not be protected by display name')
  assertFalse(replacementPolicy.isProtectedHumanName('base builder'), 'Display name match should be exact')
  assertFalse(replacementPolicy.isProtectedHumanName(nil), 'nil display names should not match')

  print('  [PASS] Base Builder display name is protected')
end

print('\n=== All tests passed! ===')
