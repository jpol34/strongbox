function Import-StrongboxSecretEnv {
    <#
    .SYNOPSIS
        Set process-scoped environment variables from the vault.
    .PARAMETER Map
        Hashtable of EnvVarName = SecretName.
    #>
    param(
        [Parameter(Mandatory)][hashtable] $Map
    )
    foreach ($envVar in $Map.Keys) {
        $value = Get-StrongboxSecret -Name $Map[$envVar]
        [System.Environment]::SetEnvironmentVariable($envVar, $value, 'Process')
    }
}
