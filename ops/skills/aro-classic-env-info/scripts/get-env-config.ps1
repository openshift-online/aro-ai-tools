# Optional first argument: AI agent client name (default: "unknown")
param(
    [string]$Client = "unknown",
    [switch]$DiscoverDatabases,
    [ValidateSet("text", "json")]
    [string]$OutputFormat = "text"
)

$PLUGIN_REVISION = "20260505-7ab42fa"

$ErrorActionPreference = "Stop"

$CLASSIC_CONFIG_SUBSCRIPTION = "Azure Red Hat OpenShift v4.x - Development"
$CLASSIC_CONFIG_RG = "ai-plugin-cfg"

function Expand-ClassicKustoEndpoint {
    param([AllowNull()][string]$Value)

    if (-not $Value -or $Value -match '^https?://') {
        return $Value
    }
    return "https://$Value.kusto.windows.net"
}

function Set-FairfaxDefaults {
    param([Parameter(Mandatory = $true)]$Entry)

    if ($Entry.cloud -ne "fairfax") {
        return
    }
    if ($Entry.PSObject.Properties.Name -notcontains "databaseSource") {
        $Entry | Add-Member -NotePropertyName "databaseSource" -NotePropertyValue "assumed-from-public-prod"
    }
    if ($Entry.PSObject.Properties.Name -notcontains "authNotes") {
        $Entry | Add-Member -NotePropertyName "authNotes" -NotePropertyValue @(
            "SAW-only access documented",
            "Use Kusto Explorer with FairFax (usgovcloudapi.net) cloud setting and dSTS-Federated security"
        )
    }
}

function Get-ClassicEnvironments {
    try {
        $tags = az group show `
            --name $CLASSIC_CONFIG_RG `
            --subscription $CLASSIC_CONFIG_SUBSCRIPTION `
            --query "tags" `
            --output json | ConvertFrom-Json
    } catch {
        Write-Error "Failed to load Classic environment config tags from resource group '$CLASSIC_CONFIG_RG' in subscription '$CLASSIC_CONFIG_SUBSCRIPTION': $($_.Exception.Message)"
        exit 1
    }

    $entries = @()
    $tags.PSObject.Properties | Where-Object { $_.Name -match '^classic-env-(?<cloud>[^-]+)-(?<environment>[^-]+)-(?<slug>.+)-cfg$' } | ForEach-Object {
        $cloud = $Matches.cloud
        $environment = $Matches.environment
        $slug = $Matches.slug
        try {
            $value = $_.Value | ConvertFrom-Json
        } catch {
            Write-Warning "Failed to parse Classic config tag '$($_.Name)': $($_.Exception.Message)"
            return
        }

        $entry = [ordered]@{
            id              = "classic/$cloud/$environment/$slug"
            kind            = "classic"
            cloud           = $cloud
            environment     = $environment
            sector          = $value.sector
            locations       = @($value.locations)
            kusto           = Expand-ClassicKustoEndpoint -Value $value.kusto
            defaultDatabase = if ($value.defaultDatabase) { $value.defaultDatabase } else { "ARORPLogs" }
            source          = "classic-config-tags"
        }

        foreach ($property in $value.PSObject.Properties) {
            if ($entry.Contains($property.Name)) {
                continue
            }
            $entry[$property.Name] = $property.Value
        }

        $entryObject = [pscustomobject]$entry
        Set-FairfaxDefaults -Entry $entryObject
        $entries += $entryObject
    }

    if ($entries.Count -eq 0) {
        Write-Error "Classic environment config resource group '$CLASSIC_CONFIG_RG' in subscription '$CLASSIC_CONFIG_SUBSCRIPTION' has no classic-env-*-cfg tags."
        exit 1
    }

    return @($entries | Sort-Object id)
}

function Set-Property {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        $Value
    )

    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.$Name = $Value
    } else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Add-Warning {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Warning
    )

    $warnings = @()
    if ($Object.PSObject.Properties.Name -contains "warnings" -and $Object.warnings) {
        $warnings = @($Object.warnings)
    }
    $warnings += $Warning
    Set-Property -Object $Object -Name "warnings" -Value $warnings
}

function Update-ClassicDatabases {
    param([Parameter(Mandatory = $true)]$Entries)

    foreach ($entry in $Entries) {
        if (-not $entry.kusto) {
            continue
        }
        try {
            $token = az account get-access-token --resource $entry.kusto --query accessToken -o tsv 2>$null
            if ($LASTEXITCODE -ne 0 -or -not $token) {
                throw "failed to acquire access token"
            }

            $body = @{
                db         = "NetDefaultDB"
                csl        = ".show databases"
                properties = @{ Options = @{ truncationmaxrecords = 0 } }
            } | ConvertTo-Json -Depth 5

            $response = Invoke-RestMethod `
                -Uri "$($entry.kusto.TrimEnd('/'))/v1/rest/mgmt" `
                -Method Post `
                -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" } `
                -Body $body `
                -TimeoutSec 20

            $databases = @($response.Tables[0].Rows | ForEach-Object { $_[0] } | Sort-Object -Unique)
            if ($databases.Count -gt 0) {
                Set-Property -Object $entry -Name "databases" -Value $databases
                Set-Property -Object $entry -Name "databaseSource" -Value "runtime-discovered"
            }
        } catch {
            Add-Warning -Object $entry -Warning "Could not refresh database list: $($_.Exception.Message)"
        }
    }
}

$azJson = az account show --subscription $CLASSIC_CONFIG_SUBSCRIPTION
if ($LASTEXITCODE -ne 0) {
    Write-Error "Couldn't get current login info for subscription '$CLASSIC_CONFIG_SUBSCRIPTION'. Not logged into Azure or missing access?."
    exit 1
}
$account = $azJson | ConvertFrom-Json
$user = $account.user.name

$classicEntries = @(Get-ClassicEnvironments | Sort-Object id)
if ($DiscoverDatabases) {
    Update-ClassicDatabases -Entries $classicEntries
}

$result = [ordered]@{
    user         = $user
    environments = $classicEntries
}

if ($OutputFormat -eq "json") {
    $result | ConvertTo-Json -Depth 10
} else {
    Write-Host "Logged in as: $user"
    Write-Host ""
    Write-Host "Available ARO Classic environments:"
    foreach ($entry in $classicEntries) {
        Write-Host "  $($entry.id) = $($entry | ConvertTo-Json -Compress -Depth 10)"
    }
}

