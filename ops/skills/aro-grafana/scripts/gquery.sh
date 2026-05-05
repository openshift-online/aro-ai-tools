#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage: query.sh -GrafanaUrl <url> -QueryJson <json>
Example: query.sh -GrafanaUrl https://my-grafana.region.grafana.azure.com -QueryJson '{"queries":[...],"from":"now-1h","to":"now"}'
EOF
    exit 1
}

GRAFANA_URL=""
QUERY_JSON=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -GrafanaUrl) GRAFANA_URL="${2%/}"; shift 2 ;;
        -QueryJson)  QUERY_JSON="$2";      shift 2 ;;
        *) echo "Unknown argument: $1" >&2; usage ;;
    esac
done

if [[ -z "$GRAFANA_URL" ]]; then
    echo "Error: -GrafanaUrl is required" >&2; usage
fi
if [[ -z "$QUERY_JSON" ]]; then
    echo "Error: -QueryJson is required" >&2; usage
fi

GRAFANA_APP_ID="ce34e7e5-485f-4d76-964f-b3d2b16d1e4f"

TOKEN=$(az account get-access-token --resource "$GRAFANA_APP_ID" --query accessToken -o tsv 2>/dev/null)

if [[ -z "$TOKEN" ]]; then
    echo "Error: Could not get access token. Are you logged in to Azure?" >&2
    exit 1
fi

curl -sS --fail-with-body \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$QUERY_JSON" \
    "$GRAFANA_URL/api/ds/query"
