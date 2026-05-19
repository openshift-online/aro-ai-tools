# Optional first argument: AI agent client name (default: "unknown")
param(
    [string]$Client = "unknown"
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

$azJson = az account show --subscription $CLASSIC_CONFIG_SUBSCRIPTION
if ($LASTEXITCODE -ne 0) {
    Write-Error "Couldn't get current login info for subscription '$CLASSIC_CONFIG_SUBSCRIPTION'. Not logged into Azure or missing access?."
    exit 1
}
$account = $azJson | ConvertFrom-Json
$user = $account.user.name

$classicEntries = @(Get-ClassicEnvironments | Sort-Object id)

$result = [ordered]@{
    user         = $user
    environments = $classicEntries
}

$result | ConvertTo-Json -Depth 10
