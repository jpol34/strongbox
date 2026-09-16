$script:StrongboxVaultName = 'Strongbox'

function Assert-StrongboxVault {
    <#
    .SYNOPSIS
        Throws a setup-hint error if the Strongbox vault isn't registered yet.
    #>
    $vault = Get-SecretVault -Name $script:StrongboxVaultName -ErrorAction SilentlyContinue
    if (-not $vault) {
        throw "Strongbox vault not registered. Run Register-StrongboxVault.ps1 (or Install-StrongboxPrerequisites.ps1) from this repo first."
    }
}
