# Optional first argument: AI agent client name (default: "unknown")
param([string]$Client = "unknown")

$PLUGIN_REVISION = "20260504-e9cf716"

$azJson = az account show
if ($LASTEXITCODE -ne 0) {
    Write-Error "Couldn't get current login info. Not logged into Azure?."
    exit 1
}
$account = $azJson | ConvertFrom-Json

$tenantId = $account.tenantId
$tenantDisplayName = $account.tenantDisplayName
if ($tenantId -notlike "64*" -and $tenantId -notlike "72*") {
    Write-Error "Logged into the wrong Azure tenant '$tenantDisplayName' (tenantId: $tenantId). Tell user to log into the base RH or MSFT tenant."
    exit 1
}

$user = $account.user.name
if ($user -like "*@redhat.com") {
    $subscription = "b23756f7-4594-40a3-980f-10bb6168fc20"
    $rg = "ai-plugin-config"
} elseif ($user -like "*@microsoft.com") {
    $subscription = "Azure Red Hat OpenShift v4.x - HCP"
    $rg = "ai-plugin-cfg"
} else {
    Write-Error "Logged in as '$user', but a @redhat.com or @microsoft.com account is required."
    exit 1
}

Write-Host "Logged in as: $user"

$tags = az group show `
    --name $rg `
    --subscription $subscription `
    --query "tags" `
    --output json | ConvertFrom-Json

if (-not $tags) {
    Write-Host "Couldn't fetch config. Sandbox issues maybe?"
    exit 0
}

# Collect env-*-cfg* tags, group by env name, deep-merge values
# Only show env configs to the user; telemetry tags are internal
Write-Host ""
Write-Host "Available environments:"

$envConfigs = @{}
$tags.PSObject.Properties | Where-Object { $_.Name -match '^env-.+-cfg' } | ForEach-Object {
    $envName = $_.Name -replace '^env-', '' -replace '-cfg.*$', ''
    if (-not $envConfigs.ContainsKey($envName)) {
        $envConfigs[$envName] = @{}
    }
    try {
        $parsed = $_.Value | ConvertFrom-Json
        $parsed.PSObject.Properties | ForEach-Object {
            $propName = $_.Name
            $propVal = $_.Value
            $existing = $envConfigs[$envName][$propName]
            if ($existing -is [hashtable] -and $propVal -is [PSCustomObject]) {
                # Deep-merge object values into existing hashtable
                $propVal.PSObject.Properties | ForEach-Object { $existing[$_.Name] = $_.Value }
            } elseif ($propVal -is [PSCustomObject]) {
                # Convert PSCustomObject to hashtable for consistent handling
                $ht = @{}
                $propVal.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }
                $envConfigs[$envName][$propName] = $ht
            } else {
                $envConfigs[$envName][$propName] = $propVal
            }
        }
    } catch {}
}

foreach ($envName in $envConfigs.Keys | Sort-Object) {
    $val = $envConfigs[$envName]
    if ($val.kusto -and $val.kusto -notmatch '^https?://') {
        $val.kusto = "https://$($val.kusto).kusto.windows.net"
    }
    if ($val.grafana -and $val.grafana -notmatch '^https?://') {
        $val.grafana = "https://$($val.grafana).grafana.azure.com"
    }
    if ($val.kustos -and $val.kustos -is [hashtable]) {
        $expanded = @{}
        foreach ($geo in $val.kustos.Keys) {
            $ep = $val.kustos[$geo]
            if ($ep -notmatch '^https?://') { $ep = "https://$ep.kusto.windows.net" }
            $expanded[$geo] = $ep
        }
        $val.kustos = $expanded
    }
    Write-Host "  $envName = $($val | ConvertTo-Json -Compress)"
}

# Internal telemetry reporting
$telemetryEndpoint = $tags.'telemetry-cfg-endpoint'
$telemetryApiKey = $tags.'telemetry-cfg-api-key'

if ($telemetryEndpoint -and $telemetryApiKey) {
    $body = @{ user = $user; skill = "aro-hcp-env-info.ps1"; client = $Client; shell = "pwsh"; revision = $PLUGIN_REVISION } | ConvertTo-Json
    try {
        Invoke-RestMethod -Uri $telemetryEndpoint `
            -Method Post `
            -Headers @{ "X-API-Key" = $telemetryApiKey; "Content-Type" = "application/json" } `
            -Body $body `
            -TimeoutSec 3 | Out-Null
    } catch {}
}
