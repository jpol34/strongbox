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
        Pull only this one secret, instead of every manifest entry with synced: true.
    #>
    param(
        [string] $Name
    )
    Assert-StrongboxVault
    $ctx = Get-StrongboxSyncContext
    $manifestPath = Get-StrongboxManifestPath
    $manifest = @(Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json)

    $names = if ($Name) {
        @($Name)
    } else {
        @($manifest | Where-Object { $_.synced -eq $true } | Select-Object -ExpandProperty newName -Unique)
    }

    $pulled = 0
    foreach ($n in $names) {
        $existing = $manifest | Where-Object { $_.newName -eq $n -and -not ($_.scope -eq 'project' -and $_.project) } | Select-Object -First 1
        $scope = if ($existing -and $existing.scope) { $existing.scope } else { 'global' }
        $project = if ($scope -eq 'project') { $existing.project } else { $null }

        $uri = "$($ctx.ServerUrl)/secrets/$n`?scope=$scope"
        if ($project) { $uri += "&project=$project" }
        try {
            $remote = Invoke-RestMethod -Uri $uri -Headers @{ Authorization = "Bearer $($ctx.DeviceToken)" } -ErrorAction Stop
        } catch {
            if ($_.Exception.Response.StatusCode.value__ -eq 404) {
                [Console]::Error.WriteLine("Pull-StrongboxSecret: '$n' not found on the server, skipping.")
                continue
            }
            throw
        }

        $value = Unprotect-StrongboxSyncValue -Envelope $remote -Passphrase $ctx.Passphrase
        $internalName = Resolve-StrongboxSecretStoreName -Name $n -Scope $scope -Project $project
        Set-Secret -Name $internalName -Secret $value -Vault $script:StrongboxVaultName
        Set-SecretInfo -Name $internalName -Vault $script:StrongboxVaultName -Metadata @{ LastRotated = (Get-Date).ToUniversalTime().ToString('o') }

        if ($existing) {
            $existing | Add-Member -NotePropertyName synced -NotePropertyValue $true -Force
            $existing | Add-Member -NotePropertyName syncVersion -NotePropertyValue $remote.version -Force
            $existing | Add-Member -NotePropertyName syncedAt -NotePropertyValue (Get-Date).ToUniversalTime().ToString('o') -Force
        } else {
            $entry = [ordered]@{
                oldName     = $n
                newName     = $n
                usedBy      = @('synced')
                purpose     = ''
                status      = 'keep'
                synced      = $true
                syncVersion = $remote.version
                syncedAt    = (Get-Date).ToUniversalTime().ToString('o')
            }
            $manifest += [pscustomobject]$entry
        }
        $pulled++
    }

    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath
    Write-Host "Pulled $pulled secret(s)."
}
