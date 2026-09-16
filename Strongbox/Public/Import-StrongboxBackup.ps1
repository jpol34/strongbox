function Import-StrongboxBackup {
    <#
    .SYNOPSIS
        Restores a backup created by Export-StrongboxBackup into the current vault + manifest.
    .DESCRIPTION
        By default, skips any secret name that already exists in the current manifest, so a
        restore never silently clobbers something newer. Pass -Force to overwrite existing
        entries too.
    .PARAMETER Path
        The backup file to restore from.
    .PARAMETER Passphrase
        The exact SecureString passphrase used at export time.
    .PARAMETER Force
        Overwrite secrets/manifest entries that already exist, instead of skipping them.
    #>
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][System.Security.SecureString] $Passphrase,
        [switch] $Force
    )
    Assert-StrongboxVault
    $envelope = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($envelope.strongboxBackup -ne 1) { throw "Not a recognized Strongbox backup file: $Path" }

    $salt = [Convert]::FromBase64String($envelope.salt)
    $nonce = [Convert]::FromBase64String($envelope.nonce)
    $tag = [Convert]::FromBase64String($envelope.tag)
    $cipherBytes = [Convert]::FromBase64String($envelope.ciphertext)

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
        # Throws CryptographicException (wrong passphrase or corrupted file) if the auth tag
        # doesn't match - that's the correct behavior, not something to swallow with try/catch.
        $aes.Decrypt($nonce, $cipherBytes, $tag, $plainBytes)
    } finally {
        $aes.Dispose()
    }

    $payload = [System.Text.Encoding]::UTF8.GetString($plainBytes) | ConvertFrom-Json

    $manifestPath = Get-StrongboxManifestPath
    $manifest = @(Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json)

    $restored = 0
    $skipped = 0
    foreach ($e in $payload.entries) {
        $existing = $manifest | Where-Object { $_.newName -eq $e.newName }
        if ($existing -and -not $Force) {
            Write-Host "Skipping '$($e.newName)' - already in manifest (use -Force to overwrite)."
            $skipped++
            continue
        }

        Set-Secret -Name $e.newName -Secret $e.value -Vault $script:StrongboxVaultName
        $metadata = @{}
        if ($e.owner) { $metadata.Owner = $e.owner }
        if ($e.rotationDays) { $metadata.RotationDays = $e.rotationDays }
        if ($e.lastRotated) { $metadata.LastRotated = $e.lastRotated }
        if ($metadata.Count -gt 0) { Set-SecretInfo -Name $e.newName -Vault $script:StrongboxVaultName -Metadata $metadata }

        if (-not $existing) {
            $entry = [ordered]@{
                oldName = $e.oldName
                newName = $e.newName
                usedBy = $e.usedBy
                purpose = $e.purpose
                status = $e.status
            }
            if ($e.rotationDays) { $entry.rotationDays = $e.rotationDays }
            $manifest += [pscustomobject]$entry
        }
        $restored++
    }

    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath
    Write-Host "Restored $restored secret(s), skipped $skipped already-present entr$(if ($skipped -eq 1) { 'y' } else { 'ies' })."
}
