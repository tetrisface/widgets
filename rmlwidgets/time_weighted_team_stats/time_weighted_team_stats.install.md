**Time Weighted Team Stats** — team statistics adjusted for eco growth ("inflation"), so a player who dominated early game gets proper credit even when late-game numbers dwarf everything.

**Why time-weighting?**
Raw totals lie. In a long game the last 5 minutes of eco output can make the first 20 irrelevant by numbers alone. This widget deflates each stat window-by-window using that stat's own per-window team total as the divisor — so early damage, early metal production, and early support all count at fair weight relative to when they happened.

**Core features**
- Three table views: **Raw** totals / **Share%** / **Time Weighted** (inflation-adjusted)
- **Graph** with three modes — stacked absolute (bar height = raw activity, splits = time-weighted shares), stacked normalized (always 100%), and overlay (independent player lines)
- Graph time-weight toggle: raw per-window values vs time-weighted per-window values
- **DmgEff** graph stat: per-window damage dealt / damage received ratio as a historical line
- **DmgEff** and **DmgPerRes** table columns (damage efficiency and damage per resource consumed); values hidden when one side is zero
- Players who leave mid-game **keep their stats visible**
- Ally team selector to isolate one team in the graph; separator between ally groups in grouped table mode
- Drag to move, Ctrl+scroll to resize font, resizable panel, configurable window aggregation (1x/2x/4x/8x — higher options only appear when there is enough data)

**Niche**
- Most useful in longer or uneven games where eco scaling makes raw numbers misleading
- Share / % view: who did what fraction of the team's work
- Time Weighted view: who punched above their weight considering *when* they did it

---

# 1. Install/Update Automatically
On Windows with BAR installed in the default location press :hwwindows: + :regional_indicator_r: and paste:
```pwsh
$d="$env:LOCALAPPDATA\Programs\Beyond-All-Reason\data"; New-Item -ItemType Directory -Force "$d\LuaUI\rmlwidgets\time_weighted_team_stats" | Out-Null; Invoke-WebRequest "https://gist.githubusercontent.com/tetrisface/GIST_ID/raw/time_weighted_team_stats.lua" -OutFile "$d\LuaUI\Widgets\time_weighted_team_stats.lua"; Invoke-WebRequest "https://gist.githubusercontent.com/tetrisface/GIST_ID/raw/time_weighted_team_stats.rml" -OutFile "$d\LuaUI\rmlwidgets\time_weighted_team_stats\time_weighted_team_stats.rml"; Invoke-WebRequest "https://gist.githubusercontent.com/tetrisface/GIST_ID/raw/time_weighted_team_stats.rcss" -OutFile "$d\LuaUI\rmlwidgets\time_weighted_team_stats\time_weighted_team_stats.rcss"
```

# 1. Install/Update Manually
Download the three raw files from https://gist.github.com/tetrisface/GIST_ID and place them as follows (create the `time_weighted_team_stats` subfolder if it doesn't exist):
```
%LOCALAPPDATA%\Programs\Beyond-All-Reason\data\LuaUI\Widgets\time_weighted_team_stats.lua
%LOCALAPPDATA%\Programs\Beyond-All-Reason\data\LuaUI\rmlwidgets\time_weighted_team_stats\time_weighted_team_stats.rml
%LOCALAPPDATA%\Programs\Beyond-All-Reason\data\LuaUI\rmlwidgets\time_weighted_team_stats\time_weighted_team_stats.rcss
```

# 2. Enable
Restart BAR or run `/luaui reload`, then enable **Time Weighted Team Stats** in the widget list.

# Help
#❓｜how-to-install-mods
