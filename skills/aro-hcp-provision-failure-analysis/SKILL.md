---
name: provision-failure-analysis
description: Triage and analyze e2e-parallel provision failures in DEV. Covers Bicep/ARM deployments, Helm releases, Shell steps, and CI or platform infrastructure. Use when investigating why e2e-parallel provision failed, which provision failure pattern is most frequent, or whether a mitigation worked.
---

# Provision Failure Analysis

Evidence-first triage of `e2e-parallel` provision failures in the DEV environment.

This skill is a method, not a checklist. The steps say where to look and which
mistakes past investigations made. They do not limit what you may find. When a
failure fits no known pattern, that is expected: follow the evidence, and report
the new mode (see "When nothing matches"). [failure-modes.md](failure-modes.md)
holds dated field notes on modes seen before. Treat them as priors to test, never
as a lookup table. [reference.md](reference.md) holds commands, URLs, and system
facts.

This skill is read-only analysis. Do not change Azure, Kubernetes, or Helm state;
propose changes and say exactly what they would do.

## Prerequisites

- `aro-kusto` skill, and ARO-HCP `docs/ai/kusto-debugging.md`, for every Kusto query.
- `hcpctl ci failure-patterns` for failure patterns and run lists (commands in
  reference.md). It replaces CIHealth, which automated consumers cannot reach.
- DEV Kusto: cluster `https://hcp-dev-us-2.eastus2.kusto.windows.net`, database
  `ServiceLogs`.

ARM and Shell failures can often be fully analyzed from the pattern report, Prow
artifacts, pipeline configuration, and source code. Do not require Kusto when
those sources already establish the failure.

## Step 1: Gather failure data

Pull failure patterns for the relevant UTC window. A pattern is a **symptom
group, not a root cause**; pattern counts overlap and must not be added.

1. **State the effective coverage window.** `rp-provision` observations exist
   only for runs ingested after the collector rollout (forward-only, no
   backfill). Failed runs with no `rp-provision` observation are *unclassified*:
   classify each from its Prow artifacts by first failing step. Coverage gaps
   are findings, not tool defects.
2. **Use settled windows.** End the window at least 5 minutes before now
   (ingestion lag). Treat an unfinished day as provisional.
3. For each affected run record: job ID, job family (presubmit / periodic /
   postsubmit), PR and SHA for presubmits, timestamps, failing step, and
   normalized pattern. Collect distinct runs, not just occurrences.
4. Keep the observation text. Shell and Helm failures often carry their
   decisive evidence there and not in the gather build log.
5. Get cluster names from Kusto `ciJobOutcomes` (`svcCluster`, `mgmtCluster`,
   joined on `buildId`), not by deriving them from the job ID. Limits: only runs
   that provision their own clusters have names; `mgmtCluster` always shows
   stamp 1 even though `e2e-parallel` has stamps 1 and 2 (only
   `e2e-parallel-inplace-upgrade` has a single stamp).
6. When comparing runs, separate jobs on current `main` from stale PR revisions
   that predate an existing mitigation.

If you were told which component or layer to look at, stay in it. Report other
failures you saw as out-of-scope notes; do not chase them.

## Step 2: Classify the failure

Classify each run by its **first** failing step, using the Prow artifacts and the
observation text:

- **Bicep/ARM deployment** — an ARM deployment or resource operation failed.
- **Helm release** — a chart failed to install, upgrade, or become ready.
- **Shell step** — a script or external command failed, timed out, or launched an
  asynchronous resource that failed.
- **CI infrastructure** — Prow, ci-operator, lease, source registry, or build
  infrastructure failed outside the product provisioning flow.
- **Does not fit** — a legitimate answer. Say so and continue from the evidence.

A CI-infrastructure signature (for example name resolution failing before
provisioning starts) that also appears on unrelated jobs and PRs in the same
window is a platform event, not a provisioning defect. Check other runs before
assigning it.

## Evidence standard

Keep three lists apart in everything you write:

- **Observed failure** — direct log, API, Kusto, or artifact evidence, with source.
- **Supported classification** — the narrowest cause category that evidence establishes.
- **Unknowns or hypotheses** — plausible explanations that are not proven.

Rules that keep conclusions honest:

- Do not promote placement, host, throttling, DNS, race, or backend hypotheses to
  root cause without evidence. If diagnostics suppress the underlying error or
  teardown removes the resource, say the precise component is unknown.
- Before naming an event or alert reason as a cause, identify which component
  emits it and what it measures. Label proxies as proxies.
- Where host, hypervisor, kernel, or network cause is unproven, write only the
  observed event sequence with timestamps.
- Data from an unmerged or unrun PR or experiment is not evidence.
- For a delay, identify the single event that gates it and verify it in source.
  A correlated condition is not the cause if the gate is elsewhere.
- A statistical argument (rate, interleaved successes) can support a
  classification. State the numbers and mark it as supported-by-rate, not proven.

## Step 3: Investigate

### Principles

These are the questions that past investigations found worth asking. Apply the
ones the evidence makes relevant.

1. **First error wins.** Read the raw failing-step `build-log.txt` and find the
   earliest failure. Later errors such as cancellation, lookup/poll failures, and
   post-step noise are fallout until the earliest error is excluded. If a
   different error follows on retry, you have two defects; report both and say
   which one a fix addresses.
2. **Same text is not the same cause.** When runs share one normalized message
   (Helm deadline, `context deadline exceeded`), pull every occurrence in the
   window, including periodic jobs, and classify each with pod-level evidence.
   Report distinct modes with counts. Test each candidate factor against
   successful runs of the same job: a factor present in all successes is not the
   cause; the cause is the delta. For a proposed log signature, query healthy and
   failed runs to measure how specific it is and how many failures carry it.
3. **Durable evidence first.** DEV environments are torn down, but their logs are
   in Kusto. Query the run's clusters for the run window before calling anything
   unknowable. Compare complete values, not suffixes. Propose a new
   pre-teardown artifact only for data that is not already in Kusto.
4. **Test claimed causes, including your own.** When a ticket, colleague, bot, or
   your own earlier step names a cause, check it against the exact failing job's
   component logs, repo facts and design intent, comparison with runs that did
   not fail, and the whole affected population. Record each claim as supported,
   not supported, or unknown.
5. **Quantify before accepting throttling, capacity, or timeouts.** A 429 or
   capacity string in test output is not yet a cause. Separate real throttling
   from other services' 429s, establish scope (principal, subscription, tenant),
   check Activity Log and backend logs for representative correlation IDs, and
   reconcile any estimate against independent volume data. Before raising a
   timeout, measure the fault duration against the step budget and against the
   same step on successful runs.
6. **Understand the step.** Know what the failing script or template does, which
   ci-operator step or pod makes the call, and where it sits in the pipeline
   `dependsOn` chain. Know what should already exist when it fails.
7. **Check phase gates and siblings.** A provision-phase candidate must match what
   provision actually tolerated or failed. Do not blame an e2e-phase failure on
   a condition provision passed unless you show how it slipped through. If
   sibling components share the pattern, explain why they are unaffected before
   proposing a workload-specific cause.
8. **Use tracked source at a cited ref.** State the current `origin/main` SHA you
   read. Do not treat Slack, a prior AI summary, a diff view, or gitignored
   rendered output as current behavior.
9. **Check evidence of intent.** An under-provisioned DEV setting may be a
   deliberate throttling mitigation; find the measured headroom before calling it
   a risk. An omission described as intentional may still be a latent bug if the
   same artifact is built and consumed elsewhere. Both need evidence.
10. **Experiment with one variable.** A reproduction that differs from the failing
    environment in more than one variable (subscription, SKU, region, identity)
    confirms nothing. Diff the rendered configuration first.
11. **Check telemetry before trusting it.** Kusto counts and timings can mislead
    (see reference.md "Telemetry pitfalls"). Sanity-check populations and which
    timestamp you are using.

### When nothing matches

Build a timeline of the failing run: Prow step boundaries, ARM operations,
Kubernetes events, workload logs. Find the earliest anomaly. Compare it with the
nearest successful run of the same job and find what differs. Write competing
hypotheses and the observation that would separate them. Run those queries. Then
check [failure-modes.md](failure-modes.md) for similar past cases, as a source of
hypotheses and queries. If nothing fits, report the mode as a new-mode
candidate (Output).

### Pipeline retry and timeout behavior

Before deciding a failure is unrecoverable, or proposing a retry or timeout
change, inspect the failing step's `automatedRetry` configuration and
`tooling/templatize/pkg/pipeline/run.go`.

- Does `errorContainsAny` match the final wrapped error text? Matching is substring based.
- `maximumRetryCount` is the maximum **total step executions**, including the initial one.
- `durationBetweenRetries` consumes wall-clock budget.
- The single-step timeout is created once and shared by all executions and delays.
- Does rerunning the step recreate the failed resource, resume it, or collide with
  leftover state? Verify cleanup and idempotency in code.

Budget with total executions:

```text
sum(failed execution durations)
+ sum(retry delays)
+ final successful execution duration
< shared step timeout
```

If cleanup is best-effort, note possible delete/create races or name collisions.
Never inherit a retry count from an earlier PR; derive it from measured delays.

### Bicep/ARM errors

1. Identify the failed deployment, operation, target resource, and error code.
2. Record correlation ID, duration, timestamp, subscription, and resource group.
3. Find the relevant Bicep template and pipeline step in `dev-infrastructure/`.
4. Decide whether the evidence supports a code/configuration bug, quota issue,
   eventual-consistency failure, or transient resource-provider problem.
5. Compare occurrences: consistent inputs and errors suggest deterministic code
   or configuration; intermittent results suggest infrastructure but do not prove
   a specific backend cause.

When a pattern has more than three occurrences, download all build logs into a
working directory (see reference.md), extract the fields above, and compare what
is constant and what varies: ordering, timing, region, subscription, concurrency.

### Shell-step errors

1. Locate the exact command and script from the pipeline step.
2. Separate outer pipeline timeout, script timeout, and any inner process timeout.
3. Trace the terminal error back through wrappers; confirm which text reaches
   `automatedRetry`.
4. Inspect side effects: does the script delete and recreate an ephemeral
   resource? Is cleanup synchronous and checked? Is a retry safe after partial
   success?
5. Compare current code and prior mitigations with the SHA each failed job used.
6. Prefer recreating a persistently unhealthy ephemeral resource over waiting
   longer, but only when code inspection confirms a full step retry recreates it.

For network, DNS, identity, or external-command failures, preserve the actual
underlying error instead of replacing it with a generic readiness result.

### Helm release failures

Map the job to its clusters (Step 1.5). Read the pipeline `dependsOn` chain to see
what should already be healthy. Use Kusto when Prow artifacts lack the pod-level
cause. Work outward in layers (queries in reference.md):

1. Kubernetes events: `ErrImagePull`, `FailedCreatePodSandBox`, `NetworkNotReady`,
   `FailedMount`, `FailedScheduling`, `Unhealthy`, `BackOff`.
2. Container logs of the affected namespace.
3. API-server audit, AKS events, and node logs when the evidence points at the
   cluster or node bootstrap, not one workload.

If a pod crash-loops, compare the chart's arguments with the image actually
deployed, and find where that image reference came from, before blaming slow startup.

## Evidence preservation in ephemeral environments

Durable evidence is limited to logs already exported to Kusto and Prow artifacts
written before teardown. Environment-local metrics are lost at teardown.
Never plan on inspecting a live environment after the job.

If current evidence is insufficient and the data is not in Kusto, recommend a
pre-teardown gather step that is failure-triggered and read-only, capturing only
non-secret diagnostics: exact stderr and timestamps, resource IDs, provisioning
state, events, correlation IDs, resolver and route state for network failures,
relevant Kubernetes events and workload logs, and retry counts and elapsed time.
It must survive a frozen node and teardown.

## Step 4: Scope, existing work, and recurrence

- **Frequency:** count distinct affected runs against all runs and provision-failed runs.
- **Consistency:** compare error, stage, duration, region, and subscription.
- **Who caused it:** for each run decide PR-induced, main/shared, CI infrastructure,
  or known flake, with per-run counts. "Known flake" requires an existing ticket or
  fix. State whether the failure is deterministic or intermittent, including the
  PR's own run.
- **Existing work:** search merged and open PRs and Jira (read-only) for the
  component and error. If a mitigation was merged, check whether it **engaged**:
  failure duration against its backoff schedule, repeated attempts in the logs,
  and whether the error text reaches the matcher it relies on. State why the
  earlier mitigation did not stop the pattern. Read the PR that introduced a
  failing guard or cleanup job and its original goal before proposing to patch
  or disable it.
- **Is it already solved?** Recompute the same pattern over a window starting at
  the merge time. Report completed post-merge runs, the occurrence count
  (explicit zero when zero), and the expected count at the pre-fix rate. Zero on
  a low-volume pattern proves nothing. Judge on settled bins, with a control
  (another region or the periodic healthcheck) and full error strings, never raw
  success rate alone.
- **Mitigation effectiveness:** look for a positive signal tied to the change
  (absence of errors proves nothing if nothing used the artifact), the same
  metric before and after with the merge as cutoff, and a baseline over all runs
  (successes and failures).
- **Region test:** use another region only as a controlled experiment.

## Step 5: Escalate platform-level errors

Escalate when evidence shows a persistent, intermittent failure in a specific
Azure resource provider or platform path and code-level mitigations are
exhausted. When several regions fail the same ARM step in the same window, prepare
the outage-search request early and keep it separate from any root-cause claim.

Prepare, as facts only:

1. Context and expected versus observed behavior.
2. Failure inventory: timestamps, subscription and resource IDs, correlation IDs,
   duration, job URLs, and exact terminal errors and commands.
3. Consistent and varying attributes.
4. Failed and successful comparison pairs.
5. Kusto queries and Prow links that remain available after teardown.
6. Impact in the owner's units, and one specific ask.

Environments outside DEV Kusto (INT, Red Hat tenant logs) are unreachable. Write
a self-contained hand-off request (environment, region, cluster, job, UTC window,
exact queries, report format) and make no conclusion about them until the reply.
Never assume an ephemeral resource can be inspected later.

## Step 6: Propose solutions

Propose; do not apply. Skip this step if the evidence is insufficient: say what
evidence is missing instead.

- **Fix at the layer that owns the defect.** If the current layer cannot express
  the needed behavior, fix the layer that can, instead of adding retry entries
  or longer waits. Check the tooling can actually perform the operation. Fix
  error text where it is produced, and never alter an error that `automatedRetry`
  matches on.
- **Fix the whole class within that layer**, with a stated selection rule, not
  only the instances in the latest runs. Do not promise to eliminate platform-side failures.
- **Never fix by suppressing the signal.** An allowlist or exemption needs
  evidence that the condition is benign. Compute the blast radius of any guard.
- **Reuse in-repo primitives** (templatize packages, `hack/ci/`, existing
  backoff and SDK clients) before writing new ones. No hand-rolled retry loops.
- **Persistent environments stay unchanged.** New behavior for INT/STG/PROD
  must be opt-in and DEV-only, with a default that changes nothing.
- **Add a retry only when** the mechanism is established, no structural fix is
  already pending on that path, and the failure keeps recurring. Match the exact
  error substring, never broad codes, and confirm it reaches the matcher in
  `run.go`. A retry is not a fix for a write race on a shared resource; change
  which pipeline owns the write.
- **A moved failing read is not a fix.** Verify against a failed resource and
  separate mocked from live evidence.
- **Enumerate consumers** before changing a shared script, lease contract, or
  lifecycle: every job and environment that uses it, and any copies of the script.
- **Verify mechanically what you claim**, for example by compiling the Bicep,
  diffing rendered output, or running the check. For Bicep, parameter, values, or
  pipeline changes use the `check-ev2-render` skill.

## Step 7: Output

Structure findings as:

- **Opening** — what the failing step does and where it sits in `dependsOn`.
- **Observed root cause/classification** — evidence only.
- **Evidence** — exact snippets, queries, artifacts, comparison tables, and the
  `origin/main` SHA read.
- **Unknowns** — what the evidence cannot establish, and **what you did not examine**.
- **Scope** — frequency, affected components, regions, effective coverage window.
- **Proposed solutions** — immediate mitigation, diagnostics, durable fix, with the
  alternatives you rejected.
- **Effort versus impact** — quick wins, without overstating certainty.
- **Post-fix result** — recurrence after merge, when data is available.
- **New failure-mode candidates** — any mode that matched nothing in
  failure-modes.md: signature, evidence, how it was separated, and the query that
  finds it again.
