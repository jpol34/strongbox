function Set-StrongboxManifestEntry {
    <#
    .SYNOPSIS
        Upserts a manifest.json entry for a secret name/scope, so it shows up in
        Get-StrongboxSecretList / the web UI.
    .DESCRIPTION
        Matched the same way Pull-StrongboxSecret finds-or-creates an entry: by newName plus
        scope/project, since a global and a project-scoped entry can legitimately share a
        newName. Only called from Set-StrongboxSecret when -Purpose is supplied - callers that
        don't pass -Purpose leave manifest.json untouched entirely, so a script writing an
        ad-hoc secret doesn't silently become a tracked, UI-visible entry.
    #>
    param(
        [Parameter(Mandatory)][string] $Name,
        [ValidateSet('global', 'project')][string] $Scope = 'global',
        [string] $Project,
        [Parameter(Mandatory)][string] $Purpose,
        [string] $UsedBy,
        [int] $RotationDays
    )
    $manifestPath = Get-StrongboxManifestPath
    $manifest = @(Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json)

    $existing = if ($Scope -eq 'project') {
        $manifest | Where-Object { $_.newName -eq $Name -and $_.scope -eq 'project' -and $_.project -eq $Project } | Select-Object -First 1
    } else {
        $manifest | Where-Object { $_.newName -eq $Name -and (-not $_.scope -or $_.scope -eq 'global') } | Select-Object -First 1
    }

    if ($existing) {
        $existing | Add-Member -NotePropertyName purpose -NotePropertyValue $Purpose -Force
        if ($UsedBy) { $existing | Add-Member -NotePropertyName usedBy -NotePropertyValue $UsedBy -Force }
        if ($RotationDays) { $existing | Add-Member -NotePropertyName rotationDays -NotePropertyValue $RotationDays -Force }
        $existing | Add-Member -NotePropertyName status -NotePropertyValue 'keep' -Force
    } else {
        $entry = [ordered]@{
            oldName = $Name
            newName = $Name
            usedBy  = if ($UsedBy) { $UsedBy } else { @() }
            purpose = $Purpose
            status  = 'keep'
        }
        if ($RotationDays) { $entry.rotationDays = $RotationDays }
        if ($Scope -eq 'project') {
            $entry.scope = 'project'
            $entry.project = $Project
        }
        $manifest += [pscustomobject]$entry
    }

    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath
}
