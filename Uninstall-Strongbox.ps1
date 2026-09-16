#Requires -Version 7.0
<#
.SYNOPSIS
    Undoes exactly what Install-StrongboxPrerequisites.ps1 / Install-StrongboxModule.ps1 /
    Register-StrongboxVault.ps1 did. Idempotent - safe to re-run.
.DESCRIPTION
    Removes:
      - Any running Strongbox UI server (port 80/443, loopback only)
      - The installed module copy under Documents\PowerShell\Modules\Strongbox
      - The 'Strongbox' entry this install added to the User PSModulePath
      - The 'Strongbox' SecretVault *registration* (Unregister-SecretVault)
      - The 'strongbox' CLI function block added to $PROFILE

    Deliberately does NOT touch:
      - Any actual secret value. SecretStore has one physical store per Windows user shared by
        every vault name registered against it - unregistering 'Strongbox' only removes that
        name/alias. Every secret is still there under the same underlying store, untouched, and
        re-running the install script re-registers the same name against the same data.
      - The Microsoft.PowerShell.SecretManagement / SecretStore / Pode PowerShell modules
        themselves - other tools/scripts on this machine may depend on them.
      - The HTTPS certificate trust (Cert:\CurrentUser\Root) or the strongbox.local hosts-file
        entry - both are machine-trust changes that shouldn't move as a side effect of uninstalling
        a module; remove them yourself if wanted (Cert:\CurrentUser\Root, and the hosts file line).
      - This repo directory itself, or manifest.json - that's your data, not installed state.
#>
$ErrorActionPreference = 'Stop'

foreach ($port in 80, 443) {
    $conns = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
        Where-Object LocalAddress -eq '127.0.0.1'
    foreach ($c in $conns) {
        $proc = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue
        if ($proc -and $proc.ProcessName -eq 'pwsh') {
            Write-Host "Stopping Strongbox UI server on port $port (PID $($proc.Id))..." -ForegroundColor Yellow
            Stop-Process -Id $proc.Id -Force
        }
    }
}

$vaultName = 'Strongbox'
if (Get-SecretVault -Name $vaultName -ErrorAction SilentlyContinue) {
    Write-Host "Unregistering vault '$vaultName' (secret values are untouched)..." -ForegroundColor Yellow
    Unregister-SecretVault -Name $vaultName
    Write-Host "Unregistered." -ForegroundColor Green
} else {
    Write-Host "Vault '$vaultName' is not registered." -ForegroundColor Cyan
}

$moduleRoot = Join-Path $HOME 'Documents\PowerShell\Modules\Strongbox'
if (Test-Path -LiteralPath $moduleRoot) {
    Remove-Item -LiteralPath $moduleRoot -Recurse -Force
    Write-Host "Removed installed module copy at $moduleRoot." -ForegroundColor Green
} else {
    Write-Host "No installed module copy found at $moduleRoot." -ForegroundColor Cyan
}

$modulePath = Join-Path $HOME 'Documents\PowerShell\Modules'
$currentPSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'User')
if ($currentPSModulePath -like "*$modulePath*") {
    $segments = $currentPSModulePath -split ';' | Where-Object { $_ -ne $modulePath }
    [Environment]::SetEnvironmentVariable('PSModulePath', ($segments -join ';'), 'User')
    Write-Host "Removed $modulePath from the User PSModulePath." -ForegroundColor Green
} else {
    Write-Host "User PSModulePath doesn't include $modulePath." -ForegroundColor Cyan
}

if (Test-Path -LiteralPath $PROFILE) {
    $profileContent = Get-Content -LiteralPath $PROFILE -Raw
    $pattern = '(?s)\r?\n?# >>> Strongbox CLI >>>.*?# <<< Strongbox CLI <<<\r?\n?'
    if ($profileContent -match $pattern) {
        Set-Content -LiteralPath $PROFILE -Value ([regex]::Replace($profileContent, $pattern, '')) -NoNewline
        Write-Host "Removed the 'strongbox' CLI function from $PROFILE." -ForegroundColor Green
    } else {
        Write-Host "No 'strongbox' CLI entry found in $PROFILE." -ForegroundColor Cyan
    }
}

Write-Host ""
Write-Host "Done. Every secret value is untouched - only the module/registration were removed." -ForegroundColor Green
Write-Host "To also remove HTTPS trust: delete the cert from Cert:\CurrentUser\Root and the" -ForegroundColor DarkGray
Write-Host "strongbox.local line from $env:WINDIR\System32\drivers\etc\hosts (manual, not done here)." -ForegroundColor DarkGray
