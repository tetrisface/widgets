# Extract `gui_pve_stats` from BAR submodule into `tetrisface/widgets` while preserving history

## Summary
- Move the widget from the nested BAR copy at `BAR-Widgets/Widgets/tetrisface/gui_pve_stats` into this repo as a local widget folder.
- Keep full file history from the source copy instead of a one-shot copy.
- Remove the widget from the BAR submodule copy so this repo no longer tracks the unsynced upstream variant.
- Reconcile build/linking scripts so they do not try to replace the new local widget path.

## Key changes
- I found the source layout is: `tetrisface/widgets` (root repo) → submodule `BAR-Widgets` → nested submodule `Widgets/tetrisface` → `gui_pve_stats`.
- Create a filtered history branch from `BAR-Widgets/Widgets/tetrisface` that contains only `gui_pve_stats`, then rewrite it to `Widgets/gui_pve_stats` path.
- Merge that branch into parent `main` using history-preserving merge from an unrelated repository history.
- In the nested BAR source (`BAR-Widgets/Widgets/tetrisface`), remove `gui_pve_stats` and commit that deletion, then update the `BAR-Widgets` submodule pointer in parent as needed.
- Update/link workflow:
  - If `community-widgets` is still used, `make sync-widget-links` will conflict on `Widgets/gui_pve_stats`; either add an explicit skip for this widget in `scripts/Sync-CommunityWidgetLinks.ps1` or keep local copy under a non-conflicting path.

## Test plan
- Verify source commit selection: confirm `git -C BAR-Widgets/Widgets/tetrisface log --oneline -n 5 -- gui_pve_stats` is from the intended unsynced BAR snapshot.
- After merge, verify `git log -- Widgets/gui_pve_stats/gui_pve_stats.lua` includes pre-existing source commits from the nested repo.
- Verify parent has no unintended files:
  - `git status --short`
  - `git ls-tree -r --name-only HEAD -- Widgets/gui_pve_stats`
- Verify source cleanup:
  - `BAR-Widgets/Widgets/tetrisface` no longer has `gui_pve_stats`
  - `git -C BAR-Widgets submodule status` (if touched)
- Run link/sync dry-run:
  - `pwsh scripts/Sync-CommunityWidgetLinks.ps1 -WhatIf`

## Assumptions
- Source is the nested BAR snapshot: `BAR-Widgets/Widgets/tetrisface/gui_pve_stats`.
- Destination is `Widgets/gui_pve_stats` in parent repo.
- You want history preserved (not squashed).
- No upstream PR/submodule remote push is included in scope unless requested.
