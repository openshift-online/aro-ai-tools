#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
kquery.sh — Run arbitrary KQL queries against Kusto

USAGE:
    kquery.sh -Cluster <url> -Database <name> -Kql <kql_string> [options]

REQUIRED:
    -Cluster <url>              Kusto cluster URL
                                  e.g. https://mycluster.region.kusto.windows.net
    -Database <name>            Database name
    -Kql <kql_string>           KQL query or control command

OPTIONS:
    -MaxRecords <int>           Row limit (default: 1000, 0 = unlimited)

EXAMPLES:
    kquery.sh -Cluster https://mycluster.region.kusto.windows.net -Database mydb -Kql "MyTable | take 10"
    kquery.sh -Cluster https://mycluster.region.kusto.windows.net -Database mydb -Kql "MyTable | summarize count() by col" -MaxRecords 0
EOF
    exit 1
}

CLUSTER=""
DATABASE=""
KQL=""
MAX_RECORDS=1000

while [[ $# -gt 0 ]]; do
    case "$1" in
        -Cluster)    CLUSTER="${2%/}"; shift 2 ;;
        -Database)   DATABASE="$2";   shift 2 ;;
        -Kql)        KQL="$2";        shift 2 ;;
        -MaxRecords) MAX_RECORDS="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; usage ;;
    esac
done

if [[ -z "$CLUSTER" || -z "$DATABASE" || -z "$KQL" ]]; then
    usage
fi

TOKEN=$(az account get-access-token --resource "$CLUSTER" --query accessToken -o tsv 2>/dev/null)

if [[ -z "$TOKEN" ]]; then
    echo "Error: Could not get access token. Are you logged in to Azure?" >&2
    exit 1
fi

BODY=$(jq -n --arg db "$DATABASE" --arg kql "$KQL" --argjson max "$MAX_RECORDS" \
    '{db: $db, csl: $kql, properties: {Options: {truncationmaxrecords: $max}}}')

# Control commands (starting with '.') use v1/rest/mgmt; queries use v2/rest/query
if [[ "$KQL" =~ ^[[:space:]]*\. ]]; then
    URI="$CLUSTER/v1/rest/mgmt"
else
    URI="$CLUSTER/v2/rest/query"
fi

curl -sS --fail-with-body \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$BODY" \
    "$URI"
