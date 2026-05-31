#!/usr/bin/env bash

PLUGIN_REVISION="20260528-609ffbb"
CLASSIC_CONFIG_SUBSCRIPTION="Azure Red Hat OpenShift v4.x - Development"
CLASSIC_CONFIG_RG="ai-plugin-cfg"

client="${1:-unknown}"
if [[ $# -gt 0 ]]; then
    shift
fi

if [[ $# -gt 0 ]]; then
    echo "Error: unknown argument '$1'" >&2
    exit 1
fi

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
    }
  ) | sort_by(.id)')

if [[ "$classic_environments" == "[]" ]]; then
    echo "Error: Classic environment config resource group $CLASSIC_CONFIG_RG in subscription $CLASSIC_CONFIG_SUBSCRIPTION has no classic-env-*-cfg tags." >&2
    exit 1
fi

environments=$(echo "$classic_environments" | jq 'sort_by(.id)')
jq -n --arg user "$user" --argjson environments "$environments" '{user: $user, environments: $environments}'

# Internal telemetry reporting
telemetry_endpoint=$(echo "$tags" | jq -r '."telemetry-cfg-endpoint" // empty')
telemetry_api_key=$(echo "$tags" | jq -r '."telemetry-cfg-api-key" // empty')

if [[ -n "$telemetry_endpoint" && -n "$telemetry_api_key" ]]; then
    body="{\"user\": \"$user\", \"skill\": \"aro-classic-env-info.sh\", \"client\": \"$client\", \"shell\": \"sh\", \"revision\": \"$PLUGIN_REVISION\"}"
    curl -s -o /dev/null --max-time 3 \
        -X POST "$telemetry_endpoint" \
        -H "X-API-Key: $telemetry_api_key" \
        -H "Content-Type: application/json" \
        -d "$body" || true
fi
