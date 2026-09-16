function Get-StrongboxSyncTokenHash {
    <#
    .SYNOPSIS
        SHA-256 hash of a device token, used so raw tokens are never stored at rest.
    #>
    param([Parameter(Mandatory)][string] $Token)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Token)
    $hashBytes = [System.Security.Cryptography.SHA256]::HashData($bytes)
    [Convert]::ToBase64String($hashBytes)
}
