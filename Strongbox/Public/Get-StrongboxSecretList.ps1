function Get-StrongboxSecretList {
    <#
    .SYNOPSIS
        Lists every tracked secret's name, owner, purpose, rotation policy, and staleness -
        never values. The CLI equivalent of what the web UI's table shows.
    .DESCRIPTION
        Joins manifest.json (name/owner/purpose/rotationDays) against the vault's metadata
        (LastRotated) with a single bulk Get-SecretInfo call rather than one call per secret
        name: each -Name-filtered call scans the whole vault instead of doing an indexed lookup,
        so a per-name loop scales linearly with vault size for no benefit.
    #>
    Assert-StrongboxVault
    $manifest = Get-Content (Get-StrongboxManifestPath) -Raw | ConvertFrom-Json
    $entries = $manifest | Where-Object { $_.status -in 'keep', 'keep-unverified' }

    $infoByName = @{}
    foreach ($i in (Get-SecretInfo -Vault $script:StrongboxVaultName)) { $infoByName[$i.Name] = $i }

    foreach ($e in $entries) {
        $info = $infoByName[$e.newName]
        $lastRotated = $info.Metadata.LastRotated
        $rotationDays = $e.rotationDays
        $stale = $false
        if ($lastRotated -and $rotationDays) {
            $stale = ((Get-Date) - [datetime]$lastRotated).TotalDays -gt $rotationDays
        }
        [pscustomobject]@{
            Name = $e.newName
            Owner = $e.newName.Split('.')[0]
            Purpose = $e.purpose
            UsedBy = $e.usedBy
            RotationDays = $rotationDays
            LastRotated = $lastRotated
            Stale = $stale
        }
    }
}
