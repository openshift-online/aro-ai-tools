REVISION := $(shell git log -1 --format="%cd-%h" --date=format:"%Y%m%d%H%M")

SCRIPTS_DIRS := skills/aro-hcp-env-info/scripts skills/aro-classic-env-info/scripts

.PHONY: update
update:
	@echo "Updating PLUGIN_REVISION to $(REVISION)"
	@for dir in $(SCRIPTS_DIRS); do \
		sed -i 's/^PLUGIN_REVISION=.*/PLUGIN_REVISION="$(REVISION)"/' $$dir/*.sh; \
		sed -i 's/^\$$PLUGIN_REVISION = .*/$$PLUGIN_REVISION = "$(REVISION)"/' $$dir/*.ps1; \
	done
	@echo "Done."

# Publishes the plugin revision baked into the shipped scripts into the
# 'ops-plugin-latest-revision' tag on the config resource groups. The revision is
# grepped from a script (set by `make update`) so the tag matches what users
# actually have, not the live git rev. Tenant-aware: the RH base tenant holds the
# HCP config RG, the MSFT base tenant holds the HCP and Classic config RGs. Run
# once per tenant you're logged into (RH and MSFT) to cover all three RGs.
.PHONY: push-latest
push-latest:
	@rev=$$(sed -n 's/^PLUGIN_REVISION="\(.*\)"/\1/p' skills/aro-hcp-env-info/scripts/get-env-config.sh); \
	[ -n "$$rev" ] || { echo "Couldn't read PLUGIN_REVISION from script" >&2; exit 1; }; \
	user=$$(az account show --query 'user.name' -o tsv) || { echo "Not logged into Azure?" >&2; exit 1; }; \
	echo "Logged in as: $$user"; \
	case "$$user" in \
	  *@redhat.com) \
	    echo "RH tenant: tagging ai-plugin-config (HCP)"; \
	    az group update -n ai-plugin-config --subscription "b23756f7-4594-40a3-980f-10bb6168fc20" \
	        --set tags.ops-plugin-latest-revision="$$rev" -o none ;; \
	  *@microsoft.com) \
	    echo "MSFT tenant: tagging ai-plugin-cfg (HCP) and ai-plugin-cfg (Classic)"; \
	    az group update -n ai-plugin-cfg --subscription "Azure Red Hat OpenShift v4.x - HCP" \
	        --set tags.ops-plugin-latest-revision="$$rev" -o none && \
	    az group update -n ai-plugin-cfg --subscription "Azure Red Hat OpenShift v4.x - Development" \
	        --set tags.ops-plugin-latest-revision="$$rev" -o none ;; \
	  *) echo "Error: logged in as '$$user', need a @redhat.com or @microsoft.com account." >&2; exit 1 ;; \
	esac; \
	echo "Tagged ops-plugin-latest-revision=$$rev."
