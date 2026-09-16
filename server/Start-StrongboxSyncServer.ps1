#Requires -Version 7.0
<#
.SYNOPSIS
    Reference BYOC sync server - zero-knowledge storage for opt-in Strongbox secret sync.
.DESCRIPTION
    Stores only ciphertext plus non-secret metadata; the encryption key never leaves a client.
    Meant to be reachable off-LAN, unlike the local web UI - every request past POST /devices
    carries a per-device bearer token, and TLS is a real deployment requirement documented in
    docs/SYNC-API.md, not optional cosmetic HTTPS.

    Port/cert/token values are baked into the server scriptblock as literal string values (via
    ExpandString) rather than captured through $using:/-ArgumentList, since Pode invokes route
    and middleware scriptblocks through its own internal mechanism that does not support
    PowerShell's $using: scoping - same constraint as ui/Start-StrongboxUi.ps1. The storage and
    device-token helpers live in the StrongboxSync module instead, and are imported (not
    dot-sourced) before Start-PodeServer runs - Pode's runspace pool only inherits commands from
    imported modules and functions declared directly in the server scriptblock's own text, not
    from files dot-sourced at setup time.
#>
param(
    [int] $Port = $(if ($env:STRONGBOX_SYNC_PORT) { [int]$env:STRONGBOX_SYNC_PORT } else { 8080 }),
    [string] $DataDir = $(if ($env:STRONGBOX_SYNC_DATA_DIR) { $env:STRONGBOX_SYNC_DATA_DIR } else { '/data' }),
    [string] $CertificateFile = $env:STRONGBOX_SYNC_CERT_FILE,
    [string] $CertificatePassword = $env:STRONGBOX_SYNC_CERT_PASSWORD
)
$ErrorActionPreference = 'Stop'

Import-Module Pode -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'StrongboxSync.psm1') -ErrorAction Stop

New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
$dbPath = Join-Path $DataDir 'strongbox-sync.db'
$bootstrapTokenPath = Join-Path $DataDir 'admin-bootstrap-token'

Initialize-StrongboxSyncDatabase -DbPath $dbPath
$bootstrapToken = Get-StrongboxSyncBootstrapToken -Path $bootstrapTokenPath

Write-Host ""
Write-Host "Strongbox sync server starting on port $Port" -ForegroundColor Cyan
Write-Host "Admin bootstrap token (needed once per device registration; also saved to $bootstrapTokenPath):" -ForegroundColor Yellow
Write-Host $bootstrapToken -ForegroundColor Yellow
Write-Host ""

$endpointLine = if ($CertificateFile) {
    "Add-PodeEndpoint -Address 0.0.0.0 -Port __PORT__ -Protocol Https -Certificate '__CERT_FILE__' -CertificatePassword '__CERT_PASSWORD__'"
} else {
    "Add-PodeEndpoint -Address 0.0.0.0 -Port __PORT__ -Protocol Http"
}

$serverScriptText = @'
__ENDPOINT_LINE__

Add-PodeMiddleware -Name 'SecurityHeaders' -ScriptBlock {
    Add-PodeHeader -Name 'X-Content-Type-Options' -Value 'nosniff'
    return $true
}

Add-PodeRoute -Method Post -Path '/devices' -ScriptBlock {
    $auth = [string]$WebEvent.Request.Headers['Authorization']
    $expected = 'Bearer __BOOTSTRAP_TOKEN__'
    # Constant-time comparison, same idiom as the local UI's bearer-token check - this token
    # crosses a real network, unlike the loopback-only UI token, so it's worth doing properly.
    $authBytes = [System.Text.Encoding]::UTF8.GetBytes($auth)
    $expectedBytes = [System.Text.Encoding]::UTF8.GetBytes($expected)
    $authMatches = ($authBytes.Length -eq $expectedBytes.Length) -and
        [System.Security.Cryptography.CryptographicOperations]::FixedTimeEquals($authBytes, $expectedBytes)
    if (-not $authMatches) {
        Set-PodeResponseStatus -Code 401
        Write-PodeJsonResponse -Value @{ error = 'unauthorized' }
        return
    }
    $deviceName = $WebEvent.Data.deviceName
    if (-not $deviceName) {
        Set-PodeResponseStatus -Code 400
        Write-PodeJsonResponse -Value @{ error = 'deviceName is required' }
        return
    }
    $device = New-StrongboxSyncDevice -DbPath '__DB_PATH__' -DeviceName $deviceName
    Write-PodeJsonResponse -Value @{ deviceId = $device.deviceId; token = $device.token }
}

Add-PodeRoute -Method Get -Path '/secrets' -ScriptBlock {
    if (-not (Assert-StrongboxSyncDeviceAuth -DbPath '__DB_PATH__')) { return }
    Add-PodeHeader -Name 'Cache-Control' -Value 'no-store'
    Write-PodeJsonResponse -Value @(Get-BlobMetadataList -DbPath '__DB_PATH__')
}

Add-PodeRoute -Method Get -Path '/secrets/:name' -ScriptBlock {
    if (-not (Assert-StrongboxSyncDeviceAuth -DbPath '__DB_PATH__')) { return }
    $name = $WebEvent.Parameters['name']
    $q = Get-StrongboxSyncQueryScope
    $blob = Get-Blob -DbPath '__DB_PATH__' -Name $name -Scope $q.Scope -Project $q.Project
    if (-not $blob) {
        Set-PodeResponseStatus -Code 404
        Write-PodeJsonResponse -Value @{ error = 'not found' }
        return
    }
    Write-PodeJsonResponse -Value $blob
}

Add-PodeRoute -Method Post -Path '/secrets/:name' -ScriptBlock {
    $device = Assert-StrongboxSyncDeviceAuth -DbPath '__DB_PATH__'
    if (-not $device) { return }
    $name = $WebEvent.Parameters['name']
    $body = $WebEvent.Data
    foreach ($field in 'scope', 'expectedVersion', 'salt', 'nonce', 'tag', 'ciphertext') {
        if ($null -eq $body.$field) {
            Set-PodeResponseStatus -Code 400
            Write-PodeJsonResponse -Value @{ error = "$field is required" }
            return
        }
    }
    if ($body.scope -notin 'global', 'project') {
        Set-PodeResponseStatus -Code 400
        Write-PodeJsonResponse -Value @{ error = "scope must be 'global' or 'project'" }
        return
    }
    if ($body.scope -eq 'project' -and -not $body.project) {
        Set-PodeResponseStatus -Code 400
        Write-PodeJsonResponse -Value @{ error = 'project is required when scope is project' }
        return
    }
    $expectedVersion = 0
    if (-not [int]::TryParse([string]$body.expectedVersion, [ref] $expectedVersion)) {
        Set-PodeResponseStatus -Code 400
        Write-PodeJsonResponse -Value @{ error = 'expectedVersion must be an integer' }
        return
    }
    $project = if ($body.scope -eq 'project') { $body.project } else { '' }
    $result = Put-Blob -DbPath '__DB_PATH__' -Name $name -Scope $body.scope -Project $project `
        -ExpectedVersion $expectedVersion -DeviceId $device.deviceId `
        -Salt $body.salt -Nonce $body.nonce -Tag $body.tag -Ciphertext $body.ciphertext
    if ($result.conflict) {
        Set-PodeResponseStatus -Code 409
        Write-PodeJsonResponse -Value @{ error = 'version conflict, pull first'; version = $result.version }
        return
    }
    Write-PodeJsonResponse -Value @{ name = $name; version = $result.version }
}

Add-PodeRoute -Method Delete -Path '/secrets/:name' -ScriptBlock {
    if (-not (Assert-StrongboxSyncDeviceAuth -DbPath '__DB_PATH__')) { return }
    $name = $WebEvent.Parameters['name']
    $q = Get-StrongboxSyncQueryScope
    $removed = Remove-Blob -DbPath '__DB_PATH__' -Name $name -Scope $q.Scope -Project $q.Project
    if (-not $removed) {
        Set-PodeResponseStatus -Code 404
        Write-PodeJsonResponse -Value @{ error = 'not found' }
        return
    }
    Write-PodeJsonResponse -Value @{ name = $name; ok = $true }
}
'@

# Every substituted value below lands inside a single-quoted PowerShell string literal in the
# script text - doubling any embedded single quote is that literal's own escape sequence, so an
# operator-supplied cert path/password or a data-dir path containing a quote can't break out of
# the literal and corrupt the generated script.
function ConvertTo-PodeStringLiteralSafe {
    param([string] $Value)
    if ($null -eq $Value) { return '' }
    $Value.Replace("'", "''")
}

$serverScriptText = $serverScriptText.
    Replace('__ENDPOINT_LINE__', $endpointLine).
    Replace('__PORT__', $Port).
    Replace('__CERT_FILE__', (ConvertTo-PodeStringLiteralSafe $CertificateFile)).
    Replace('__CERT_PASSWORD__', (ConvertTo-PodeStringLiteralSafe $CertificatePassword)).
    Replace('__DB_PATH__', (ConvertTo-PodeStringLiteralSafe $dbPath)).
    Replace('__BOOTSTRAP_TOKEN__', (ConvertTo-PodeStringLiteralSafe $bootstrapToken))

$serverScript = [scriptblock]::Create($serverScriptText)
Start-PodeServer -Threads 2 -ScriptBlock $serverScript
