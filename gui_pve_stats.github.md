# Add PvE Stats to the BAR Community Widgets hub

## Summary

Advance the existing `Widgets/tetrisface` submodule so the hub can publish `gui_pve_stats` alongside Time Weighted Team Stats.

PvE Stats adds an in-game RmlUi panel for supported PvE modes. It shows representative-team win chance, played difficulty placement, setting-match evidence, and sortable player accomplishments for the current game context.

*Network note: PvE Stats currently uses unencrypted HTTP, so requests and responses are not encrypted in transit.*

## Widget highlights

- Win chance for the current map, team size, encounter, and effective lobby settings
- Played Rank plus a histogram of eligible played-game difficulty
- Exact or similar setting comparison with useful lobby differences
- Player views for Awards, Encounters, Games & Maps, Milestones, and Lobby Settings
- Optional spectator rows and copyable support diagnostics
- Persistent minimize and per-game close behavior

## BAR-Widgets integration

- Globally scoped lower-snake-case ID: `gui_pve_stats`
- Manifest ID matches the widget directory
- Semantic version and RFC 3339 `last_updated` metadata
- Detailed `README.md` and a prepared Discord announcement
- Multi-file package compatible with `LuaUI/Widgets/gui_pve_stats`, with helper modules isolated under `include/`
- Package size remains well below the 5 MiB limit

## Verification

- [x] Lua unit tests pass for the model, non-blocking HTTP client, and widget scheduler
- [x] Runtime RML and helper-module paths match the Community Widgets install directory
- [x] Manifest validates against the BAR-Widgets schema
- [x] Package is below the 5 MiB limit
- [ ] Publish the Discord announcement and place its URL in `manifest.json`
