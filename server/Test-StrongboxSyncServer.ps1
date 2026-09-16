#Requires -Version 7.0
<#
.SYNOPSIS
    Lightweight Invoke-RestMethod integration check against a running sync server. No Pester
    coverage plan for this server, matching the existing gap noted for the local UI - this
    script is the practical minimum instead of full unit coverage.
.PARAMETER BaseUrl
    The running server's base URL, e.g. http://127.0.0.1:8080.
.PARAMETER BootstrapToken
    The server's admin bootstrap token (printed to its startup log, or read from
    <data-dir>/admin-bootstrap-token).
#>
param(
    [Parameter(Mandatory)][string] $BaseUrl,
    [Parameter(Mandatory)][string] $BootstrapToken
)
$ErrorActionPreference = 'Stop'
$failures = @()

function Assert-True {
    param([string] $Description, [bool] $Condition)
    if ($Condition) {
        Write-Host "  PASS: $Description" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: $Description" -ForegroundColor Red
        $script:failures += $Description
    }
}

Write-Host "POST /devices without bootstrap token -> 401" -ForegroundColor Cyan
try {
    Invoke-RestMethod -Uri "$BaseUrl/devices" -Method Post -Body (@{ deviceName = 'nope' } | ConvertTo-Json) -ContentType 'application/json' | Out-Null
    Assert-True "rejected without token" $false
} catch {
    Assert-True "rejected without token" ($_.Exception.Response.StatusCode.value__ -eq 401)
}

Write-Host "POST /devices with bootstrap token -> device token" -ForegroundColor Cyan
$device = Invoke-RestMethod -Uri "$BaseUrl/devices" -Method Post `
    -Headers @{ Authorization = "Bearer $BootstrapToken" } `
    -Body (@{ deviceName = 'integration-test' } | ConvertTo-Json) -ContentType 'application/json'
Assert-True "device token issued" (-not [string]::IsNullOrEmpty($device.token))
$authHeader = @{ Authorization = "Bearer $($device.token)" }

$secretName = "integration-test-secret-$([guid]::NewGuid().ToString('N').Substring(0,8))"

Write-Host "POST /secrets/:name (initial push, expectedVersion 0) -> version 1" -ForegroundColor Cyan
$pushBody = @{
    scope           = 'global'
    expectedVersion = 0
    salt            = [Convert]::ToBase64String([byte[]](1..16))
    nonce           = [Convert]::ToBase64String([byte[]](1..12))
    tag             = [Convert]::ToBase64String([byte[]](1..16))
    ciphertext      = [Convert]::ToBase64String([byte[]](1..32))
} | ConvertTo-Json
$pushResult = Invoke-RestMethod -Uri "$BaseUrl/secrets/$secretName" -Method Post -Headers $authHeader -Body $pushBody -ContentType 'application/json'
Assert-True "first push accepted at version 1" ($pushResult.version -eq 1)

Write-Host "GET /secrets/:name -> envelope round-trips" -ForegroundColor Cyan
$fetched = Invoke-RestMethod -Uri "$BaseUrl/secrets/$secretName`?scope=global" -Method Get -Headers $authHeader
Assert-True "ciphertext round-trips" ($fetched.ciphertext -eq ($pushBody | ConvertFrom-Json).ciphertext)
Assert-True "version is 1" ($fetched.version -eq 1)

Write-Host "GET /secrets -> metadata only, no ciphertext fields" -ForegroundColor Cyan
$list = Invoke-RestMethod -Uri "$BaseUrl/secrets" -Method Get -Headers $authHeader
$listEntry = $list | Where-Object { $_.name -eq $secretName }
Assert-True "listed" ($null -ne $listEntry)
Assert-True "no ciphertext/salt/nonce/tag in list" (
    -not ($listEntry.PSObject.Properties.Name -contains 'ciphertext') -and
    -not ($listEntry.PSObject.Properties.Name -contains 'salt') -and
    -not ($listEntry.PSObject.Properties.Name -contains 'nonce') -and
    -not ($listEntry.PSObject.Properties.Name -contains 'tag')
)

Write-Host "POST /secrets/:name with stale expectedVersion -> 409, version unchanged" -ForegroundColor Cyan
try {
    Invoke-RestMethod -Uri "$BaseUrl/secrets/$secretName" -Method Post -Headers $authHeader -Body $pushBody -ContentType 'application/json' | Out-Null
    Assert-True "stale push rejected" $false
} catch {
    Assert-True "stale push rejected with 409" ($_.Exception.Response.StatusCode.value__ -eq 409)
}
$stillFetched = Invoke-RestMethod -Uri "$BaseUrl/secrets/$secretName`?scope=global" -Method Get -Headers $authHeader
Assert-True "version still 1 after rejected push" ($stillFetched.version -eq 1)

Write-Host "DELETE /secrets/:name -> ok, then 404" -ForegroundColor Cyan
$deleteResult = Invoke-RestMethod -Uri "$BaseUrl/secrets/$secretName`?scope=global" -Method Delete -Headers $authHeader
Assert-True "delete acknowledged" ($deleteResult.ok -eq $true)
try {
    Invoke-RestMethod -Uri "$BaseUrl/secrets/$secretName`?scope=global" -Method Get -Headers $authHeader | Out-Null
    Assert-True "deleted secret now 404" $false
} catch {
    Assert-True "deleted secret now 404" ($_.Exception.Response.StatusCode.value__ -eq 404)
}

Write-Host ""
if ($failures.Count -eq 0) {
    Write-Host "All checks passed." -ForegroundColor Green
    exit 0
} else {
    Write-Host "$($failures.Count) check(s) failed:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
