function Set-StrongboxSecret {
    <#
    .SYNOPSIS
        Write a secret to the Strongbox vault, stamping LastRotated metadata on every call.
    .PARAMETER Scope
        'Global' (the default) writes under $Name unchanged. 'Project' writes a project-scoped
        secret that shadows any global entry of the same name while inside that project.
    .PARAMETER Project
        The project slug for -Scope Project. Defaults to the current repo, resolved the same way
        Get/Remove-StrongboxSecret do, when not given.
    .PARAMETER Purpose
        When given, registers/updates this secret's manifest.json entry so it appears in
        Get-StrongboxSecretList / the web UI. Omit to leave manifest.json untouched entirely -
        the secret is still written and retrievable, just not listed, so a script writing an
        ad-hoc secret doesn't silently become a tracked, UI-visible entry.
    .PARAMETER UsedBy
        Recorded alongside -Purpose in the manifest entry. Ignored if -Purpose is not given.
    #>
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Value,
        [string] $Owner,
        [int] $RotationDays,
        [ValidateSet('Global', 'Project')][string] $Scope = 'Global',
        [string] $Project,
        [string] $Purpose,
        [string] $UsedBy
    )
    Assert-StrongboxVault

    $internalName = $Name
    if ($Scope -eq 'Project') {
        if (-not $Project) { $Project = Resolve-StrongboxProjectScope }
        if (-not $Project) { throw "Set-StrongboxSecret: -Scope Project requires -Project, or being run inside a git repo to infer it." }
        $internalName = Resolve-StrongboxSecretStoreName -Name $Name -Scope 'project' -Project $Project
    }

    Set-Secret -Name $internalName -Secret $Value -Vault $script:StrongboxVaultName

    $metadata = @{ LastRotated = (Get-Date).ToUniversalTime().ToString('o') }
    if ($Owner) { $metadata.Owner = $Owner }
    if ($RotationDays) { $metadata.RotationDays = $RotationDays }
    Set-SecretInfo -Name $internalName -Vault $script:StrongboxVaultName -Metadata $metadata

    if ($Purpose) {
        Set-StrongboxManifestEntry -Name $Name -Scope $Scope.ToLower() -Project $Project `
            -Purpose $Purpose -UsedBy $UsedBy -RotationDays $RotationDays
    }
}
