---
name: cihealth-api
description: Query CIHealth REST API to retrieve CI failure history, failure patterns, and run data for ARO-HCP. Use when investigating CI failures, triaging provision or e2e issues, or reviewing failure trends.
---

# CIHealth API

CIHealth tracks ARO-HCP CI job outcomes, groups failures by pattern, and provides
historical data.

## Base URL

`https://cihealth.tools.hcpsvc.osadev.cloud`

Use `curl` from the shell. Responses are JSON. Fail on HTTP errors and use bounded
retries because the API can return transient 5xx responses:

```bash
curl -fsS --retry 3 --retry-delay 2 "<url>"
```

Avoid large uncontrolled parallel request bursts.

## Response shape

Both endpoints below return:

```json
{
  "meta": {},
  "environments": [
    {
      "environment": "dev"
    }
  ]
}
```

`environments` is a list, not an object keyed by environment name.

### Failure patterns in a date window

```text
GET /api/failure-patterns/window?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD
```

Each environment contains a `rows` list. Rows include the normalized failure
pattern, occurrence and affected-run counts, trend data, error samples, and
`affected_runs`.

Use this endpoint to identify active patterns, compare frequency over time, and
collect affected run URLs. Count distinct run URLs when combining patterns because
one run can match more than one pattern.

The window and timestamps are UTC unless the response metadata says otherwise.

### Run log for a single day

```text
GET /api/run-log/day?date=YYYY-MM-DD
```

Each environment contains a `runs` list. A run includes the Prow run metadata,
failure stages, occurrences, and matched failure-pattern summary.

`failed_at` is a list. Filter provision failures using membership, not scalar
equality:

```python
dev = next(e for e in data["environments"] if e["environment"] == "dev")
provision_runs = [
    run for run in dev["runs"]
    if "provision" in (run.get("failed_at") or [])
]
```

Within a run, filter `occurrences` by their scalar `failed_at` value when only one
stage is relevant.

## Mapping Prow Job IDs to AKS Cluster Names

DEV `e2e-parallel` jobs provision on-demand AKS clusters. The cluster name is
derived from the Prow job ID:

- Take the last 7 digits of the Prow job ID.
- Cluster names are `ci01-j<last7digits>-svc` and
  `ci01-j<last7digits>-mgmt-1`.

Example: Prow job ID `2062209290243936256` maps to
`ci01-j3936256-svc` and `ci01-j3936256-mgmt-1`.

## Prow Artifacts

The Prow job page uses a `view/gs` URL:

```text
https://prow.ci.openshift.org/view/gs/test-platform-results/pr-logs/pull/<org>_<repo>/<pr_number>/<job_name>/<job_id>
```

Prefer the `run_url` supplied by CIHealth instead of constructing this path. Batch
jobs and other job types can use a different segment after `pull/`.

Do not append artifact paths to the Prow URL: it can return a login HTML page
instead of the artifact. Convert the prefix to the public Google Cloud Storage
endpoint while preserving the remainder of the CIHealth URL:

```text
https://storage.googleapis.com/test-platform-results/pr-logs/pull/<org>_<repo>/<pr_number>/<job_name>/<job_id>
```

The provision failure build log is:

```text
<storage-job-url>/artifacts/e2e-parallel/aro-hcp-gather-provision-failure/build-log.txt
```

Example conversion:

```python
storage_url = run_url.replace(
    "https://prow.ci.openshift.org/view/gs/",
    "https://storage.googleapis.com/",
)
build_log_url = (
    storage_url
    + "/artifacts/e2e-parallel/"
      "aro-hcp-gather-provision-failure/build-log.txt"
)
```

Download with `curl -fsS` and confirm the response is the expected text artifact,
not HTML or an API error body.
