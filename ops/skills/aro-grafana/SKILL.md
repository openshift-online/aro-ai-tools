---
name: aro-grafana
description: Explore datasources and run PromQL queries against ARO (HCP and classic) Grafana instances — discover datasource UIDs and available metrics, then query resource utilization, request latency, error rates, cluster health, tenant utilization, and more. Use `aro-hcp-env-info` first to get the Grafana URL.
allowed-tools: shell
---

When invoked, discover datasources and metrics in, or execute queries against, an ARO Grafana instance.

## Arguments

- **grafana-url** (required): The base URL of the Grafana instance (e.g. `https://my-grafana.region.grafana.azure.com`). Use the `aro-hcp-env-info` skill to discover the Grafana URL for a given environment if not already known.
- **query-json** (required for queries): A JSON string containing the full query body to send. The structure depends on the datasource type. See Query JSON example below.

## Instructions

### Listing datasources

Use this to discover datasource UIDs needed for queries.

1. Determine the Grafana endpoint URL from context or by asking the user.
2. Detect the operating system and run the appropriate script:
   - On **macOS**: run `scripts/list-datasources.sh -GrafanaUrl "<grafana-url>"` using `zsh`.
   - On **Linux/WSL2**: run `scripts/list-datasources.sh -GrafanaUrl "<grafana-url>"` using `bash`.
   - On **Windows (non-WSL)**: run `scripts/list-datasources.ps1 -GrafanaUrl "<grafana-url>"` using `pwsh`.
3. Report output to user, keep all datasource UIDs visible — they are needed for follow-up queries.
   - If there are prometheus datasources named like: hcps-ln, hcps-cdm, services-by, services-chn (two or three characters after '-'), report them as obsolete and not to be used.

### Listing metrics

Use this to discover what metrics exist for a datasource before building queries.

1. Determine the Grafana endpoint URL and datasource UID from context or by asking the user.
   - If the datasource UID is not known, list datasources first (see above).
2. Detect the operating system and run the appropriate script:
   - On **macOS**: run `scripts/list-metrics.sh -GrafanaUrl "<grafana-url>" -DatasourceUid "<datasource-uid>"` using `zsh`.
   - On **Linux/WSL2**: run `scripts/list-metrics.sh -GrafanaUrl "<grafana-url>" -DatasourceUid "<datasource-uid>"` using `bash`.
   - On **Windows (non-WSL)**: run `scripts/list-metrics.ps1 -GrafanaUrl "<grafana-url>" -DatasourceUid "<datasource-uid>"` using `pwsh`.

### Running queries

1. Determine the Grafana endpoint URL and query from context or by asking the user.
   - If the Grafana URL is not known, use `aro-hcp-env-info` skill.
   - If `DATASOURCE_UID` (`uid`) is not known, list datasources first (see above).
   - If metrics to query aren't known, list metrics first — it's more efficient than a raw query.
2. Build the query JSON appropriate for the datasource type.
3. Detect the operating system and run the appropriate script:
   - On **macOS**: run `scripts/gquery.sh -GrafanaUrl "<grafana-url>" -QueryJson '<query-json>'` using `zsh`.
   - On **Linux/WSL2**: run `scripts/gquery.sh -GrafanaUrl "<grafana-url>" -QueryJson '<query-json>'` using `bash`.
   - On **Windows (non-WSL)**: run `scripts/gquery.ps1 -GrafanaUrl "<grafana-url>" -QueryJson '<query-json>'` using `pwsh`.

## Query JSON example

**Prometheus / Thanos:**
```json
{"queries":[{"refId":"A","datasource":{"uid":"DATASOURCE_UID","type":"prometheus"},"expr":"up","instant":true}],"from":"now-1h","to":"now"}
```
