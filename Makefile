POWERSHELL ?= pwsh
WIDGET_LINK_SCRIPT := ./scripts/Sync-CommunityWidgetLinks.ps1
KEYBIND_SCRIPT := ./scripts/Repair-BarKeybinds.ps1

.DEFAULT_GOAL := help

.PHONY: help links sync-widget-links preview-widget-links keybinds preview-keybinds

help:
	@echo "Widget workspace commands:"
	@echo "  make sync-widget-links     Create/update widget junctions (community-widgets, widgets-extra)"
	@echo "  make preview-widget-links  Show the junction changes without applying them"
	@echo "  make links                 Short alias for sync-widget-links"
	@echo "  make keybinds              Point every BAR write dir's uikeys.txt at this repo"
	@echo "  make preview-keybinds      Show the keybind link/cfg changes without applying them"

links: sync-widget-links

sync-widget-links:
	$(POWERSHELL) -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$(WIDGET_LINK_SCRIPT)"
sync: sync-widget-links
links: sync-widget-links

preview-widget-links:
	$(POWERSHELL) -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$(WIDGET_LINK_SCRIPT)" -WhatIf

keybinds:
	$(POWERSHELL) -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$(KEYBIND_SCRIPT)"

preview-keybinds:
	$(POWERSHELL) -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$(KEYBIND_SCRIPT)" -DryRun
