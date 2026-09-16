function Test-Strongbox {
    <#
    .SYNOPSIS
        Drift check: confirms manifest.json and the vault agree on what secrets exist.
    .DESCRIPTION
        Exits non-zero (via throw) on any drift: a manifest entry with no matching vault secret,
        or a vault secret with no matching manifest entry.
    #>
    Assert-StrongboxVault
    $manifest = Get-Content (Get-StrongboxManifestPath) -Raw | ConvertFrom-Json
    $keepEntries = $manifest | Where-Object { $_.status -in 'keep', 'keep-unverified' }
    $manifestNames = @($keepEntries.newName)

    $vaultNames = @((Get-SecretInfo -Vault $script:StrongboxVaultName).Name)

    # A manifest entry's oldName, if set, just documents what this secret used to be called
    # before a rename - it's still a "known" name even though it's not what's actually stored
    # under anymore, so it doesn't count as vault/manifest drift on its own.
    $knownNames = @($manifestNames) + @($manifest.oldName) | Where-Object { $_ } | Select-Object -Unique

    $problems = @()

    foreach ($n in $manifestNames) {
        if ($n -notin $vaultNames) { $problems += "In manifest but missing from vault: $n" }
    }

    foreach ($n in $vaultNames) {
        if ($n -notin $knownNames) { $problems += "In vault but missing from manifest: $n" }
    }

    if ($problems.Count -gt 0) {
        $problems | ForEach-Object { [Console]::Error.WriteLine("DRIFT: $_") }
        throw "Test-Strongbox found $($problems.Count) drift issue(s)."
    }

    Write-Host "Test-Strongbox: no drift found ($($manifestNames.Count) secrets)."
}
