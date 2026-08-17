---
name: aro-hcp-e2e-capacity
description: Calculate and explain ARO-HCP E2E capacity from the checked-in Bicep role assignments, e2e-slots.yaml, and docs/ci scaling constraints. Use for per-run role-assignment cost, test concurrency, slot sizing, subscription headroom, and maximum concurrent E2E job questions.
allowed-tools: shell
---

# ARO-HCP E2E Capacity

Answer E2E capacity-planning questions from the current ARO-HCP checkout. Never
reuse role counts, slot counts, quotas, headroom, or scaling limits from this
skill, memory, a previous chat, or an old calculation.

## Source priority

Read sources in this order:

1. `test/e2e-setup/bicep/modules/managed-identities.bicep` and the role-assignment
   modules it invokes, plus `test/e2e-config/e2e-slots.yaml`
2. `docs/ci/`, especially `docs/ci/identity-leasing.md`

The checked-in Bicep is authoritative for E2E-created role assignments. The slot
catalog is authoritative for configured subscriptions, slots, and identity
container counts. Documentation supplies constraints not represented in those
files, such as RP-managed assignments, reserved headroom, quota assumptions,
deny-assignment limits, environment applicability, and the intended capacity
formula.

If a documented test-side count or total conflicts with the Bicep inventory,
calculate from Bicep, report the documentation drift, and do not silently use
the stale documented total.

## Locate the checkout

Use the ARO-HCP worktree in or below the current workspace. Confirm it with:

```bash
git -C <ARO-HCP-dir> rev-parse --show-toplevel
git -C <ARO-HCP-dir> status --short --branch
```

Use the checked-out revision unless the user explicitly asks for another branch,
PR, or `origin/main`. Report the revision or branch used.

## Inventory role assignments

Start at:

```text
test/e2e-setup/bicep/modules/managed-identities.bicep
```

Follow its module references. For the current suite, count
`Microsoft.Authorization/roleAssignments` resources in the invoked current
modules, normally:

```text
test/e2e-setup/bicep/modules/non-msi-scoped-assignments.bicep
test/e2e-setup/bicep/modules/msi-scoped-assignments.bicep
```

Do not count similarly named backlevel modules unless the question concerns that
backlevel test path. If it does, inventory the modules actually referenced by
that path separately.

Classify every assignment resource as:

- unconditional
- active when `rbacScope == 'resourceGroup'`
- active when `rbacScope == 'resource'`
- guarded by another condition that affects whether it exists

Then calculate:

```text
test_rg_cost       = unconditional + resourceGroup-active
test_resource_cost = unconditional + resource-active
```

Do not count comments, role definitions, existing identities, or module
declarations as assignments. Inspect multiline declarations and conditions; do
not rely on a raw substring count alone.

Useful inventory commands:

```bash
rg -n "Microsoft\.Authorization/roleAssignments|rbacScope" \
  test/e2e-setup/bicep/modules/{managed-identities,non-msi-scoped-assignments,msi-scoped-assignments}.bicep

rg -n "RBACScopeResource(Group)?" test/e2e test/util/framework
```

Compile the affected entry-point templates with the repository's existing Bicep
tooling when a proposed change or branch is being evaluated. A successful
compile validates syntax but does not replace the source inventory.

## Add documented non-Bicep costs

Read `docs/ci/identity-leasing.md` on every calculation. Extract, rather than
assume:

- assignments created outside the E2E Bicep, especially RP-managed assignments
- reserved role-assignment headroom
- the role-assignment quota or limit used by the documented model
- the expected resource-group/resource-scope suite mix
- deny-assignment limits, per-HCP cost, and environments where they apply
- any individual-spec or unmanaged-pool caveats

Compute total per-HCP costs from the current inventory:

```text
rg_hcp_cost       = test_rg_cost       + documented_non_bicep_hcp_cost
resource_hcp_cost = test_resource_cost + documented_non_bicep_hcp_cost
```

If documentation only gives totals, derive the non-Bicep component from its
stated breakdown. Show that derivation and flag ambiguity instead of inventing a
value.

## Read configured capacity

Read every pool from `test/e2e-config/e2e-slots.yaml`. Capture:

- environment and deploy environments
- `subscription_name`
- `resource_type`
- `slot_count`
- `identity_container_count`
- region and region mode
- identity provisioning mode, when present

Group pools by environment and `subscription_name`. Multiple regional pools can
share one subscription and therefore one subscription-wide role-assignment
budget. Do not calculate each such pool as if it had an independent quota.

Treat:

```text
configured_jobs_for_pool = slot_count
max_concurrent_hcps_for_pool = slot_count * identity_container_count
```

as configured capacity, not proof that Azure quota permits it.

## Capacity calculations

### One E2E run

Determine or state the assumed concurrent HCP mix:

```text
run_cost =
    rg_scoped_hcps       * rg_hcp_cost
  + resource_scoped_hcps * resource_hcp_cost
  + extra_spec_assignments
```

The identity container count is the maximum concurrent HCP demand available to
the run. It is not automatically the number of test specs or Ginkgo workers.
Use `labels.MIContainers(N)`, test setup, and the documented suite model when the
question is about a specific test or suite.

For a specific test that consumes multiple containers:

```text
test_instance_cost =
    test_rg_scoped_hcps       * rg_hcp_cost
  + test_resource_scoped_hcps * resource_hcp_cost
  + test_specific_assignments

container_limited_test_concurrency =
  floor(identity_container_count / MIContainers_per_test)
```

Inspect the test implementation when `MIContainers(N)` does not directly equal
the number of simultaneously provisioned HCPs. The effective test concurrency is
the minimum of the suite runner's configured concurrency, container-limited
concurrency, role-assignment budget, and any other documented resource limit.

For the common model where one resource-scoped HCP is mixed with the remaining
resource-group-scoped HCPs:

```text
run_cost =
    (hcp_concurrency - resource_scoped_hcps) * rg_hcp_cost
  + resource_scoped_hcps * resource_hcp_cost
```

Obtain `resource_scoped_hcps` from current documentation or current test code;
never assume a fixed count from this skill.

### One subscription

For all pools sharing a subscription:

```text
configured_subscription_jobs = sum(slot_count)
configured_subscription_cost = sum(slot_count * run_cost_for_that_pool)
```

Using the documented reserve:

```text
role_limited_jobs =
  floor((documented_role_limit - documented_reserved_headroom) / run_cost)
```

When pools have different run costs, add them explicitly rather than using this
single-cost shortcut.

If the user asks about actual current headroom, query Azure and replace the
generic reserve only for that live comparison:

```bash
az role assignment list --subscription <subscription-id> --all -o json
```

Filter assignments whose scope equals `/subscriptions/<subscription-id>`
case-insensitively to measure exact subscription-scoped baseline assignments.
Keep exact-subscription and child-scoped assignments separate. Child-scoped
assignments may overlap active E2E HCP cost, so do not add them to the model
without classifying their scopes.

Report both:

```text
documented_model_remaining =
  role_limit - configured_subscription_cost - documented_reserved_headroom

live_exact_scope_remaining =
  role_limit - configured_subscription_cost - exact_subscription_scope_baseline
```

Do not claim that exact subscription scope represents the full persistent
baseline. State what was and was not classified.

### Effective job capacity

Read every applicable constraint from the current docs and catalog. Calculate
each independently:

```text
effective_jobs =
  min(
    configured_slot_jobs,
    role_assignment_limited_jobs,
    deny_assignment_limited_jobs,
    any_other_documented_limit
  )
```

Only apply a constraint to the environments where documentation says it applies.
For deny assignments, derive maximum HCPs and slots from the documented limit,
per-HCP consumption, and each pool's identity container count.

### Overall environment capacity

Calculate effective jobs independently for each unique subscription, then sum:

```text
overall_configured_jobs = sum(configured_jobs_by_unique_subscription)
overall_effective_jobs  = sum(effective_jobs_by_unique_subscription)
```

Do not sum independent theoretical maxima for two pools that share a
subscription. If jobs can be restricted by region, deploy environment, allowed
subscription list, or unmanaged provisioning, report both the full catalog
maximum and the maximum reachable by the specific job configuration in the
question.

### Proposed role changes

For a proposed assignment delta, classify the new Bicep resources by activation
condition:

```text
proposed_rg_hcp_cost       = current_rg_hcp_cost       + rg_active_delta
proposed_resource_hcp_cost = current_resource_hcp_cost + resource_active_delta
```

Recalculate every affected run and subscription. Show current, proposed, delta,
remaining quota, and whether configured slots must change. Do not edit
`e2e-slots.yaml` unless the user asks for an implementation.

## Capacity-change guidance

When the user asks how to change pool sizes or maximum job counts, provide an
ordered rollout plan, not just the final YAML values. Re-read these current
sources before giving instructions:

```text
docs/ci/identity-leasing.md
docs/ci/e2e-subscription-onboarding.md
test/cmd/aro-hcp-tests/slot-manager/slots/generate_boskos.go
test/cmd/aro-hcp-tests/slot-manager/identity-pool/
test/Makefile
```

Also inspect the current `openshift/release` checkout:

```text
core-services/prow/02_config/generate-boskos.py
core-services/prow/02_config/_boskos.yaml
ci-operator/config/Azure/ARO-HCP/
ci-operator/jobs/Azure/ARO-HCP/
```

Use `rg` to find the affected `resource_type`, job name, lease, selectors, and
any job-level concurrency setting. Edit source configuration, not generated job
files, and use the release repository's documented regeneration command.

Before proposing any rollout:

1. Recalculate post-change role-assignment, deny-assignment, identity-container,
   and job capacity.
2. Confirm the target subscription quota and persistent baseline leave enough
   margin.
3. Identify whether the change affects:
   - `slot_count`
   - `identity_container_count`
   - an entire pool/subscription
   - release-side job admission or maximum job count
   - more than one of the above
4. Identify whether the pool is managed or marked
   `identity_provisioning: unmanaged`.
5. List the ARO-HCP PR, `openshift/release` PR, manual Azure action, rollout
   wait, and verification as separate steps with explicit dependencies.

For an unmanaged pool, read the current external-subscription onboarding
documentation and name the owning team's approval/provisioning step. Do not
apply or delete owner-managed resources merely because the local command
supports an explicit subscription selector.

### Tooling facts to verify from source

The skill should confirm these behaviors in current code before relying on them:

- `sync-boskos-config` rewrites the ARO-HCP-managed Boskos types and resource
  names from the slot catalog.
- `validate-boskos-config` intentionally permits a temporary cross-repository
  mismatch because growth and shrink require opposite ordering.
- The source currently states: grow the catalog before Boskos; shrink Boskos
  before the catalog.
- `apply-identity-pool` creates or updates a deployment stack for every managed
  slot present in the selected catalog.
- Reducing `identity_container_count` updates an existing stack. If its current
  `ActionOnUnmanage` deletes unmanaged resources/resource groups, applying the
  reduction is destructive.
- Removing a slot from the catalog means `apply-identity-pool` no longer visits
  that slot. Do not assume this automatically deletes the removed slot's
  deployment stack or resource groups.

If current code differs, follow current code and report the drift from this
workflow.

### Increasing slot count

Consumer capacity must become usable only after the backing Azure resources
exist.

1. Prepare the ARO-HCP catalog change and recalculate capacity.
2. Build the E2E binary/artifacts from that proposed ARO-HCP revision.
3. Manually apply the expanded identity pool from the proposed revision using
   the current Make target documented in `test/Makefile`. Prefer the Make target
   over `go run` or a stale binary because it rebuilds embedded Bicep artifacts.
   Read the target before quoting syntax; when unchanged, use
   `make -C test apply-identity-pool ENVIRONMENT=<environment>` and add its
   optional subscription selector only when intentionally targeting one
   subscription.
4. Verify every new slot deployment stack and every expected identity-container
   resource group exists.
5. Merge the ARO-HCP catalog PR.
6. From a release checkout, run the current `sync-boskos-config`, regenerate
   release config, and run `validate-boskos-config`.
7. Merge the `openshift/release` PR only after the ARO-HCP catalog revision and
   Azure identity containers are ready. Wait for the Boskos rollout.
8. Increase any separate release-side maximum job count last.
9. Rehearse acquisition, confirm the new slots can be leased, and verify release
   returns them to Boskos.

The release PR can be prepared in parallel, but it must not expose new slots
before their containers exist.

### Increasing identity containers in existing slots

Existing slots are already leaseable, so this ordering is stricter:

1. Prepare the ARO-HCP `identity_container_count` change.
2. From that proposed revision, manually apply the expanded deployment stacks.
3. Verify the added containers before merging the ARO-HCP PR.
4. Merge the ARO-HCP PR so new jobs begin requesting the larger container set.
5. Change `openshift/release` only if job admission, selectors, leases, or a
   separate maximum job count also changes; merge that change after the Azure
   expansion and ARO-HCP merge.

Changing only `identity_container_count` does not inherently add Boskos slot
resource names. Confirm whether the generated release inventory actually
changes rather than opening an empty release PR.

### Decreasing slot count

Stop consumers before removing catalog capacity:

1. Lower any release-side maximum job count or routing that could fill the slots
   being removed.
2. Update `openshift/release` Boskos inventory first, regenerate it, merge, and
   wait for rollout. This is the shrink ordering required by the current
   slot-manager source.
3. Verify removed slot names are no longer acquirable and wait for existing
   leases/jobs on them to finish.
4. Reduce `slot_count` in the ARO-HCP catalog and merge that PR.
5. Decide explicitly whether to retain or delete the removed slot deployment
   stacks and identity-container resource groups.

Do not tell the user that `apply-identity-pool` cleans up removed slots unless
current code implements that reconciliation. Any deployment-stack deletion is a
separate destructive operation: inventory the exact stacks, prove they have no
active leases or HCP resources, and require explicit approval before deletion.

### Decreasing identity containers in existing slots

Do not apply the smaller deployment stack while jobs can still be using the
containers that will be removed.

1. If needed, temporarily lower job admission/concurrency so the pool can drain.
2. Merge the ARO-HCP catalog reduction first. New jobs can safely use the
   smaller prefix range because those lower-index containers already exist.
3. Wait for every job started with the old catalog revision to finish and verify
   the soon-to-be-removed containers are not leased or busy.
4. Manually apply the reduced identity pool.
5. Treat the apply as destructive when the current deployment stack uses delete
   on unmanage; verify exactly which resource groups will be removed.
6. Restore or adjust release-side job concurrency only after the reduced pool is
   stable.

### Adding or removing a subscription/pool

For additions, follow the current onboarding document in full. A slot-catalog
entry alone is insufficient; onboarding can also require Azure provider/quota
setup, cluster-profile inventory, bootstrap RBAC, monitoring inventory, AFEC
registration, cleanup jobs, and owner-operated actions. Managed and external
subscriptions have different ownership boundaries.

For removals, reverse consumer exposure before deleting infrastructure:

1. Remove or restrict release-side routing and Boskos resources.
2. Wait for rollout and drain all leases/jobs.
3. Remove the ARO-HCP catalog entry.
4. Update cluster-profile, monitoring, cleanup, and bootstrap inventories as
   applicable.
5. Handle deployment stacks and Azure resources as an explicit, separately
   approved cleanup; absence from the catalog is not proof of deletion.

### Required rollout-plan format

Present coordinated changes as a dependency table:

| Order | Repository / system | Change or action | Must wait for | Verification |
| ---: | --- | --- | --- | --- |
| ... | ARO-HCP | ... | ... | ... |
| ... | Azure manual action | ... | ... | ... |
| ... | openshift/release | ... | ... | ... |

State which PR must merge first, which manual action is not automated, what
rollout must complete, and what would fail if the order were reversed.

## Required answer format

Lead with the binding result, then show a compact table:

| Scope | Current source count | Proposed count | Source |
| --- | ---: | ---: | --- |
| E2E Bicep, resource-group mode | ... | ... | file:lines |
| E2E Bicep, resource mode | ... | ... | file:lines |
| Non-Bicep per HCP | ... | ... | docs file:lines |

For capacity:

| Subscription / pool | Slots | HCPs per run | Cost per run | Total modeled cost | Remaining | Binding constraint |
| --- | ---: | ---: | ---: | ---: | ---: | --- |

Always include:

- branch or commit inspected
- formulas with substituted current values
- configured capacity versus theoretical maximum
- assumptions about resource-scope test count and extra per-spec assignments
- documentation drift or unclassified live assignments
- file-and-line citations for every material input

Keep calculations reproducible. Prefer a short command or arithmetic expression
that another engineer can rerun over an unexplained number.

## Guardrails

- Never hardcode capacity values in this skill.
- Never trust a previous answer over the current checkout.
- Never multiply slots across pools before grouping by subscription.
- Never treat Ginkgo parallelism, test count, identity containers, HCP
  concurrency, and concurrent jobs as interchangeable.
- Never use a documented test-side total when current Bicep disagrees.
- Never treat a live Azure snapshot as the checked-in capacity plan.
- Never change leases, job counts, quotas, or Azure resources unless explicitly
  asked.
