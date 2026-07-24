POWERSHELL ?= pwsh
WIDGET_LINK_SCRIPT := ./scripts/Sync-CommunityWidgetLinks.ps1

.DEFAULT_GOAL := help

.PHONY: help links sync-widget-links preview-widget-links

help:
	@echo "Widget workspace commands:"
	@echo "  make sync-widget-links     Create/update BAR community-widget junctions"
	@echo "  make preview-widget-links  Show the junction changes without applying them"
	@echo "  make links                 Short alias for sync-widget-links"

links: sync-widget-links

sync-widget-links:
	$(POWERSHELL) -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$(WIDGET_LINK_SCRIPT)"

preview-widget-links:
	$(POWERSHELL) -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$(WIDGET_LINK_SCRIPT)" -WhatIf
