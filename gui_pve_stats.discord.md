**PvE Stats** — difficulty and accomplishment context for Beyond All Reason PvE games, shown directly in an in-game RmlUi panel.

It uses the current map, team size, encounter, and effective lobby settings to show a representative-team win chance and where the setup sits among eligible played games. It also provides setting-match evidence and accomplishment-focused player statistics.

*Network note: PvE Stats currently uses unencrypted HTTP, so requests and responses are not encrypted in transit.*

# 1. Install

### __Community Widgets (maybe soon)__

~~Open the plugins browser in the BAR lobby, find **PvE Stats**, and select **Install**.~~

### __PowerShell__

With BAR in its default location, this installs the five required files:

```pwsh
$widget = "gui_pve_stats"
$folder = "$env:LOCALAPPDATA\Programs\Beyond-All-Reason\data\LuaUI\Widgets\$widget"
$source = "https://raw.githubusercontent.com/tetrisface/community-widgets/main/$widget"
$files = @("$widget.lua", "$widget.rml", "$widget.rcss",
    "include/pve_stats_http_client.lua", "include/pve_stats_rml_model.lua")

New-Item -ItemType Directory -Force -Path "$folder\include" | Out-Null

foreach ($file in $files) {
    Invoke-WebRequest -Uri "$source/$file" -OutFile "$folder/$file"
}
```

### __Manual__

1. Open `%LOCALAPPDATA%\Programs\Beyond-All-Reason\data\LuaUI\Widgets`.
2. Download the repository ZIP from <https://github.com/tetrisface/community-widgets/archive/refs/heads/main.zip>.
3. Open the ZIP and then the `community-widgets-main` folder.
4. Drag the `gui_pve_stats` folder into `Widgets`.
5. Verify this folder structure:

```text
LuaUI/
└─ Widgets/
   └─ gui_pve_stats/
      ├─ gui_pve_stats.lua
      ├─ gui_pve_stats.rml
      ├─ gui_pve_stats.rcss
      └─ include/
         ├─ pve_stats_http_client.lua
         └─ pve_stats_rml_model.lua
```

# 2. Enable

Restart BAR or run `/luaui reload`, then enable **PvE Stats** in the widget list (F11).


---------- MESSAGE LIMIT BREAK ----------


# **Core features**

- **Win Chance** for a representative current BAR human team playing the current setup
- **Challenge** score, **Difficulty Percentile**, and a histogram showing the setup's difficulty among eligible played games
- Exact or similar **setting comparison**, with detailed lobby-setting differences available under **Diag**
- Sortable player views for **Awards**, **Encounters**, **Games & Maps**, **Milestones**, and **Lobby Settings**
- Optional spectator rows
- Copyable **Diag** information for support and troubleshooting
- Persistent minimize behavior; closing hides the panel only for the current game

The widget requires an internet connection to reach the PvE Stats service. The current players' identities and skill ratings are not used for the displayed win-chance estimate.

# TROUBLESHOOTING / Problems installing or running

You can ask for help here or in #❓｜how-to-install-mods.

On Windows, run these commands in PowerShell and post the output together with a screenshot of the F11 widget list:

```pwsh
Select-String -Path "$env:LOCALAPPDATA\Programs\Beyond-All-Reason\data\log\*.*","$env:LOCALAPPDATA\Programs\Beyond-All-Reason\data\infolog.txt" -Pattern 'gui_pve_stats' -SimpleMatch -Context 0,3 -AllMatches
Get-ChildItem -Path "$env:LOCALAPPDATA\Programs\Beyond-All-Reason\data\LuaUI\Widgets\gui_pve_stats"
```

The log results can contain your Windows username or name. Review them before posting publicly.
