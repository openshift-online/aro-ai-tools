#!/usr/bin/env bash

PLUGIN_REVISION="20260505-7ab42fa"
CLASSIC_CONFIG_SUBSCRIPTION="Azure Red Hat OpenShift v4.x - Development"
CLASSIC_CONFIG_RG="ai-plugin-cfg"

client="${1:-unknown}"
if [[ $# -gt 0 ]]; then
    shift
fi

discover_databases=false
output_format="text"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --discover-databases)
            discover_databases=true
            shift
            ;;
        --json)
            output_format="json"
            shift
            ;;
        --text)
            output_format="text"
            shift
            ;;
        *)
            echo "Error: unknown argument '$1'" >&2
            exit 1
            ;;
    esac
done

if ! account=$(az account show --subscription "$CLASSIC_CONFIG_SUBSCRIPTION"); then
    echo "Error: Couldn't get current login info for subscription '$CLASSIC_CONFIG_SUBSCRIPTION'. Not logged into Azure or missing access?." >&2
    exit 1
fi
if [[ -z "$account" ]]; then
    echo "Error: Couldn't get current login info for subscription '$CLASSIC_CONFIG_SUBSCRIPTION'. Not logged into Azure or missing access?." >&2
    exit 1
fi
user=$(echo "$account" | jq -r '.user.name')

if ! tags=$(az group show \
    --name "$CLASSIC_CONFIG_RG" \
    --subscription "$CLASSIC_CONFIG_SUBSCRIPTION" \
    --query "tags" \
    --output json); then
    echo "Error: failed to load Classic environment config tags from resource group $CLASSIC_CONFIG_RG in subscription $CLASSIC_CONFIG_SUBSCRIPTION" >&2
    exit 1
fi

classic_environments=$(echo "$tags" | jq '
  [to_entries[] | select(.key | test("^classic-env-[^-]+-[^-]+-.+-cfg$"))] |
  map(
    (.key | capture("^classic-env-(?<cloud>[^-]+)-(?<environment>[^-]+)-(?<slug>.+)-cfg$")) as $meta |
    (.value | fromjson) as $cfg |
    $cfg +
    {
      id: ("classic/" + $meta.cloud + "/" + $meta.environment + "/" + $meta.slug),
      kind: "classic",
      cloud: $meta.cloud,
      environment: $meta.environment,
      sector: $cfg.sector,
      locations: ($cfg.locations // []),
      kusto: (
        if ($cfg.kusto | test("^https?://")) then $cfg.kusto
        else "https://\($cfg.kusto).kusto.windows.net"
        end
      ),
      defaultDatabase: ($cfg.defaultDatabase // "ARORPLogs"),
      source: "classic-config-tags"
    } |
    if .cloud == "fairfax" then
      .databaseSource = (.databaseSource // "assumed-from-public-prod") |
      .authNotes = (.authNotes // [
        "SAW-only access documented",
        "Use Kusto Explorer with FairFax (usgovcloudapi.net) cloud setting and dSTS-Federated security"
      ])
    else . end
  ) | sort_by(.id)')

if [[ "$classic_environments" == "[]" ]]; then
    echo "Error: Classic environment config resource group $CLASSIC_CONFIG_RG in subscription $CLASSIC_CONFIG_SUBSCRIPTION has no classic-env-*-cfg tags." >&2
    exit 1
fi

if [[ "$discover_databases" == "true" ]]; then
    tmp_file=$(mktemp)
    tmp_next="$tmp_file.next"
    trap 'rm -f "$tmp_file" "$tmp_next"' EXIT HUP INT TERM
    echo "$classic_environments" > "$tmp_file"
    count=$(jq 'length' "$tmp_file")
    for ((i = 0; i < count; i++)); do
        kusto=$(jq -r ".[$i].kusto" "$tmp_file")
        if token=$(az account get-access-token --resource "$kusto" --query accessToken -o tsv 2>/dev/null); then
            body='{"db":"NetDefaultDB","csl":".show databases","properties":{"Options":{"truncationmaxrecords":0}}}'
            if response=$(curl -sS --max-time 20 \
                -H "Authorization: Bearer $token" \
                -H "Content-Type: application/json" \
                -d "$body" \
                "$kusto/v1/rest/mgmt"); then
                databases=$(echo "$response" | jq -c '[.Tables[0].Rows[][0]] | unique' 2>/dev/null || echo "[]")
                if [[ "$databases" != "[]" ]]; then
                    if jq ".[$i].databases = $databases | .[$i].databaseSource = \"runtime-discovered\"" "$tmp_file" > "$tmp_next"; then
                        mv "$tmp_next" "$tmp_file"
                    else
                        rm -f "$tmp_next"
                        echo "Error: failed to update database list for $kusto" >&2
                        exit 1
                    fi
                    continue
                fi
            fi
        fi
        if jq ".[$i].warnings = ((.[$i].warnings // []) + [\"Could not refresh database list\"])" "$tmp_file" > "$tmp_next"; then
            mv "$tmp_next" "$tmp_file"
        else
            rm -f "$tmp_next"
            echo "Error: failed to record database refresh warning for $kusto" >&2
            exit 1
        fi
    done
    classic_environments=$(cat "$tmp_file")
    rm -f "$tmp_file" "$tmp_next"
    trap - EXIT HUP INT TERM
fi

environments=$(echo "$classic_environments" | jq 'sort_by(.id)')
result=$(jq -n --arg user "$user" --argjson environments "$environments" '{user: $user, environments: $environments}')

if [[ "$output_format" == "json" ]]; then
    echo "$result"
else
    echo "Logged in as: $user"
    echo ""
    echo "Available ARO Classic environments:"
    echo "$environments" | jq -r '.[] | "  \(.id) = \(. | @json)"'
fi

