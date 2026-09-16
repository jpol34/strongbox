function Set-StrongboxSecret {
    <#
    .SYNOPSIS
        Write a secret to the Strongbox vault, stamping LastRotated metadata on every call.
    #>
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Value,
        [string] $Owner,
        [int] $RotationDays
    )
    Assert-StrongboxVault
    Set-Secret -Name $Name -Secret $Value -Vault $script:StrongboxVaultName

    $metadata = @{ LastRotated = (Get-Date).ToUniversalTime().ToString('o') }
    if ($Owner) { $metadata.Owner = $Owner }
    if ($RotationDays) { $metadata.RotationDays = $RotationDays }
    Set-SecretInfo -Name $Name -Vault $script:StrongboxVaultName -Metadata $metadata
}
