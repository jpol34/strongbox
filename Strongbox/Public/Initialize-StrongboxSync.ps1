function Initialize-StrongboxSync {
    <#
    .SYNOPSIS
        Registers this device against a Strongbox sync server and caches sync credentials.
    .DESCRIPTION
        Caches the sync passphrase and the issued device token in ~/.strongbox/ (outside the git
        checkout, so they survive a repo re-clone or deletion). Re-running this after the cache
        has been deleted re-registers the device and re-caches everything from scratch, the same
        way the local UI regenerates .token when it's missing.
    .PARAMETER ServerUrl
        The sync server's base URL, e.g. http://127.0.0.1:8080.
    .PARAMETER DeviceName
        A label for this device, shown in the server's device list.
    .PARAMETER SyncPassphrase
        A SecureString passphrase, dedicated to sync - separate from SecretStore's own vault
        config and from the backup passphrase. You'll need this exact passphrase on every other
        device that syncs the same secrets.
    .PARAMETER BootstrapToken
        The server's admin bootstrap token (obtained out-of-band from whoever runs the server -
        see docs/SYNC-API.md). Only needed for this one-time registration call.
    #>
    param(
        [Parameter(Mandatory)][string] $ServerUrl,
        [Parameter(Mandatory)][string] $DeviceName,
        [Parameter(Mandatory)][System.Security.SecureString] $SyncPassphrase,
        [Parameter(Mandatory)][System.Security.SecureString] $BootstrapToken
    )
    $ServerUrl = $ServerUrl.TrimEnd('/')

    $bootstrapPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringUni(
        [System.Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($BootstrapToken))
    try {
        $body = @{ deviceName = $DeviceName } | ConvertTo-Json
        $response = Invoke-RestMethod -Uri "$ServerUrl/devices" -Method Post `
            -Headers @{ Authorization = "Bearer $bootstrapPlain" } -Body $body -ContentType 'application/json' -ErrorAction Stop
    } finally {
        $bootstrapPlain = $null
    }

    $cacheDir = Get-StrongboxSyncCachePath -Item Directory
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    Set-Content -LiteralPath (Get-StrongboxSyncCachePath -Item ServerUrl) -Value $ServerUrl -NoNewline
    $deviceTokenPath = Get-StrongboxSyncCachePath -Item DeviceToken
    Set-Content -LiteralPath $deviceTokenPath -Value $response.token -NoNewline
    if ($IsLinux -or $IsMacOS) {
        # This token is bearer auth for every sync request this device makes - restrict it to this
        # user in case another local account shares the machine, matching the server's own
        # bootstrap-token hardening (Get-StrongboxSyncBootstrapToken.ps1).
        [System.IO.File]::SetUnixFileMode($deviceTokenPath, [System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite)
    }
    # DPAPI-encrypted (ConvertFrom-SecureString with no -Key), unlike backup's deliberately
    # portable encryption - this cache only ever needs to survive on this machine, for this user.
    $SyncPassphrase | ConvertFrom-SecureString | Set-Content -LiteralPath (Get-StrongboxSyncCachePath -Item Passphrase) -NoNewline

    Write-Host "Registered device '$DeviceName' (id $($response.deviceId)) against $ServerUrl."
    Write-Host "Cached sync credentials in $cacheDir."
}
