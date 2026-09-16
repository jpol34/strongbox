function Get-BlobMetadataList {
    <#
    .SYNOPSIS
        Lists every stored secret's metadata only - never salt/nonce/tag/ciphertext. Backs the
        zero-knowledge GET /secrets endpoint.
    #>
    param([Parameter(Mandatory)][string] $DbPath)
    $rows = Invoke-SqliteQuery -DataSource $DbPath -Query `
        'SELECT name, scope, project, version, device_id, updated_at FROM secrets ORDER BY name, scope, project'
    @($rows | ForEach-Object {
        [pscustomobject]@{
            name      = $_.name
            scope     = $_.scope
            project   = if ($_.project) { $_.project } else { $null }
            version   = [int]$_.version
            deviceId  = $_.device_id
            updatedAt = $_.updated_at
        }
    })
}
