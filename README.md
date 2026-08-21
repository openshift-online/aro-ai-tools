# aro-ai-tools

## Tools

### Ops Plugin

- Compatible with all agents and OSes.
- Zero-setup, just make sure you're `az`-logged into the appropriate tenant.
- Provides easy access to ARO HCP Grafana/Prometheus metrics and Kusto logs for ARO HCP and Classic.
  - (Not all Classic Kusto endpoints are accessible due to permissions; also there's no Grafana for Classic.)

#### Installation

```
/plugin marketplace add openshift-online/aro-ai-tools
/plugin install ops@aro-ai-tools
```

Now reload plugins / restart the agent and ask it, e.g. "which ARO HCP Kusto instances can I query" or "which ARO Classic Kusto instances can I query".

Note: **If your client supports it, you should enable marketplace autoupgrade as it won't be on by default.**. (Claude Code has this feature, Copilot CLI doesn't.)

### Standalone Skills

All skills, whether part of a plugin or not, can be installed on their own.

1. Run the skills installer
   ```
   npx skills@latest add openshift-online/aro-ai-tools
   ```
2. Pick the skills and agents you want.
3. Done (`npx skills --help` for more).

### Oncall CLI & Release Skills

The [`oncall-cli/`](oncall-cli/) directory holds a small Go CLI (`oncall`) that
queries Azure DevOps and EV2 for ARO HCP pipeline builds and rollouts. Build and
install it with `oncall-cli/setup.sh` (requires Go; auth via `ADO_PAT` or `az`).

Two standalone skills wrap it and filter results to a single environment
(distinguished by the trailing `- <env>` segment of the pipeline name, e.g.
`... - stg`):

- `aro-hcp-releases` — "get all releases for test/stg/prod" (ADO pipeline builds)
- `aro-hcp-ev2-releases` — "get all ev2 releases for prod/stg/test" (EV2 rollouts)


## Contributing

The lifecycle of a skill is split into two parts

### Standalone Skill

1. You do something.
2. You make a skill of it.
3. You use the skill multiple times and refine it.
4. You have the thought that it might be of use to others.
5. You send in a PR adding the skill into the `skills/` directory.

If *you* found it useful enough to refine how it works, who knows, maybe others will.

Things to consider:
- Was this a temporary task or something people will be doing long term (and therefore maintaining a skill for it makes sense).
- How hard is it to use? Will it work immediately or do people need to set up elaborate environments first.
- How hard is it to review? Is it a large verbose black box or can it be reviewed in under a minute by people wondering if they'd like to try it out? (See [grill-me](https://github.com/mattpocock/skills/blob/main/skills/productivity/grill-me/SKILL.md) for the gold standard.)
- (A common theme of all the points above is – what's the chance anyone other than you will actually take the time to install your skill and then use it more than once.)
- Will you maintain it? If a PR comes in, will you review it?

### Plugin Skill

The bar is considerably higher here.

1. Your skill is being used by multiple people and forms a basis of a common workflow.
2. Those people agree it should be available out of the box in a plugin.
3. At this point you can send in a PR to move your skill into a plugin (or to create a new plugin if interested parties agree to use it).

### PR Requirements

- Never push PRs that contain internal Microsoft endpoint URLs (e.g. ICM kusto). See how the `*-env-info` plugins handle this problem.
- If referencing internal Microsoft systems, only mention the parts your skill needs, never e.g. attach a full schema dump.
- If unsure, DM @mmazur first.

If you did end up pushing a PR containing more data then you should have:
- Ping repo maintainers.
- Overwrite your branch with commits not containing it, then remove the branch.
- Verify the PR no longer shows the info in the diff or description.
- Close the PR.

## Continuous Integration

This repository is onboarded onto [OpenShift CI (Prow)](https://docs.ci.openshift.org/). Configuration lives in [openshift/release](https://github.com/openshift/release) under `ci-operator/config/openshift-online/aro-ai-tools/` and `core-services/prow/02_config/openshift-online/aro-ai-tools/`.

### Presubmit checks

Every pull request automatically runs:

- **`ci/prow/shellcheck`** — [ShellCheck](https://www.shellcheck.net/) over all `*.sh` scripts.
- **`ci/prow/psscriptanalyzer`** — [PSScriptAnalyzer](https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/overview) (Warning and Error severity) over all `*.ps1` scripts.

Re-run a check by commenting `/test shellcheck`, `/test psscriptanalyzer`, or `/test all`.

### Merge flow

Merges are handled by Prow (Tide), not by pressing the GitHub merge button. A PR merges once it has both labels:

- `lgtm` — added when a reviewer comments `/lgtm`.
- `approved` — added when an [OWNERS](./OWNERS) approver comments `/approve`.

Approvers and reviewers are defined in [`OWNERS`](./OWNERS) / [`OWNERS_ALIASES`](./OWNERS_ALIASES), inherited from the ARO-HCP Service Lifecycle SRE team. Use `/hold` to block a merge and `/hold cancel` to release it.
