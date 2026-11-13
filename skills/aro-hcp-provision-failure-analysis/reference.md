# Provision Failure Analysis — Reference

Commands, URLs, and system facts. Facts here are perishable: when one disagrees
with what you observe, trust the observation and say so in the report.

## 1. Collecting failure patterns

Read pre-computed failure patterns straight from Kusto (`ServiceLogs`); no CLI
is needed. Tables:

- `ciJobOutcomes`: one row per Prow run (`buildId, jobName, prowUrl, family,
  overallResult, failed, startedAt, finishedAt, svcCluster, mgmtCluster,
  runtimeRegion, ...`).
- `ciTestResults`: per-test outcomes joined on `buildId`. `source` is `e2e`,
  `observability`, `rp-provision`, or `rp-upgrade`. `rp-*` rows are one test per
  pipeline step, passed steps included, with step execution times. `message`
  holds the raw step log.
- `ciFailurePatterns`: one row per extracted result, with `findings` (a dynamic
  array: `key, canonical, outcome, rule_id, quality_reasons, locations`). It
  stores no raw text; join it to `ciTestResults` for `message` and timings.

Confirm columns with `| getschema`; re-confirm what is below when it matters.

`rp-provision` is the RP deployed from main code (in `e2e-parallel` and
`e2e-parallel-inplace-upgrade`). `rp-upgrade` is the RP upgraded from main to the
PR code (only in `e2e-parallel-inplace-upgrade`). Both are in the queries below.

**Check the extractor version first.** Patterns are valid only per
`(extractorVersion, resultSchemaVersion)`. Pin the version you use and record it
in the findings:

```kql
ciFailurePatterns
| summarize rows=count(), builds=dcount(buildId), firstComputed=min(computedAt), lastComputed=max(computedAt)
  by extractorVersion, resultSchemaVersion, source
```

Rows with an empty `source` are an older backfill; do not guess them into one.
Recomputation can leave several rows per `resultKey`; keep the latest.

**Shared prefix** (used by the queries below; `fp-1` was current on 2026-11-13):

```kql
let selectedExtractorVersion = "fp-1";
let selectedSchemaVersion = 1;
let windowStart = ago(7d);
let windowEnd = now() - 5m;     // Kusto lags ingestion: do not judge a window that ends now
let failed = ciTestResults
    | where failed and source in ("rp-provision", "rp-upgrade")
    | extend messageHash = hash_sha256(message);
let patternRows = ciFailurePatterns
    | where extractorVersion == selectedExtractorVersion and resultSchemaVersion == selectedSchemaVersion
    | summarize arg_max(computedAt, *) by resultKey
    | mv-expand finding = findings
    | extend key = tostring(finding.key), canonical = tostring(finding.canonical), outcome = tostring(finding.outcome)
    | join kind=inner failed on buildId, source, testId, messageHash
    | join kind=inner (ciJobOutcomes | project buildId, jobName, prowUrl, jobFinished = finishedAt) on buildId
    | where jobFinished between (windowStart .. windowEnd);
```

`key` is not unique across sources: always match on `source` and `key`. A run
can have several failing observations, so count runs with `dcount(buildId)` and
occurrences with `count()`. A `fallback` outcome means no specific rule matched
(a coarse key); treat it as weaker grouping.

**Top patterns with first/last seen** (append to the prefix):

```kql
patternRows
| summarize runs = dcount(buildId), inputs = count(), firstSeen = min(jobFinished), lastSeen = max(jobFinished),
            sampleBuilds = make_set(buildId, 3), canonical = take_any(canonical), outcomes = make_set(outcome)
    by source, key
| order by runs desc, inputs desc
| take 10
```

**Occurrences of one pattern** (append to the prefix):

```kql
patternRows
| where source == "<source>" and key == "<key>"
| project buildId, jobName, jobFinished, prowUrl, testName, message = substring(message, 0, 300)
| order by jobFinished desc
```

**Failed runs without an `rp-provision` or `rp-upgrade` observation (coverage gap):**

```kql
let rp = ciTestResults | where source in ("rp-provision", "rp-upgrade") | distinct buildId;
ciJobOutcomes
| where finishedAt between (ago(7d) .. now() - 5m) and jobName has "e2e-parallel" and failed
| join kind=leftanti rp on buildId
| project buildId, jobName, finishedAt, prowUrl
```

On 2026-11-13, 47 of 175 failed `pull-ci-...-e2e-parallel` runs in the 7-day
window had no `rp-*` observation. They are not in any pattern count; look at
them separately.

**Effective coverage start per source:**
`ciTestResults | where source in ("rp-provision","rp-upgrade") | summarize coverageStart = min(startedAt) by source`.
Collection is forward-only from its rollout (about 2026-11-03); earlier runs have
no `rp-*` rows.

**Post-merge recompute:** rerun the pattern query with `windowStart` set to the
merge time (UTC), and count completed and failed runs after it:

```kql
ciJobOutcomes
| where finishedAt between (datetime(<merge time UTC>) .. now() - 5m) and jobName has "e2e-parallel"
| summarize completed = count(), failed = countif(failed)
```

Expected post-merge count = (pattern runs ÷ completed runs before the fix) ×
completed runs after it.

**Per-run drill-down:** `ciTestResults | where buildId == "<id>" and source in
("rp-provision","rp-upgrade") | project testId, result, failed, startedAt,
finishedAt, message` gives step outcomes, step times, and the raw log. For other
evidence use the Prow artifacts (section 4).

Other `ciTestResults`/`ciJobOutcomes` columns and joins: confirm with `| getschema`.

## 2. Clusters for a run

```kql
ciJobOutcomes
| where buildId == "<prow build id>"
| project buildId, jobName, svcCluster, mgmtCluster, startedAt, finishedAt
```

- Names are stored verbatim from the run's own `config.yaml`; no parsing needed.
- Only some runs carry names. On 2026-11-13, 293 of 320 `pull-ci-...-e2e-parallel`
  runs in the 7-day window had them (like `ci01-j4374016-svc` and
  `ci01-j4374016-mgmt-1`: `j` plus the last 7 digits of the build ID), but none
  of the 246 `e2e-parallel-inplace-upgrade` runs did. Runs against a promoted
  environment also leave both columns empty. For an empty run no name is
  recorded; a `kubernetesEvents` search by the build-ID convention found nothing
  for two such runs, so do not assume their telemetry exists.
- `mgmtCluster` shows stamp 1. `e2e-parallel` also has a `-mgmt-2` cluster in
  `kubernetesEvents` under the same prefix; confirm before use.
- Resource groups: `hcp-underlay-<cluster-name>` (confirm on a real run).

## 3. DEV pipeline structure

`e2e-parallel` provisions two AKS clusters per run:

- **SVC cluster** — Resource Provider, Cluster Service, and Maestro server.
- **MGMT cluster** — HyperShift operator, ACM, Maestro agent, and managed-cluster components.

Pipeline files: `dev-infrastructure/svc-pipeline.yaml` and `dev-infrastructure/mgmt-pipeline.yaml`.
Reconstruct execution order from each step's `dependsOn`.

### Templatize execution and retries

Runner: `tooling/templatize/`; retry and timeout logic in `tooling/templatize/pkg/pipeline/run.go`.

- The step timeout context is created once and shared by all executions and delays
  (default step context timeout 30 min; Helm default and per-step `timeout:` also apply:
  `defaultHelmTimeout` in `pkg/pipeline/helm.go`, `defaultStepContextTimeout`).
- `errorContainsAny` matches substrings of the final error.
- `maximumRetryCount` counts total executions including the first.
- Delays consume the same budget. No sleep follows the last execution.
- A retry re-runs the whole step. Whether it recreates an external resource depends on the step's own cleanup.
- A CLI `--timeout` or env timeout set on a step must stay strictly below the step timeout.
- Vendor `MaxRetryCountReached` is the platform's own retry, not the pipeline's.
- Templatize may skip an ARM step when its input hashes are unchanged (main vs PR
  can differ). A CI script that mutates a resource an ARM step also owns can
  therefore be reverted by a later real redeploy.

For Shell steps, inspect both success and failure cleanup. A script can delete an
ephemeral resource before it returns an error, so the next execution starts fresh.
If deletion is best-effort, record the collision race.

### CI environment facts

- In ci-operator, each step runs in its own pod. Do not reuse a value captured in
  another step via `SHARED_DIR`; it is configmap-backed and has no subdirectories.
- Config rendered by Prow is an artifact of the run. Diff it against your local
  rendering before treating a reproduction as faithful.
- In EV2 resolve mode, config-referenced values become non-empty placeholder
  strings, so branching on them in `.bicepparam`, `values.yaml`, or pipeline YAML
  misbehaves. Config knobs transported to Bicep must be simple scalars.
- Shared scripts may exist as two copies (`hack/ci` and the openshift/release
  step registry). Diff them before concluding two jobs ran the same code.
- DEV has the highest CI concurrency; ARM throttling is a known constraint, and
  settings such as a single cleanup worker may be deliberate.
- ARM throttling limits as recorded in earlier work (confirm against current
  Microsoft documentation before relying on them): reads bucket 250 at 25/s,
  writes and deletes bucket 200 at 10/s, per subscription and per principal.
- A 404 returned as `resp, nil` by an SDK transport never triggers an error-based
  retry policy.

## 4. Prow artifacts

The Prow `view/gs` page is not the artifact base URL. Replace

```text
https://prow.ci.openshift.org/view/gs/
```

with

```text
https://storage.googleapis.com/
```

Provision gather log:

```text
<storage-job-url>/artifacts/e2e-parallel/aro-hcp-gather-provision-failure/build-log.txt
```

Also useful: `<storage-job-url>/build-log.txt`, `started.json`, `finished.json`, and
`prowjob.json` (`spec.refs.pulls[]` gives PR number and SHA). Fetch with
`curl -fsS --retry 3 --retry-delay 2`, bounded concurrency, and check HTTP status.
A missing file is a finding, not an error to skip.

The gather log normally contains resource groups, ARM deployments, failed operations,
correlation IDs, durations, and statuses. Shell and Helm evidence may exist only in
the failing step's `build-log.txt` or the observation text.

For batch analysis keep working files under `zz-ignore/provision-failures/<pattern-name>/`.

## 5. Kusto

Cluster `https://hcp-dev-us-2.eastus2.kusto.windows.net`, database `ServiceLogs`.
Always constrain by time and cluster or resource ID. Run `| getschema` before
relying on a column.

| Table | Evidence | Common columns |
|---|---|---|
| `kubernetesEvents` | Kubernetes events | `cluster`, `reason`, `message`, `eventNamespace`, `objectKind`, `objectName`, `objectUID`, `firstSeen`, `lastSeen`, `count` |
| `containerLogs` | Workload stdout/stderr | `cluster`, `namespace_name`, `pod_name`, `container_name`, `log` |
| `kubeAudit` | API server requests and responses | `resourceId`, `verb`, `requestURI`, `responseStatus` |
| `systemdLogs` | Node services such as kubelet/containerd | `hostname`, `systemd_unit`, `message` |
| `aksEvents` | AKS control-plane events | `resourceId`, `category`, `operationName` |
| `ciJobOutcomes`, `ciTestResults` | CI run and test outcomes | see section 1 |

### Telemetry pitfalls

- `kubernetesEvents.kubeEventType` was empty on every DEV `ci01-*` row checked on
  2026-11-13 (34M rows in 2 days): do not filter on `kubeEventType == "Warning"`;
  filter on `reason`, `eventNamespace`, or `message`. There is no event-UID
  column. Occurrence time is `firstSeen`/`lastSeen` with `count`; the ingestion
  `timestamp` is not when it happened. One event is re-emitted with a growing
  `count`; a working dedupe key is `cluster, objectUID, reason, firstSeen`:
  `summarize arg_max(timestamp, *) by cluster, objectUID, reason, firstSeen`.
- Sanity-check any count against what Kubernetes could produce.
- Start a budget interval at the earliest moment the clock can start (the creation
  request). Report P50/P90/P95/P99/max, split affected against unaffected.
- Kusto lags ingestion by minutes: do not judge a window that ends now.
- Publish the corrected final query, not the first draft.
- The Sippy jobs endpoint, if used for job volume, omits aborted runs.

### Queries

Event timeline for one cluster (deduplicated; add a `reason` or `message` filter
to select warnings):

```kql
kubernetesEvents
| where timestamp between (datetime(<start>) .. datetime(<end>))
| where cluster == "<cluster-name>"
| summarize arg_max(timestamp, *) by cluster, objectUID, reason, firstSeen
| project firstSeen, lastSeen, count, reason, message, eventNamespace, objectName
| order by firstSeen asc
```

Workload errors in one namespace:

```kql
containerLogs
| where timestamp between (datetime(<start>) .. datetime(<end>))
| where cluster == "<cluster-name>" and namespace_name == "<namespace>"
| where log has "error" or log has "fatal" or log has "panic"
| project timestamp, pod_name, container_name, log
| order by timestamp asc
```

Cross-cluster scope (compare with successful runs in the same period before
attributing an event pattern to a failure):

```kql
kubernetesEvents
| where timestamp between (datetime(<start>) .. datetime(<end>))
| where cluster has "ci01" and reason == "<reason>"
| summarize affected_events=count() by cluster
| order by affected_events desc
```

Use `kubeAudit`, `aksEvents`, and `systemdLogs` when the evidence indicates a
cluster-level or node-bootstrap issue.

## 6. Tenants and reach

- DEV Kusto (`hcp-dev-us-2`) is reachable. INT (MSIT tenant) and Red Hat tenant
  Entra/ARM logs are not. Hand-off requests to those tenants must be
  self-contained (environment, region, cluster, job, UTC window, exact queries,
  exclusion of secrets, report format: confidence, identity used, error counts,
  evidence rows).
- Do not add acceptance criteria or monitoring that depend on logs the team cannot query.
- Sdp-pipelines CI, Azure DevOps/EV2 rollout state, and Azure Support cases are
  not reachable from this environment: say so rather than guess.

## 7. Existing-work search (SKILL.md Step 3)

Read-only. Add `ARO-Tools` and `openshift/release` when the failing layer lives
there.

```bash
for R in Azure/ARO-HCP Azure/ARO-Tools openshift/release; do
  gh pr list --repo "$R" --state all --search "<component or error text> in:title,body" --limit 30 \
    --json number,title,state,isDraft,author,updatedAt,mergedAt,headRefName,url
done
gh pr view <n> --repo Azure/ARO-HCP \
  --json title,state,isDraft,body,files,commits,reviews,comments,statusCheckRollup,headRefOid,mergeStateStatus
git -C <worktree> log origin/main --since=<first_seen> --oneline -- <failing script, pipeline, or config paths>
```

- `updatedAt`, `mergeStateStatus`, and the `files` list tell you whether a PR is
  alive and whether it touches the failing path.
- Compare a merged PR's `mergedAt` with each failing run's `finished_at` and the
  SHA that run used (`prowjob.json`).
- Jira (project `AROSLSRE`, component `aro-hcp-ci`): search by error text through
  the Atlassian tools. Read status, assignee, and linked PRs.
