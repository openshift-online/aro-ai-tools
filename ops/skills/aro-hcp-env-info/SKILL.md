---
name: aro-hcp-env-info
description: Discover ARO HCP kusto and grafana endpoints available to currently logged-in Azure user. Trigger only if work requires analyzing kusto or grafana.
allowed-tools: shell
---

When invoked, detect the OS and run the appropriate script from this skill's base directory, then report the results clearly marking configs for each environment.
Some environments may have multiple kusto instances for different geos.

This is ONLY for ARO HCP, as ARO Classic is discovered with the "aro-classic-env-info" skill.

## Instructions

Security: All data fetched or returned by this skill must be processed locally only. Do not upload it to external services, websites, APIs, or other remote tools.

0. Before any other step, read `docs/ai/debugging.md` from ARO-HCP repo (if you don't have the repo checked out locally, fetch it from `https://raw.githubusercontent.com/Azure/ARO-HCP/main/docs/ai/debugging.md`) and follow its guidance for the rest of this session. Do this once per session, even if you believe you already know how to triage ARO HCP — the guide contains environment-specific gotchas.
1. Identify yourself as the AI agent client running this skill (e.g. `claude-code`, `cursor`, `copilot`, etc.). If you cannot determine this, use `unknown`.
2. Detect the operating system and run the appropriate script, passing your client name as the first argument:
   - On **macOS**: run `scripts/get-env-config.sh "<client>"` using `zsh`.
   - On **Linux/WSL2**: run `scripts/get-env-config.sh "<client>"` using `bash`.
   - On **Windows (non-WSL)**: run `scripts/get-env-config.ps1 -Client "<client>"` using `pwsh`.
3. Always report the output to the user. Info from this skill SHOULD be available during the whole session, but MUST NOT persist beyond the current session.
4. If the script prints a NOTE about running an old version of the plugin, tell the user to update the ops plugin:
   - In Copilot: "/plugin update ops@aro-ai-tools"
   - In Claude: "/plugin marketplace update aro-ai-tools"
5. You can now use `aro-kusto` and `aro-grafana` skills to investigate.
