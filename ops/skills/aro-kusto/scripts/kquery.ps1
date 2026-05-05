<#
.SYNOPSIS
    Zero-dependency KQL query script. Requires only az CLI and PowerShell.

.DESCRIPTION
    Runs arbitrary KQL queries against Azure Data Explorer (Kusto) clusters via the v2 REST API.

.EXAMPLE
    .\kquery.ps1 -Cluster https://mycluster.region.kusto.windows.net -Database mydb -Kql "MyTable | take 10"
#>

param(
    [Parameter()]
    [string]$Cluster,

    [Parameter()]
    [string]$Database,

    [Parameter()]
    [string]$Kql,

    [Parameter()]
    [int]$MaxRecords = 1000
)

$ErrorActionPreference = "Stop"

# --- Help ---

function Show-Help {
    $help = @"
kquery.ps1 — Run arbitrary KQL queries against Kusto

USAGE:
    kquery.ps1 -Cluster <url> -Database <name> -Kql <kql_string> [options]

REQUIRED:
    -Cluster <url>              Kusto cluster URL
                                  e.g. https://mycluster.region.kusto.windows.net
    -Database <name>            Database name
    -Kql <kql_string>           KQL query or control command

OPTIONS:
    -MaxRecords <int>           Row limit (default: 1000, 0 = unlimited)

EXAMPLES:
    .\kquery.ps1 -Cluster https://mycluster.region.kusto.windows.net -Database mydb -Kql "MyTable | take 10"
    .\kquery.ps1 -Cluster https://mycluster.region.kusto.windows.net -Database mydb -Kql "MyTable | summarize count() by col" -MaxRecords 0
"@
    Write-Host $help
    exit 1
}

# --- Validation ---

if (-not $Cluster) {
    [Console]::Error.WriteLine("Error: -Cluster is required")
    Show-Help
}

if (-not $Database) {
    [Console]::Error.WriteLine("Error: -Database is required")
    Show-Help
}

if (-not $Kql) {
    [Console]::Error.WriteLine("Error: -Kql is required")
    Show-Help
}

# Trim trailing slash from cluster URL
$Cluster = $Cluster.TrimEnd("/")

# --- Auth ---

$token = az account get-access-token --resource $Cluster --query accessToken -o tsv
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to get access token for cluster $Cluster"
    exit 1
}

# --- Query execution ---

# Control commands (starting with '.') use v1/rest/mgmt; queries use v2/rest/query
$isControlCommand = $Kql.TrimStart().StartsWith(".")

$body = @{
    db         = $Database
    csl        = $Kql
    properties = @{
        Options = @{
            truncationmaxrecords = $MaxRecords
        }
    }
} | ConvertTo-Json -Depth 5

$headers = @{
    Authorization    = "Bearer $token"
    "Content-Type"   = "application/json"
    Accept           = "application/json"
}

if ($isControlCommand) {
    $uri = "$Cluster/v1/rest/mgmt"
} else {
    $uri = "$Cluster/v2/rest/query"
}

try {
    $response = Invoke-WebRequest -Uri $uri -Method Post -Headers $headers -Body $body -UseBasicParsing -SkipHttpErrorCheck
}
catch {
    Write-Error "Kusto query failed: $_"
    exit 1
}
if ($response.StatusCode -ge 400) {
    Write-Error "Kusto query failed (HTTP $($response.StatusCode)): $($response.Content)"
    exit 1
}

Write-Output $response.Content
