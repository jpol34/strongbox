#Requires -Version 7.0
<#
.SYNOPSIS
    Idempotent: registers the 'Strongbox' SecretStore vault if not already registered.
.DESCRIPTION
    This aliases the same physical per-user SecretStore file as any other vault name you've
    registered against Microsoft.PowerShell.SecretStore on this machine - SecretStore has no
    per-vault-name storage path, so no data migration happens here.
#>
$ErrorActionPreference = 'Stop'

$vaultName = 'Strongbox'
$existing = Get-SecretVault -Name $vaultName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Vault '$vaultName' is already registered."
} else {
    Write-Host "Registering vault '$vaultName'..."
    Register-SecretVault -Name $vaultName -ModuleName Microsoft.PowerShell.SecretStore
}

try {
    Set-SecretStoreConfiguration -Authentication None -Interaction None -Confirm:$false -ErrorAction Stop | Out-Null
} catch {
    Write-Host "Note: could not set non-interactive SecretStore configuration (may already be set): $_"
}

# Permanent, obviously-fake sandbox secret: gives anyone (human or an AI agent driving the CLI)
# a safe, always-present target to test get/reveal/list against, so there's never a reason to
# reach for a real secret name just to check a command works.
$sandboxName = 'tools.StrongboxSelfTest'
if (-not (Get-SecretInfo -Vault $vaultName -Name $sandboxName -ErrorAction SilentlyContinue)) {
    Set-Secret -Name $sandboxName -Secret 'THIS IS A SAFE TEST VALUE - NOT A REAL SECRET' -Vault $vaultName
    Set-SecretInfo -Name $sandboxName -Vault $vaultName -Metadata @{ Owner = 'tools' } -ErrorAction SilentlyContinue
    Write-Host "Provisioned permanent sandbox test secret '$sandboxName' (always safe to reveal/test with)."
} else {
    Write-Host "Sandbox test secret '$sandboxName' already exists."
}

Get-SecretVault | Format-Table Name, ModuleName, IsDefault
