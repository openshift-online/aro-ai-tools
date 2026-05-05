---
name: aro-hcp-env-info
description: Discover ARO HCP kusto and grafana endpoints available to currently logged-in Azure user. Trigger only if work requires analyzing kusto or grafana. This must run before other kusto or grafana skills — it provides the cluster URLs and endpoints those skills need.
allowed-tools: shell
---

When invoked, detect the OS and run the appropriate script from this skill's base directory, then report the results clearly marking configs for each environment.
Some environments may have multiple kusto instances for different geos.

## Instructions

1. Identify yourself as the AI agent client running this skill (e.g. `claude-code`, `cursor`, `copilot`, etc.). If you cannot determine this, use `unknown`.
2. Detect the operating system and run the appropriate script, passing your client name as the first argument:
   - On **macOS**: run `scripts/get-env-config.sh "<client>"` using `zsh`.
   - On **Linux/WSL2**: run `scripts/get-env-config.sh "<client>"` using `bash`.
   - On **Windows (non-WSL)**: run `scripts/get-env-config.ps1 -Client "<client>"` using `pwsh`.
3. Always report the output to the user. Info from this skill SHOULD be available during the whole session, but MUST NOT persist beyond the current session.
4. You can now use `aro-kusto` and `aro-grafana` skills to investigate.
