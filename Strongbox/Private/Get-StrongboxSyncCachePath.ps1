function Get-StrongboxSyncCachePath {
    <#
    .SYNOPSIS
        Resolves paths under ~/.strongbox - a per-user directory outside the git checkout, so
        sync credentials survive a repo re-clone or deletion (unlike manifest-path.txt or the
        UI's .token, which are both repo/install-relative).
    #>
    param(
        [ValidateSet('Directory', 'ServerUrl', 'DeviceToken', 'Passphrase')]
        [string] $Item = 'Directory'
    )
    $dir = Join-Path $HOME '.strongbox'
    switch ($Item) {
        'Directory' { $dir }
        'ServerUrl' { Join-Path $dir 'server-url' }
        'DeviceToken' { Join-Path $dir 'device-token' }
        'Passphrase' { Join-Path $dir 'sync-passphrase' }
    }
}
