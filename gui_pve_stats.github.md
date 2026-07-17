## Summary

PvE Stats adds an in-game RmlUi panel for supported PvE modes. It shows representative-team win chance, played difficulty placement, setting-match evidence, and sortable player accomplishments for the current game context.

*Network note: PvE Stats currently uses unencrypted HTTP, so requests and responses are not encrypted in transit.*

This work was almost entirely made by agents.

## Widget highlights

- Win chance for the current map, team size, encounter, and effective lobby settings
- Played Rank plus a histogram of eligible played-game difficulty
- Exact or similar setting comparison with useful lobby differences
- Player views for Awards, Encounters, Games & Maps, Milestones, and Lobby Settings
- Optional spectator rows and copyable support diagnostics
- Persistent minimize and per-game close behavior

## Behavior

The widget is enabled by default and display-only. It sends the current PvE context to the stats service but does not issue commands or automate gameplay.

## Included

- Lua, RML, RCSS, and helper modules
- Community widget manifest and documentation
- Automated tests
- Cover image

## Verification

- [x] Lua unit tests pass for the model, non-blocking HTTP client, and widget scheduler
- [x] Docker build passed
