#Requires -Version 7.0
<#
.SYNOPSIS
    One-command setup for a fresh machine: installs every module Strongbox depends on, registers
    the vault, and installs the Strongbox module itself. Idempotent - safe to re-run if it fails
    partway or if some prerequisites are already present.
.DESCRIPTION
    Handles the two things that block non-interactive PowerShell module installs on a genuinely
    fresh machine:
      1. The NuGet package provider may not be present yet, and PowerShellGet's first
         Install-Module call would otherwise prompt interactively to install it.
      2. PSGallery is untrusted by default, so Install-Module would otherwise prompt to confirm
         an untrusted source.
    Both are handled per-call via -Force rather than by permanently flipping PSGallery to
    Trusted (Set-PSRepository -InstallationPolicy Trusted) - that would trust every future
    install from PSGallery, for anything, forever; -Force only bypasses the prompt for the
    specific modules this script installs.

    Does NOT set up HTTPS (see ui\New-StrongboxCert.ps1 for that - separate and opt-in, since it
    writes into the Windows trusted-certificate store, a bigger action than a routine dependency
    install should take silently).
#>
$ErrorActionPreference = 'Stop'

function Install-IfMissing {
    param(
        [Parameter(Mandatory)][string] $Name,
        [string] $MinimumVersion
    )
    $existing = Get-Module -ListAvailable -Name $Name |
        Where-Object { -not $MinimumVersion -or $_.Version -ge [version]$MinimumVersion } |
        Select-Object -First 1
    if ($existing) {
        Write-Host "$Name already installed (v$($existing.Version))." -ForegroundColor Cyan
        return
    }
    Write-Host "Installing $Name..." -ForegroundColor Yellow
    Install-Module -Name $Name -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    Write-Host "Installed $Name." -ForegroundColor Green
}

$nuget = Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue
if (-not $nuget) {
    Write-Host "Installing NuGet package provider..." -ForegroundColor Yellow
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
    Write-Host "Installed NuGet package provider." -ForegroundColor Green
} else {
    Write-Host "NuGet package provider already present." -ForegroundColor Cyan
}

Install-IfMissing -Name Microsoft.PowerShell.SecretManagement
Install-IfMissing -Name Microsoft.PowerShell.SecretStore
Install-IfMissing -Name Pode

Write-Host ""
Write-Host "Registering the Strongbox vault..." -ForegroundColor Cyan
& (Join-Path $PSScriptRoot 'Register-StrongboxVault.ps1')

Write-Host ""
Write-Host "Installing the Strongbox module..." -ForegroundColor Cyan
& (Join-Path $PSScriptRoot 'Install-StrongboxModule.ps1')

Write-Host ""
Write-Host "Registering the 'strongbox' CLI command..." -ForegroundColor Cyan
& (Join-Path $PSScriptRoot 'Install-StrongboxCli.ps1')

Write-Host ""
Write-Host "Done. Open a new shell, then:" -ForegroundColor Green
Write-Host "  strongbox help" -ForegroundColor Green
Write-Host "  (or: Import-Module Strongbox; Get-Command -Module Strongbox)" -ForegroundColor Green
Write-Host ""
Write-Host "For the web UI: pwsh -NoProfile -File ui\Start-StrongboxUi.ps1 (or /strongbox in Claude Code)" -ForegroundColor Green
Write-Host "For HTTPS + the strongbox.local hostname (optional, one-time): see ui\New-StrongboxCert.ps1" -ForegroundColor Green
