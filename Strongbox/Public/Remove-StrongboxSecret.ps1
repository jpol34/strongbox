function Remove-StrongboxSecret {
    <#
    .SYNOPSIS
        Deletes a secret from the Strongbox vault.
    .DESCRIPTION
        Only removes the secret value/metadata from the underlying SecretStore vault - does not
        touch manifest.json. If the secret is tracked there, remove its entry separately.
    .PARAMETER Name
        The prefixed secret name (e.g. relay.SqlDb_ConnectionString).
    #>
    param(
        [Parameter(Mandatory)][string] $Name
    )
    Assert-StrongboxVault
    Remove-Secret -Name $Name -Vault $script:StrongboxVaultName
}
