function Resolve-StrongboxSecretTarget {
    <#
    .SYNOPSIS
        Resolves a logical secret name to the manifest-scoped entry that applies right now.
    .DESCRIPTION
        A project-scoped manifest entry named $Name shadows a global entry of the same name while
        the caller is inside that entry's project; everywhere else (including when the manifest
        has no matching entry at all, e.g. manifest.json doesn't exist yet) the global entry - or,
        absent any manifest entry, the name itself unchanged - applies.
    #>
    param(
        [Parameter(Mandatory)][string] $Name
    )

    $manifest = @()
    $manifestPath = Get-StrongboxManifestPath
    if (Test-Path -LiteralPath $manifestPath) {
        $manifest = @(Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json)
    }

    $projectSlug = Resolve-StrongboxProjectScope
    if ($projectSlug) {
        $projectEntry = $manifest | Where-Object {
            $_.newName -eq $Name -and $_.scope -eq 'project' -and $_.project -eq $projectSlug
        } | Select-Object -First 1
        if ($projectEntry) {
            return [pscustomobject]@{
                Scope        = 'project'
                Project      = $projectSlug
                InternalName = Resolve-StrongboxSecretStoreName -Name $Name -Scope 'project' -Project $projectSlug
            }
        }
    }

    return [pscustomobject]@{
        Scope        = 'global'
        Project      = $null
        InternalName = Resolve-StrongboxSecretStoreName -Name $Name -Scope 'global'
    }
}
