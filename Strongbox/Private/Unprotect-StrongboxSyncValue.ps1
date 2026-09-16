function Unprotect-StrongboxSyncValue {
    <#
    .SYNOPSIS
        Decrypts one secret's envelope from the sync server, the inverse of
        Protect-StrongboxSyncValue.
    #>
    param(
        [Parameter(Mandatory)][object] $Envelope,
        [Parameter(Mandatory)][System.Security.SecureString] $Passphrase
    )
    $salt = [Convert]::FromBase64String($Envelope.salt)
    $nonce = [Convert]::FromBase64String($Envelope.nonce)
    $tag = [Convert]::FromBase64String($Envelope.tag)
    $cipherBytes = [Convert]::FromBase64String($Envelope.ciphertext)

    $passphrasePlain = [System.Runtime.InteropServices.Marshal]::PtrToStringUni(
        [System.Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($Passphrase))
    try {
        $key = [System.Security.Cryptography.Rfc2898DeriveBytes]::Pbkdf2(
            [System.Text.Encoding]::UTF8.GetBytes($passphrasePlain), $salt, 210000,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256, 32)
    } finally {
        $passphrasePlain = $null
    }

    $plainBytes = [byte[]]::new($cipherBytes.Length)
    $aes = [System.Security.Cryptography.AesGcm]::new($key, 16)
    try {
        # Throws CryptographicException (wrong passphrase or corrupted envelope) if the auth tag
        # doesn't match - that's the correct behavior, not something to swallow with try/catch.
        $aes.Decrypt($nonce, $cipherBytes, $tag, $plainBytes)
    } finally {
        $aes.Dispose()
    }
    [System.Text.Encoding]::UTF8.GetString($plainBytes)
}
