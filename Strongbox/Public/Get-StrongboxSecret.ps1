function Get-StrongboxSecret {
    <#
    .SYNOPSIS
        Read a plaintext secret from the Strongbox vault.
    .PARAMETER Optional
        Return $null instead of throwing when the secret is missing.
    #>
    param(
        [Parameter(Mandatory)][string] $Name,
        [switch] $Optional
    )
    Assert-StrongboxVault
    try {
        $value = Get-Secret -Name $Name -Vault $script:StrongboxVaultName -AsPlainText -ErrorAction Stop
        if ([string]::IsNullOrEmpty($value)) { throw "empty" }
        return [string]$value
    } catch {
        if ($Optional) { return $null }
        [Console]::Error.WriteLine("Strongbox: missing or unreadable secret '$Name' in vault '$script:StrongboxVaultName'.")
        throw
    }
}
