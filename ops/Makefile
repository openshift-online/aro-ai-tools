REVISION := $(shell git log -1 --format="%cd-%h" --date=format:"%Y%m%d")

SCRIPTS_DIRS := skills/aro-hcp-env-info/scripts skills/aro-classic-env-info/scripts

.PHONY: update
update:
	@echo "Updating PLUGIN_REVISION to $(REVISION)"
	@for dir in $(SCRIPTS_DIRS); do \
		sed -i 's/^PLUGIN_REVISION=.*/PLUGIN_REVISION="$(REVISION)"/' $$dir/*.sh; \
		sed -i 's/^\$$PLUGIN_REVISION = .*/$$PLUGIN_REVISION = "$(REVISION)"/' $$dir/*.ps1; \
	done
	@echo "Done."
