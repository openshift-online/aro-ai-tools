---
name: aro-hcp-releases
description: List ARO HCP pipeline releases (Azure DevOps builds) for a specific environment (test, stg, prod, int). Use when asked things like "get all releases for test", "show stage releases", or "what's releasing to prod".
allowed-tools: shell
---

List ARO HCP SDP pipeline releases (Azure DevOps builds) filtered to a single
environment. Environments are distinguished by the trailing `- <env>` segment of
the pipeline definition name (e.g. `Incremental - Entrypoint - HCP.Global - stg`),
so this skill runs the `oncall builds` CLI and keeps only the rows for the
requested environment.

For **EV2 rollouts** (not pipeline builds), use the `aro-hcp-ev2-releases` skill.

## Prerequisites

- The `oncall` CLI must be installed and on `PATH` or at `~/bin/oncall`. It is
  built from `oncall-cli/` in this repo — run `oncall-cli/setup.sh` to build and
  install it there (requires Go).
- Azure DevOps auth: either the `ADO_PAT` env var is set, or you are logged in
  via `az` (the CLI falls back to an `az` access token).

If the CLI is missing, the script prints setup instructions and exits.

## Arguments

- **Environment** (required): `test`, `stg`, `prod`, or `int`. Natural-language
  aliases are normalised: `stage`/`staging` → `stg`, `production` → `prod`,
  `integration` → `int`, `tst` → `test`.
- **Hours** (optional, default `24`): look back N hours. Use `0` for currently
  running builds only.
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
   - On **macOS**: run `scripts/get-releases.sh -Environment <env> [-Hours N] [-Path PATH]` using `zsh`.
   - On **Linux/WSL2**: run `scripts/get-releases.sh -Environment <env> [-Hours N] [-Path PATH]` using `bash`.
   - On **Windows (non-WSL)**: run `scripts/get-releases.ps1 -Environment <env> [-Hours N] [-Path PATH]` using `pwsh`.
3. Present the returned markdown table to the user as-is.
4. If the script reports that no releases matched the environment, it also lists
   the environment tokens it did see — re-run with one of those if appropriate,
   or tell the user which environments are currently present.

## Reference

```
get-releases (.sh and .ps1) — List ARO HCP pipeline releases for one environment

USAGE:
    get-releases -Environment <env> [-Hours <int>] [-Path <path>]

REQUIRED:
    -Environment <env>   test | stg | prod | int
                           (aliases: stage/staging->stg, production->prod,
                            integration->int, tst->test). Matched against the
                            trailing "- <env>" segment of the pipeline name.

OPTIONS:
    -Hours <int>         Look back N hours (default: 24; 0 = running only)
    -Path <path>         ADO folder path (default: \OneBranch\sdp-pipelines\hcp\Incremental)

EXAMPLES:
    get-releases -Environment stg
    get-releases -Environment test -Hours 6
    get-releases -Environment prod -Hours 0
```
