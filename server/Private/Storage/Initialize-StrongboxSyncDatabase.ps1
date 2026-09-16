function Initialize-StrongboxSyncDatabase {
    <#
    .SYNOPSIS
        Creates the sync server's SQLite schema if it doesn't already exist. Safe to call on
        every boot.
    #>
    param([Parameter(Mandatory)][string] $DbPath)
    # WAL lets readers proceed while a writer holds the Put-Blob/Remove-Blob transaction open;
    # busy_timeout makes a second writer wait for that transaction instead of failing immediately
    # with "database is locked".
    Invoke-SqliteQuery -DataSource $DbPath -Query 'PRAGMA journal_mode = WAL; PRAGMA busy_timeout = 5000;'
    $query = @'
CREATE TABLE IF NOT EXISTS secrets (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    scope TEXT NOT NULL,
    project TEXT NOT NULL DEFAULT '',
    version INTEGER NOT NULL,
    device_id TEXT NOT NULL,
    salt TEXT NOT NULL,
    nonce TEXT NOT NULL,
    tag TEXT NOT NULL,
    ciphertext TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    UNIQUE(name, scope, project)
);

CREATE TABLE IF NOT EXISTS devices (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    token_hash TEXT NOT NULL UNIQUE,
    created_at TEXT NOT NULL
);
'@
    Invoke-SqliteQuery -DataSource $DbPath -Query $query
}
