function Put-Blob {
    <#
    .SYNOPSIS
        Compare-and-swap write of one secret's envelope.
    .DESCRIPTION
        Never overwrites a version the caller hasn't seen - a mismatched ExpectedVersion is a
        conflict the caller reports as 409, not an exception. A secret that doesn't exist yet has
        an implicit version of 0, so the first push for a name must pass -ExpectedVersion 0.
    #>
    param(
        [Parameter(Mandatory)][string] $DbPath,
        [Parameter(Mandatory)][string] $Name,
        [string] $Scope = 'global',
        [string] $Project = '',
        [Parameter(Mandatory)][int] $ExpectedVersion,
        [Parameter(Mandatory)][string] $DeviceId,
        [Parameter(Mandatory)][string] $Salt,
        [Parameter(Mandatory)][string] $Nonce,
        [Parameter(Mandatory)][string] $Tag,
        [Parameter(Mandatory)][string] $Ciphertext
    )
    $existing = Invoke-SqliteQuery -DataSource $DbPath -Query `
        'SELECT version FROM secrets WHERE name = @name AND scope = @scope AND project = @project' `
        -SqlParameters @{ name = $Name; scope = $Scope; project = $Project }

    $currentVersion = if ($existing) { [int]$existing.version } else { 0 }
    if ($currentVersion -ne $ExpectedVersion) {
        return [pscustomobject]@{ conflict = $true; version = $currentVersion }
    }

    $newVersion = $currentVersion + 1
    $updatedAt = (Get-Date).ToUniversalTime().ToString('o')
    $params = @{
        name      = $Name
        scope     = $Scope
        project   = $Project
        version   = $newVersion
        deviceId  = $DeviceId
        salt      = $Salt
        nonce     = $Nonce
        tag       = $Tag
        ciphertext = $Ciphertext
        updatedAt = $updatedAt
    }
    if ($existing) {
        Invoke-SqliteQuery -DataSource $DbPath -Query @'
UPDATE secrets SET version = @version, device_id = @deviceId, salt = @salt, nonce = @nonce,
    tag = @tag, ciphertext = @ciphertext, updated_at = @updatedAt
WHERE name = @name AND scope = @scope AND project = @project
'@ -SqlParameters $params
    } else {
        Invoke-SqliteQuery -DataSource $DbPath -Query @'
INSERT INTO secrets (name, scope, project, version, device_id, salt, nonce, tag, ciphertext, updated_at)
VALUES (@name, @scope, @project, @version, @deviceId, @salt, @nonce, @tag, @ciphertext, @updatedAt)
'@ -SqlParameters $params
    }
    return [pscustomobject]@{ conflict = $false; version = $newVersion }
}
