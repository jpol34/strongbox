function Resolve-StrongboxSecretStoreName {
    <#
    .SYNOPSIS
        Maps a logical secret name + scope to the actual name it's stored under in SecretStore.
    .DESCRIPTION
        Global-scoped names (the default) pass through unchanged, so nothing about existing
        secrets or callers changes. Project-scoped names are joined with the project slug via
        '::', a separator not confirmed safe against every SecretStore character restriction by a
        live test in this environment - swap it out here if that's ever verified otherwise.
    #>
    param(
        [Parameter(Mandatory)][string] $Name,
        [string] $Scope = 'global',
        [string] $Project
    )
    if ($Scope -eq 'project') {
        if (-not $Project) { throw "Resolve-StrongboxSecretStoreName: -Project is required when -Scope is 'project'." }
        return "$Name::$Project"
    }
    return $Name
}
