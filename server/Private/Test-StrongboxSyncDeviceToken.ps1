function Test-StrongboxSyncDeviceToken {
    <#
    .SYNOPSIS
        Resolves a presented bearer token to its registered device, or $null if it doesn't
        match any stored (hashed) token.
    #>
    param(
        [Parameter(Mandatory)][string] $DbPath,
        [Parameter(Mandatory)][string] $Token
    )
    $hash = Get-StrongboxSyncTokenHash -Token $Token
    $device = Invoke-SqliteQuery -DataSource $DbPath -Query `
        'SELECT id, name FROM devices WHERE token_hash = @hash' -SqlParameters @{ hash = $hash }
    if (-not $device) { return $null }
    [pscustomobject]@{ deviceId = $device.id; deviceName = $device.name }
}
