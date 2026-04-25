**Time Weighted Team Stats** — team statistics adjusted for eco growth ("inflation"), so a player who dominated early game gets proper credit even when late-game numbers dwarf everything.

**Why time-weighting?**
Raw totals lie. In a long game the last 5 minutes of eco output can make the first 20 irrelevant by numbers alone. This widget deflates each stat window-by-window using that stat's own per-window team total as the divisor — so early damage, early metal production, and early support all count at fair weight relative to when they happened.

# 1. Install/Update Automatically
On Windows with BAR installed in the default location press :hwwindows: + :regional_indicator_r: and paste:
```pwsh
$n="time_weighted_team_stats"; $d="$env:LOCALAPPDATA\Programs\Beyond-All-Reason\data\LuaUI\rmlwidgets\$n"; $u="https://gist.githubusercontent.com/tetrisface/12f8265f8cf6b156b113f91085de8a55/raw/$n"; New-Item -ItemType Directory -Force $d | Out-Null; 'lua','rml','rcss'|%{iwr "$u.$_" -OutFile "$d\$n.$_"}
```

# 2. Enable
Restart BAR or run `/luaui reload`, then enable **Time Weighted Team Stats** in the widget list.

# Help
#❓｜how-to-install-mods


---------- MESSAGE LIMIT BREAK ----------


**Core features**
- Three table views: **Raw** totals / **Share%** / **Time Weighted** (inflation-adjusted)
- **Graph** with three modes — stacked absolute (bar height = raw activity, splits = time-weighted shares), stacked normalized (always 100%), and overlay (independent player lines)
- Graph time-weight toggle: raw per-window values vs time-weighted per-window values
- Players who leave mid-game **keep their stats visible**
- Ally team selector to isolate one team in the graph; separator between ally groups in grouped table mode
- Drag to move, resizable panel, configurable window aggregation (1x/2x/4x/8x — higher options only appear when there is enough data)

**Niche**
- Most useful in longer or uneven games where eco scaling makes raw numbers misleading
- Share / % view: who did what fraction of the team's work
- Time Weighted view: who punched above their weight considering *when* they did it


