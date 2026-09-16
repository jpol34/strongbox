function Get-Blob {
    <#
    .SYNOPSIS
        Fetches one secret's stored envelope and metadata by (name, scope, project).
    #>
    param(
        [Parameter(Mandatory)][string] $DbPath,
        [Parameter(Mandatory)][string] $Name,
        [string] $Scope = 'global',
        [string] $Project = ''
    )
    $row = Invoke-SqliteQuery -DataSource $DbPath -Query `
        'SELECT * FROM secrets WHERE name = @name AND scope = @scope AND project = @project' `
        -SqlParameters @{ name = $Name; scope = $Scope; project = $Project }
    if (-not $row) { return $null }
    [pscustomobject]@{
        name       = $row.name
        scope      = $row.scope
        project    = if ($row.project) { $row.project } else { $null }
        version    = [int]$row.version
        deviceId   = $row.device_id
        salt       = $row.salt
        nonce      = $row.nonce
        tag        = $row.tag
        ciphertext = $row.ciphertext
        updatedAt  = $row.updated_at
    }
}
