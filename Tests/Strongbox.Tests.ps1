#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\Strongbox\Strongbox.psd1'
    Import-Module $modulePath -Force

    # Every test mocks Assert-StrongboxVault as a no-op and Get-StrongboxManifestPath to point at
    # a per-test fixture in TestDrive - nothing here ever touches a real vault or manifest.json.
    Mock -ModuleName Strongbox Assert-StrongboxVault { }
}

Describe 'Get-StrongboxSecret' {
    It 'returns the plaintext value on success' {
        Mock -ModuleName Strongbox Get-Secret { 'super-secret-value' }
        Get-StrongboxSecret -Name 'tools.Example' | Should -Be 'super-secret-value'
    }

    It 'throws when the secret is missing and -Optional is not set' {
        Mock -ModuleName Strongbox Get-Secret { throw 'not found' }
        { Get-StrongboxSecret -Name 'tools.Missing' } | Should -Throw
    }

    It 'returns $null when the secret is missing and -Optional is set' {
        Mock -ModuleName Strongbox Get-Secret { throw 'not found' }
        Get-StrongboxSecret -Name 'tools.Missing' -Optional | Should -BeNullOrEmpty
    }

    It 'treats an empty string value the same as missing' {
        Mock -ModuleName Strongbox Get-Secret { '' }
        Get-StrongboxSecret -Name 'tools.Empty' -Optional | Should -BeNullOrEmpty
    }
}

Describe 'Set-StrongboxSecret' {
    It 'writes the value and stamps LastRotated metadata' {
        Mock -ModuleName Strongbox Set-Secret { }
        Mock -ModuleName Strongbox Set-SecretInfo { }

        Set-StrongboxSecret -Name 'tools.Example' -Value 'abc'

        Should -Invoke -ModuleName Strongbox Set-Secret -Times 1 -ParameterFilter {
            $Name -eq 'tools.Example' -and $Secret -eq 'abc'
        }
        Should -Invoke -ModuleName Strongbox Set-SecretInfo -Times 1 -ParameterFilter {
            $Metadata.ContainsKey('LastRotated')
        }
    }

    It 'includes Owner and RotationDays in metadata when supplied' {
        Mock -ModuleName Strongbox Set-Secret { }
        Mock -ModuleName Strongbox Set-SecretInfo { }

        Set-StrongboxSecret -Name 'tools.Example' -Value 'abc' -Owner 'tools' -RotationDays 90

        Should -Invoke -ModuleName Strongbox Set-SecretInfo -Times 1 -ParameterFilter {
            $Metadata.Owner -eq 'tools' -and $Metadata.RotationDays -eq 90
        }
    }
}

Describe 'Remove-StrongboxSecret' {
    It 'calls Remove-Secret with the given name' {
        Mock -ModuleName Strongbox Remove-Secret { }
        Remove-StrongboxSecret -Name 'tools.Example'
        Should -Invoke -ModuleName Strongbox Remove-Secret -Times 1 -ParameterFilter { $Name -eq 'tools.Example' }
    }
}

Describe 'Import-StrongboxSecretEnv' {
    It 'sets one process environment variable per map entry' {
        Mock -ModuleName Strongbox Get-Secret { 'value-for-' + $Name }

        Import-StrongboxSecretEnv -Map @{ MY_VAR = 'tools.Example' }

        [System.Environment]::GetEnvironmentVariable('MY_VAR', 'Process') | Should -Be 'value-for-tools.Example'
    }
}

Describe 'Get-StrongboxSecretHeaders' {
    It 'emits a JSON object with the prefixed value under the given header name' {
        Mock -ModuleName Strongbox Get-Secret { 'tok123' }
        $json = Get-StrongboxSecretHeaders -Name 'tools.GitHub_Pat' -Header 'Authorization' -Prefix 'Bearer '
        ($json | ConvertFrom-Json).Authorization | Should -Be 'Bearer tok123'
    }
}

Describe 'Get-StrongboxSecretList / Get-StrongboxStaleSecrets' {
    BeforeEach {
        $manifestPath = Join-Path $TestDrive 'manifest.json'
        @(
            [pscustomobject]@{ oldName = 'A'; newName = 'tools.Fresh'; usedBy = @('x'); purpose = 'p1'; rotationDays = 90; status = 'keep' }
            [pscustomobject]@{ oldName = 'B'; newName = 'tools.Stale'; usedBy = @('y'); purpose = 'p2'; rotationDays = 30; status = 'keep' }
            [pscustomobject]@{ oldName = 'C'; newName = 'tools.Removed'; purpose = 'gone'; status = 'remove' }
        ) | ConvertTo-Json | Set-Content -LiteralPath $manifestPath

        Mock -ModuleName Strongbox Get-StrongboxManifestPath { $manifestPath }
        Mock -ModuleName Strongbox Get-SecretInfo {
            @(
                [pscustomobject]@{ Name = 'tools.Fresh'; Metadata = @{ LastRotated = (Get-Date).ToUniversalTime().ToString('o') } }
                [pscustomobject]@{ Name = 'tools.Stale'; Metadata = @{ LastRotated = (Get-Date).AddDays(-90).ToUniversalTime().ToString('o') } }
            )
        }
    }

    It 'only lists entries with status keep/keep-unverified, never "remove"' {
        $list = Get-StrongboxSecretList
        $list.Name | Should -Not -Contain 'tools.Removed'
        $list.Count | Should -Be 2
    }

    It 'marks a secret stale once its age exceeds RotationDays' {
        $list = Get-StrongboxSecretList
        ($list | Where-Object Name -eq 'tools.Fresh').Stale | Should -BeFalse
        ($list | Where-Object Name -eq 'tools.Stale').Stale | Should -BeTrue
    }

    It 'Get-StrongboxStaleSecrets returns only the stale ones' {
        $stale = Get-StrongboxStaleSecrets
        $stale.Count | Should -Be 1
        $stale[0].Name | Should -Be 'tools.Stale'
    }
}

Describe 'Test-Strongbox' {
    BeforeEach {
        $manifestPath = Join-Path $TestDrive 'manifest.json'
        @(
            [pscustomobject]@{ oldName = 'A'; newName = 'tools.One'; usedBy = @('x'); purpose = 'p'; status = 'keep' }
        ) | ConvertTo-Json | Set-Content -LiteralPath $manifestPath
        Mock -ModuleName Strongbox Get-StrongboxManifestPath { $manifestPath }
    }

    It 'passes with no drift when manifest and vault agree' {
        Mock -ModuleName Strongbox Get-SecretInfo { @([pscustomobject]@{ Name = 'tools.One' }) }
        { Test-Strongbox } | Should -Not -Throw
    }

    It 'throws when the vault has a secret missing from the manifest' {
        Mock -ModuleName Strongbox Get-SecretInfo {
            @(
                [pscustomobject]@{ Name = 'tools.One' }
                [pscustomobject]@{ Name = 'tools.Orphan' }
            )
        }
        { Test-Strongbox } | Should -Throw
    }

    It 'throws when the manifest references a secret missing from the vault' {
        Mock -ModuleName Strongbox Get-SecretInfo { @() }
        { Test-Strongbox } | Should -Throw
    }
}

Describe 'Export-StrongboxBackup / Import-StrongboxBackup' {
    BeforeEach {
        $manifestPath = Join-Path $TestDrive 'manifest.json'
        @(
            [pscustomobject]@{ oldName = 'A'; newName = 'tools.Example'; usedBy = @('x'); purpose = 'p'; rotationDays = 90; status = 'keep' }
        ) | ConvertTo-Json | Set-Content -LiteralPath $manifestPath
        Mock -ModuleName Strongbox Get-StrongboxManifestPath { $manifestPath }
        Mock -ModuleName Strongbox Get-SecretInfo {
            @([pscustomobject]@{ Name = 'tools.Example'; Metadata = @{ Owner = 'tools'; LastRotated = '2026-01-01T00:00:00Z' } })
        }
        Mock -ModuleName Strongbox Get-Secret { 'the-real-secret-value' }
    }

    It 'round-trips a secret through export + import with the correct passphrase' {
        $backupPath = Join-Path $TestDrive 'backup.json'
        $pass = ConvertTo-SecureString 'correct horse battery staple' -AsPlainText -Force

        Export-StrongboxBackup -Path $backupPath -Passphrase $pass

        $freshManifestPath = Join-Path $TestDrive 'fresh-manifest.json'
        '[]' | Set-Content -LiteralPath $freshManifestPath
        Mock -ModuleName Strongbox Get-StrongboxManifestPath { $freshManifestPath }
        Mock -ModuleName Strongbox Set-Secret { }
        Mock -ModuleName Strongbox Set-SecretInfo { }

        Import-StrongboxBackup -Path $backupPath -Passphrase $pass

        Should -Invoke -ModuleName Strongbox Set-Secret -Times 1 -ParameterFilter {
            $Name -eq 'tools.Example' -and $Secret -eq 'the-real-secret-value'
        }
        $restoredManifest = Get-Content -LiteralPath $freshManifestPath -Raw | ConvertFrom-Json
        $restoredManifest.newName | Should -Contain 'tools.Example'
    }

    It 'fails to decrypt with the wrong passphrase' {
        $backupPath = Join-Path $TestDrive 'backup2.json'
        Export-StrongboxBackup -Path $backupPath -Passphrase (ConvertTo-SecureString 'right-pass' -AsPlainText -Force)

        {
            Import-StrongboxBackup -Path $backupPath -Passphrase (ConvertTo-SecureString 'wrong-pass' -AsPlainText -Force)
        } | Should -Throw
    }

    It 'skips an already-present entry unless -Force is given' {
        $backupPath = Join-Path $TestDrive 'backup3.json'
        $pass = ConvertTo-SecureString 'pw' -AsPlainText -Force
        Export-StrongboxBackup -Path $backupPath -Passphrase $pass

        Mock -ModuleName Strongbox Set-Secret { }
        Mock -ModuleName Strongbox Set-SecretInfo { }

        # manifest already has tools.Example (set up in BeforeEach) -> should be skipped without -Force
        Import-StrongboxBackup -Path $backupPath -Passphrase $pass
        Should -Invoke -ModuleName Strongbox Set-Secret -Times 0

        Import-StrongboxBackup -Path $backupPath -Passphrase $pass -Force
        Should -Invoke -ModuleName Strongbox Set-Secret -Times 1
    }
}
