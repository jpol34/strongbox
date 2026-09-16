# Strongbox

A machine-level secrets vault for personal/small-team dev work: a thin PowerShell module over
`Microsoft.PowerShell.SecretManagement` + `Microsoft.PowerShell.SecretStore`, plus a CLI and a
local web UI on top of it. No account, no subscription, no third-party service - everything lives
in your own user profile unless you opt into [cloud sync](#cloud-sync-byoc) against a server you
run yourself.

**Windows and Linux**, each a full local peer - not a sync-only client of the other. Windows uses
the Windows certificate store, `Get-NetTCPConnection`, and the Windows hosts file path; Linux uses
a PFX-based cert (with `update-ca-certificates` for trust), `ss`, `/etc/hosts`, and
`xclip`/`wl-copy`/`xsel` for clipboard support. Both branch from the same `$IsWindows`/`$IsLinux`
checks at each call site - no separate codebases to keep in sync.

## Get started with an AI coding agent

Paste this to an agent working on any project on a machine that has (or should have) Strongbox:

> This machine may have Strongbox set up for secrets (PowerShell module + CLI + web UI over
> Microsoft.PowerShell.SecretManagement/SecretStore). Check with `strongbox help` - if it's not
> there, tell me rather than installing it yourself. Once it's available, get values via
> `strongbox get <name>` or `Get-StrongboxSecret -Name <name>` - don't ask me to paste one in,
> don't hardcode one. Use `tools.StrongboxSelfTest` to test commands; `get`/`reveal` refuse any
> other name when run non-interactively unless I pass `--real`.

## Contents

- [Get started with an AI coding agent](#get-started-with-an-ai-coding-agent)
- [Features](#features)
- [Quick start](#quick-start)
- [PowerShell module](#powershell-module)
- [CLI](#cli)
- [Web UI](#web-ui)
- [Naming convention & manifest.json](#naming-convention--manifestjson)
- [Backup / restore](#backup--restore)
- [Cloud sync (BYOC)](#cloud-sync-byoc)
- [Uninstalling](#uninstalling)
- [Tests](#tests)
- [Known issues](#known-issues)

## Features

- Get/set/remove secrets from any PowerShell session, on any repo on the machine
- Windows and Linux, each a full local vault - not one syncing off the other
- A `strongbox` CLI (`list`, `get`, `set`, `reveal`, `backup`, `serve`, `sync`, ...) for people who
  don't want to remember cmdlet names
- A local, bearer-token-gated web UI (optional HTTPS with a real "Secure" indicator) for browsing,
  editing, and revealing secrets
- Global and project-scoped secrets - a project can override a global secret with its own value
- Opt-in, per-secret, zero-knowledge cloud sync against a server you host yourself (see
  [Cloud sync (BYOC)](#cloud-sync-byoc)) - nothing syncs unless you turn it on for that secret
- Drift checking (`Test-Strongbox`) - catches a manifest and vault that have quietly gone out of
  sync
- Rotation-policy tracking with a staleness check, in the CLI, the module, and the UI
- Encrypted, passphrase-protected backup/restore - the one thing SecretStore doesn't provide on
  its own
- A safeguard specifically against scripts/AI agents grabbing a real secret by accident while
  testing a command (see [CLI](#cli))

## Quick start

```powershell
pwsh -NoProfile -File Install-StrongboxPrerequisites.ps1
```

One command, idempotent (safe to re-run if it fails partway). It installs every module this tool
depends on (`Microsoft.PowerShell.SecretManagement`, `Microsoft.PowerShell.SecretStore`, `Pode`),
bootstraps the NuGet provider and bypasses the PSGallery untrusted-repository prompt on a
genuinely fresh machine (via `-Force` on each `Install-Module` call, not by permanently trusting
PSGallery machine-wide), registers the vault, installs the `Strongbox` module, and registers the
`strongbox` CLI command.

Open a new shell, then:

```powershell
strongbox help
```

## PowerShell module

```powershell
Import-Module Strongbox
Get-Command -Module Strongbox
```

| Function | What it does |
|---|---|
| `Get-StrongboxSecret -Name X [-Optional]` | Read a plaintext value (a project-scoped entry shadows a global one of the same name while inside that project) |
| `Set-StrongboxSecret -Name X -Value Y [-Owner ...] [-RotationDays N] [-Scope Project [-Project slug]]` | Write a value; stamps `LastRotated` automatically. `-Scope Project` writes a project-scoped secret instead of global |
| `Remove-StrongboxSecret -Name X` | Delete a value |
| `Get-StrongboxSecretList` | Every tracked secret's name/owner/purpose/rotation/staleness/scope/sync state - never values |
| `Get-StrongboxStaleSecrets` | Just the entries past their `RotationDays` policy |
| `Test-Strongbox` | Drift check: confirms `manifest.json` and the vault agree on what secrets exist |
| `Export-StrongboxBackup` / `Import-StrongboxBackup` | See [Backup / restore](#backup--restore) |
| `Initialize-StrongboxSync` / `Push-StrongboxSecret` / `Pull-StrongboxSecret` / `Get-StrongboxSyncStatus` | See [Cloud sync (BYOC)](#cloud-sync-byoc) |
| `Import-StrongboxSecretEnv -Map @{ENV_VAR='secret.name'}` | Set process-scoped env vars from the vault |
| `Export-StrongboxSecretUserSecrets -Project <csproj> -Map @{ConfigKey='secret.name'}` | Fan vault secrets into `dotnet user-secrets` |
| `Get-StrongboxSecretHeaders -Name X -Header Y [-Prefix 'Bearer ']` | JSON header object, for an MCP `headersHelper` |

## CLI

A subcommand wrapper over the module functions above - pure presentation layer, no new logic.

```
strongbox list [--json]                    List every tracked secret
strongbox stale [--json]                   List only secrets past their rotation policy
strongbox check                            Drift check: manifest vs. vault

strongbox get <name> [--real]               Print a secret's value to stdout (for scripting)
strongbox set <name> <value> [--rotation-days N] [--owner X] [--scope project [--project X]]
                                            --scope project writes a project-scoped secret that
                                            shadows a global one of the same name inside that
                                            project; --project defaults to the current repo
strongbox remove <name> [--force]          Prompts for confirmation unless --force
strongbox reveal <name> [--stdout] [--real] Copies to clipboard (auto-clears in 30s) by default;
                                             --stdout prints it instead

strongbox backup export <path>             Prompts for a passphrase - never pass one as an
strongbox backup import <path> [--force]   argument, it would land in shell history

strongbox sync init <server-url> [--device-name X]
                                            Register this device against a sync server (prompts
                                            for the sync passphrase and the server's admin
                                            bootstrap token)
strongbox sync push [name]                 Push synced secrets (or just [name]) to the server
strongbox sync pull [name] [--scope project --project X]
                                            Pull synced secrets (or just [name]) from the server;
                                            --scope is only needed the first time this device
                                            pulls a project-scoped secret it has no local record
                                            of yet
strongbox sync status [--json]             Local vs. remote sync version drift, read-only

strongbox serve start|stop|status          Manage the local web UI server
```

`reveal` defaults to clipboard-only (never printing the value), matching the web UI's reveal
modal's threat model - `get` is the deliberate exception, since its whole purpose is scripting/
piping the value somewhere.

**Safeguard against scripts/agents grabbing the wrong secret.** `get`/`reveal` refuse to touch
anything except the permanent sandbox secret `tools.StrongboxSelfTest` (auto-provisioned by
`Register-StrongboxVault.ps1` with a harmless placeholder value) when run **non-interactively** (no
real terminal attached - a script, or an AI coding agent's tool calls), unless you pass `--real`.
A human typing at a real interactive prompt never sees this gate. It exists to prevent a script
or automated agent from grabbing a real secret when it's only trying to verify a command works -
`tools.StrongboxSelfTest` removes any reason to reach for a real name just to test with.

Registered as a bare `strongbox` command by `Install-StrongboxPrerequisites.ps1` (or run
`Install-StrongboxCli.ps1` on its own) - this adds a small forwarding function to `$PROFILE`
rather than adding `.ps1` to `$env:PATHEXT`, since the latter would make every `.ps1` file
anywhere on `$env:Path` silently executable by bare name.

## Web UI

```powershell
pwsh -NoProfile -File ui/Start-StrongboxUi.ps1
```

Or `strongbox serve start` / `/strongbox` from Claude Code - either way it's idempotent (safe to
run repeatedly) and won't print the bearer token unless one is freshly generated.

Binds `127.0.0.1` only - no external network exposure either way. The auth token is generated
once and persisted to `.token` (gitignored); the browser saves it to `localStorage` after first
use, so you shouldn't need to paste it again. Delete `.token` to force a fresh one.

Every reveal, add/update, and delete is appended to `ui/audit.log` (gitignored, local-only) -
who/when/what, never values.

### HTTPS + a friendly hostname

By default the server serves plain HTTP on port 80 at `http://127.0.0.1` (Chrome shows a "Not
secure" indicator for any hostname other than the literal `localhost` served over HTTP; this is
purely cosmetic, since nothing ever leaves the loopback interface either way. For a friendlier
hostname *and* a real "Secure" indicator, run this once per machine:

```powershell
# 1. Requires elevation (hosts file is a protected system file):
Add-Content -Path "$env:WINDIR\System32\drivers\etc\hosts" -Value "127.0.0.1 strongbox.local"   # Windows
echo '127.0.0.1 strongbox.local' | sudo tee -a /etc/hosts                                        # Linux

# 2. Does NOT require elevation - generates a self-signed cert and trusts it for your user only:
pwsh -NoProfile -File ui/New-StrongboxCert.ps1
```

Start (or restart) the server afterward - it auto-detects the trusted cert and switches to HTTPS
on `https://strongbox.local` (no port needed); without the cert it falls back to plain HTTP.

Certificate trust is inherently per-machine, so there's no certificate (or private key) this repo
could ship that would make *your* browser trust it too - everyone, including on a fresh clone,
runs `New-StrongboxCert.ps1` once on their own machine.

On Windows, it uses the built-in `New-SelfSignedCertificate` and trusts the cert in
`Cert:\CurrentUser\Root` (no admin elevation needed, unlike `Cert:\LocalMachine\Root`) - scoped to
exactly one cert, one hostname, one user. Linux has no cert store to use, so the cert is built
directly via .NET's `CertificateRequest` API and exported as a password-protected PFX under
`ui/.certs/` (gitignored) for Pode's HTTPS endpoint. Trusting it system-wide needs
`update-ca-certificates`, which needs root - that command is printed, not run for you.

## Naming convention & manifest.json

Secret names are prefixed by ownership: `relay.`, `yardi.`, `tools.`, `personal.` (change the
regex in `ui/Start-StrongboxUi.ps1`'s POST/reveal/delete routes for different prefixes).

`manifest.json` is your own local record of every secret's purpose, consumers, and rotation
policy. It never contains secret *values*, but it does describe your own systems (internal
hostnames, client names, etc.), so it's gitignored rather than committed. See
`manifest.example.json` for the schema shape with fake placeholder data.

Entries also carry `scope` (`"global"`, the default, or `"project"`), `project` (a repo slug, for
project-scoped entries), and the sync fields `synced`/`syncVersion`/`syncedAt` (see
[Cloud sync (BYOC)](#cloud-sync-byoc)). All optional - an entry with none of them is just an
ordinary global, unsynced secret.

## Backup / restore

SecretStore has no documented backup path of its own - if the underlying vault store is lost (OS
reinstall, corrupted profile), every secret goes with it.

```powershell
$pass = Read-Host -AsSecureString "Backup passphrase"
Export-StrongboxBackup -Path strongbox-backup.json -Passphrase $pass
```

```powershell
$pass = Read-Host -AsSecureString "Backup passphrase"
Import-StrongboxBackup -Path strongbox-backup.json -Passphrase $pass   # add -Force to overwrite existing entries
```

The backup file is AES-256-GCM encrypted with a key derived from your passphrase (PBKDF2, 210,000
iterations, random per-file salt) - deliberately *not* Windows DPAPI, since a DPAPI-"protected"
file would only ever be restorable on the exact same Windows profile, defeating the point of a
disaster-recovery backup. There is no recovery if you lose the passphrase.

## Cloud sync (BYOC)

Opt-in, per-secret, zero-knowledge sync against a self-hosted reference server (see
[`server/README.md`](server/README.md) and [`docs/SYNC-API.md`](docs/SYNC-API.md)). Nothing syncs
until a manifest entry is explicitly marked `synced: true` - most secrets stay purely local.

```powershell
strongbox sync init http://your-server:8080 --device-name my-laptop   # once per device
strongbox sync push                                                   # push every synced secret
strongbox sync pull                                                   # pull every synced secret
strongbox sync status                                                 # local vs. remote version drift
```

Sync uses the same AES-256-GCM/PBKDF2 encryption as backup, but a separate passphrase - the server
only ever stores/serves ciphertext plus non-secret metadata (name, scope, project, version), and
never sees the encryption key. A push against a stale local version is refused ("pull first"),
never silently overwritten. Sync credentials (the passphrase and this device's server-issued
token) are cached in `~/.strongbox/`, outside this repo, so they survive a re-clone.

## Uninstalling

```powershell
pwsh -NoProfile -File Uninstall-Strongbox.ps1
```

Stops any running UI server, removes the installed module copy (`~/Documents/PowerShell/Modules`
on Windows, `~/.local/share/powershell/Modules` on Linux), the `strongbox` CLI function from
`$PROFILE`, and unregisters the `Strongbox` vault *name* - every actual secret value is untouched
(SecretStore has one physical store per user shared by every vault name registered against it, so
unregistering a name never touches the data; re-running the install script re-registers the same
name against the same store). Does not touch the HTTPS cert trust, the `strongbox.local` hosts
entry, this repo directory, or `manifest.json` - remove those yourself if wanted.

## Tests

```powershell
Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force -SkipPublisherCheck
Invoke-Pester -Path Tests/Strongbox.Tests.ps1
```

Covers the module's public functions against mocked `Get-Secret`/`Set-Secret`/`Get-SecretInfo`/
`Set-SecretInfo` calls (never a real vault) and a temp-file manifest. No Pester coverage exists yet
for the web UI backend (`ui/Start-StrongboxUi.ps1`).

## Known issues

`Set-SecretInfo` reliably succeeds for a call or two per PowerShell process, then starts failing
with an opaque "cannot write metadata" error for the rest of that session - confirmed
empirically while bulk-fixing metadata across 47 secrets. Each call works fine in its own fresh
`pwsh` process. If you need to bulk-update metadata across many secrets, loop over separate `pwsh
-Command` invocations rather than one loop inside a single session.

## License

[MIT](LICENSE)
