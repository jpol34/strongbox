function Resolve-StrongboxSecretTarget {
    <#
    .SYNOPSIS
        Resolves a logical secret name to the vault entry that applies right now.
    .DESCRIPTION
        A project-scoped entry named $Name shadows a global entry of the same name while the
        caller is inside that project, exactly like Set-StrongboxSecret's own doc describes -
        checked by probing the vault directly for "$Name::<projectSlug>" (via Get-SecretInfo, no
        decryption), so this works the moment Set-StrongboxSecret writes it, independent of the
        cloud-sync manifest. The manifest (see Get-StrongboxManifestPath) only tracks what's been
        synced; a purely local project-scoped secret that was never pushed/pulled has no manifest
        entry at all, and previously fell back to global-only resolution and could never be
        retrieved by its project-scoped name. Everywhere else (no project, or no project-scoped
        entry in the vault) the global entry - or, absent any vault entry, the name itself
        unchanged - applies.
    #>
    param(
        [Parameter(Mandatory)][string] $Name
    )

    $projectSlug = Resolve-StrongboxProjectScope
    if ($projectSlug) {
        $projectInternalName = Resolve-StrongboxSecretStoreName -Name $Name -Scope 'project' -Project $projectSlug
        $projectInfo = Get-SecretInfo -Name $projectInternalName -Vault $script:StrongboxVaultName -ErrorAction SilentlyContinue
        if ($projectInfo) {
            return [pscustomobject]@{
                Scope        = 'project'
                Project      = $projectSlug
                InternalName = $projectInternalName
            }
        }
    }

    return [pscustomobject]@{
        Scope        = 'global'
        Project      = $null
        InternalName = Resolve-StrongboxSecretStoreName -Name $Name -Scope 'global'
    }
}
