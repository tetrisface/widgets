## Summary

PvE Stats adds an in-game RmlUi panel for supported PvE modes. It shows representative-team win chance, played difficulty placement, setting-match evidence, and sortable player accomplishments for the current game context.

*Network note: PvE Stats currently uses unencrypted HTTP, so requests and responses are not encrypted in transit.*

This work was almost entirely made by agents.

## Widget highlights

- Win chance for the current map, team size, encounter, and effective lobby settings
- Challenge score, Difficulty Percentile, and a histogram of eligible played-game difficulty
- Exact or similar setting comparison with detailed lobby differences available under Diag
- Player views for Awards, Encounters, Games & Maps, Milestones, and Lobby Settings
- Optional spectator rows and copyable support diagnostics
- Persistent minimize and per-game close behavior

## Behavior

The widget is enabled by default and display-only. It sends the current PvE context to the stats service but does not issue commands or automate gameplay.

The remote connection is purpose-specific and fixed to `POST http://d29i3oohxql6zz.cloudfront.net:80/stats`. It is non-blocking, bounded, has no runtime endpoint override, and runs only for the initial automatic fetch or an explicit manual/scheduled fetch. See the README and the request/remote modules for the complete outbound allowlist and connection policy.

## Included

- Lua, RML, RCSS, and helper modules
- Community widget manifest and documentation
- Automated tests
- Cover image

## Verification

- [x] The unified Lua suite passes request, remote-boundary, fetch-policy, presenter, and widget-integration tests
- [x] Lua 5.1 and Lua 5.4 compatibility checks pass
- [x] Lua syntax, RML/XML, and manifest/JSON validation pass
