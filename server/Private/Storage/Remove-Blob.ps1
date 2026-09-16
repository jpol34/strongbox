function Remove-Blob {
    <#
    .SYNOPSIS
        Deletes one secret's stored envelope by (name, scope, project). Returns $false if it
        didn't exist.
    #>
    param(
        [Parameter(Mandatory)][string] $DbPath,
        [Parameter(Mandatory)][string] $Name,
        [string] $Scope = 'global',
        [string] $Project = ''
    )
    $existing = Invoke-SqliteQuery -DataSource $DbPath -Query `
        'SELECT id FROM secrets WHERE name = @name AND scope = @scope AND project = @project' `
        -SqlParameters @{ name = $Name; scope = $Scope; project = $Project }
    if (-not $existing) { return $false }
    Invoke-SqliteQuery -DataSource $DbPath -Query `
        'DELETE FROM secrets WHERE name = @name AND scope = @scope AND project = @project' `
        -SqlParameters @{ name = $Name; scope = $Scope; project = $Project }
    return $true
}
