REVISION := $(shell git log -1 --format="%cd-%h" --date=format:"%Y%m%d")

SCRIPTS_DIR := skills/aro-hcp-env-info/scripts

.PHONY: update
update:
	@echo "Updating PLUGIN_REVISION to $(REVISION)"
	sed -i 's/^PLUGIN_REVISION=.*/PLUGIN_REVISION="$(REVISION)"/' $(SCRIPTS_DIR)/*.sh
	sed -i 's/^\$$PLUGIN_REVISION = .*/$$PLUGIN_REVISION = "$(REVISION)"/' $(SCRIPTS_DIR)/*.ps1
	@echo "Done."
