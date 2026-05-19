#!/usr/bin/env bash

PLUGIN_REVISION="20260505-7ab42fa"
CLASSIC_CONFIG_SUBSCRIPTION="Azure Red Hat OpenShift v4.x - Development"
CLASSIC_CONFIG_RG="ai-plugin-cfg"

client="${1:-unknown}"
if [[ $# -gt 0 ]]; then
    shift
fi

output_format="text"

while [[ $# -gt 0 ]]; do
    case "$1" in
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

