#Requires -Version 7.0
<#
.SYNOPSIS
    Registers the bare `strongbox` command in your PowerShell profile. Idempotent.
.DESCRIPTION
    Windows deliberately excludes .ps1 from $env:PATHEXT, so a script sitting in $env:Path won't
    resolve by typing its bare name - that's a security guard against arbitrary .ps1 files
    becoming silently executable by name, not something to work around by widening PATHEXT
    (which would affect every application's command resolution, not just this one command).

    Instead, this appends a small forwarding function to $PROFILE (creating it if needed) that
    calls bin\strongbox.ps1 with your arguments - the same pattern most PowerShell-distributed
    CLI tools use for their entry point.
#>
$ErrorActionPreference = 'Stop'

$scriptPath = (Resolve-Path (Join-Path $PSScriptRoot 'bin' 'strongbox.ps1')).Path
$marker = '# >>> Strongbox CLI >>>'
$endMarker = '# <<< Strongbox CLI <<<'
$functionBlock = @"
$marker
function strongbox { & '$scriptPath' @args }
$endMarker
"@

if (-not (Test-Path -LiteralPath $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
}

$profileContent = Get-Content -LiteralPath $PROFILE -Raw -ErrorAction SilentlyContinue
if ($profileContent -and $profileContent.Contains($marker)) {
    Write-Host "strongbox command already registered in $PROFILE."
} else {
    Add-Content -LiteralPath $PROFILE -Value "`n$functionBlock"
    Write-Host "Added the 'strongbox' command to $PROFILE."
}

Write-Host "Open a new shell (or run '. `$PROFILE') to use the 'strongbox' command."
