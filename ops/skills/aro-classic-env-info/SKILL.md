---
name: aro-classic-env-info
description: Discover ARO Classic Kusto endpoints available to the currently logged-in Azure user. Trigger before aro-kusto when the user needs ARO Classic environment endpoints.
allowed-tools: shell
---

When invoked, detect the OS and run the appropriate script from this skill's base directory, then report the ARO Classic configs for each environment.

This is ONLY for ARO Classic, as ARO HCP is discovered with the "aro-hcp-env-info" skill.

## References

Fetch https://github.com/Azure/ARO-RP/blob/master/docs/ai/classic-debugging.md for info on how to effectively triage ARO Classic issues.

## Instructions

1. Identify yourself as the AI agent client running this skill (e.g. `claude-code`, `cursor`, `copilot`, etc.). If you cannot determine this, use `unknown`.
2. Detect the operating system and run the appropriate script, passing your client name as the first argument:
   - On **macOS**: run `scripts/get-env-config.sh "<client>"` using `zsh`.
   - On **Linux/WSL2**: run `scripts/get-env-config.sh "<client>"` using `bash`.
   - On **Windows (non-WSL)**: run `scripts/get-env-config.ps1 -Client "<client>"` using `pwsh`.
3. Always report the output to the user. Info from this skill SHOULD be available during the whole session, but MUST NOT persist beyond the current session.
4. Use the returned endpoint fields with `aro-kusto`:
   - `kusto`: single Kusto cluster endpoint for the Classic sector.
   - `defaultDatabase`: recommended starting database when present.
5. ARO Classic has no Grafana endpoints; `aro-grafana` skill is HCP-only and won't work with Classic.
