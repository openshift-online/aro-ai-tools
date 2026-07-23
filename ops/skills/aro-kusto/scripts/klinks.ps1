<#
.SYNOPSIS
    Generate an Azure Data Explorer (ADX) web link for a KQL query.

.EXAMPLE
    .\klinks.ps1 -Cluster https://mycluster.region.kusto.windows.net -Database mydb -Kql "MyTable | take 10"
#>

param(
    [Parameter()]
    [string]$Cluster,

    [Parameter()]
    [string]$Database,

    [Parameter()]
    [string]$Kql
)

$ErrorActionPreference = "Stop"

function Show-Help {
    $help = @"
klinks.ps1 - Generate an Azure Data Explorer (ADX) web link for a KQL query

USAGE:
    klinks.ps1 -Cluster <url> -Database <name> -Kql <kql_string>

REQUIRED:
    -Cluster <url>     Kusto cluster URL
                         e.g. https://mycluster.region.kusto.windows.net
    -Database <name>   Database name
    -Kql <kql_string>  KQL query

EXAMPLES:
    .\klinks.ps1 -Cluster https://mycluster.region.kusto.windows.net -Database mydb -Kql "MyTable | take 10"
"@
    [Console]::Error.WriteLine($help)
    exit 1
}

if (-not $Cluster)  { [Console]::Error.WriteLine("Error: -Cluster is required");  Show-Help }
if (-not $Database) { [Console]::Error.WriteLine("Error: -Database is required"); Show-Help }
if (-not $Kql)      { [Console]::Error.WriteLine("Error: -Kql is required");      Show-Help }

$Cluster = $Cluster.TrimEnd("/")

# Strip scheme and .kusto.windows.net suffix to get <name>.<region>
$hostName = $Cluster -replace '^https?://',''
$clusterPath = $hostName -replace '\.kusto\.windows\.net$',''

# gzip + base64 encode the query
$ms = New-Object System.IO.MemoryStream
$gz = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Compress)
$sw = New-Object System.IO.StreamWriter($gz, [System.Text.Encoding]::UTF8)
$sw.Write($Kql)
$sw.Close()
$encoded = [Convert]::ToBase64String($ms.ToArray())
$urlEncoded = [uri]::EscapeDataString($encoded)

$adxUrl = "https://dataexplorer.azure.com/clusters/$clusterPath/databases/$Database`?query=$urlEncoded"

Write-Output "ADX: $adxUrl"
