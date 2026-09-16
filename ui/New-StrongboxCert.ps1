#Requires -Version 7.0
<#
.SYNOPSIS
    One-time setup: creates and locally trusts a self-signed HTTPS certificate for the Strongbox UI.
.DESCRIPTION
    Certificate trust is inherently per-machine - there is no way to ship a certificate in this
    repo that browsers on someone else's machine would trust. Anyone using this tool (including
    on a fresh clone of this repo) runs this script once on their own machine to generate and
    trust their own certificate.

    On Windows: generates a self-signed cert via the built-in New-SelfSignedCertificate (no
    third-party tools like mkcert - this is a single personal tool, not a shared dev environment,
    so a broader local-CA trust model is more than the problem needs) and adds it to
    Cert:\CurrentUser\Root so Chrome/Edge treat it as trusted, without requiring admin elevation
    (Cert:\LocalMachine\Root would require elevation, same friction as the hosts-file entry below).

    On Linux: New-SelfSignedCertificate is part of the Windows-only PKI module, so the cert is
    built directly via .NET's CertificateRequest API instead (genuinely cross-platform) and
    exported as a password-protected PFX file under ui/.certs/ (gitignored) - Pode's HTTPS
    endpoint takes -CertificateFile/-CertificatePassword rather than a certificate-store
    reference. System-wide trust via update-ca-certificates requires root, unlike the Windows
    flow above, so - like the hosts-file entry below - the command is printed for you to run
    yourself rather than run here.

    Also requires a hosts-file entry mapping the hostname to 127.0.0.1 - that edit needs an
    elevated shell and is not done by this script; the command is printed if the entry is missing.
#>
param(
    [string] $HostName = 'strongbox.local'
)
$ErrorActionPreference = 'Stop'

if ($IsWindows) {
    $existing = Get-ChildItem Cert:\CurrentUser\My |
        Where-Object { $_.Subject -eq "CN=$HostName" -and $_.NotAfter -gt (Get-Date) } |
        Select-Object -First 1

    if ($existing) {
        Write-Host "A valid certificate for $HostName already exists (thumbprint $($existing.Thumbprint), expires $($existing.NotAfter))." -ForegroundColor Cyan
        $cert = $existing
    } else {
        $cert = New-SelfSignedCertificate -DnsName $HostName -CertStoreLocation Cert:\CurrentUser\My `
            -NotAfter (Get-Date).AddYears(5) -FriendlyName "Strongbox local dev cert ($HostName)"
        Write-Host "Created certificate for $HostName (thumbprint $($cert.Thumbprint))." -ForegroundColor Green
    }

    $rootStore = [System.Security.Cryptography.X509Certificates.X509Store]::new('Root', 'CurrentUser')
    $rootStore.Open('ReadWrite')
    $alreadyTrusted = $rootStore.Certificates | Where-Object Thumbprint -eq $cert.Thumbprint
    if (-not $alreadyTrusted) {
        $rootStore.Add($cert)
        Write-Host "Trusted the certificate in Cert:\CurrentUser\Root." -ForegroundColor Green
    } else {
        Write-Host "Certificate is already trusted in Cert:\CurrentUser\Root." -ForegroundColor Cyan
    }
    $rootStore.Close()
} else {
    $certDir = Join-Path $PSScriptRoot '.certs'
    New-Item -ItemType Directory -Path $certDir -Force | Out-Null
    $pfxPath = Join-Path $certDir "$HostName.pfx"
    $passwordPath = Join-Path $certDir "$HostName.pfx.pass"
    $crtPath = Join-Path $certDir "$HostName.crt"

    $existingValid = $false
    if ((Test-Path -LiteralPath $pfxPath) -and (Test-Path -LiteralPath $passwordPath)) {
        $existingPassword = (Get-Content -LiteralPath $passwordPath -Raw).Trim()
        $existingCert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($pfxPath, $existingPassword)
        $existingValid = $existingCert.NotAfter -gt (Get-Date)
    }

    if ($existingValid) {
        Write-Host "A valid certificate for $HostName already exists at $pfxPath (expires $($existingCert.NotAfter))." -ForegroundColor Cyan
    } else {
        $rsa = [System.Security.Cryptography.RSA]::Create(2048)
        $req = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
            "CN=$HostName", $rsa, [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        $sanBuilder = [System.Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder]::new()
        $sanBuilder.AddDnsName($HostName)
        $req.CertificateExtensions.Add($sanBuilder.Build())
        # A self-signed leaf with no BasicConstraints isn't a valid trust anchor as far as
        # OpenSSL-based chain validation (what .NET uses on Linux) is concerned - marking it as
        # its own CA is what makes `update-ca-certificates` actually able to trust it.
        $req.CertificateExtensions.Add([System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($true, $false, 0, $true))
        $req.CertificateExtensions.Add([System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new(
            [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyCertSign -bor
            [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature -bor
            [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyEncipherment, $true))
        $cert = $req.CreateSelfSigned([System.DateTimeOffset]::UtcNow.AddDays(-1), [System.DateTimeOffset]::UtcNow.AddYears(5))

        $pfxPasswordBytes = [byte[]]::new(24)
        [System.Security.Cryptography.RandomNumberGenerator]::Fill($pfxPasswordBytes)
        $pfxPassword = [Convert]::ToBase64String($pfxPasswordBytes)

        [System.IO.File]::WriteAllBytes($pfxPath, $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $pfxPassword))
        Set-Content -LiteralPath $passwordPath -Value $pfxPassword -NoNewline
        # update-ca-certificates requires PEM (base64 text), not the raw DER bytes X509ContentType
        # Cert would produce - it silently skips anything else, so trust would never actually work.
        Set-Content -LiteralPath $crtPath -Value $cert.ExportCertificatePem() -NoNewline
        [System.IO.File]::SetUnixFileMode($pfxPath, [System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite)
        [System.IO.File]::SetUnixFileMode($passwordPath, [System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite)

        Write-Host "Created certificate for $HostName at $pfxPath." -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "To trust this certificate system-wide (requires root), run:" -ForegroundColor Yellow
    Write-Host "  sudo cp $crtPath /usr/local/share/ca-certificates/strongbox-$HostName.crt" -ForegroundColor Yellow
    Write-Host "  sudo update-ca-certificates" -ForegroundColor Yellow
}

$hostsPath = if ($IsWindows) { "$env:WINDIR\System32\drivers\etc\hosts" } else { '/etc/hosts' }
$hostsContent = Get-Content -LiteralPath $hostsPath -Raw -ErrorAction SilentlyContinue
if ($hostsContent -notmatch "(?m)^\s*127\.0\.0\.1\s+$([regex]::Escape($HostName))\s*$") {
    Write-Host ""
    if ($IsWindows) {
        Write-Host "Hosts-file entry for $HostName not found. Run this in an elevated PowerShell:" -ForegroundColor Yellow
        Write-Host "  Add-Content -Path `"`$env:WINDIR\System32\drivers\etc\hosts`" -Value `"127.0.0.1 $HostName`"" -ForegroundColor Yellow
    } else {
        Write-Host "Hosts-file entry for $HostName not found. Run:" -ForegroundColor Yellow
        Write-Host "  echo '127.0.0.1 $HostName' | sudo tee -a /etc/hosts" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Done. Start (or restart) the Strongbox UI to pick up HTTPS on https://$HostName" -ForegroundColor Green
