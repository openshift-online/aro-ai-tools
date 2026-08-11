# Provision Failure Analysis — Reference

## DEV pipeline structure

The `e2e-parallel` job provisions two AKS clusters per run:

- **SVC cluster** — Resource Provider, Cluster Service, and Maestro server.
- **MGMT cluster** — HyperShift operator, ACM, Maestro agent, and managed-cluster
  components.

Primary pipeline files:

- `dev-infrastructure/svc-pipeline.yaml`
- `dev-infrastructure/mgmt-pipeline.yaml`

Use each step's `dependsOn` entries to reconstruct execution order and determine
what should already exist when the failure occurs.

## Templatize execution and retries

The runner is under `tooling/templatize/`; retry and timeout behavior is in
`tooling/templatize/pkg/pipeline/run.go`.

Key behaviors:

- A step's timeout context is created once and shared across all executions.
- `errorContainsAny` performs substring matching on the final error.
- `maximumRetryCount` is total executions, including the initial execution.
- Retry delays consume the same wall-clock budget.
- The executor invokes the complete step again. Whether that recreates an external
  resource depends on the step implementation and its cleanup path.

For a Shell step, inspect both success and failure cleanup. A script can delete an
ephemeral resource before returning an error, causing the next execution to create
a fresh resource. If deletion is best-effort, record the possible collision race.

## CIHealth and provision artifacts

Use the `cihealth-api` skill for response schemas and URL construction.

The Prow `view/gs` job page is not the artifact base URL. Convert its prefix:

```text
https://prow.ci.openshift.org/view/gs/
```

to:

```text
https://storage.googleapis.com/
```

The provision gather log is:

```text
<storage-job-url>/artifacts/e2e-parallel/aro-hcp-gather-provision-failure/build-log.txt
```

The gather log normally contains resource groups, ARM deployments, failed
operations, correlation IDs, durations, and status details. Shell and Helm failure
evidence may instead be present only in the CIHealth occurrence or other Prow
artifacts.

## Evidence preservation

DEV environments are ephemeral. After teardown, durable evidence is limited to:

- data exported to Kusto before teardown;
- Prow artifacts produced by pre-teardown job steps.

Environment-local metrics disappear during teardown and are not a preservation
mechanism unless exported to durable storage first.

When diagnostics are missing, extend the gather flow before teardown. Useful,
non-secret data includes exact stderr, timestamps, resource IDs and events,
correlation IDs, retry timing, resolver configuration, routes, Kubernetes events,
and relevant container logs.

## AKS cluster naming

DEV CI clusters:

```text
ci01-j<last7digits_of_prow_job_id>-svc
ci01-j<last7digits_of_prow_job_id>-mgmt-1
```

Resource groups use `hcp-underlay-<cluster-name>`.

## Kusto tables

All tables are in database `ServiceLogs` on
`https://hcp-dev-us-2.eastus2.kusto.windows.net`.

| Table | Evidence | Common columns |
|---|---|---|
| `kubernetesEvents` | Kubernetes warnings and state changes | `cluster`, `reason`, `message`, `eventNamespace`, `objectName` |
| `containerLogs` | Workload stdout/stderr | `cluster`, `namespace_name`, `pod_name`, `container_name`, `log` |
| `kubeAudit` | API server requests and responses | `resourceId`, `verb`, `requestURI`, `responseStatus` |
| `systemdLogs` | Node services such as kubelet/containerd | `hostname`, `systemd_unit`, `message` |
| `aksEvents` | AKS control-plane events | `resourceId`, `category`, `operationName` |

Always constrain queries by timestamp and cluster/resource ID.

## Common queries

### Warning-event timeline

```kql
kubernetesEvents
| where timestamp between (datetime(<start>) .. datetime(<end>))
| where cluster == "<cluster-name>"
| where kubeEventType == "Warning"
| project timestamp, reason, message, eventNamespace, objectName
| order by timestamp asc
```

### Cross-cluster scope

```kql
kubernetesEvents
| where timestamp between (datetime(<start>) .. datetime(<end>))
| where cluster has "ci01"
| where reason == "<reason>"
| summarize affected_events=count() by cluster
| order by affected_events desc
```

Compare failed runs with successful runs in the same period before attributing an
event pattern to the provision failure.
