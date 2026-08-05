---
name: release-rollout
description: Guide and track ARO HCP release rollouts through INT, Stage, and Prod environments. Use when performing, monitoring, retrying, or troubleshooting an EV2 rollout.
---

## Personal Overrides

If a `SKILL.local.md` file exists in this skill's directory, read it before
proceeding. It contains personal instructions that augment (never contradict)
the directions below.

# ARO HCP Release Rollout Guide

## What I Do

Guide the oncall IC through the ARO HCP release process across all three
environments (INT, Stage, Prod). This includes:

1. Understanding the current rollout state
2. Identifying the correct release candidate
3. Walking through promotion steps (PR, merge, EV2 approval)
4. Monitoring rollout progress
5. Handling failures, retries, and reverts
6. Documenting rollout actions on the oncall JIRA

## When to Use Me

- User is performing a Stage or Prod rollout
- User asks about the release process or promotion flow
- User has a failed EV2 rollout and needs to retry or revert
- User is monitoring a rollout's e2e gating
- User mentions "rollout", "release", "RC", "release candidate", "EV2",
  "promote to stage", "promote to prod"

## Core Principles

1. **Never skip environments.** Always INT -> Stage -> Prod.
2. **CI must be green enough before promoting to Stage.** CI health takes
   priority over completing a release.
3. **Quick reverts are the default fix.** If a component breaks a rollout
   or fails a gate, revert first, investigate second.
4. **Stage is a prerequisite for Prod.** Never promote to Prod without a
   green Stage rollout.

## Release Cadence

| Environment | Cadence | Trigger |
|-------------|---------|---------|
| INT | Every 2 hours (automated) | Merge to `main` in sdp-pipelines |
| Stage | Daily | Manual RC pipeline + PR approval |
| Prod | Twice weekly (Mon + Wed ideal) | Manual RC pipeline + PR approval + manual pipeline trigger |

## Architecture: Branching and Promotion

The sdp-pipelines ADO repo uses a three-branch promotion model:

```
main (INT) --> release/hcp/public/stg (Stage) --> release/hcp/public/prod (Prod)
```

### Key Repositories and Locations

| Item | Location |
|------|----------|
| sdp-pipelines repo | `https://dev.azure.com/msazure/AzureRedHatOpenShift/_git/sdp-pipelines` |
| EV2 approval portal (SAW) | `https://approval.azengsys.com/` |
| Release Dashboard | `https://release-dashboard.tools.hcpsvc.osadev.cloud/` |
| CI Health Dashboard | `https://cihealth.tools.hcpsvc.osadev.cloud/` |
| ARO-HCP GitHub repo | `https://github.com/Azure/ARO-HCP` |

## The Release Flow (End to End)

### Step 1: ARO-HCP Bump (Automated)

Every 2 hours, the `bump-aro-hcp` pipeline runs on `main`:
- Checks out the latest ARO-HCP commit from GitHub
- Bumps the revision in `hcp/Revision.mk`
- Bumps container image digests in `hcp/digests.yaml`
- Creates a PR to `main` (branch pattern:
  `release-candidate-creator/hcp/int/update-to-<short-sha>`)
- When the PR merges, the global buildout pipeline deploys to INT

### Step 2: Promote to Stage

#### 2a. Create the Release Candidate PR

The **Pipeline Candidate branch pipeline** creates a promotion PR:

- **Pipeline**: `release-candidate-promoter.yaml`
  (`https://dev.azure.com/msazure/AzureRedHatOpenShift/_build?definitionId=...`)
- **What it does**: Runs `./tooling/aro release candidate create
  --environment stg --service hcp`
- **Output**: Creates a branch
  `release-candidate-creator/hcp/stg/update-to-<commit-sha>` and a PR
  targeting `release/hcp/public/stg`
- **Alternative**: The Release Dashboard's release-candidate controller can
  also create these PRs automatically when enabled.

If no automatic PR is available, run the Pipeline Candidate branch pipeline
manually from ADO.

#### 2b. Review and Approve the PR

- The PR shows the diff between current `release/hcp/public/stg` and
  `main` (or the selected green INT commit)
- Review the changes (config bumps, digest updates, etc.)
- **A second SL SRE is needed for approval** (for Prod; Stage may be
  self-approved depending on policy)
- Complete (merge) the PR

#### 2c. Global Buildout Triggers

Merging the PR to `release/hcp/public/stg` automatically triggers:
1. The **global buildout pipeline** which generates EV2 manifests
2. An **EV2 approval request** is created

#### 2d. Approve the EV2 Rollout

- An EV2 approval link appears (format:
  `https://approval.azengsys.com/approvalRequest?id=<GUID>`)
- Approve via the SAW portal
- The EV2 rollout begins executing

#### 2e. Monitor E2E Gating

- The rollout runs e2e tests as a gate
- Monitor via the ADO build link
- If e2e passes: rollout completes
- If e2e fails: see "Handling Failures" below

### Step 3: Promote to Prod

#### 3a. Create the Prod Release Candidate PR

Same as Stage, but targeting `release/hcp/public/prod`:

- Run the Pipeline Candidate branch pipeline with `promotionBranch=prod`
- Creates a PR from `release/hcp/public/stg` to `release/hcp/public/prod`

#### 3b. Review and Approve

- **Requires a second SL SRE for approval**
- Review changes, complete the PR

#### 3c. Manual Pipeline Trigger (Prod Only)

Unlike Stage, merging to `release/hcp/public/prod` does NOT auto-trigger
deployment. You must manually run the entrypoint pipeline:

- Pipeline: **Entrypoint - HCP.Global - prod**
  (`https://dev.azure.com/msazure/AzureRedHatOpenShift/_build?definitionId=...`)
- **Run from the `release/hcp/public/prod` branch**
- Specify regions:
  `uksouth,switzerlandnorth,canadacentral,australiaeast,centralindia,brazilsouth,eastus2,westeurope`
- Prod rolls out region-by-region with EV2 approval gates between regions

#### 3d. Approve EV2 Rollouts

- Each region generates a separate EV2 approval
- Approve each as it becomes ready
- Monitor e2e gating per region

## Handling Failures

### E2E Gate Failure

1. **Check if the failure is a known flake** — consult the CI Health
   Dashboard Failure Patterns page
2. **If flake**: the rollout can be retried. Options:
   - Wait for the pipeline to auto-retry (if configured)
   - Manually retry the failed step in the ADO pipeline
   - Create a new RC pipeline run to generate a fresh promotion PR
3. **If regression**: investigate the root cause
   - Check which commits are new in this RC vs. the previous green rollout
   - Identify the breaking change
   - **Revert first**, then notify the component team

### EV2 Rollout Failure (Non-E2E)

EV2 steps can fail for infrastructure reasons (node issues, namespace
stuck, etc.):

1. Check the EV2 step logs in the ADO build
2. Identify the failing step (e.g., `service-lifecycle`, `region-pipeline`)
3. Fix the underlying issue (e.g., force-delete stuck pods, clean up
   orphaned resources)
4. **Retry the failed EV2 step** in the ADO pipeline — do NOT re-merge
   the PR (it already merged)

### PR Already Merged but EV2 Failed

This is a common scenario. The PR merging and the EV2 rollout are
**decoupled**:

- The PR merges commits into the release branch
- The merge triggers the buildout pipeline which generates EV2 manifests
- The EV2 rollout is a separate process that can fail independently

**To retry after this scenario:**
1. A new RC pipeline run creates a fresh branch and PR with the latest
   green INT state
2. The new PR may contain the same or newer commits
3. Approve and merge the new PR
4. Approve the new EV2 rollout
5. The previous failed rollout's state is superseded

### Reverting a Rollout

If a rollout introduced a regression to Stage or Prod:

1. Identify the breaking commit(s)
2. Revert the commit(s) on `main`
3. Wait for INT to pick up the revert
4. Create a new RC promotion PR to push the revert through Stage/Prod
5. Notify the responsible team to provide a fix for re-submission

## Checking Current State

### What's deployed where?

```bash
# Check what's on the stage release branch (from your local sdp-pipelines clone)
cd <sdp-pipelines-clone>
git fetch origin
git log --oneline -10 origin/release/hcp/public/stg

# Check what's on the prod release branch
git log --oneline -10 origin/release/hcp/public/prod

# What's on main but not yet on stage
git log --oneline origin/release/hcp/public/stg..origin/main | head -20

# What's on stage but not yet on prod
git log --oneline origin/release/hcp/public/prod..origin/release/hcp/public/stg | head -20
```

### Finding RC branches and PRs

```bash
# List recent stage RC branches
git branch -a --sort=-committerdate | grep 'release-candidate-creator/hcp/stg' | head -5

# List recent prod RC branches
git branch -a --sort=-committerdate | grep 'release-candidate-creator/hcp/prod' | head -5
```

## Pre-Release Checklist (Stage)

Before promoting to Stage, verify:

- [ ] CI Health Dashboard shows acceptable e2e pass rate
- [ ] No active regressions in Failure Patterns
- [ ] INT rollout is green (check Release Dashboard)
- [ ] No blocking IcM incidents
- [ ] The RC PR contains a coherent set of digests deployed to INT together

## Pre-Release Checklist (Prod)

Before promoting to Prod (per the release policy):

- [ ] Stage rollout completed successfully with green e2e
- [ ] Release thread created in `#external-rh-msft-forum-aro-release`
  (Friday, preferably APAC hours) with:
  - Summary of components being released
  - Digests deployed to INT as a single set
  - Summary of recent CI INT job runs
  - Message to component owners asking about known issues
- [ ] No objections from component teams (implied approval if no response)
- [ ] Second SL SRE available for approvals
- [ ] Run from `release/hcp/public/prod` branch

## Stage Environments

There may be multiple Stage environments in play:

| Environment | Region | Branch | Status |
|-------------|--------|--------|--------|
| Old Stage | uksouth | `release/hcp/public/stg` | Current rollout target |
| New Stage | westus3 | `release/hcp/public/stg` | Trial environment |

Both use the same release branch. Regional differences are handled by
rendered config files (`hcp/rendered/public/stg/uksouth.yaml`,
`hcp/rendered/public/stg/westus3.yaml`).

## Prod Regions

Prod rolls out across these regions (in order specified at pipeline
trigger):

```
uksouth, switzerlandnorth, canadacentral, australiaeast,
centralindia, brazilsouth, eastus2, westeurope
```

Plus the canary region: `eastus2euap`

## JIRA Documentation

All rollout actions must be documented on the oncall JIRA. Use the
`oncall-shift` skill to post updates. Key things to document:

- RC PR number and link
- EV2 approval link
- E2E gate result (pass/fail, with failure details if applicable)
- Any manual interventions (retries, force-deletes, step retries)
- Chat excerpts with attribution for rollout decisions

## Reference: Key ADO Pipelines

| Pipeline | Purpose | Trigger |
|----------|---------|---------|
| `bump-aro-hcp` | Bump ARO-HCP revision + digests | Cron (every 2h on main) |
| `artifact-bumper` | Bump build artifact IDs | Cron (4x daily weekdays) |
| `release-candidate-promoter` | Create RC promotion PRs | Manual |
| Global buildout (stg) | Generate EV2 manifests for Stage | Merge to `release/hcp/public/stg` |
| Global buildout (prod) | Generate EV2 manifests for Prod | Merge to `release/hcp/public/prod` |
| Entrypoint - HCP.Global - prod | Execute Prod rollout | Manual (from prod branch) |

## Reference: Key File Paths (sdp-pipelines)

| File | Purpose |
|------|---------|
| `hcp/Revision.mk` | ARO-HCP commit SHA pinned for this release |
| `hcp/digests.yaml` | Container image digests |
| `hcp/config.yaml` | Merged service configuration |
| `hcp/rendered/` | Per-environment, per-region rendered configs |
| `.pipelines/release-candidate-promoter.yaml` | RC promotion pipeline definition |
| `.pipelines/bump-aro-hcp.yaml` | Auto-bump pipeline definition |
