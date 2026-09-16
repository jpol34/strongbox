function Pull-StrongboxSecret {
    <#
    .SYNOPSIS
        Pulls -Name (or every already-synced manifest entry) from the sync server into the local
        vault and manifest.
    .DESCRIPTION
        Decrypts with the sync passphrase and writes the value with Set-Secret, keyed by the
        server's version rather than merely by presence - unlike Import-StrongboxBackup, this
        always overwrites the local value with the server's, since sync's whole point is
        convergence, not backup's "never clobber what's already there" caution.
    .PARAMETER Name
        Pull only this one secret (resolved in the current project's context, same as
        Get-StrongboxSecret - a project-scoped entry shadows a global one of the same name),
        instead of every manifest entry with synced: true.
    .PARAMETER Scope
        Pull explicitly from this scope instead of auto-detecting it from an existing manifest
        entry. Needed the first time a device pulls a project-scoped secret it has never seen
        before - with no local entry to infer scope from, auto-detection can only assume global.
    .PARAMETER Project
        The project slug for -Scope project. Defaults to the current repo (same resolution as
        Set-StrongboxSecret) when not given.
    #>
    param(
        [string] $Name,
        [ValidateSet('global', 'project')][string] $Scope,
        [string] $Project
    )
    Assert-StrongboxVault
    $ctx = Get-StrongboxSyncContext
    $manifestPath = Get-StrongboxManifestPath
    $manifest = @(Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json)

    $targets = if ($Name) {
        if ($Scope) {
            if ($Scope -eq 'project' -and -not $Project) { $Project = Resolve-StrongboxProjectScope }
            if ($Scope -eq 'project' -and -not $Project) { throw "Pull-StrongboxSecret: -Scope project requires -Project, or being run inside a git repo to infer it." }
            $resolvedScope = $Scope
            $resolvedProject = if ($Scope -eq 'project') { $Project } else { $null }
            $internalName = Resolve-StrongboxSecretStoreName -Name $Name -Scope $resolvedScope -Project $resolvedProject
        } else {
            $target = Resolve-StrongboxSecretTarget -Name $Name
            $resolvedScope = $target.Scope
            $resolvedProject = $target.Project
            $internalName = $target.InternalName
        }
        $existing = if ($resolvedScope -eq 'project') {
            $manifest | Where-Object { $_.newName -eq $Name -and $_.scope -eq 'project' -and $_.project -eq $resolvedProject } | Select-Object -First 1
        } else {
            $manifest | Where-Object { $_.newName -eq $Name -and (-not $_.scope -or $_.scope -eq 'global') } | Select-Object -First 1
        }
        @([pscustomobject]@{ Name = $Name; Scope = $resolvedScope; Project = $resolvedProject; InternalName = $internalName; Existing = $existing })
    } else {
        # Iterate the actual synced entries, not deduplicated names - a global and a
        # project-scoped entry can share a newName and both be synced independently.
        @($manifest | Where-Object { $_.synced -eq $true } | ForEach-Object {
            $resolved = Resolve-StrongboxManifestScope -Entry $_
            [pscustomobject]@{
                Name         = $_.newName
                Scope        = $resolved.Scope
                Project      = $resolved.Project
                InternalName = Resolve-StrongboxSecretStoreName -Name $_.newName -Scope $resolved.Scope -Project $resolved.Project
                Existing     = $_
            }
        })
    }

    $pulled = 0
    foreach ($t in $targets) {
        $uri = "$($ctx.ServerUrl)/secrets/$($t.Name)`?scope=$($t.Scope)"
        if ($t.Project) { $uri += "&project=$($t.Project)" }
        try {
            $remote = Invoke-RestMethod -Uri $uri -Headers @{ Authorization = "Bearer $($ctx.DeviceToken)" } -ErrorAction Stop
        } catch {
            if ($_.Exception.Response.StatusCode.value__ -eq 404) {
                [Console]::Error.WriteLine("Pull-StrongboxSecret: '$($t.Name)' not found on the server, skipping.")
                continue
            }
            throw
        }

        $value = Unprotect-StrongboxSyncValue -Envelope $remote -Passphrase $ctx.Passphrase
        Set-Secret -Name $t.InternalName -Secret $value -Vault $script:StrongboxVaultName
        Set-SecretInfo -Name $t.InternalName -Vault $script:StrongboxVaultName -Metadata @{ LastRotated = (Get-Date).ToUniversalTime().ToString('o') }

        if ($t.Existing) {
            $t.Existing | Add-Member -NotePropertyName synced -NotePropertyValue $true -Force
            $t.Existing | Add-Member -NotePropertyName syncVersion -NotePropertyValue $remote.version -Force
            $t.Existing | Add-Member -NotePropertyName syncedAt -NotePropertyValue (Get-Date).ToUniversalTime().ToString('o') -Force
        } else {
            $entry = [ordered]@{
                oldName     = $t.Name
                newName     = $t.Name
                usedBy      = @('synced')
                purpose     = ''
                status      = 'keep'
                synced      = $true
                syncVersion = $remote.version
                syncedAt    = (Get-Date).ToUniversalTime().ToString('o')
            }
            # A brand-new project-scoped entry must record its scope/project explicitly - left
            # absent, it would silently normalize to global (Resolve-StrongboxManifestScope's
            # default) the next time anything reads the manifest.
            if ($t.Scope -eq 'project') {
                $entry.scope = 'project'
                $entry.project = $t.Project
            }
            $manifest += [pscustomobject]$entry
        }
        $pulled++
        # Persist after every secret - if a later one in this run fails, the ones already
        # pulled must not revert to a stale local syncVersion on the next status/push.
        $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath
    }

    Write-Host "Pulled $pulled secret(s)."
}
