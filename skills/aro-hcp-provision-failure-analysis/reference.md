# Provision Failure Analysis — Reference

Commands, URLs, and system facts. Facts here are perishable: when one disagrees
with what you observe, trust the observation and say so in the report.

## 1. Collecting failure patterns

`hcpctl ci failure-patterns` is introduced by Azure/ARO-HCP#7945. Until it is
merged, build it from a worktree of that PR's branch
(`HCPCTL="go run ./tooling/hcpctl"`). Confirm flags with `--help` first. After
merge, use the released `hcpctl`. Record the CLI version and the report's
`extractor_version` in the findings.

```bash
RUN_DIR="<scratch>/provision-triage-$(date -u +%Y%m%dT%H%M%SZ)"; mkdir -m 700 "$RUN_DIR"
TO=$(date -u -d '-5 min' +%Y-%m-%dT%H:%M:00Z)      # settled window
FROM=$(date -u -d "$TO -7 days" +%Y-%m-%dT%H:%M:00Z)
$HCPCTL ci failure-patterns --kusto hcp-dev-us-2 --region eastus2 --database ServiceLogs \
  --environment dev --source rp-provision --job-filter e2e-parallel \
  --from "$FROM" --to "$TO" --timeout 10m \
  --save-input "$RUN_DIR/bundle.json" > "$RUN_DIR/report.json" 2> "$RUN_DIR/collect.stderr"
```

`--save-input` refuses to overwrite, so use a fresh `RUN_DIR`. Output is JSON.
A saved bundle replays offline with `--input bundle.json`.

- Check that the command exited 0 and that `summary.input_count == (.results|length)`
  and `metadata.window` equals what you requested. A query or partial failure is a
  collection problem: retry once, then report it. Never analyze a partial bundle.
- Report: `patterns[]` (`environment, source, key, canonical, affected_run_count,
  affected_input_count, result_indexes`) ranked by affected runs, and `results[]`
  (`observation`, `findings[]`). `result_indexes` are valid only inside that
  report. `key` is not unique across `(environment, source)`: always match on all three.
- Bundle: `runs[]` (`build_id, job_name, prow_url, finished_at, failed`) and
  `observations[]` (`build_id, source, test_name, text, started_at, finished_at`).

`$REPORT` = `$RUN_DIR/report.json`, `$BUNDLE` = `$RUN_DIR/bundle.json`.

**Top patterns with first/last seen:**

```bash
jq '. as $r | [.patterns[] | select(.environment=="dev" and .source=="rp-provision")] | .[0:5]
  | map(. as $p | [$p.result_indexes[] | $r.results[.].observation] as $o
    | {key:$p.key, canonical:($p.canonical[0:90]), runs:$p.affected_run_count, inputs:$p.affected_input_count,
       first_seen:([$o[].finished_at]|min), last_seen:([$o[].finished_at]|max),
       sample_builds:([$o[].build_id]|unique|.[0:3])})' "$REPORT"
```

**Occurrences of one pattern (index `i`):**

```bash
jq --argjson i 0 '.patterns[$i] as $p | [ $p.result_indexes[] as $x | .results[$x]
  | {build_id:.observation.build_id, test:.observation.test_name, text:(.observation.text[0:300]),
     findings:[.findings[]|select(.key==$p.key)|{rule_id,outcome}]} ]' "$REPORT"
```

**Failed runs without an `rp-provision` observation (coverage gap):**

```bash
jq '(.observations|map(select(.source=="rp-provision").build_id)|unique) as $has
  | [.runs[]|select(.failed and ((.build_id as $b|$has|index($b))==null))|{build_id,job_name,finished_at,prow_url}]' "$BUNDLE"
```

**Effective `rp-provision` coverage start:**
`jq '[.observations[]|select(.source=="rp-provision")|.started_at]|min' "$BUNDLE"`.
The collector writes forward-only from its rollout (about 2026-11-03 10:26 UTC);
older rows have an empty `source` and must not be guessed into one.

**Post-merge recompute:** repeat the collection into a new `RUN_DIR2` with
`--from <merge time UTC>`, then:

```bash
jq --arg k "$KEY" '[.patterns[]|select(.environment=="dev" and .source=="rp-provision" and .key==$k)]
  | if length==0 then {occurrences:0} else {occurrences:.[0].affected_input_count, runs:.[0].affected_run_count} end' "$RUN_DIR2/report.json"
jq '[.runs[]|select(.finished_at>="<cutoff>")]|{completed:length, failed:(map(select(.failed))|length)}' "$RUN_DIR2/bundle.json"
```

Completed post-merge runs come from `runs[]`, not from the pattern. Expected
post-merge count = (pattern runs ÷ completed runs before the fix) × completed
runs after it.

**Per-run drill-down:** `$HCPCTL snapshot from-prow-job --url <prow job url> [--test <substring>]`.
Non-PR (EV2-triggered) jobs also need `--sdp-pipelines-dir <checkout>`. Do not
use `snapshot analyze`; it calls a nested AI provider.

Other CI outcome data is in Kusto (`ServiceLogs`): `ciJobOutcomes` (one row per
Prow run: `buildId, jobName, prowUrl, family, overallResult, failed, startedAt,
finishedAt, svcCluster, mgmtCluster, runtimeRegion, ...`) and `ciTestResults`
(per-test outcomes joined on `buildId`; `source` is `e2e`, `observability`,
`rp-provision`, or `rp-upgrade`; `rp-*` rows are one test per pipeline step,
passed steps included, with step execution times). Confirm columns with
`| getschema`.

## 2. Clusters for a run

```kql
ciJobOutcomes
| where buildId == "<prow build id>"
| project buildId, jobName, svcCluster, mgmtCluster, startedAt, finishedAt
```

- Names are stored verbatim from the run's own `config.yaml`; no parsing needed.
- Only runs that provision their own clusters carry names. Runs against a promoted
  environment leave both columns empty (their telemetry is elsewhere).
- `mgmtCluster` always shows stamp 1. `e2e-parallel` has stamps 1 and 2;
  `e2e-parallel-inplace-upgrade` has only stamp 1. For stamp 2, take the stamp-1
  name's pattern and confirm it exists in `kubernetesEvents` before use.
- Resource groups: `hcp-underlay-<cluster-name>` (from the previous skill version;
  confirm on a real run).

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
| `kubernetesEvents` | Kubernetes warnings and state changes | `cluster`, `reason`, `message`, `eventNamespace`, `objectName`, `kubeEventType` |
| `containerLogs` | Workload stdout/stderr | `cluster`, `namespace_name`, `pod_name`, `container_name`, `log` |
| `kubeAudit` | API server requests and responses | `resourceId`, `verb`, `requestURI`, `responseStatus` |
| `systemdLogs` | Node services such as kubelet/containerd | `hostname`, `systemd_unit`, `message` |
| `aksEvents` | AKS control-plane events | `resourceId`, `category`, `operationName` |
| `ciJobOutcomes`, `ciTestResults` | CI run and test outcomes | see section 1 |

### Telemetry pitfalls

- For `kubernetesEvents`, occurrence time is `firstSeen`/`lastSeen` with `count`;
  the ingestion `timestamp` is not when it happened. Dedupe by event UID:
  `summarize arg_max(timestamp, *) by cluster, eventUID`.
- Sanity-check any count against what Kubernetes could produce.
- Start a budget interval at the earliest moment the clock can start (the creation
  request). Report P50/P90/P95/P99/max, split affected against unaffected.
- Kusto lags ingestion by minutes: do not judge a window that ends now.
- Publish the corrected final query, not the first draft.
- The Sippy jobs endpoint, if used for job volume, omits aborted runs.

### Queries

Warning-event timeline (deduplicated):

```kql
kubernetesEvents
| where timestamp between (datetime(<start>) .. datetime(<end>))
| where cluster == "<cluster-name>" and kubeEventType == "Warning"
| summarize arg_max(timestamp, *) by cluster, eventUID
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
