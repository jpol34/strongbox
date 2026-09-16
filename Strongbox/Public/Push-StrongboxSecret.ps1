function Push-StrongboxSecret {
    <#
    .SYNOPSIS
        Pushes every synced:true manifest entry (or just -Name) to the sync server.
    .DESCRIPTION
        Compare-and-swap against the server's stored version: a stale local syncVersion is
        hard-refused with a "pull first" message, never silently overwritten. On success, updates
        the manifest entry's synced/syncVersion/syncedAt fields.
    .PARAMETER Name
        Push only this one secret (must already be synced: true), instead of every synced entry.
    #>
    param(
        [string] $Name
    )
    Assert-StrongboxVault
    $ctx = Get-StrongboxSyncContext
    $manifestPath = Get-StrongboxManifestPath
    $manifest = @(Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json)

    $targets = $manifest | Where-Object {
        $_.synced -eq $true -and $_.status -in 'keep', 'keep-unverified' -and (-not $Name -or $_.newName -eq $Name)
    }
    if ($Name -and -not $targets) {
        throw "Push-StrongboxSecret: no synced:true manifest entry named '$Name'."
    }

    $pushed = 0
    foreach ($entry in $targets) {
        $resolved = Resolve-StrongboxManifestScope -Entry $entry
        $scope = $resolved.Scope
        $project = $resolved.Project
        $internalName = Resolve-StrongboxSecretStoreName -Name $entry.newName -Scope $scope -Project $project

        $value = Get-Secret -Name $internalName -Vault $script:StrongboxVaultName -AsPlainText -ErrorAction Stop
        $envelope = Protect-StrongboxSyncValue -Value $value -Passphrase $ctx.Passphrase
        $expectedVersion = if ($entry.syncVersion) { [int]$entry.syncVersion } else { 0 }

        $body = @{
            scope           = $scope
            expectedVersion = $expectedVersion
            salt            = $envelope.salt
            nonce           = $envelope.nonce
            tag             = $envelope.tag
            ciphertext      = $envelope.ciphertext
        }
        if ($project) { $body.project = $project }

        try {
            $result = Invoke-RestMethod -Uri "$($ctx.ServerUrl)/secrets/$($entry.newName)" -Method Post `
                -Headers @{ Authorization = "Bearer $($ctx.DeviceToken)" } -Body ($body | ConvertTo-Json) `
                -ContentType 'application/json' -ErrorAction Stop
        } catch {
            if ($_.Exception.Response.StatusCode.value__ -eq 409) {
                throw "Push-StrongboxSecret: '$($entry.newName)' is out of date on the server - run 'sync pull' first."
            }
            throw
        }

        $entry | Add-Member -NotePropertyName synced -NotePropertyValue $true -Force
        $entry | Add-Member -NotePropertyName syncVersion -NotePropertyValue $result.version -Force
        $entry | Add-Member -NotePropertyName syncedAt -NotePropertyValue (Get-Date).ToUniversalTime().ToString('o') -Force
        $pushed++
        # Persist after every secret, not just at the end - if a later secret in this run fails,
        # the ones already accepted by the server must not revert to a stale local syncVersion
        # (which would otherwise cause a spurious 409 on the next push).
        $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath
    }

    Write-Host "Pushed $pushed secret(s)."
}
