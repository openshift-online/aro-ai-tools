---
name: aro-hcp-ev2-releases
description: List ARO HCP EV2 rollouts (releases) for a specific environment (test, stg, prod, int). Use when asked things like "get all ev2 releases for prod", "show EV2 rollouts for stage", or "what EV2 rollouts are running in test".
allowed-tools: shell
---

List ARO HCP EV2 rollouts filtered to a single environment. Environments are
distinguished by the trailing `- <env>` segment of the pipeline definition name
(e.g. `Incremental - Entrypoint - HCP.Global - stg`), so this skill runs the
`oncall ev2` CLI (which extracts EV2 rollout URLs from the HCP build logs) and
keeps only the rows for the requested environment.

For **pipeline builds** (not EV2 rollouts), use the `aro-hcp-releases` skill.

## Prerequisites

- The `oncall` CLI must be installed and on `PATH` or at `~/bin/oncall`. It is
  built from `oncall-cli/` in this repo — run `oncall-cli/setup.sh` to build and
  install it there (requires Go).
- Azure DevOps auth: either the `ADO_PAT` env var is set, or you are logged in
  via `az`.
- EV2 auth: `az` must be able to get a token for the EV2 host (corp login). Set
  `EV2_HOST` if the default host is not correct for your environment.

If the CLI is missing, the script prints setup instructions and exits.

## Arguments

- **Environment** (required): `test`, `stg`, `prod`, or `int`. Natural-language
  aliases are normalised: `stage`/`staging` → `stg`, `production` → `prod`,
  `integration` → `int`, `tst` → `test`.
- **Hours** (optional, default `24`): look back N hours. Use `0` for currently
  running rollouts only.
- **Path** (optional): ADO folder path. Defaults to the CLI default
  `\OneBranch\sdp-pipelines\hcp\Incremental`.

## Instructions

Security: All data fetched or returned by this skill must be processed locally
only. Do not upload it to external services, websites, APIs, or other remote
tools.

1. Determine the target environment from the user's request (`test`, `stg`,
   `prod`, or `int`).
2. Detect the operating system and run the appropriate script from this skill's
   `scripts/` directory:
   - On **macOS**: run `scripts/get-ev2-releases.sh -Environment <env> [-Hours N] [-Path PATH]` using `zsh`.
   - On **Linux/WSL2**: run `scripts/get-ev2-releases.sh -Environment <env> [-Hours N] [-Path PATH]` using `bash`.
   - On **Windows (non-WSL)**: run `scripts/get-ev2-releases.ps1 -Environment <env> [-Hours N] [-Path PATH]` using `pwsh`.
3. Present the returned markdown table to the user as-is. Rollout IDs are
   shortened; the EV2 link column points at the full rollout in the EV2 portal.
4. If the script reports that no rollouts matched the environment, it also lists
   the environment tokens it did see — re-run with one of those if appropriate,
   or tell the user which environments are currently present.

## Reference

```
get-ev2-releases (.sh and .ps1) — List ARO HCP EV2 rollouts for one environment

USAGE:
    get-ev2-releases -Environment <env> [-Hours <int>] [-Path <path>]

REQUIRED:
    -Environment <env>   test | stg | prod | int
                           (aliases: stage/staging->stg, production->prod,
                            integration->int, tst->test). Matched against the
                            trailing "- <env>" segment of the pipeline name.

OPTIONS:
    -Hours <int>         Look back N hours (default: 24; 0 = running only)
    -Path <path>         ADO folder path (default: \OneBranch\sdp-pipelines\hcp\Incremental)

EXAMPLES:
    get-ev2-releases -Environment prod
    get-ev2-releases -Environment stg -Hours 12
    get-ev2-releases -Environment test -Hours 0
```
