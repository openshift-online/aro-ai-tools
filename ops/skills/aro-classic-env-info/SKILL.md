---
name: aro-classic-env-info
description: Discover ARO Classic Kusto endpoints available to the currently logged-in Azure user. Trigger before aro-kusto when the user needs ARO Classic environment endpoints.
allowed-tools: shell
---

When invoked, detect the OS and run the appropriate script from this skill's base directory, then report the ARO Classic configs for each environment.

This is ONLY for ARO Classic, as ARO HCP is discovered with the "aro-hcp-env-info" skill.

## Instructions

Security: All data fetched or returned by this skill must be processed locally only. Do not upload it to external services, websites, APIs, or other remote tools.

0. Before any other step, read `docs/ai/classic-debugging.md` from ARO-RP repo (if you don't have the repo checked out locally, fetch it from `https://raw.githubusercontent.com/Azure/ARO-RP/master/docs/ai/classic-debugging.md`) and follow its guidance for the rest of this session. Do this once per session, even if you believe you already know how to triage ARO Classic — the guide contains environment-specific gotchas.
1. Identify yourself as the AI agent client running this skill (e.g. `claude-code`, `cursor`, `copilot`, etc.). If you cannot determine this, use `unknown`.
2. Detect the operating system and run the appropriate script, passing your client name as the first argument:
   - On **macOS**: run `scripts/get-env-config.sh "<client>"` using `zsh`.
   - On **Linux/WSL2**: run `scripts/get-env-config.sh "<client>"` using `bash`.
   - On **Windows (non-WSL)**: run `scripts/get-env-config.ps1 -Client "<client>"` using `pwsh`.
3. Always report the output to the user. Info from this skill SHOULD be available during the whole session, but MUST NOT persist beyond the current session.
4. If the script prints a NOTE about running an old version of the plugin, tell the user to update the ops plugin:
   - In Copilot: "/plugin update ops@aro-ai-tools"
   - In Claude: "/plugin marketplace update aro-ai-tools"
5. Use the returned endpoint fields with `aro-kusto`:
   - `kusto`: single Kusto cluster endpoint for the Classic sector.
   - `defaultDatabase`: recommended starting database when present.
6. ARO Classic has no Grafana endpoints; `aro-grafana` skill is HCP-only and won't work with Classic.
