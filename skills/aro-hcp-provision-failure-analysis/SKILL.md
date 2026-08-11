---
name: provision-failure-analysis
description: Triage and analyze e2e-parallel provision failures in DEV. Covers Bicep/ARM deployments, Helm releases, Shell steps, and CI or platform infrastructure. Use when investigating why e2e-parallel provision failed.
---

# Provision Failure Analysis

Systematic triage of `e2e-parallel` provision failures in the DEV environment.

## Prerequisites

- Required: `cihealth-api` skill for failure history, run data, and Prow artifacts.
- Conditional: `aro-kusto` skill for Kubernetes, application, or node evidence
  that is not present in Prow artifacts.
- DEV Kusto: cluster `https://hcp-dev-us-2.eastus2.kusto.windows.net`, database
  `ServiceLogs`.

ARM and Shell failures can often be fully analyzed from CIHealth, Prow artifacts,
pipeline configuration, and source code. Do not require Kusto when those sources
already establish the failure.

## Step 1: Gather failure data

Use the `cihealth-api` skill to pull failure patterns and run logs for the relevant
UTC dates. Collect distinct affected run URLs and multiple job IDs for recurring
patterns.

For each affected run:

1. Record job ID, PR and SHA, timestamp, failing service group/resource group/step,
   and normalized failure pattern.
2. Fetch the provision failure build log through the public storage URL documented
   by `cihealth-api`.
3. Keep the CIHealth occurrence text: Shell and Helm failures may contain their
   decisive evidence there even when the gather build log has no failed ARM
   deployment.

When comparing runs, distinguish jobs using current `main` from stale PR revisions
that predate an existing mitigation.

## Step 2: Classify the failure

Read the CIHealth occurrence and Prow artifacts. Classify the failing step:

- **Bicep/ARM deployment** — an ARM deployment or resource operation failed.
- **Helm release** — a chart failed to install, upgrade, or become ready.
- **Shell step** — a script or external command failed, timed out, or launched an
  asynchronous resource that failed.
- **CI infrastructure** — Prow, ci-operator, lease, source registry, or build
  infrastructure failed outside the product provisioning flow.

## Evidence standard

Keep these separate in the output:

- **Observed failure** — direct log, API, Kusto, or artifact evidence.
- **Supported classification** — the narrowest cause category established by that
  evidence.
- **Unknowns or hypotheses** — plausible explanations that are not proven.

Do not promote placement, host, throttling, DNS, race, or backend-service hypotheses
to root cause without evidence. If diagnostics suppress the underlying error or
teardown removes the resource, state that the precise component is unknown.

## Step 3: Investigate

### Pipeline retry and timeout behavior

Before deciding a failure is unrecoverable, inspect the failing step's
`automatedRetry` configuration and
`tooling/templatize/pkg/pipeline/run.go`.

Determine:

- Does `errorContainsAny` match the final wrapped error text? Matching is substring
  based.
- `maximumRetryCount` is the maximum **total step executions**, including the
  initial execution; it is not additional retries.
- `durationBetweenRetries` consumes wall-clock budget.
- The single-step timeout is created once and shared by all executions and delays.
- Does rerunning the step recreate the failed resource, resume it, or collide with
  leftover state? Verify cleanup and idempotency in code rather than assuming.

Budget using total executions:

```text
sum(failed execution durations)
+ sum(retry delays)
+ final successful execution duration
< shared step timeout
```

If cleanup is best-effort, note possible delete/create races or name collisions.

### Bicep/ARM errors

1. Identify the failed deployment, operation, target resource, and error code.
2. Record correlation ID, duration, timestamp, subscription, and resource group.
3. Find the relevant Bicep template and pipeline step in `dev-infrastructure/`.
4. Determine whether the evidence supports a code/configuration bug, quota issue,
   eventual-consistency failure, or transient resource-provider problem.
5. Compare occurrences: consistent inputs and errors suggest deterministic code or
   configuration; intermittent results suggest infrastructure but do not prove a
   specific backend cause.

#### Batch analysis

When a pattern has more than three occurrences:

1. Create a local working directory under
   `zz-ignore/provision-failures/<pattern-name>/`.
2. Download all build logs with bounded concurrency and HTTP failure checking.
3. Extract correlation ID, resource group, target resource/type, duration, error,
   and timestamp.
4. Compare what is consistent and what varies.
5. Look for ordering, timing, region, subscription, and concurrency patterns.

### Shell-step errors

1. Locate the exact command and script from the pipeline step.
2. Separate outer pipeline timeout, script timeout, and any inner process/resource
   timeout.
3. Trace the failure path from the observed terminal error back through wrappers;
   confirm which text reaches `automatedRetry`.
4. Inspect side effects and retry behavior:
   - Does the script delete/recreate an ephemeral resource?
   - Is cleanup synchronous and checked, or best-effort?
   - Is a retry safe after partial success?
5. Compare current code and prior mitigations with the SHA used by each failed job.
6. Prefer recreating a persistently unhealthy ephemeral resource over extending
   its wait indefinitely, but only when code inspection confirms that a full step
   retry performs that recreation.

For network, DNS, identity, or external command failures, preserve the actual
underlying error rather than replacing it with a generic readiness result.

### Helm release failures

Map the Prow job ID to cluster names using `cihealth-api`. Read the pipeline
`dependsOn` chain to understand what should already be healthy.

Use Kusto when the Prow artifacts do not contain the pod-level cause.

**Layer 1 — Kubernetes events**

```kql
kubernetesEvents
| where timestamp > datetime(YYYY-MM-DD HH:MM)
| where cluster == "<cluster-name>"
| where kubeEventType == "Warning"
| project timestamp, reason, message, eventNamespace, objectName
| order by timestamp asc
```

Look for `ErrImagePull`, `ImagePullBackOff`, `FailedCreatePodSandBox`,
`NetworkNotReady`, `FailedMount`, `FailedScheduling`, `Unhealthy`, and `BackOff`.

**Layer 2 — Container logs**

```kql
containerLogs
| where timestamp > datetime(YYYY-MM-DD HH:MM)
| where cluster == "<cluster-name>"
| where namespace_name == "<namespace>"
| where log has "error" or log has "fatal" or log has "panic"
| project timestamp, pod_name, container_name, log
| order by timestamp asc
```

**Layer 3 — API server and node logs**

Use `kubeAudit`, `aksEvents`, and `systemdLogs` when evidence indicates a
cluster-level or node-bootstrap issue rather than one workload.

## Evidence preservation in ephemeral environments

DEV CI environments are torn down after the job. Environment-local logs and
metrics are not durable evidence; metrics are lost during teardown.

The durable preservation mechanisms are:

- Logs already exported to Kusto before teardown.
- Prow artifacts written by job steps that run before environment teardown.

If current evidence is insufficient, recommend adding or extending a pre-teardown
gather step. Capture only non-secret diagnostics such as:

- exact command/resolver errors and timestamps;
- resource IDs, provisioning state, events, and correlation IDs;
- `/etc/resolv.conf`, address and route state for network failures;
- relevant Kubernetes events and workload logs;
- retry attempt counts and elapsed time.

Do not rely on inspecting the live environment after the job. Do not recommend
metrics as a preservation mechanism unless they are exported to a durable external
store before teardown.

## Step 4: Determine scope and validate mitigations

- **Frequency:** count distinct affected runs and calculate impact against all runs
  and provision-failed runs.
- **Consistency:** compare error, stage, duration, region, and subscription.
- **Change correlation:** inspect recent changes to the failing component and
  distinguish stale PR jobs from current-main jobs.
- **Before/after:** after a mitigation merges, query the same CIHealth pattern over
  a new window. Report zero occurrences explicitly when confirmed; otherwise
  compare rates rather than isolated counts.
- **Region test:** use another region only as a controlled experiment, not proof of
  root cause.

## Step 5: Escalate platform-level errors

Escalate when evidence shows a persistent, intermittent failure in a specific
Azure resource provider or platform path and code-level mitigations are exhausted.

Prepare:

1. Context and expected versus observed behavior.
2. Failure inventory with timestamps, subscription/resource IDs, correlation IDs,
   duration, job URLs, and exact terminal errors.
3. Consistent and varying attributes across failures.
4. Failed/successful comparison pairs, including recreated-resource attempts.
5. Kusto queries and Prow artifact links that remain available after teardown.
6. Specific questions for the owning platform team.

When ARM internal logs are available, use correlation IDs to reconstruct the
operation timeline. Otherwise prepare an IcM from the durable Kusto and Prow
evidence. Never assume the ephemeral resource can be inspected later.

## Step 6: Output

Structure findings as:

- **Observed root cause/classification** — evidence only.
- **Evidence** — exact snippets, queries, artifacts, and comparison tables.
- **Unknowns** — what the available evidence cannot establish.
- **Scope** — frequency, affected components, regions, and time window.
- **Proposed solutions** — immediate mitigation, diagnostics, and durable fix.
- **Effort versus impact** — prioritize quick wins without overstating certainty.
- **Post-fix result** — recurrence after merge when data is available.

For pipeline details and query references, see [reference.md](reference.md).
