===== PvE STATS =====

PvE Stats brings difficulty and accomplishment context into Beyond All Reason PvE games. It queries the PvE Stats service with the current game context, then presents the result in a compact RmlUi panel.

Network note: PvE Stats currently uses unencrypted HTTP, so requests and responses are not encrypted in transit.

--- CORE FEATURES ---

- Representative-team win chance for the current map, team size, encounter, and effective lobby settings
- Challenge score, Difficulty Percentile, and a histogram showing where the current setup sits among eligible played games
- Setting-match evidence, with detailed lobby differences available under Diag when the current setup is not an exact match
- Sortable player accomplishment views for Awards, Encounters, Games & Maps, Milestones, and Lobby Settings
- Optional spectator rows and copyable support diagnostics
- Persistent minimized state and a close button that hides only the current game's window

The win-chance estimate represents a current BAR human team. The identities and skill ratings of the players in the lobby are not used for that estimate.

--- REQUIREMENTS ---

- An internet connection to reach the PvE Stats service
- A supported BAR PvE game, such as Raptors, Scavengers, or BARbarians

If the service is still starting or temporarily busy, the widget retries expected transient failures without blocking LuaUI. The Diag panel exposes copyable, support-oriented request status without displaying sensitive implementation details.

--- REMOTE CONNECTION ---

The complete outbound contract is split between [`pve_stats_request.lua`](include/pve_stats_request.lua) and [`pve_stats_remote.lua`](include/pve_stats_remote.lua). The widget sends one of seven explicitly allowlisted JSON fields with `POST http://d29i3oohxql6zz.cloudfront.net:80/stats`. It fetches once during initial startup and on explicit manual or scheduled requests; it does not poll periodically.

Each fetch controller owns the lifecycle of its request and prevents duplicate work for that resource. The remote transport keeps operations independent and does not serialize unrelated operations, so future features can use separate controllers without sharing a global request lock.

Each attempt has a 30-second deadline, a 256 KiB request body limit, a 64 KiB response headers limit, and a 1 MiB response body limit. The client does not follow redirects, authenticate, retain cookies, download files, or execute response content. The fixed endpoint currently uses unencrypted HTTP.
