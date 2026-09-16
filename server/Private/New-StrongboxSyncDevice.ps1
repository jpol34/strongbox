function New-StrongboxSyncDevice {
    <#
    .SYNOPSIS
        Registers a new device and returns its bearer token.
    .DESCRIPTION
        The raw token is only ever available here, at registration time - only its hash is
        stored, so it can't be recovered from the database afterward. Losing it means
        re-registering the device.
    #>
    param(
        [Parameter(Mandatory)][string] $DbPath,
        [Parameter(Mandatory)][string] $DeviceName
    )
    $deviceId = [guid]::NewGuid().ToString()
    $tokenBytes = [byte[]]::new(32)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($tokenBytes)
    $token = [Convert]::ToBase64String($tokenBytes)
    $tokenHash = Get-StrongboxSyncTokenHash -Token $token

    Invoke-SqliteQuery -DataSource $DbPath -Query `
        'INSERT INTO devices (id, name, token_hash, created_at) VALUES (@id, @name, @hash, @createdAt)' `
        -SqlParameters @{
            id        = $deviceId
            name      = $DeviceName
            hash      = $tokenHash
            createdAt = (Get-Date).ToUniversalTime().ToString('o')
        }

    [pscustomobject]@{ deviceId = $deviceId; token = $token }
}
