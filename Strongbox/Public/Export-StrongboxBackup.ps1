function Export-StrongboxBackup {
    <#
    .SYNOPSIS
        Backs up manifest.json + every tracked secret's value to one passphrase-encrypted file.
    .DESCRIPTION
        SecretStore has no documented backup/restore path of its own - if the vault's underlying
        store is lost (OS reinstall, corrupted profile), every secret is gone with it. This is
        the mitigation: one encrypted file you can copy anywhere.

        Deliberately NOT DPAPI/Windows-user-tied encryption (ConvertTo-SecureString's default key
        is derived from the current user+machine, so a backup "protected" that way would only
        ever be restorable on this exact Windows profile - useless as a disaster-recovery backup).
        Instead: AES-256-GCM with a key derived from your passphrase via PBKDF2 (210,000
        iterations, random per-file salt) - restorable on any machine that has the passphrase,
        which is the actual point of a backup.
    .PARAMETER Path
        Output file path.
    .PARAMETER Passphrase
        A SecureString passphrase. You will need this exact passphrase to restore - there is no
        recovery if it's lost.
    #>
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][System.Security.SecureString] $Passphrase
    )
    Assert-StrongboxVault
    $manifest = Get-Content (Get-StrongboxManifestPath) -Raw | ConvertFrom-Json
    $entries = $manifest | Where-Object { $_.status -in 'keep', 'keep-unverified' }

    $backupEntries = foreach ($e in $entries) {
        $info = Get-SecretInfo -Vault $script:StrongboxVaultName -Name $e.newName -ErrorAction SilentlyContinue
        $value = Get-Secret -Name $e.newName -Vault $script:StrongboxVaultName -AsPlainText -ErrorAction SilentlyContinue
        if ($null -eq $value) { continue }
        [pscustomobject]@{
            oldName = $e.oldName
            newName = $e.newName
            value = $value
            usedBy = $e.usedBy
            purpose = $e.purpose
            rotationDays = $e.rotationDays
            status = $e.status
            owner = $info.Metadata.Owner
            lastRotated = $info.Metadata.LastRotated
        }
    }

    $payload = [pscustomobject]@{
        version = 1
        exportedAt = (Get-Date).ToUniversalTime().ToString('o')
        entries = @($backupEntries)
    } | ConvertTo-Json -Depth 6

    $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
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

    $envelope = [pscustomobject]@{
        strongboxBackup = 1
        salt = [Convert]::ToBase64String($salt)
        nonce = [Convert]::ToBase64String($nonce)
        tag = [Convert]::ToBase64String($tag)
        ciphertext = [Convert]::ToBase64String($cipherBytes)
    }
    $envelope | ConvertTo-Json | Set-Content -LiteralPath $Path -NoNewline

    Write-Host "Backed up $($backupEntries.Count) secrets to $Path (encrypted, passphrase-protected)."
}
