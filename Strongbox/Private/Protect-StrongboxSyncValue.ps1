function Protect-StrongboxSyncValue {
    <#
    .SYNOPSIS
        Encrypts one secret's value for sync, using the same scheme as Export-StrongboxBackup
        (AES-256-GCM, PBKDF2-derived key, fresh random salt/nonce) - scoped to a single value
        rather than a whole-manifest payload.
    #>
    param(
        [Parameter(Mandatory)][string] $Value,
        [Parameter(Mandatory)][System.Security.SecureString] $Passphrase
    )
    $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $salt = [byte[]]::new(16)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($salt)
    $nonce = [byte[]]::new(12)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($nonce)

    $passphrasePlain = [System.Runtime.InteropServices.Marshal]::PtrToStringUni(
        [System.Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($Passphrase))
    try {
        $key = [System.Security.Cryptography.Rfc2898DeriveBytes]::Pbkdf2(
            [System.Text.Encoding]::UTF8.GetBytes($passphrasePlain), $salt, 210000,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256, 32)
    } finally {
        $passphrasePlain = $null
    }

    $cipherBytes = [byte[]]::new($plainBytes.Length)
    $tag = [byte[]]::new(16)
    $aes = [System.Security.Cryptography.AesGcm]::new($key, 16)
    try {
        $aes.Encrypt($nonce, $plainBytes, $cipherBytes, $tag)
    } finally {
        $aes.Dispose()
    }

    [pscustomobject]@{
        salt       = [Convert]::ToBase64String($salt)
        nonce      = [Convert]::ToBase64String($nonce)
        tag        = [Convert]::ToBase64String($tag)
        ciphertext = [Convert]::ToBase64String($cipherBytes)
    }
}
