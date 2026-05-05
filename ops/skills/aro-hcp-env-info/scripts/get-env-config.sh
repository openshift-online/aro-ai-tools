PLUGIN_REVISION="20260505-7ab42fa"

# Optional first argument: AI agent client name (default: "unknown")
client="${1:-unknown}"

account=$(az account show)

if [[ -z "$account" ]]; then
    echo "Error: Couldn't get current login info. Not logged into Azure?." >&2
    exit 1
fi

tenantId=$(echo "$account" | jq -r '.tenantId')
tenantDisplayName=$(echo "$account" | jq -r '.tenantDisplayName')
if [[ "$tenantId" != 64* && "$tenantId" != 72* ]]; then
    echo "Error: Logged into the wrong Azure tenant '$tenantDisplayName' (tenantId: $tenantId). Tell user to log into the base RH or MSFT tenant." >&2
    exit 1
fi

user=$(echo "$account" | jq -r '.user.name')

if [[ "$user" == *@redhat.com ]]; then
    subscription="b23756f7-4594-40a3-980f-10bb6168fc20"
    rg="ai-plugin-config"
elif [[ "$user" == *@microsoft.com ]]; then
    subscription="Azure Red Hat OpenShift v4.x - HCP"
    rg="ai-plugin-cfg"
else
    echo "Error: Logged in as '$user', but a @redhat.com or @microsoft.com account is required." >&2
    exit 1
fi

echo "Logged in as: $user"

tags=$(az group show \
    --name "$rg" \
    --subscription "$subscription" \
    --query "tags" \
    --output json)

if [[ -z "$tags" || "$tags" == "null" ]]; then
    echo "Couldn't fetch config. Sandbox issues maybe?"
    exit 0
fi

# Collect env-*-cfg* tags, group by env name, deep-merge values
# Only show env configs to the user; telemetry tags are internal
echo ""
echo "Available environments:"
echo "$tags" | jq -r '
  # Collect all env config tags and group by env name
  [to_entries[] | select(.key | test("^env-.+-cfg"))] |
  group_by(.key | sub("^env-"; "") | sub("-cfg.*$"; "")) |
  map(
    (.[0].key | sub("^env-"; "") | sub("-cfg.*$"; "")) as $name |
    # Deep-merge all tag values for this env
    (reduce .[].value as $raw ({}; . * ($raw | try fromjson catch {}))) |
    # Expand short-format endpoints to full URLs
    if .kusto and (.kusto | test("^https?://") | not) then .kusto = "https://\(.kusto).kusto.windows.net" else . end |
    if .grafana and (.grafana | test("^https?://") | not) then .grafana = "https://\(.grafana).grafana.azure.com" else . end |
    if .kustos and (.kustos | type) == "object" then .kustos = (.kustos | with_entries(
      if (.value | test("^https?://") | not) then .value = "https://\(.value).kusto.windows.net" else . end
    )) else . end |
    "  \($name) = \(tojson)"
  ) | .[]'

# Internal telemetry reporting
telemetry_endpoint=$(echo "$tags" | jq -r '."telemetry-cfg-endpoint" // empty')
telemetry_api_key=$(echo "$tags" | jq -r '."telemetry-cfg-api-key" // empty')

if [[ -n "$telemetry_endpoint" && -n "$telemetry_api_key" ]]; then
    body="{\"user\": \"$user\", \"skill\": \"aro-hcp-env-info.sh\", \"client\": \"$client\", \"shell\": \"sh\", \"revision\": \"$PLUGIN_REVISION\"}"
    curl -s -o /dev/null --max-time 3 \
        -X POST "$telemetry_endpoint" \
        -H "X-API-Key: $telemetry_api_key" \
        -H "Content-Type: application/json" \
        -d "$body" || true
fi
