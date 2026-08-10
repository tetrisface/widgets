# eco_cons.lua — bug fixes & efficiency improvements

## Context

`Widgets/eco_cons.lua` (~1900 lines) is a BAR widget that auto-manages constructors: assigns them to eco builds by need (power/energy/metal-makers), purges stale repair orders, opportunistically reclaims wrecks, and fast-forwards assisted build queues. The user asked for an efficiency review plus an investigation of blatant bugs. The review found one structural corruption bug (builder tracking desyncs on every unit death), several dead/broken features, a few nil-crash hazards, and multiple per-frame hot spots doing redundant engine calls.

Key dependency semantics (verified in `c:/Users/a/git/Beyond-All-Reason/common/SetList.lua`): `SetList:Remove(key)` is a **swap-remove** — it moves the _last_ element into the removed slot and updates its hash index. `SetList:Add` silently no-ops on duplicates and returns nothing.

## Implementation status

Completed on 2026-08-10. The widget fixes and optimizations are covered by 13 deterministic Lua regression scenarios, including BAR's `_G == nil` widget environment. Lua syntax, Luacheck 1.2.0, and whitespace/diff validation pass.

---

## Part 1 — Blatant bugs (priority order)

### B1. `builders` parallel array desyncs on every removal — CRITICAL

`widget:UnitDestroyed` (eco_cons.lua:383) does `builders[index] = nil` then `builderUnitIds:Remove(unitID)`. The swap-remove moves the last unit's id into `index`, so that live unit's hash now points at the slot just nil'ed, and its real record is stranded at the old tail index. Every subsequent `BuilderById(thatUnit)` returns nil → the widget treats a _live_ builder as destroyed, and the corruption compounds with each death.

Related: `widget:UnitFinished` (line 361) does `builderUnitIds:Add(unitID); builders[builderUnitIds.count] = {...}` — if the id is already in the set, `Add` no-ops and the write **overwrites another builder's record** at the tail slot. The 300-frame rescan (line 1768) duplicates this same add code and hits exactly this case once B1 has corrupted the arrays.

**Fix:** stop mirroring SetList indices. Key records by unit id: `builders[unitID] = {...}`; `BuilderById(id)` → `builders[id]`. Keep `builderUnitIds` purely for ordered iteration (`builders[builderUnitIds.list[i]]`). Extract one `AddBuilder(unitID, unitDefID)` helper (guarded by `builderUnitIds.hash[unitID]`) used by `UnitFinished` and the rescan, and one `RemoveBuilder(unitID)` used by `UnitDestroyed`.

### B2. `BuilderById` self-heal is a no-op

`BuilderById` (line 197) calls `widget:UnitDestroyed(id)` with no team argument; `UnitDestroyed` starts with `if unitTeam == myTeamId` → nothing ever happens, stale ids are never cleaned. With B1's fix, have `BuilderById` call `RemoveBuilder(id)` directly.

### B3. Widget silently stops at responsiveness 3x/4x with few builders

`GameFrameModulo()` (line 1695): base modulo is `1` for ≤15 builders; ×`frameStaggeringModuloMultiplier` (1/3 or 1/4) → `math.floor(0.5 + 0.33) = 0`. Then `gameFrame % 0` is NaN, `NaN ~= 0`, so `Builders()` **never runs**. Fix: `math.max(1, ...)` around the result.

### B4. Ctrl+L debug feature is dead (inverted logic + no-op log)

- `Builders()` line 1668: `if not isUnitLogActive then` populate `selectedUnits` — inverted. When logging is ON, `selectedUnits` stays empty so `IsUnitSelectedLog` is always false and selected builders lose their "don't touch my selection" protection.
- Line 131: `log = function() end` permanently overrides the `Spring.Echo`-backed `log` from helpers.lua, so _all_ feedback (including the Ctrl+Shift+T responsiveness toast) is silent.

**Fix:** always populate `selectedUnits`; make Ctrl+L toggle `log` between no-op and `Spring.Echo` (keep no-op as default to preserve current silence).

Implementation clarification: normal mode continues to protect selected builders. Debug mode deliberately allows selected builders through the per-builder processing path so the selected-unit diagnostics can execute. User-triggered responsiveness changes echo directly even while diagnostic logging is disabled.

### B5. Metal-maker totals corrupted by unrelated unit deaths

`UnregisterMetalMaker` (line 332) subtracts `energyUpkeep`/`makesMetal` for **every** destroyed team unit, registered or not — any non-maker with energy upkeep (radar, jammer) skews `possibleMetalMakersUpkeep` on death. Also, when the def can't be resolved, a registered maker's totals are never subtracted (permanent leak). **Fix:** store `{upkeep, makesMetal}` in `metalMakers[unitID]` at register time; unregister early-returns if not registered and subtracts the _stored_ values.

### B6. Reclaim-cancel-on-overflow branch never fires

`tryReclaimOrGuard` (line 1176): `featureId = cmdQueue[1].params[1]` — for feature reclaim orders the param is `Game.maxUnits + featureId`, so `GetFeatureResources(featureId)` always returns nil and the cancel never happens. Also misreads area-reclaim orders (4 params: x,y,z,radius). **Fix:** only handle single-param orders; subtract `Game.maxUnits` when `params[1] > Game.maxUnits` (skip unit-reclaim ids).

### B7. Nil-crash hazards

- `SetBuilderLastOrder` (line 206): `BuilderById(...).lastOrder` — crashes if nil (mitigated by B1 but still guard).
- `WG['ObjectSpotlight'].addSpotlight` (lines 1476, 1623): crashes if that widget isn't loaded → guard `local spotlight = WG['ObjectSpotlight']; if spotlight then ...`.
- `Spring.GetTeamRulesParam(myTeamId, 'mmLevel')` (lines 725, 1730): nil if the rules param is absent → `(... or 0)` / skip the send.
- `traceUpkeep` (line 842): `BuilderById(guardID).owned` — `.owned` is never set anywhere and `builder.guards` is never populated; the loop is dead code that would crash if it ever ran. Delete the loop.

### B8. Small correctness items

- `widget:Initialize` (line 251): missing `return` after `widgetHandler:RemoveWidget()` — spectators still register `WG['eco_cons']`, scan defs, etc.
- `widget:GameFrame` (line 1725): sends the conversion-level `SendLuaRulesMsg` **every frame** (30/s) while metal > 0.96 — throttle to the `gameFrameModulo` cadence.
- `hasMultiSlotBuildQueue` (line 163): `firstId < 1` includes CMD.STOP(0); use `< 0` to match `hasOwnBuildOrder` and the comment.
- `scanNearbyBuildables` passes a unit definition id to `IsInBuildRange`, whose helper contract requires the target unit id. Pass `candidateId`; otherwise range checks address an unrelated or nonexistent unit and can exclude valid work or fail in helper code.

---

## Part 2 — Efficiency improvements

### E1. Precompute per-def eco scores at Initialize

`BuildPowerScore` / `EnergyScore` / `MetalAndMMScore` (and `EnergyMakeDef`, `MetalMakingEfficiencyDef`) are pure functions of the unitDef, but `scoreEcoCandidate` recomputes them **inside the `SortBuildEcoPrio` comparator** — O(n log n) times per sort, per builder, per cycle. Precompute the three static scores into `defID`-keyed tables during the existing `Initialize` def loop; before each `table.sort`, compute each candidate's combined score once into `candidate.score`. (Also removes any comparator-consistency risk.)

### E2. Collapse redundant full-team scans

Per `Builders()` cycle the widget walks every team unit up to 3 times with per-unit engine calls:

- `GetResourceStatus('metal')` and `('energy')` (line 747) each loop all units calling `GetUnitResources` — but `GetUnitResources` returns all four values. Fill **both** caches in one pass.
- `getUnitsUpkeep` (line 854) loops all team units + `UnitDefs` lookup just to reach `traceUpkeep`, which self-filters to tracked builders anyway. Iterate `builderUnitIds.list` directly.

### E3. BatchOrder hot loop (line 1371)

- `GetUnitCommands(builder.id, 3)` is fetched per builder **per need type** (×3). Fetch once per builder per BatchOrder call.
- `GetUnitSeparation` is called builders × candidates per need — with 200 cons and 30 candidates that's thousands of engine calls every 4 frames. Fetch each builder's and candidate's position and radius once, then compare squared 2D center distance against the radius-adjusted threshold. This preserves the existing `GetUnitSeparation(..., true, true)` surface-distance semantics.

### E4. Cache the purged command queue per builder per frame

`processBuilder` → `GetPurgedUnitCommands`, then `tryReclaimOrGuard` → `GetPurgedUnitCommands` again: each call is 1–2 `GetUnitCommands` engine fetches. Extend the existing `purgedThisFrame` marker to store the logically filtered queue table and return it. Explicitly invalidate that cache after later queue mutations so stale WAIT, REPAIR, RECLAIM, or GUARD state is never reused.

### E5. Minor allocations / dead work

- `getReclaimableFeatures` (line 1038): `table.has_value({'armcom','legcom','corcom'}, ...)` allocates a fresh table per feature per scan → hoist a constant `{armcom=true, legcom=true, corcom=true}` map.
- `BatchOrder` log call (line 1501) builds `string.format` + `table.tostring(_builders)` even though `log` is a no-op → gate behind the debug toggle from B4.
- Delete dead state: `anyBuildWillStall` (written, never read), `builder.previousBuilding` (written, never read), `builder.guards`/`owned` (never populated, see B7), `candidateBuilders` list in BatchOrder (only its count is used).

---

## Files to modify

- [Widgets/eco_cons.lua](Widgets/eco_cons.lua) — all changes above.
- [tests/eco_cons_test.lua](../tests/eco_cons_test.lua) — deterministic regression coverage using mocked BAR/Recoil APIs and a narrow `ECO_CONS_TEST` export seam.
- This plan file — records the approved behavior-preserving E3/E4 clarifications and test-file deviation.
- `helpers.lua` stays as is (its `Spring.Echo` behavior becomes reachable again via the B4 toggle).

## Suggested implementation order

1. B1 + B2 (builder registry refactor — touches `UnitFinished`, `UnitDestroyed`, `BuilderById`, rescan, `Builders` loops, `BatchOrder` iteration)
2. B3–B8 (small, independent fixes)
3. E1–E5 (each independent; E1 piggybacks on the Initialize def loop)

## Verification

- `lua tests/eco_cons_test.lua` (registry, scheduling, logging, accounting, reclaim decoding, nil safety, caches, scoring, radius-aware range checks, and engine-call counts).
- `luacheck Widgets/eco_cons.lua` (repo has `.luacheckrc`; keep it clean of new warnings).
- Sanity-check Lua syntax: `lua -e "loadfile('Widgets/eco_cons.lua')"` equivalent via luacheck load.
- In-game smoke test (user-side, BAR): load the widget, verify a) builders still get batch eco assignments (green spotlights when ObjectSpotlight is on), b) killing several constructors doesn't stop remaining ones from being managed (B1), c) Ctrl+Shift+T now echoes the responsiveness change and Ctrl+L enables per-selected-unit logging (B4), d) responsiveness 3x/4x still processes builders with a small builder count (B3).
