function Invoke-SqliteQuery {
    <#
    .SYNOPSIS
        Runs a SQL statement against either a fresh connection (-DataSource) or a caller-held
        open connection (-SQLiteConnection), returning rows as PSCustomObjects.
    .DESCRIPTION
        -DataSource opens and closes its own connection for the call; -SQLiteConnection reuses a
        connection the caller already holds open (Put-Blob.ps1 uses this to keep several calls
        inside one BEGIN IMMEDIATE/COMMIT transaction). Backed by the libsqlite3 P/Invoke wrapper
        in New-SQLiteConnection.ps1.
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
