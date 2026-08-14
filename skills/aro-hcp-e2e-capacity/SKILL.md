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
