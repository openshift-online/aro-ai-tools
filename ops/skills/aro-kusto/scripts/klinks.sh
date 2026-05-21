#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
klinks.sh — Generate an Azure Data Explorer (ADX) web link for a KQL query

USAGE:
    klinks.sh -Cluster <url> -Database <name> -Kql <kql_string>

REQUIRED:
    -Cluster <url>     Kusto cluster URL
                         e.g. https://mycluster.region.kusto.windows.net
    -Database <name>   Database name
    -Kql <kql_string>  KQL query

EXAMPLES:
    klinks.sh -Cluster https://mycluster.region.kusto.windows.net -Database mydb -Kql "MyTable | take 10"
EOF
    exit 1
}

CLUSTER=""
DATABASE=""
KQL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -Cluster)  CLUSTER="${2%/}"; shift 2 ;;
        -Database) DATABASE="$2";    shift 2 ;;
        -Kql)      KQL="$2";         shift 2 ;;
        *) echo "Unknown argument: $1" >&2; usage ;;
    esac
done

if [[ -z "$CLUSTER" || -z "$DATABASE" || -z "$KQL" ]]; then
    usage
fi

# Extract host (strip scheme) and the <name>.<region> portion (strip .kusto.windows.net)
HOST="${CLUSTER#http://}"
HOST="${HOST#https://}"
CLUSTER_PATH="${HOST%.kusto.windows.net}"

urlencode() {
    local s="$1" i c out=""
    for (( i=0; i<${#s}; i++ )); do
        c="${s:i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]) out+="$c" ;;
            *) out+=$(printf '%%%02X' "'$c") ;;
        esac
    done
    printf '%s' "$out"
}

ENCODED_QUERY=$(printf '%s' "$KQL" | gzip -c | base64 -w0)
ENCODED_QUERY=$(urlencode "$ENCODED_QUERY")

ADX_URL="https://dataexplorer.azure.com/clusters/${CLUSTER_PATH}/databases/${DATABASE}?query=${ENCODED_QUERY}"

echo "ADX: ${ADX_URL}"
