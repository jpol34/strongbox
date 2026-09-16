function Invoke-SqliteQuery {
    <#
    .SYNOPSIS
        Runs a SQL statement against either a fresh connection (-DataSource) or a caller-held
        open connection (-SQLiteConnection), returning rows as PSCustomObjects.
    .DESCRIPTION
        Same call shape the storage layer already used against PSSQLite (-DataSource/
        -SQLiteConnection/-Query/-SqlParameters), backed instead by the direct libsqlite3
        P/Invoke wrapper in New-SQLiteConnection.ps1 - Get-Blob.ps1/Put-Blob.ps1/Remove-Blob.ps1/
        Get-BlobMetadataList.ps1/Initialize-StrongboxSyncDatabase.ps1 needed no changes.
    #>
    param(
        [string] $DataSource,
        [object] $SQLiteConnection,
        [Parameter(Mandatory)][string] $Query,
        [hashtable] $SqlParameters
    )
    $ownsConnection = $false
    if ($SQLiteConnection) {
        $db = $SQLiteConnection.Handle
    } else {
        $ownsConnection = $true
        $db = [Strongbox.Sqlite.Helper]::Open($DataSource)
    }
    try {
        if ($SqlParameters -and $SqlParameters.Count -gt 0) {
            $rows = [Strongbox.Sqlite.Helper]::ExecuteQuery($db, $Query, $SqlParameters)
        } else {
            $rows = [Strongbox.Sqlite.Helper]::ExecuteNonQuery($db, $Query)
        }
    } finally {
        if ($ownsConnection) { [Strongbox.Sqlite.Helper]::Close($db) }
    }
    foreach ($row in $rows) { [pscustomobject]$row }
}
