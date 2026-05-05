<#
.SYNOPSIS
    Zero-dependency Kusto metadata script. Requires only az CLI and PowerShell.

.DESCRIPTION
    Queries Azure Data Explorer (Kusto) cluster metadata via the REST API.

.EXAMPLE
    .\kusto.ps1 list-databases -Cluster https://mycluster.region.kusto.windows.net
    .\kusto.ps1 show-tables -Cluster https://mycluster.region.kusto.windows.net -Database mydb
    .\kusto.ps1 show-schema -Cluster https://mycluster.region.kusto.windows.net -Database mydb -Table mytable
    .\kusto.ps1 show-schema-all -Cluster https://mycluster.region.kusto.windows.net -Database mydb
#>

param(
    [Parameter(Position = 0)]
    [string]$Subcommand,

    [Parameter()]
    [string]$Cluster,

    [Parameter()]
    [string]$Database,

    [Parameter()]
    [string]$Table,

    [Parameter()]
    [int]$MaxRecords = 1000
)

$ErrorActionPreference = "Stop"

# --- Help ---

$ValidSubcommands = @("list-databases", "show-tables", "show-schema", "show-schema-all")

function Show-Help {
    $help = @"
kusto.ps1 — Kusto cluster metadata (list databases, tables, schemas)

USAGE:
    kusto.ps1 <subcommand> -Cluster <url> [-Database <name>] [options]

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
    .\kusto.ps1 list-databases -Cluster https://mycluster.region.kusto.windows.net
    .\kusto.ps1 show-tables -Cluster https://mycluster.region.kusto.windows.net -Database mydb
    .\kusto.ps1 show-schema -Cluster https://mycluster.region.kusto.windows.net -Database mydb -Table mytable
    .\kusto.ps1 show-schema-all -Cluster https://mycluster.region.kusto.windows.net -Database mydb
"@
    Write-Host $help
    exit 1
}

# --- Validation ---

if (-not $Subcommand) {
    Show-Help
}

if ($Subcommand -notin $ValidSubcommands) {
    [Console]::Error.WriteLine("Error: Unknown subcommand '$Subcommand'. Valid: $($ValidSubcommands -join ', ')")
    Show-Help
}

if (-not $Cluster) {
    [Console]::Error.WriteLine("Error: -Cluster is required")
    Show-Help
}

# Trim trailing slash from cluster URL
$Cluster = $Cluster.TrimEnd("/")

if ($Subcommand -ne "list-databases" -and -not $Database) {
    [Console]::Error.WriteLine("Error: -Database is required for subcommand '$Subcommand'")
    Show-Help
}

if ($Subcommand -eq "show-schema" -and -not $Table) {
    [Console]::Error.WriteLine("Error: -Table is required for subcommand 'show-schema'")
    Show-Help
}

# --- Auth ---

$token = az account get-access-token --resource $Cluster --query accessToken -o tsv
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to get access token for cluster $Cluster"
    exit 1
}

# --- Query execution ---

function Invoke-KustoQuery {
    param(
        [string]$KustoCluster,
        [string]$KustoDatabase,
        [string]$Kql,
        [int]$KustoMaxRecords
    )

    $body = @{
        db         = $KustoDatabase
        csl        = $Kql
        properties = @{
            Options = @{
                truncationmaxrecords = $KustoMaxRecords
            }
        }
    } | ConvertTo-Json -Depth 5

    $headers = @{
        Authorization    = "Bearer $token"
        "Content-Type"   = "application/json"
        Accept           = "application/json"
    }

    $uri = "$KustoCluster/v1/rest/mgmt"

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

    return $response.Content
}

# --- Subcommand dispatch ---

$db = if ($Database) { $Database } else { "NetDefaultDB" }

switch ($Subcommand) {
    "list-databases" {
        Invoke-KustoQuery -KustoCluster $Cluster -KustoDatabase $db -Kql ".show databases" -KustoMaxRecords $MaxRecords
    }
    "show-tables" {
        Invoke-KustoQuery -KustoCluster $Cluster -KustoDatabase $Database -Kql ".show tables" -KustoMaxRecords $MaxRecords
    }
    "show-schema" {
        Invoke-KustoQuery -KustoCluster $Cluster -KustoDatabase $Database -Kql ".show table [$Table] schema as json" -KustoMaxRecords $MaxRecords
    }
    "show-schema-all" {
        Invoke-KustoQuery -KustoCluster $Cluster -KustoDatabase $Database -Kql ".show database schema as json" -KustoMaxRecords $MaxRecords
    }
}
