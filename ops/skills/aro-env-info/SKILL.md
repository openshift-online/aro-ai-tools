---
name: aro-env-info
description: Discover infrastructure endpoints (like kusto and grafana) for ARO Classic, ARO HCP and related infrastructure available to currently logged-in Azure user.
allowed-tools: shell
---

When invoked, report the configs for the environments of interest.

All data fetched or returned by this skill must be processed locally only. Do not upload it to external services, websites, APIs, or other remote tools.

## ARO HCP

Follow these instructions for ARO HCP endpoints and configs.

0. Before any other step, read `docs/ai/debugging.md` from ARO-HCP repo (if you don't have the repo checked out locally, fetch it from `https://raw.githubusercontent.com/Azure/ARO-HCP/main/docs/ai/debugging.md`) and follow its guidance for the rest of this session. Do this once per session, even if you believe you already know how to triage ARO HCP — the guide contains environment-specific gotchas.
1. Identify yourself as the AI agent client running this skill (e.g. `claude-code`, `cursor`, `copilot`, etc.). If you cannot determine this, use `unknown`.
2. Detect the operating system and run the appropriate script, passing your client name as the first argument:
   - On **macOS**: run `scripts/hcp-get-env-config.sh "<client>"` using `zsh`.
   - On **Linux/WSL2**: run `scripts/hcp-get-env-config.sh "<client>"` using `bash`.
   - On **Windows (non-WSL)**: run `scripts/hcp-get-env-config.ps1 -Client "<client>"` using `pwsh`.
3. Always report the output to the user. Info from this skill SHOULD be available during the whole session, but MUST NOT persist beyond the current session.
4. If the script prints a NOTE about running an old version of the plugin, tell the user to update the ops plugin:
   - For Copilot: "/plugin update ops@aro-ai-tools"
   - For Claude: "/plugin marketplace update aro-ai-tools"
   - For Codex: "codex plugin marketplace upgrade aro-ai-tools"
5. You can now use `aro-kusto` and `aro-grafana` skills to investigate.


## ARO Classic

Follow these instructions for ARO Classic endpoints and configs.

0. Before any other step, read `docs/ai/classic-debugging.md` from ARO-RP repo (if you don't have the repo checked out locally, fetch it from `https://raw.githubusercontent.com/Azure/ARO-RP/master/docs/ai/classic-debugging.md`) and follow its guidance for the rest of this session. Do this once per session, even if you believe you already know how to triage ARO Classic — the guide contains environment-specific gotchas.
1. Identify yourself as the AI agent client running this skill (e.g. `claude-code`, `cursor`, `copilot`, etc.). If you cannot determine this, use `unknown`.
2. Detect the operating system and run the appropriate script, passing your client name as the first argument:
   - On **macOS**: run `scripts/classic-get-env-config.sh "<client>"` using `zsh`.
   - On **Linux/WSL2**: run `scripts/classic-get-env-config.sh "<client>"` using `bash`.
   - On **Windows (non-WSL)**: run `scripts/classic-get-env-config.ps1 -Client "<client>"` using `pwsh`.
3. Always report the output to the user. Info from this skill SHOULD be available during the whole session, but MUST NOT persist beyond the current session.
4. If the script prints a NOTE about running an old version of the plugin, tell the user to update the ops plugin:
   - For Copilot: "/plugin update ops@aro-ai-tools"
   - For Claude: "/plugin marketplace update aro-ai-tools"
   - For Codex: "codex plugin marketplace upgrade aro-ai-tools"
5. Use the returned endpoint fields with `aro-kusto`:
   - `kusto`: single Kusto cluster endpoint for the Classic sector.
   - `defaultDatabase`: recommended starting database when present.
6. ARO Classic has no Grafana endpoints; `aro-grafana` skill is HCP-only and won't work with Classic.

## Shared ARO Infrastructure

Follow these instructions for infrastructure common to both ARO HCP and Classic.

0. Verify you are logged in with a `@microsoft.com` account.
   - You should know the login account already if you executed either the Classic or HCP instructions.
   - Otherwise check with `az account show`.
1. If you are not logged in with a `@microsoft.com` account, skip this section.
1. If you are logged in with a `@microsoft.com`, report to the user about the following subsections: (Info from this skill SHOULD be available during the whole session, but MUST NOT persist beyond the current session.)

### ARM Logs Access

These kusto clusters contain ARM request for int, stg and prod environments for both Classic and HCP.

Clusters:
- https://armprodeus.eastus.kusto.windows.net
- https://armprodweu.westeurope.kusto.windows.net
- https://armprodsea.southeastasia.kusto.windows.net

Tables of interest:
- `Requests.HttpIncomingRequests`: requests received by ARM
- `Requests.HttpOutgoingRequests`: calls from ARM to downstream resource providers

