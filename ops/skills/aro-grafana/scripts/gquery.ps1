param(
    [Parameter(Mandatory = $true)]
    [string]$GrafanaUrl,

    [Parameter(Mandatory = $true)]
    [string]$QueryJson
)

$GrafanaUrl = $GrafanaUrl.TrimEnd('/')
$GrafanaAppId = "ce34e7e5-485f-4d76-964f-b3d2b16d1e4f"

$token = az account get-access-token --resource $GrafanaAppId --query accessToken -o tsv 2>$null
if ($LASTEXITCODE -ne 0 -or -not $token) {
    Write-Error "Could not get access token. Are you logged in to Azure?"
    exit 1
}

$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type"  = "application/json"
}

try {
    $response = Invoke-WebRequest -Uri "$GrafanaUrl/api/ds/query" -Headers $headers -Method Post -Body $QueryJson -SkipHttpErrorCheck
} catch {
    Write-Error "Request failed: $_"
    exit 1
}
if ($response.StatusCode -ge 400) {
    Write-Error "Request failed (HTTP $($response.StatusCode)): $($response.Content)"
    exit 1
}
$response.Content
