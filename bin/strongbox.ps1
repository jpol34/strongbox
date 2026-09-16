#Requires -Version 7.0
<#
.SYNOPSIS
    Strongbox CLI - a subcommand wrapper over the Strongbox PowerShell module's functions.
.DESCRIPTION
    Pure presentation layer: every subcommand here is a thin call into an already-tested module
    function (Strongbox\Public\*.ps1) - no new vault/manifest logic lives in this file.
#>
param(
    [Parameter(Position = 0)] [string] $Command,
    [Parameter(Position = 1, ValueFromRemainingArguments)] [string[]] $Rest = @()
)
$ErrorActionPreference = 'Stop'

function Test-InteractiveTerminal {
    -not ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected)
}

# get/reveal --stdout are documented as piping-safe ("Print a secret's value to stdout, for
# scripting/piping"), which only holds if stdout carries nothing but the secret. In a
# non-interactive session (no real console - SSH, a shell script), PowerShell's warning stream
# writes ANSI-colored text directly onto stdout instead of staying separate from it, so any
# warning anywhere in this script's execution would corrupt a piped capture. A human at a real
# interactive prompt still sees warnings normally.
if (-not (Test-InteractiveTerminal)) {
    $WarningPreference = 'SilentlyContinue'
}

try {
    Import-Module Strongbox -ErrorAction Stop
} catch {
    Import-Module (Join-Path $PSScriptRoot '..' 'Strongbox' 'Strongbox.psd1') -ErrorAction Stop
}
. (Join-Path $PSScriptRoot '..' 'Get-StrongboxListeningProcess.ps1')

function Show-Usage {
    @'
strongbox <command> [args]

  list [--json]                    List every tracked secret (name/owner/purpose/rotation/stale)
  stale [--json]                   List only secrets past their rotation policy
  check                            Drift check: manifest vs. vault

  get <name> [--real]               Print a secret's value to stdout (for scripting/piping)
  set <name> <value> [--rotation-days N] [--owner X] [--scope project [--project X]]
                                    Write a secret. --scope project writes a project-scoped
                                    secret that shadows any global one of the same name while
                                    inside that project; --project defaults to the current repo
                                    when not given
  remove <name> [--force]           Delete a secret (prompts for confirmation unless --force)
  reveal <name> [--stdout] [--real] Copy a secret to the clipboard (auto-clears after 30s);
                                    --stdout prints it instead, for cases where you truly need
                                    that (accepts the same exposure tradeoff -reveal in the web
                                    UI/browser copy button already accepts)

  'get'/'reveal' refuse to output anything but tools.StrongboxSelfTest (a permanent, harmless
  sandbox value - always fine to touch) when run non-interactively (no real terminal attached -
  e.g. from a script or an AI agent's tool calls) unless you pass --real. A human typing at a
  real interactive prompt never sees this gate.

  backup export <path>             Back up manifest + every secret value to an encrypted file
                                    (prompts for a passphrase - never pass it as an argument,
                                    that would land in shell history and process-list args)
  backup import <path> [--force]   Restore from a backup file (prompts for the passphrase)

  sync init <server-url> [--device-name X]
                                    Register this device against a sync server (prompts for the
                                    sync passphrase and the server's admin bootstrap token)
  sync push [name]                 Push synced secrets (or just [name]) to the server
  sync pull [name] [--scope project --project X]
                                    Pull synced secrets (or just [name]) from the server.
                                    --scope is only needed the first time this device pulls a
                                    project-scoped secret it has no local record of yet
  sync status [--json]             Show local vs. remote sync version drift, without changing
                                    anything

  serve start                      Start the web UI server (idempotent - safe if already running)
  serve stop                       Stop it, if running
  serve status                     Show whether it's running and its URL

  help                              Show this text
'@ | Write-Host
}

$script:SandboxSecretName = 'tools.StrongboxSelfTest'

function Assert-RevealAllowed {
    <#
    Prevents a script or automated agent from grabbing a real secret when it's only trying to
    verify a command works. The sandbox secret is always safe to touch; anything else requires
    either a real interactive terminal (a human consciously typing this) or an explicit --real
    flag.
    #>
    param([string] $Name, [string[]] $ArgList)
    if ($Name -eq $script:SandboxSecretName) { return }
    if (Test-InteractiveTerminal) { return }
    if ($ArgList -contains '--real') { return }
    throw "Refusing to reveal '$Name' in a non-interactive session without --real. Use '$script:SandboxSecretName' to test commands safely, or pass --real if you genuinely mean this one."
}

function Find-StrongboxServerProcess {
    foreach ($port in 443, 80) {
        $proc = Get-StrongboxListeningProcess -Port $port
        if ($proc) {
            return [pscustomobject]@{ Port = $port; Process = $proc }
        }
    }
    return $null
}

function ConvertTo-DisplayTable {
    param($InputObject)
    $InputObject | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
}

function Set-StrongboxClipboard {
    param([string] $Value)
    if ($IsWindows) {
        Set-Clipboard -Value $Value
        return
    }
    # No universal clipboard cmdlet on Linux - shell out to whichever tool is actually
    # available (Wayland vs. X11, or neither on a headless box).
    foreach ($tool in 'wl-copy', 'xclip', 'xsel') {
        if (Get-Command $tool -ErrorAction SilentlyContinue) {
            $args = switch ($tool) {
                'xclip' { '-selection', 'clipboard' }
                'xsel' { '--clipboard', '--input' }
                default { @() }
            }
            $Value | & $tool @args
            return
        }
    }
    throw "No clipboard tool found (tried wl-copy, xclip, xsel). Install one, or use --stdout instead."
}

function Get-StrongboxClipboard {
    if ($IsWindows) { return Get-Clipboard -Raw -ErrorAction SilentlyContinue }
    # Same tool-preference order as Set-StrongboxClipboard - reading back with a different tool
    # than what wrote it can hit a different clipboard backend (X11 vs. Wayland) and never see
    # the value that was actually set.
    foreach ($tool in 'wl-paste', 'xclip', 'xsel') {
        if (Get-Command $tool -ErrorAction SilentlyContinue) {
            $args = switch ($tool) {
                'xclip' { '-selection', 'clipboard', '-o' }
                'xsel' { '--clipboard' }
                default { @() }
            }
            return (& $tool @args 2>$null) -join "`n"
        }
    }
    return $null
}

function Set-ClipboardWithAutoClear {
    param([string] $Value, [int] $ClearAfterSeconds = 30)
    Set-StrongboxClipboard -Value $Value
    Write-Host "Copied to clipboard (clears in ${ClearAfterSeconds}s - best-effort: won't fire if you close this shell first)."
    # Start-ThreadJob runs in its own runspace, which doesn't inherit this script's functions -
    # -InitializationScript re-declares them there from their own (already-defined) bodies.
    $initScript = [scriptblock]::Create(@"
function Set-StrongboxClipboard { ${function:Set-StrongboxClipboard} }
function Get-StrongboxClipboard { ${function:Get-StrongboxClipboard} }
"@)
    Start-ThreadJob -InitializationScript $initScript -ScriptBlock {
        param($Expected, $Delay)
        Start-Sleep -Seconds $Delay
        try {
            if ((Get-StrongboxClipboard) -eq $Expected) {
                Set-StrongboxClipboard -Value ''
            }
        } catch { }
    } -ArgumentList $Value, $ClearAfterSeconds | Out-Null
}

switch ($Command) {
    'list' {
        $json = $Rest -contains '--json'
        $result = Get-StrongboxSecretList
        if ($json) { $result | ConvertTo-Json -Depth 4 } else { ConvertTo-DisplayTable $result }
    }
    'stale' {
        $json = $Rest -contains '--json'
        $result = Get-StrongboxStaleSecrets
        if ($json) { $result | ConvertTo-Json -Depth 4 } else { ConvertTo-DisplayTable $result }
    }
    'check' {
        Test-Strongbox
    }
    'get' {
        $name = $Rest[0]
        if (-not $name) { throw "Usage: strongbox get <name> [--real]" }
        Assert-RevealAllowed -Name $name -ArgList $Rest
        Get-StrongboxSecret -Name $name
    }
    'set' {
        $name = $Rest[0]
        $value = $Rest[1]
        if (-not $name -or -not $value) { throw "Usage: strongbox set <name> <value> [--rotation-days N] [--owner X] [--scope project [--project X]]" }
        $params = @{ Name = $name; Value = $value }
        $rdIdx = [array]::IndexOf($Rest, '--rotation-days')
        if ($rdIdx -ge 0 -and $Rest.Count -gt $rdIdx + 1) { $params.RotationDays = [int]$Rest[$rdIdx + 1] }
        $ownerIdx = [array]::IndexOf($Rest, '--owner')
        if ($ownerIdx -ge 0 -and $Rest.Count -gt $ownerIdx + 1) { $params.Owner = $Rest[$ownerIdx + 1] }
        $scopeIdx = [array]::IndexOf($Rest, '--scope')
        if ($scopeIdx -ge 0 -and $Rest.Count -gt $scopeIdx + 1) { $params.Scope = $Rest[$scopeIdx + 1] }
        $projectIdx = [array]::IndexOf($Rest, '--project')
        if ($projectIdx -ge 0 -and $Rest.Count -gt $projectIdx + 1) { $params.Project = $Rest[$projectIdx + 1] }
        Set-StrongboxSecret @params
        Write-Host "Set '$name'."
    }
    'remove' {
        $name = $Rest[0]
        if (-not $name) { throw "Usage: strongbox remove <name> [--force]" }
        $force = $Rest -contains '--force'
        if (-not $force) {
            $confirm = Read-Host "Delete '$name'? Type the name again to confirm"
            if ($confirm -ne $name) { Write-Host "Cancelled."; return }
        }
        Remove-StrongboxSecret -Name $name
        Write-Host "Removed '$name'."
    }
    'reveal' {
        $name = $Rest[0]
        if (-not $name) { throw "Usage: strongbox reveal <name> [--stdout] [--real]" }
        Assert-RevealAllowed -Name $name -ArgList $Rest
        $value = Get-StrongboxSecret -Name $name
        if ($Rest -contains '--stdout') { $value } else { Set-ClipboardWithAutoClear -Value $value }
    }
    'backup' {
        $sub = $Rest[0]
        $path = $Rest[1]
        if (-not $path) { throw "Usage: strongbox backup export|import <path> [--force]" }
        $pass = Read-Host -AsSecureString "Passphrase"
        switch ($sub) {
            'export' { Export-StrongboxBackup -Path $path -Passphrase $pass }
            'import' {
                $force = $Rest -contains '--force'
                Import-StrongboxBackup -Path $path -Passphrase $pass -Force:$force
            }
            default { throw "Usage: strongbox backup export|import <path> [--force]" }
        }
    }
    'sync' {
        $sub = $Rest[0]
        switch ($sub) {
            'init' {
                $serverUrl = $Rest[1]
                if (-not $serverUrl) { throw "Usage: strongbox sync init <server-url> [--device-name X]" }
                $deviceName = $env:COMPUTERNAME
                $dnIdx = [array]::IndexOf($Rest, '--device-name')
                if ($dnIdx -ge 0 -and $Rest.Count -gt $dnIdx + 1) { $deviceName = $Rest[$dnIdx + 1] }
                $syncPass = Read-Host -AsSecureString "Sync passphrase (separate from your backup passphrase - you'll need this exact value on every other device)"
                $bootstrapToken = Read-Host -AsSecureString "Server admin bootstrap token"
                Initialize-StrongboxSync -ServerUrl $serverUrl -DeviceName $deviceName -SyncPassphrase $syncPass -BootstrapToken $bootstrapToken
            }
            'push' {
                Push-StrongboxSecret -Name $Rest[1]
            }
            'pull' {
                $params = @{}
                if ($Rest.Count -gt 1 -and $Rest[1] -notlike '--*') { $params.Name = $Rest[1] }
                $scopeIdx = [array]::IndexOf($Rest, '--scope')
                if ($scopeIdx -ge 0 -and $Rest.Count -gt $scopeIdx + 1) { $params.Scope = $Rest[$scopeIdx + 1] }
                $projectIdx = [array]::IndexOf($Rest, '--project')
                if ($projectIdx -ge 0 -and $Rest.Count -gt $projectIdx + 1) { $params.Project = $Rest[$projectIdx + 1] }
                Pull-StrongboxSecret @params
            }
            'status' {
                $json = $Rest -contains '--json'
                $result = Get-StrongboxSyncStatus
                if ($json) { $result | ConvertTo-Json -Depth 4 } else { ConvertTo-DisplayTable $result }
            }
            default { throw "Usage: strongbox sync init|push|pull|status ..." }
        }
    }
    'serve' {
        $sub = $Rest[0]
        switch ($sub) {
            'start' {
                $existing = Find-StrongboxServerProcess
                if ($existing) {
                    Write-Host "Already running on port $($existing.Port) (PID $($existing.Process.Id))."
                    return
                }
                $uiScript = (Resolve-Path (Join-Path $PSScriptRoot '..' 'ui' 'Start-StrongboxUi.ps1')).Path
                if ($IsWindows) {
                    Start-Process pwsh -ArgumentList '-NoProfile', '-File', $uiScript -WindowStyle Hidden
                } else {
                    # -WindowStyle is Windows-only; Linux has no window to hide - just detach it
                    # from this shell so it keeps running after the CLI command returns.
                    Start-Process pwsh -ArgumentList '-NoProfile', '-File', $uiScript
                }
                # The Pode server takes a couple seconds to bind - poll rather than assume.
                $found = $null
                for ($i = 0; $i -lt 10 -and -not $found; $i++) {
                    Start-Sleep -Seconds 1
                    $found = Find-StrongboxServerProcess
                }
                if ($found) {
                    $scheme = if ($found.Port -eq 443) { 'https' } else { 'http' }
                    Write-Host "Started on $scheme`://strongbox.local (PID $($found.Process.Id))."
                } else {
                    Write-Host "Started, but couldn't confirm it's listening yet - check 'strongbox serve status' shortly." -ForegroundColor Yellow
                }
            }
            'stop' {
                $existing = Find-StrongboxServerProcess
                if (-not $existing) { Write-Host "Not running."; return }
                if ($existing.Process.ProcessName -ne 'pwsh') {
                    Write-Host "Port $($existing.Port) is held by $($existing.Process.ProcessName) (PID $($existing.Process.Id)), not a pwsh process - not stopping something that might not be Strongbox." -ForegroundColor Yellow
                    return
                }
                Stop-Process -Id $existing.Process.Id -Force
                Write-Host "Stopped (was PID $($existing.Process.Id) on port $($existing.Port))."
            }
            'status' {
                $existing = Find-StrongboxServerProcess
                if (-not $existing) { Write-Host "Not running."; return }
                $scheme = if ($existing.Port -eq 443) { 'https' } else { 'http' }
                Write-Host "Running on $scheme`://strongbox.local (PID $($existing.Process.Id), port $($existing.Port))."
            }
            default { throw "Usage: strongbox serve start|stop|status" }
        }
    }
    { $_ -in $null, '', 'help', '-h', '--help' } {
        Show-Usage
    }
    default {
        Write-Host "Unknown command: $Command" -ForegroundColor Red
        Show-Usage
        exit 1
    }
}
