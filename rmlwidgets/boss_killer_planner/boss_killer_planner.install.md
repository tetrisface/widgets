# Boss Killer Planner

Install into:

```text
LuaUI/rmlwidgets/boss_killer_planner/
```

Files:

```text
boss_killer_planner.lua
boss_killer_planner.rml
boss_killer_planner.rcss
```

The widget is read-only in v1. It consumes `pveBossInfo`, runtime `UnitDefs`, unit lifecycle callbacks, and own command queues for display only.

Ranked scoring can use either build cost only or full cost. Full cost adds estimated weapon shot costs and unit upkeep over the score window, converted through the configured energy-per-metal ratio.

Historical samples are saved to `LuaUI/Config/boss_killer_planner_stats.lua` and can be inspected from the History tab.
