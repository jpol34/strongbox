function Get-StrongboxSyncBootstrapToken {
    <#
    .SYNOPSIS
        Returns the server's admin bootstrap token, generating it on first boot.
    .DESCRIPTION
        Written once to a file inside the persistent data directory - never an environment
        variable, never a default baked into the image. Only POST /devices accepts it.
    #>
    param([Parameter(Mandatory)][string] $Path)
    if (Test-Path -LiteralPath $Path) {
        return (Get-Content -LiteralPath $Path -Raw).Trim()
    }
    $tokenBytes = [byte[]]::new(32)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($tokenBytes)
    $token = [Convert]::ToBase64String($tokenBytes)
    Set-Content -LiteralPath $Path -Value $token -NoNewline
    if ($IsLinux -or $IsMacOS) {
        # This file is the sole gate on device registration - restrict it to the server process's
        # own user in case the data volume ends up readable by more than just this container.
        [System.IO.File]::SetUnixFileMode($Path, [System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite)
    }
    return $token
}
