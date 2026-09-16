function Export-StrongboxSecretUserSecrets {
    <#
    .SYNOPSIS
        Fan vault secrets into dotnet user-secrets for a project.
    .PARAMETER Map
        Hashtable of ConfigurationKey = SecretName.
    #>
    param(
        [Parameter(Mandatory)][string] $Project,
        [Parameter(Mandatory)][hashtable] $Map
    )
    foreach ($configKey in $Map.Keys) {
        $value = Get-StrongboxSecret -Name $Map[$configKey]
        & dotnet user-secrets set $configKey $value --project $Project | Out-Null
        Write-Host "Set user secret: $configKey (from $($Map[$configKey]))"
    }
}
