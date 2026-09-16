function Get-StrongboxSyncStatus {
    <#
    .SYNOPSIS
        Lists every synced secret with its local vs. remote version, flagging drift - a
        metadata-only dry run against GET /secrets that never changes anything.
    #>
    Assert-StrongboxVault
    $ctx = Get-StrongboxSyncContext
    $manifestPath = Get-StrongboxManifestPath
    $manifest = @(Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json)
    $synced = $manifest | Where-Object { $_.synced -eq $true }

    $remoteList = Invoke-RestMethod -Uri "$($ctx.ServerUrl)/secrets" -Headers @{ Authorization = "Bearer $($ctx.DeviceToken)" } -ErrorAction Stop
    $remoteByKey = @{}
    foreach ($r in $remoteList) {
        $remoteByKey["$($r.name)|$($r.scope)|$($r.project)"] = $r
    }

    foreach ($e in $synced) {
        $resolved = Resolve-StrongboxManifestScope -Entry $e
        $scope = $resolved.Scope
        $project = $resolved.Project
        $localVersion = if ($e.syncVersion) { [int]$e.syncVersion } else { 0 }
        $remote = $remoteByKey["$($e.newName)|$scope|$project"]

        $drift = if (-not $remote) {
            'missing-on-server'
        } elseif ([int]$remote.version -ne $localVersion) {
            'out-of-sync'
        } else {
            'in-sync'
        }

        [pscustomobject]@{
            Name          = $e.newName
            Scope         = $scope
            Project       = $project
            LocalVersion  = $localVersion
            RemoteVersion = if ($remote) { [int]$remote.version } else { $null }
            Drift         = $drift
        }
    }
}
