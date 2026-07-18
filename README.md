===== PvE STATS =====

PvE Stats brings difficulty and accomplishment context into Beyond All Reason PvE games. It queries the PvE Stats service with the current game context, then presents the result in a compact RmlUi panel.

Network note: PvE Stats currently uses unencrypted HTTP, so requests and responses are not encrypted in transit.

--- CORE FEATURES ---

- Representative-team win chance for the current map, team size, encounter, and effective lobby settings
- Difficulty Percentile and a difficulty histogram showing where the current setup sits among eligible played games
- Setting-match evidence with useful lobby differences when the current setup does not exactly match a recorded setup
- Sortable player accomplishment views for Awards, Encounters, Games & Maps, Milestones, and Lobby Settings
- Optional spectator rows and copyable support diagnostics
- Persistent minimized state and a close button that hides only the current game's window

The win-chance estimate represents a current BAR human team. The identities and skill ratings of the players in the lobby are not used for that estimate.

--- REQUIREMENTS ---

- An internet connection to reach the PvE Stats service
- A supported BAR PvE game, such as Raptors, Scavengers, or BARbarians

If the service is still starting or temporarily busy, the widget retries expected transient failures without blocking LuaUI. The Diag panel exposes copyable, support-oriented request status without displaying sensitive implementation details.
