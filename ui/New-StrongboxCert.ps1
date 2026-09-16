#Requires -Version 7.0
<#
.SYNOPSIS
    One-time setup: creates and locally trusts a self-signed HTTPS certificate for the Strongbox UI.
.DESCRIPTION
    Certificate trust is inherently per-machine - there is no way to ship a certificate in this
    repo that browsers on someone else's machine would trust. Anyone using this tool (including
    on a fresh clone of this repo) runs this script once on their own machine to generate and
    trust their own certificate.

    Generates a self-signed cert via the built-in New-SelfSignedCertificate (no third-party tools
    like mkcert - this is a single personal tool, not a shared dev environment, so a broader
    local-CA trust model is more than the problem needs) and adds it to Cert:\CurrentUser\Root so
    Chrome/Edge treat it as trusted, without requiring admin elevation (Cert:\LocalMachine\Root
    would require elevation, same friction as the hosts-file entry below).

    Also requires a hosts-file entry mapping the hostname to 127.0.0.1 - that edit needs an
    elevated shell and is not done by this script; the command is printed if the entry is missing.
#>
param(
    [string] $HostName = 'strongbox.local'
)
$ErrorActionPreference = 'Stop'

$existing = Get-ChildItem Cert:\CurrentUser\My |
    Where-Object { $_.Subject -eq "CN=$HostName" -and $_.NotAfter -gt (Get-Date) } |
    Select-Object -First 1

if ($existing) {
    Write-Host "A valid certificate for $HostName already exists (thumbprint $($existing.Thumbprint), expires $($existing.NotAfter))." -ForegroundColor Cyan
    $cert = $existing
} else {
    $cert = New-SelfSignedCertificate -DnsName $HostName -CertStoreLocation Cert:\CurrentUser\My `
        -NotAfter (Get-Date).AddYears(5) -FriendlyName "Strongbox local dev cert ($HostName)"
    Write-Host "Created certificate for $HostName (thumbprint $($cert.Thumbprint))." -ForegroundColor Green
}

$rootStore = [System.Security.Cryptography.X509Certificates.X509Store]::new('Root', 'CurrentUser')
$rootStore.Open('ReadWrite')
$alreadyTrusted = $rootStore.Certificates | Where-Object Thumbprint -eq $cert.Thumbprint
if (-not $alreadyTrusted) {
    $rootStore.Add($cert)
    Write-Host "Trusted the certificate in Cert:\CurrentUser\Root." -ForegroundColor Green
} else {
    Write-Host "Certificate is already trusted in Cert:\CurrentUser\Root." -ForegroundColor Cyan
}
$rootStore.Close()

$hostsPath = "$env:WINDIR\System32\drivers\etc\hosts"
$hostsContent = Get-Content -LiteralPath $hostsPath -Raw -ErrorAction SilentlyContinue
if ($hostsContent -notmatch "(?m)^\s*127\.0\.0\.1\s+$([regex]::Escape($HostName))\s*$") {
    Write-Host ""
    Write-Host "Hosts-file entry for $HostName not found. Run this in an elevated PowerShell:" -ForegroundColor Yellow
    Write-Host "  Add-Content -Path `"`$env:WINDIR\System32\drivers\etc\hosts`" -Value `"127.0.0.1 $HostName`"" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Done. Start (or restart) the Strongbox UI to pick up HTTPS on https://$HostName" -ForegroundColor Green
