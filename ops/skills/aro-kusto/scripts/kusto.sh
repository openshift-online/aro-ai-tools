#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
kusto.sh — Kusto cluster metadata (list databases, tables, schemas)

USAGE:
    kusto.sh <subcommand> -Cluster <url> [-Database <name>] [options]

SUBCOMMANDS:
    list-databases              List all databases on the cluster
                                  Required: -Cluster
    show-tables                 List all tables in a database
                                  Required: -Cluster, -Database
    show-schema                 Show schema for a single table (as JSON)
                                  Required: -Cluster, -Database, -Table
    show-schema-all             Show full database schema (as JSON)
                                  Required: -Cluster, -Database

GLOBAL OPTIONS:
    -Cluster <url>              Kusto cluster URL (required)
                                  e.g. https://mycluster.region.kusto.windows.net
    -Database <name>            Database name (required except for list-databases)
    -Table <name>               Table name (required for show-schema)
    -MaxRecords <int>           Row limit (default: 1000, 0 = unlimited)

EXAMPLES:
    kusto.sh list-databases -Cluster https://mycluster.region.kusto.windows.net
    kusto.sh show-tables -Cluster https://mycluster.region.kusto.windows.net -Database mydb
    kusto.sh show-schema -Cluster https://mycluster.region.kusto.windows.net -Database mydb -Table mytable
    kusto.sh show-schema-all -Cluster https://mycluster.region.kusto.windows.net -Database mydb
EOF
    exit 1
}

SUBCOMMAND="${1:-}"
shift || true

CLUSTER=""
DATABASE=""
TABLE=""
MAX_RECORDS=1000

while [[ $# -gt 0 ]]; do
    case "$1" in
        -Cluster)    CLUSTER="${2%/}"; shift 2 ;;
        -Database)   DATABASE="$2";   shift 2 ;;
        -Table)      TABLE="$2";      shift 2 ;;
        -MaxRecords) MAX_RECORDS="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; usage ;;
    esac
done

case "$SUBCOMMAND" in
    list-databases|show-tables|show-schema|show-schema-all) ;;
    *) echo "Error: Unknown subcommand '${SUBCOMMAND:-}'. Valid: list-databases, show-tables, show-schema, show-schema-all" >&2; usage ;;
esac

if [[ -z "$CLUSTER" ]]; then
    echo "Error: -Cluster is required" >&2; usage
fi

if [[ "$SUBCOMMAND" != "list-databases" && -z "$DATABASE" ]]; then
    echo "Error: -Database is required for subcommand '$SUBCOMMAND'" >&2; usage
fi

if [[ "$SUBCOMMAND" == "show-schema" && -z "$TABLE" ]]; then
    echo "Error: -Table is required for subcommand 'show-schema'" >&2; usage
fi

TOKEN=$(az account get-access-token --resource "$CLUSTER" --query accessToken -o tsv 2>/dev/null)
if [[ -z "$TOKEN" ]]; then
    echo "Error: Failed to get access token for cluster $CLUSTER" >&2
    exit 1
fi

kusto_query() {
    local db="$1" kql="$2"
    local body
    body=$(jq -n --arg db "$db" --arg kql "$kql" --argjson max "$MAX_RECORDS" \
        '{db: $db, csl: $kql, properties: {Options: {truncationmaxrecords: $max}}}')
    curl -sS --fail-with-body \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "$body" \
        "$CLUSTER/v1/rest/mgmt"
}

DB="${DATABASE:-NetDefaultDB}"

case "$SUBCOMMAND" in
    list-databases) kusto_query "$DB"       ".show databases" ;;
    show-tables)    kusto_query "$DATABASE" ".show tables" ;;
    show-schema)    kusto_query "$DATABASE" ".show table [$TABLE] schema as json" ;;
    show-schema-all) kusto_query "$DATABASE" ".show database schema as json" ;;
esac
