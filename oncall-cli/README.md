# ARO HCP Oncall CLI

Go CLI (`oncall`) for ARO HCP oncall engineers to check running pipelines and EV2 rollout status from the terminal.

It also powers the `aro-hcp-releases` and `aro-hcp-ev2-releases` skills in this
repo, which wrap `oncall builds` / `oncall ev2` and filter the results to a
single environment (test / stg / prod / int).

## Setup

```bash
./setup.sh
```

Builds the CLI, installs it to `$HOME/bin/oncall`, and adds `builds` / `ev2` / `e2e` aliases (absolute paths) to `~/.zshrc`, so you can run them directly instead of `oncall <subcommand>`. Idempotent — re-run anytime to rebuild. Then `source ~/.zshrc` or open a new shell.

Requires Go, and either `ADO_PAT` set or `az` CLI logged in.

## Commands

| Command | Description |
|---------|-------------|
| `oncall builds [--hours N] [--path PATH]` | List running/recent HCP pipeline builds |
| `oncall ev2 [--hours N] [--path PATH]` | Extract EV2 rollout URLs from build logs |
| `oncall e2e [--hours N] [--path PATH] [--ev2-host URL]` | E2E regional gating step status |

Defaults: `--hours 24`, `--path \OneBranch\sdp-pipelines\hcp\Incremental`.

```bash
oncall builds --hours 6
oncall ev2 --path '\OneBranch\sdp-pipelines\hcp\Incremental'
oncall e2e --ev2-host https://ev2.azure.net
```

## Auth

- **ADO:** `ADO_PAT` env var, else `az account get-access-token`
- **EV2:** `az account get-access-token --resource {ev2Host}` (corp login required)

## Project Structure

- `cmd/oncall/main.go` — entrypoint, subcommands, table formatting
- `internal/ado/` — Azure DevOps REST client
- `internal/ev2/` — EV2 REST client
- `internal/auth/` — token acquisition
- `setup.sh` — build, install, alias setup
- `SPEC.md` — full technical spec

## Known Issues

- EV2 `serviceGroupName` sent empty — may need deriving from rollout URL
- EV2 host/AAD resource unconfirmed on corpnet (default `https://ev2.azure.net`)
- ADO folder recursion (`path` param) needs real-world confirmation
- No caching — every call hits the APIs live
- Originally envisioned as a Copilot CLI skill; could become an MCP server

## Key API Details

- ADO base: `https://dev.azure.com/msazure/AzureRedHatOpenShift/_apis` (api-version 7.1)
- EV2 docs: https://eng.ms/docs/products/ev2/references/api/intro
- EV2 endpoint: `GET /api/rollouts/{rolloutId}?api-version=2016-07-01&embed-detail=true`

See `SPEC.md` for full technical details.
