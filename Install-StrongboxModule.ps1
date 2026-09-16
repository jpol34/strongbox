#Requires -Version 7.0
<#
.SYNOPSIS
    Copies the Strongbox module onto $PSModulePath so `Import-Module Strongbox` works from any repo.
#>
$ErrorActionPreference = 'Stop'

$version = '1.0.0'
$source = Join-Path $PSScriptRoot 'Strongbox'
# Windows' user module path isn't on $env:PSModulePath by default, so it's registered below.
# Linux/macOS's ~/.local/share/powershell/Modules is already on pwsh's default PSModulePath -
# nothing to register there.
$modulePath = if ($IsWindows) { Join-Path $HOME 'Documents\PowerShell\Modules' } else { Join-Path $HOME '.local/share/powershell/Modules' }
$destRoot = Join-Path $modulePath 'Strongbox'
$dest = Join-Path $destRoot $version

New-Item -ItemType Directory -Path $dest -Force | Out-Null
Copy-Item -Path (Join-Path $source '*') -Destination $dest -Recurse -Force

# manifest.json lives one level up from Strongbox/ (in strongbox/, alongside this script),
# not inside the module folder that gets copied onto $PSModulePath - write a pointer so the
# installed module can still find the canonical manifest for editing/drift-checking.
$manifestPath = Join-Path $PSScriptRoot 'manifest.json'
Set-Content -LiteralPath (Join-Path $dest 'manifest-path.txt') -Value $manifestPath -NoNewline

if ($IsWindows) {
    $currentPSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'User')
    if ($currentPSModulePath -notlike "*$modulePath*") {
        Write-Host "PSModulePath (User) doesn't include $modulePath - appending."
        $newValue = if ($currentPSModulePath) { "$currentPSModulePath;$modulePath" } else { $modulePath }
        [Environment]::SetEnvironmentVariable('PSModulePath', $newValue, 'User')
        Write-Host "Updated. Open a new shell for this to take effect."
    } else {
        Write-Host "PSModulePath already includes $modulePath."
    }
}

Write-Host "Installed Strongbox $version to $dest"
