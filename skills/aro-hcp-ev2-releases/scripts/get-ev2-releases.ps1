<#
.SYNOPSIS
    List ARO HCP EV2 rollouts for one environment.

.DESCRIPTION
    Wraps the ARO HCP oncall dashboard CLI ('oncall ev2') and filters the
    resulting EV2 rollouts down to a single environment. The environment is
    encoded in the trailing "- <env>" segment of the pipeline definition name,
    e.g. "Incremental - Entrypoint - HCP.Global - stg".

.EXAMPLE
    .\get-ev2-releases.ps1 -Environment prod
    .\get-ev2-releases.ps1 -Environment stg -Hours 12
    .\get-ev2-releases.ps1 -Environment test -Hours 0
#>

param(
    [Parameter()]
    [string]$Environment,

    [Parameter()]
    [int]$Hours = 24,

    [Parameter()]
    [string]$Path,

    [Parameter()]
    [switch]$Help
)

$ErrorActionPreference = "Stop"

$Subcommand = "ev2"

function Show-Help {
    $help = @"
get-ev2-releases.ps1 — List ARO HCP EV2 rollouts for one environment

USAGE:
    .\get-ev2-releases.ps1 -Environment <env> [options]

REQUIRED:
    -Environment <env>   Target environment. Matched against the trailing
                           "- <env>" segment of the pipeline definition name.
                           Known tokens: test | stg | prod | int
                           Aliases: stage/staging -> stg, production -> prod,
                                    integration -> int, tst -> test

OPTIONS:
    -Hours <int>         Look back N hours (default: 24; 0 = currently running only)
    -Path <path>         ADO folder path (default: the oncall CLI default,
                           \OneBranch\sdp-pipelines\hcp\Incremental)

EXAMPLES:
    .\get-ev2-releases.ps1 -Environment prod
    .\get-ev2-releases.ps1 -Environment stg -Hours 12
    .\get-ev2-releases.ps1 -Environment test -Hours 0
"@
    Write-Host $help
    exit 1
}

if ($Help) { Show-Help }
if (-not $Environment) {
    [Console]::Error.WriteLine("Error: -Environment is required")
    Show-Help
}

# Locate the oncall CLI (on PATH, or installed by its setup.sh into ~/bin).
$oncall = $null
if (Get-Command oncall -ErrorAction SilentlyContinue) {
    $oncall = "oncall"
} elseif (Test-Path "$HOME/bin/oncall") {
    $oncall = "$HOME/bin/oncall"
} else {
    [Console]::Error.WriteLine(@"
Error: the 'oncall' CLI was not found (looked on PATH and in ~/bin/oncall).

This skill wraps the oncall CLI that lives in 'oncall-cli/' in the aro-ai-tools
repo. Build and install it:
    oncall-cli/setup.sh
That installs 'oncall' to ~/bin. Requires Go, and either ADO_PAT set or az logged in.
EV2 lookups additionally need an az login that can get a token for the EV2 host
(corp login). Then re-run this skill.
"@)
    exit 127
}

# Normalise the environment to the canonical trailing-segment token.
$raw = $Environment.ToLower()
switch -Regex ($raw) {
    '^(test|tst)$'              { $canon = "test"; break }
    '^(stg|stage|staging)$'     { $canon = "stg";  break }
    '^(prod|prd|production)$'   { $canon = "prod"; break }
    '^(int|integration|integ)$' { $canon = "int";  break }
    default                     { $canon = $raw }
}

# Assemble oncall arguments.
$oncallArgs = @($Subcommand, "--hours", "$Hours")
if ($Path) { $oncallArgs += @("--path", $Path) }

# Run the CLI (its stderr flows through); capture stdout for filtering.
$out = & $oncall @oncallArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Filter the markdown table by the environment (trailing "- <env>" segment of the
# Pipeline column, which is the 2nd column). Non-table messages pass through.
$header = $null
$sep = $null
$rows = @()
$seen = [ordered]@{}
$sawTable = $false
$matched = 0

foreach ($line in @($out)) {
    $l = ([string]$line).TrimEnd("`r")
    if ($l -notmatch '^\s*\|') { if ($l.Trim().Length -gt 0) { Write-Output $l }; continue }
    if ($l -match '^\s*\|[-:\| ]+$') { $sep = $l; $sawTable = $true; continue }
    if ($l -match 'Pipeline') { $header = $l; $sawTable = $true; continue }

    $sawTable = $true
    $cols = $l -split '\|'
    $name = $cols[2].Trim()
    $parts = $name.ToLower() -split ' - '
    $segment = $parts[-1].Trim()
    $seen[$segment] = $true
    if ($segment -eq $canon -or $segment -eq $raw) {
        $matched++
        $cols[1] = " $matched "
        $rows += ($cols -join '|')
    }
}

if ($matched -gt 0) {
    if ($header) { Write-Output $header }
    if ($sep) { Write-Output $sep }
    $rows | ForEach-Object { Write-Output $_ }
} elseif ($sawTable) {
    [Console]::Error.WriteLine("No EV2 rollouts matched environment `"$Environment`".")
    if ($seen.Count -gt 0) {
        [Console]::Error.WriteLine("Environments present in the results: " + (($seen.Keys) -join ", "))
    }
}
