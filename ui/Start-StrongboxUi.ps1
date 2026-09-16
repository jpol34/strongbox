#Requires -Version 7.0
<#
.SYNOPSIS
    Local-only Strongbox management UI. Binds 127.0.0.1 only. Requires: Install-Module Pode -Scope CurrentUser.
.DESCRIPTION
    The bearer token is generated once and persisted to .token (gitignored, same directory as
    this script) so it survives restarts - the browser page saves it to localStorage after first
    use, so in practice you paste it once, ever. Delete .token to force a fresh one (invalidates
    any copies already saved in a browser).

    Port/token/paths are baked into the server scriptblock as literal string values (via
    ExpandString) rather than captured through $using:/-ArgumentList, since Pode invokes route
    and middleware scriptblocks through its own internal mechanism that does not support
    PowerShell's $using: scoping.
#>
param(
    [string] $HostName = 'strongbox.local',
    [int] $Port = 0,
    [switch] $RotateToken
)
$ErrorActionPreference = 'Stop'

# Certificate trust is per-machine (see New-StrongboxCert.ps1) - this just detects whichever
# state the current machine is in rather than assuming one.
$certPfxPath = $null
$certPfxPassword = $null
if ($IsWindows) {
    $cert = Get-ChildItem Cert:\CurrentUser\My -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -eq "CN=$HostName" -and $_.NotAfter -gt (Get-Date) } |
        Select-Object -First 1
} else {
    $certDir = Join-Path $PSScriptRoot '.certs'
    $pfxPath = Join-Path $certDir "$HostName.pfx"
    $passwordPath = Join-Path $certDir "$HostName.pfx.pass"
    $cert = $null
    if ((Test-Path -LiteralPath $pfxPath) -and (Test-Path -LiteralPath $passwordPath)) {
        try {
            $certPfxPassword = (Get-Content -LiteralPath $passwordPath -Raw).Trim()
            $candidate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($pfxPath, $certPfxPassword)
            if ($candidate.NotAfter -gt (Get-Date)) {
                $cert = $candidate
                $certPfxPath = $pfxPath
            }
        } catch {
            # A corrupt/stale PFX or a password out of sync with it shouldn't take the whole
            # server down - fall back to plain HTTP, same as the "no cert present" case.
            Write-Host "Couldn't load the certificate at $pfxPath ($($_.Exception.Message)) - serving plain HTTP. Re-run New-StrongboxCert.ps1 to regenerate it." -ForegroundColor DarkYellow
            $certPfxPassword = $null
        }
    }
}
$protocol = if ($cert) { 'Https' } else { 'Http' }
if ($Port -eq 0) { $Port = if ($protocol -eq 'Https') { 443 } else { 80 } }

$portSuffix = if (($protocol -eq 'Https' -and $Port -eq 443) -or ($protocol -eq 'Http' -and $Port -eq 80)) { '' } else { ":$Port" }
$scheme = $protocol.ToLower()
$displayUrl = "$scheme`://$HostName$portSuffix"
$fallbackUrl = "$scheme`://127.0.0.1$portSuffix"
if (-not $cert) {
    Write-Host ""
    Write-Host "No trusted certificate found for $HostName - serving plain HTTP. Run .\New-StrongboxCert.ps1 for HTTPS." -ForegroundColor DarkYellow
}

# Idempotency guard: a second instance on the same port would otherwise crash with a raw
# "address already in use" exception from Pode's underlying HttpListener. Report and exit
# cleanly instead - and don't guess whether the existing holder is a stale Strongbox server;
# let a human decide whether to stop it.
. (Join-Path $PSScriptRoot '..\Get-StrongboxListeningProcess.ps1')
$existingProcess = Get-StrongboxListeningProcess -Port $Port
if ($existingProcess) {
    Write-Host ""
    Write-Host "Strongbox UI is already running on $displayUrl ($fallbackUrl)" -ForegroundColor Cyan
    Write-Host "Held by: $($existingProcess.ProcessName) (PID $($existingProcess.Id))" -ForegroundColor DarkGray
    Write-Host ""
    exit 0
}

Import-Module Pode -ErrorAction Stop
Import-Module Strongbox -ErrorAction Stop

$tokenPath = Join-Path $PSScriptRoot '.token'
if ($RotateToken -or -not (Test-Path -LiteralPath $tokenPath)) {
    $tokenBytes = [byte[]]::new(32)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($tokenBytes)
    $token = [Convert]::ToBase64String($tokenBytes)
    Set-Content -LiteralPath $tokenPath -Value $token -NoNewline
    Write-Host ""
    Write-Host "Strongbox UI starting on $displayUrl (or $fallbackUrl)" -ForegroundColor Cyan
    Write-Host "New bearer token (paste once - the page remembers it after that): $token" -ForegroundColor Yellow
    Write-Host ""
} else {
    $token = (Get-Content -LiteralPath $tokenPath -Raw).Trim()
    Write-Host ""
    Write-Host "Strongbox UI starting on $displayUrl (or $fallbackUrl)" -ForegroundColor Cyan
    Write-Host "Reusing existing token from .token (already saved in your browser if you've used this before)." -ForegroundColor Cyan
    Write-Host ""
}

$manifestPath = (Resolve-Path (Join-Path $PSScriptRoot '..\manifest.json')).Path
$publicDir = (Resolve-Path (Join-Path $PSScriptRoot 'public')).Path
$auditLogPath = Join-Path $PSScriptRoot 'audit.log'

$endpointLine = if ($protocol -eq 'Https' -and $IsWindows) {
    "Add-PodeEndpoint -Address 127.0.0.1 -Port __PORT__ -Protocol Https -CertificateThumbprint '__CERT_THUMBPRINT__' -CertificateStoreName My -CertificateStoreLocation CurrentUser"
} elseif ($protocol -eq 'Https') {
    "Add-PodeEndpoint -Address 127.0.0.1 -Port __PORT__ -Protocol Https -Certificate '__CERT_FILE__' -CertificatePassword '__CERT_PASSWORD__'"
} else {
    "Add-PodeEndpoint -Address 127.0.0.1 -Port __PORT__ -Protocol Http"
}
$hostPattern = [regex]::Escape($HostName)

$serverScriptText = @'
function Write-StrongboxAudit {
    param([string] $Action, [string] $Name)
    $line = "$(Get-Date -Format o) $Action $Name"
    Write-Host "[Strongbox UI] $line"
    Add-Content -LiteralPath '__AUDIT_LOG_PATH__' -Value $line
}

__ENDPOINT_LINE__

Add-PodeMiddleware -Name 'SecurityHeaders' -ScriptBlock {
    Add-PodeHeader -Name 'X-Content-Type-Options' -Value 'nosniff'
    Add-PodeHeader -Name 'Content-Security-Policy' -Value "default-src 'self'"
    return $true
}

Add-PodeMiddleware -Name 'AuthAndOrigin' -ScriptBlock {
    $expected = 'Bearer __TOKEN__'
    $auth = $WebEvent.Request.Headers['Authorization']
    # Constant-time comparison - not meaningfully exploitable on a loopback-only server, but
    # cheap to do properly rather than leave a naive string-inequality timing side-channel.
    $authBytes = [System.Text.Encoding]::UTF8.GetBytes([string]$auth)
    $expectedBytes = [System.Text.Encoding]::UTF8.GetBytes($expected)
    $authMatches = ($authBytes.Length -eq $expectedBytes.Length) -and
        [System.Security.Cryptography.CryptographicOperations]::FixedTimeEquals($authBytes, $expectedBytes)
    if (-not $authMatches) {
        Set-PodeResponseStatus -Code 401
        Write-PodeJsonResponse -Value @{ error = 'unauthorized' }
        return $false
    }
    $originHeader = $WebEvent.Request.Headers['Origin']
    $hostHeader = $WebEvent.Request.Headers['Host']
    if ($originHeader -and ($originHeader -notmatch '^(https?://)?(127\.0\.0\.1|localhost|__HOST_PATTERN__)(:\d+)?$')) {
        Set-PodeResponseStatus -Code 403
        Write-PodeJsonResponse -Value @{ error = 'forbidden: bad origin' }
        return $false
    }
    if ($hostHeader -and ($hostHeader -notmatch '^(127\.0\.0\.1|localhost|__HOST_PATTERN__)(:\d+)?$')) {
        Set-PodeResponseStatus -Code 403
        Write-PodeJsonResponse -Value @{ error = 'forbidden: bad host' }
        return $false
    }
    return $true
} -Route '/api/*'

Add-PodeRoute -Method Get -Path '/api/secrets' -ScriptBlock {
    Add-PodeHeader -Name 'Cache-Control' -Value 'no-store'
    $manifestFile = '__MANIFEST_PATH__'
    $vaultName = 'Strongbox'
    $manifest = Get-Content -LiteralPath $manifestFile -Raw | ConvertFrom-Json
    # Project-scoped secrets can share a newName with a global one - only ever show the global
    # entry here, so the UI never surfaces an ambiguous name or a project-scoped value. A
    # scope: "project" entry with no project value is malformed and normalizes to global, same
    # as Resolve-StrongboxManifestScope.
    $entries = $manifest | Where-Object {
        $_.status -in 'keep', 'keep-unverified' -and -not ($_.scope -eq 'project' -and $_.project)
    }

    # Get-SecretInfo -Name scans the whole vault per call rather than doing an indexed lookup,
    # so fetching metadata one secret at a time scales linearly with vault size. Fetch all
    # vault entries once instead and index them locally.
    $infoByName = @{}
    foreach ($i in (Get-SecretInfo -Vault $vaultName)) { $infoByName[$i.Name] = $i }

    $result = foreach ($e in $entries) {
        $info = $infoByName[$e.newName]
        $lastRotated = $info.Metadata.LastRotated
        $rotationDays = $e.rotationDays
        $stale = $false
        if ($lastRotated -and $rotationDays) {
            $age = (Get-Date) - [datetime]$lastRotated
            $stale = $age.TotalDays -gt $rotationDays
        }
        [pscustomobject]@{
            name = $e.newName
            usedBy = $e.usedBy
            purpose = $e.purpose
            status = $e.status
            lastRotated = $lastRotated
            rotationDays = $rotationDays
            stale = $stale
        }
    }
    Write-PodeJsonResponse -Value @($result)
}

Add-PodeRoute -Method Get -Path '/api/secrets/:name/reveal' -ScriptBlock {
    $vaultName = 'Strongbox'
    $name = $WebEvent.Parameters['name']
    if ($name -notmatch '^(relay|yardi|tools|personal)\.[A-Za-z0-9_]+$') {
        Set-PodeResponseStatus -Code 400
        Write-PodeJsonResponse -Value @{ error = 'name must match <relay|yardi|tools|personal>.<Name>' }
        return
    }
    # No manifest scope check needed here, unlike the other three routes: a project-scoped
    # secret is stored under a distinct internal SecretStore name (<name>::<project>), so
    # Get-Secret -Name $name below can never resolve to a project-scoped value in the first
    # place - there's no ambiguity to filter out.
    Write-StrongboxAudit -Action 'REVEAL' -Name $name
    try {
        $value = Get-Secret -Name $name -Vault $vaultName -AsPlainText -ErrorAction Stop
        Write-PodeJsonResponse -Value @{ name = $name; value = $value }
    } catch {
        Set-PodeResponseStatus -Code 404
        Write-PodeJsonResponse -Value @{ error = 'not found' }
    }
}

Add-PodeRoute -Method Post -Path '/api/secrets' -ScriptBlock {
    $manifestFile = '__MANIFEST_PATH__'
    $vaultName = 'Strongbox'
    $body = $WebEvent.Data

    $name = $body.name
    $value = $body.value
    if (-not $name) {
        Set-PodeResponseStatus -Code 400
        Write-PodeJsonResponse -Value @{ error = 'name is required' }
        return
    }
    if ($name -notmatch '^(relay|yardi|tools|personal)\.[A-Za-z0-9_]+$') {
        Set-PodeResponseStatus -Code 400
        Write-PodeJsonResponse -Value @{ error = 'name must match <relay|yardi|tools|personal>.<Name>' }
        return
    }

    $manifest = @(Get-Content -LiteralPath $manifestFile -Raw | ConvertFrom-Json)
    # Only ever match the global entry - a project-scoped entry sharing this newName is left
    # untouched, not silently overwritten or duplicated. A scope: "project" entry with no
    # project value is malformed and normalizes to global, same as Resolve-StrongboxManifestScope.
    $existing = $manifest | Where-Object { $_.newName -eq $name -and -not ($_.scope -eq 'project' -and $_.project) }

    if (-not $existing -and -not $value) {
        Set-PodeResponseStatus -Code 400
        Write-PodeJsonResponse -Value @{ error = 'value is required for a new secret' }
        return
    }

    $owner = $name.Split('.')[0]
    if ($value) {
        Set-Secret -Name $name -Secret $value -Vault $vaultName
        $metadata = @{ LastRotated = (Get-Date).ToUniversalTime().ToString('o'); Owner = $owner }
        if ($body.rotationDays) { $metadata.RotationDays = [int]$body.rotationDays }
        Set-SecretInfo -Name $name -Vault $vaultName -Metadata $metadata
    } elseif ($body.rotationDays) {
        $info = Get-SecretInfo -Vault $vaultName -Name $name -ErrorAction SilentlyContinue
        $metadata = @{ Owner = $owner; RotationDays = [int]$body.rotationDays }
        if ($info.Metadata.LastRotated) { $metadata.LastRotated = $info.Metadata.LastRotated }
        Set-SecretInfo -Name $name -Vault $vaultName -Metadata $metadata
    }

    if (-not $existing) {
        $usedBy = if ($body.usedBy) { @($body.usedBy) } else { @('added via Strongbox UI') }
        $entry = [ordered]@{
            oldName = $name
            newName = $name
            usedBy = $usedBy
            purpose = if ($body.purpose) { $body.purpose } else { '' }
            status = 'keep'
        }
        if ($body.rotationDays) { $entry.rotationDays = [int]$body.rotationDays }
        $manifest += [pscustomobject]$entry
    } else {
        $existing.usedBy = if ($body.usedBy) { @($body.usedBy) } else { $existing.usedBy }
        $existing.purpose = if ($body.purpose) { $body.purpose } else { $existing.purpose }
        if ($body.rotationDays) {
            $existing | Add-Member -NotePropertyName rotationDays -NotePropertyValue ([int]$body.rotationDays) -Force
        }
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestFile

    Write-StrongboxAudit -Action $(if ($value) { 'SET' } else { 'UPDATE-METADATA' }) -Name $name
    Write-PodeJsonResponse -Value @{ name = $name; ok = $true }
}

Add-PodeRoute -Method Delete -Path '/api/secrets/:name' -ScriptBlock {
    $manifestFile = '__MANIFEST_PATH__'
    $vaultName = 'Strongbox'
    $name = $WebEvent.Parameters['name']
    if ($name -notmatch '^(relay|yardi|tools|personal)\.[A-Za-z0-9_]+$') {
        Set-PodeResponseStatus -Code 400
        Write-PodeJsonResponse -Value @{ error = 'name must match <relay|yardi|tools|personal>.<Name>' }
        return
    }

    $manifest = @(Get-Content -LiteralPath $manifestFile -Raw | ConvertFrom-Json)
    $existing = $manifest | Where-Object { $_.newName -eq $name -and -not ($_.scope -eq 'project' -and $_.project) }
    if (-not $existing) {
        Set-PodeResponseStatus -Code 404
        Write-PodeJsonResponse -Value @{ error = 'not found' }
        return
    }

    Remove-Secret -Name $name -Vault $vaultName -ErrorAction SilentlyContinue
    # Only removes the global entry - a project-scoped entry sharing this newName stays.
    $manifest = $manifest | Where-Object { -not ($_.newName -eq $name -and -not ($_.scope -eq 'project' -and $_.project)) }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestFile

    Write-StrongboxAudit -Action 'DELETE' -Name $name
    Write-PodeJsonResponse -Value @{ name = $name; ok = $true }
}

Add-PodeStaticRoute -Path '/' -Source '__PUBLIC_DIR__' -FileBrowser:$false
'@

$serverScriptText = $serverScriptText.
    Replace('__ENDPOINT_LINE__', $endpointLine).
    Replace('__PORT__', $Port).
    Replace('__CERT_THUMBPRINT__', $(if ($IsWindows -and $cert) { $cert.Thumbprint } else { '' })).
    Replace('__CERT_FILE__', $(if ($certPfxPath) { $certPfxPath.Replace("'", "''") } else { '' })).
    Replace('__CERT_PASSWORD__', $(if ($certPfxPassword) { $certPfxPassword.Replace("'", "''") } else { '' })).
    Replace('__TOKEN__', $token).
    Replace('__HOST_PATTERN__', $hostPattern).
    Replace('__MANIFEST_PATH__', $manifestPath).
    Replace('__PUBLIC_DIR__', $publicDir).
    Replace('__AUDIT_LOG_PATH__', $auditLogPath)

$serverScript = [scriptblock]::Create($serverScriptText)

Start-PodeServer -Threads 2 -ScriptBlock $serverScript
