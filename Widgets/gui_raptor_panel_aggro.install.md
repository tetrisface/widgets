A modded version of the raptor panel that displays aggro/eco attraction for the current player and their most significant peers'.
[Check screenshot](https://discord.com/channels/549281623154229250/1203485910512173096/1203488503053287425)
It is both displayed as a multiple (the "X" value) relative to playing it solo and as a percentage of all the players combined.
If the current player is not present in the top 4-5 players displayed or drop below 0.8X they will be slightly grey. As a player's aggro climbs above 1.2X they will be progressively tinted red.
# 1. Install/Update Automatically
On Windows and with BAR installed in the default location you can press :hwwindows: + :regional_indicator_r:  and paste in
```pwsh
powershell.exe Invoke-WebRequest -Uri "gist.githubusercontent.com/tetrisface/2f99f5a5b179e3ac42e7e63825880713/raw/gui_raptor_panel_aggro.lua" -OutFile "%USERPROFILE%\AppData\Local\Programs\Beyond-All-Reason\data\LuaUI\Widgets\gui_raptor_panel_aggro.lua
```
# 1. Install/Update Manually
Copy the raw file from https://gist.github.com/tetrisface/2f99f5a5b179e3ac42e7e63825880713#file-gui_raptor_panel_aggro-lua to the folder ```%USERPROFILE%\AppData\Local\Programs\Beyond-All-Reason\data\LuaUI\Widgets``` with the file name
```gui_raptor_panel_aggro.lua```
# 2. Restart
Restart BAR or run `/luaui reload`

# Help
#❓｜how-to-install-mods
If that doesn't help check raptor panel specific troubleshooting [here](https://discord.com/channels/549281623154229250/1203485910512173096/1203488503053287425)
This widget will turn off the official version widget.
