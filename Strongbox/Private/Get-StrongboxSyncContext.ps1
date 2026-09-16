function Get-StrongboxSyncContext {
    <#
    .SYNOPSIS
        Reads the server URL, device token, and sync passphrase cached by Initialize-StrongboxSync.
    .DESCRIPTION
        Throws a setup-hint error if any piece of the cache is missing, so a deleted/never-created
        cache fails with a clear next step rather than a confusing downstream HTTP error.
    #>
    $serverUrlPath = Get-StrongboxSyncCachePath -Item ServerUrl
    $tokenPath = Get-StrongboxSyncCachePath -Item DeviceToken
    $passphrasePath = Get-StrongboxSyncCachePath -Item Passphrase
    if (-not (Test-Path -LiteralPath $serverUrlPath) -or -not (Test-Path -LiteralPath $tokenPath) -or -not (Test-Path -LiteralPath $passphrasePath)) {
        throw "Strongbox sync isn't initialized (or its cache was deleted). Run 'strongbox sync init <server-url>' first."
    }
    [pscustomobject]@{
        ServerUrl   = (Get-Content -LiteralPath $serverUrlPath -Raw).Trim()
        DeviceToken = (Get-Content -LiteralPath $tokenPath -Raw).Trim()
        Passphrase  = (Get-Content -LiteralPath $passphrasePath -Raw).Trim() | ConvertTo-SecureString
    }
}
