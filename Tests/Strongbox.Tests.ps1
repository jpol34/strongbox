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

Describe 'Project scope resolution and shadowing' {
    BeforeEach {
        $manifestPath = Join-Path $TestDrive 'manifest.json'
        @(
            [pscustomobject]@{ oldName = 'A'; newName = 'tools.Example'; purpose = 'global one'; status = 'keep' }
            [pscustomobject]@{ oldName = 'B'; newName = 'tools.Example'; purpose = 'project one'; status = 'keep'; scope = 'project'; project = 'owner/myapp' }
        ) | ConvertTo-Json | Set-Content -LiteralPath $manifestPath
        Mock -ModuleName Strongbox Get-StrongboxManifestPath { $manifestPath }
    }

    It 'Get-StrongboxSecret reads the project-scoped internal name when inside that project' {
        Mock -ModuleName Strongbox Resolve-StrongboxProjectScope { 'owner/myapp' }
        Mock -ModuleName Strongbox Get-Secret { 'project-value' }

        Get-StrongboxSecret -Name 'tools.Example' | Should -Be 'project-value'
        Should -Invoke -ModuleName Strongbox Get-Secret -Times 1 -ParameterFilter {
            $Name -eq 'tools.Example::owner/myapp'
        }
    }

    It 'Get-StrongboxSecret falls back to the global entry outside that project' {
        Mock -ModuleName Strongbox Resolve-StrongboxProjectScope { $null }
        Mock -ModuleName Strongbox Get-Secret { 'global-value' }

        Get-StrongboxSecret -Name 'tools.Example' | Should -Be 'global-value'
        Should -Invoke -ModuleName Strongbox Get-Secret -Times 1 -ParameterFilter {
            $Name -eq 'tools.Example'
        }
    }

    It 'Get-StrongboxSecret falls back to the global entry inside a different project' {
        Mock -ModuleName Strongbox Resolve-StrongboxProjectScope { 'owner/otherapp' }
        Mock -ModuleName Strongbox Get-Secret { 'global-value' }

        Get-StrongboxSecret -Name 'tools.Example' | Should -Be 'global-value'
        Should -Invoke -ModuleName Strongbox Get-Secret -Times 1 -ParameterFilter {
            $Name -eq 'tools.Example'
        }
    }

    It 'Remove-StrongboxSecret removes the project-scoped internal name when inside that project' {
        Mock -ModuleName Strongbox Resolve-StrongboxProjectScope { 'owner/myapp' }
        Mock -ModuleName Strongbox Remove-Secret { }

        Remove-StrongboxSecret -Name 'tools.Example'
        Should -Invoke -ModuleName Strongbox Remove-Secret -Times 1 -ParameterFilter {
            $Name -eq 'tools.Example::owner/myapp'
        }
    }
}

Describe 'Resolve-StrongboxSecretStoreName' {
    It 'returns the name unchanged for global scope' {
        InModuleScope Strongbox {
            Resolve-StrongboxSecretStoreName -Name 'tools.Example' -Scope 'global' | Should -Be 'tools.Example'
        }
    }

    It 'joins name and project with :: for project scope' {
        InModuleScope Strongbox {
            Resolve-StrongboxSecretStoreName -Name 'tools.Example' -Scope 'project' -Project 'owner/myapp' |
                Should -Be 'tools.Example::owner/myapp'
        }
    }

    It 'throws for project scope without a project' {
        InModuleScope Strongbox {
            { Resolve-StrongboxSecretStoreName -Name 'tools.Example' -Scope 'project' } | Should -Throw
        }
    }
}

Describe 'Set-StrongboxSecret project scope' {
    It 'writes under the project-scoped internal name when -Scope Project is given' {
        Mock -ModuleName Strongbox Set-Secret { }
        Mock -ModuleName Strongbox Set-SecretInfo { }

        Set-StrongboxSecret -Name 'tools.Example' -Value 'abc' -Scope Project -Project 'owner/myapp'

        Should -Invoke -ModuleName Strongbox Set-Secret -Times 1 -ParameterFilter {
            $Name -eq 'tools.Example::owner/myapp' -and $Secret -eq 'abc'
        }
    }

    It 'infers the project from the current repo when -Project is not given' {
        Mock -ModuleName Strongbox Set-Secret { }
        Mock -ModuleName Strongbox Set-SecretInfo { }
        Mock -ModuleName Strongbox Resolve-StrongboxProjectScope { 'owner/myapp' }

        Set-StrongboxSecret -Name 'tools.Example' -Value 'abc' -Scope Project

        Should -Invoke -ModuleName Strongbox Set-Secret -Times 1 -ParameterFilter {
            $Name -eq 'tools.Example::owner/myapp'
        }
    }

    It 'throws when -Scope Project is given outside any repo and without -Project' {
        Mock -ModuleName Strongbox Set-Secret { }
        Mock -ModuleName Strongbox Set-SecretInfo { }
        Mock -ModuleName Strongbox Resolve-StrongboxProjectScope { $null }

        { Set-StrongboxSecret -Name 'tools.Example' -Value 'abc' -Scope Project } | Should -Throw
    }

    It 'defaults to global scope, unchanged from prior behavior, when -Scope is not given' {
        Mock -ModuleName Strongbox Set-Secret { }
        Mock -ModuleName Strongbox Set-SecretInfo { }

        Set-StrongboxSecret -Name 'tools.Example' -Value 'abc'

        Should -Invoke -ModuleName Strongbox Set-Secret -Times 1 -ParameterFilter {
            $Name -eq 'tools.Example' -and $Secret -eq 'abc'
        }
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

    It 'defaults Scope/Synced/SyncVersion/SyncedAt when the manifest entry has none of those fields' {
        $entry = Get-StrongboxSecretList | Where-Object Name -eq 'tools.Fresh'
        $entry.Scope | Should -Be 'global'
        $entry.Project | Should -BeNullOrEmpty
        $entry.Synced | Should -BeFalse
        $entry.SyncVersion | Should -Be 0
        $entry.SyncedAt | Should -BeNullOrEmpty
    }
}

Describe 'Get-StrongboxSecretList scope/sync properties' {
    It 'surfaces scope/project/sync fields from a project-scoped manifest entry' {
        $manifestPath = Join-Path $TestDrive 'manifest.json'
        @(
            [pscustomobject]@{
                oldName = $null; newName = 'tools.Example'; usedBy = @('x'); purpose = 'p'; status = 'keep'
                scope = 'project'; project = 'owner/myapp'; synced = $true; syncVersion = 3; syncedAt = '2026-08-01T12:00:00Z'
            }
        ) | ConvertTo-Json | Set-Content -LiteralPath $manifestPath
        Mock -ModuleName Strongbox Get-StrongboxManifestPath { $manifestPath }
        Mock -ModuleName Strongbox Get-SecretInfo {
            @([pscustomobject]@{ Name = 'tools.Example::owner/myapp'; Metadata = @{} })
        }

        $entry = Get-StrongboxSecretList
        $entry.Scope | Should -Be 'project'
        $entry.Project | Should -Be 'owner/myapp'
        $entry.Synced | Should -BeTrue
        $entry.SyncVersion | Should -Be 3
        ([datetime]$entry.SyncedAt).ToUniversalTime() | Should -Be ([datetime]'2026-08-01T12:00:00Z').ToUniversalTime()
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

    It 'does not collide a global and a project-scoped entry sharing the same newName' {
        $manifestPath = Join-Path $TestDrive 'manifest.json'
        @(
            [pscustomobject]@{ oldName = 'A'; newName = 'tools.Example'; purpose = 'global'; status = 'keep' }
            [pscustomobject]@{ oldName = 'B'; newName = 'tools.Example'; purpose = 'project'; status = 'keep'; scope = 'project'; project = 'owner/myapp' }
        ) | ConvertTo-Json | Set-Content -LiteralPath $manifestPath
        Mock -ModuleName Strongbox Get-StrongboxManifestPath { $manifestPath }
        Mock -ModuleName Strongbox Get-SecretInfo {
            @(
                [pscustomobject]@{ Name = 'tools.Example' }
                [pscustomobject]@{ Name = 'tools.Example::owner/myapp' }
            )
        }

        { Test-Strongbox } | Should -Not -Throw
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

Describe 'Initialize-StrongboxSync' {
    It 'registers the device and caches server URL, token, and encrypted passphrase' {
        $cacheDir = Join-Path $TestDrive 'strongbox-home'
        Mock -ModuleName Strongbox Get-StrongboxSyncCachePath {
            param($Item)
            switch ($Item) {
                'Directory' { $cacheDir }
                'ServerUrl' { Join-Path $cacheDir 'server-url' }
                'DeviceToken' { Join-Path $cacheDir 'device-token' }
                'Passphrase' { Join-Path $cacheDir 'sync-passphrase' }
            }
        }
        Mock -ModuleName Strongbox Invoke-RestMethod {
            [pscustomobject]@{ deviceId = 'abc-123'; token = 'the-device-token' }
        }

        $pass = ConvertTo-SecureString 'sync-pw' -AsPlainText -Force
        $bootstrap = ConvertTo-SecureString 'bootstrap-token' -AsPlainText -Force
        Initialize-StrongboxSync -ServerUrl 'http://127.0.0.1:8080/' -DeviceName 'test-device' -SyncPassphrase $pass -BootstrapToken $bootstrap

        Should -Invoke -ModuleName Strongbox Invoke-RestMethod -Times 1 -ParameterFilter {
            $Uri -eq 'http://127.0.0.1:8080/devices' -and $Headers.Authorization -eq 'Bearer bootstrap-token'
        }
        (Get-Content -LiteralPath (Join-Path $cacheDir 'server-url') -Raw) | Should -Be 'http://127.0.0.1:8080'
        (Get-Content -LiteralPath (Join-Path $cacheDir 'device-token') -Raw) | Should -Be 'the-device-token'
        { Get-Content -LiteralPath (Join-Path $cacheDir 'sync-passphrase') -Raw | ConvertTo-SecureString } | Should -Not -Throw
    }
}

Describe 'Push-StrongboxSecret / Pull-StrongboxSecret / Get-StrongboxSyncStatus' {
    BeforeEach {
        $manifestPath = Join-Path $TestDrive 'manifest.json'
        @(
            [pscustomobject]@{
                oldName = 'A'; newName = 'tools.Example'; usedBy = @('x'); purpose = 'p'; status = 'keep'
                synced = $true; syncVersion = 1; syncedAt = '2026-01-01T00:00:00Z'
            }
            [pscustomobject]@{ oldName = 'B'; newName = 'tools.NotSynced'; usedBy = @('y'); purpose = 'p2'; status = 'keep' }
        ) | ConvertTo-Json | Set-Content -LiteralPath $manifestPath
        Mock -ModuleName Strongbox Get-StrongboxManifestPath { $manifestPath }
        Mock -ModuleName Strongbox Get-StrongboxSyncContext {
            [pscustomobject]@{
                ServerUrl   = 'http://127.0.0.1:8080'
                DeviceToken = 'device-token'
                Passphrase  = (ConvertTo-SecureString 'sync-pw' -AsPlainText -Force)
            }
        }
    }

    It 'Push-StrongboxSecret pushes every synced:true entry and updates syncVersion/syncedAt' {
        Mock -ModuleName Strongbox Get-Secret { 'plaintext-value' }
        Mock -ModuleName Strongbox Invoke-RestMethod {
            [pscustomobject]@{ name = 'tools.Example'; version = 2 }
        }

        Push-StrongboxSecret

        Should -Invoke -ModuleName Strongbox Invoke-RestMethod -Times 1 -ParameterFilter {
            $Uri -eq 'http://127.0.0.1:8080/secrets/tools.Example' -and $Method -eq 'Post' -and
            $Headers.Authorization -eq 'Bearer device-token'
        }
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $entry = $manifest | Where-Object newName -eq 'tools.Example'
        $entry.syncVersion | Should -Be 2
        $entry.syncedAt | Should -Not -Be '2026-01-01T00:00:00Z'
    }

    It 'Push-StrongboxSecret throws a pull-first error on a 409 version conflict' {
        Mock -ModuleName Strongbox Get-Secret { 'plaintext-value' }
        Mock -ModuleName Strongbox Invoke-RestMethod {
            $resp = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::Conflict)
            $ex = [Microsoft.PowerShell.Commands.HttpResponseException]::new('409 conflict', $resp)
            throw $ex
        }

        { Push-StrongboxSecret -Name 'tools.Example' } | Should -Throw '*sync pull*'
    }

    It 'Push-StrongboxSecret throws when -Name has no synced:true manifest entry' {
        { Push-StrongboxSecret -Name 'tools.NotSynced' } | Should -Throw
    }

    It 'Pull-StrongboxSecret decrypts the server envelope and writes it locally' {
        $envelope = InModuleScope Strongbox { Protect-StrongboxSyncValue -Value 'pulled-plaintext' -Passphrase (ConvertTo-SecureString 'sync-pw' -AsPlainText -Force) }
        Mock -ModuleName Strongbox Invoke-RestMethod {
            [pscustomobject]@{
                name = 'tools.Example'; version = 5; salt = $envelope.salt; nonce = $envelope.nonce
                tag = $envelope.tag; ciphertext = $envelope.ciphertext
            }
        }
        Mock -ModuleName Strongbox Set-Secret { }
        Mock -ModuleName Strongbox Set-SecretInfo { }

        Pull-StrongboxSecret -Name 'tools.Example'

        Should -Invoke -ModuleName Strongbox Set-Secret -Times 1 -ParameterFilter {
            $Name -eq 'tools.Example' -and $Secret -eq 'pulled-plaintext'
        }
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        ($manifest | Where-Object newName -eq 'tools.Example').syncVersion | Should -Be 5
    }

    It 'Pull-StrongboxSecret creates a new manifest entry for a name not yet tracked' {
        $envelope = InModuleScope Strongbox { Protect-StrongboxSyncValue -Value 'brand-new' -Passphrase (ConvertTo-SecureString 'sync-pw' -AsPlainText -Force) }
        Mock -ModuleName Strongbox Invoke-RestMethod {
            [pscustomobject]@{
                name = 'tools.Untracked'; version = 1; salt = $envelope.salt; nonce = $envelope.nonce
                tag = $envelope.tag; ciphertext = $envelope.ciphertext
            }
        }
        Mock -ModuleName Strongbox Set-Secret { }
        Mock -ModuleName Strongbox Set-SecretInfo { }

        Pull-StrongboxSecret -Name 'tools.Untracked'

        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $entry = $manifest | Where-Object newName -eq 'tools.Untracked'
        $entry.synced | Should -BeTrue
        $entry.syncVersion | Should -Be 1
    }

    It 'Pull-StrongboxSecret skips a name that is 404 on the server' {
        Mock -ModuleName Strongbox Invoke-RestMethod {
            $resp = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::NotFound)
            $ex = [Microsoft.PowerShell.Commands.HttpResponseException]::new('404', $resp)
            throw $ex
        }
        { Pull-StrongboxSecret -Name 'tools.Ghost' } | Should -Not -Throw
    }

    It 'Get-StrongboxSyncStatus reports drift without mutating the manifest' {
        Mock -ModuleName Strongbox Invoke-RestMethod {
            @([pscustomobject]@{ name = 'tools.Example'; scope = 'global'; project = $null; version = 3 })
        }
        $before = Get-Content -LiteralPath $manifestPath -Raw

        $status = Get-StrongboxSyncStatus

        $status.Name | Should -Be 'tools.Example'
        $status.LocalVersion | Should -Be 1
        $status.RemoteVersion | Should -Be 3
        $status.Drift | Should -Be 'out-of-sync'
        (Get-Content -LiteralPath $manifestPath -Raw) | Should -Be $before
    }

    It 'Pull-StrongboxSecret queries and writes under the project-scoped name for a synced project entry' {
        @(
            [pscustomobject]@{
                oldName = 'A'; newName = 'tools.ProjExample'; usedBy = @('x'); purpose = 'p'; status = 'keep'
                scope = 'project'; project = 'owner/myapp'; synced = $true; syncVersion = 0
            }
        ) | ConvertTo-Json | Set-Content -LiteralPath $manifestPath
        Mock -ModuleName Strongbox Resolve-StrongboxProjectScope { 'owner/myapp' }
        $envelope = InModuleScope Strongbox { Protect-StrongboxSyncValue -Value 'proj-value' -Passphrase (ConvertTo-SecureString 'sync-pw' -AsPlainText -Force) }
        Mock -ModuleName Strongbox Invoke-RestMethod {
            [pscustomobject]@{
                name = 'tools.ProjExample'; version = 1; salt = $envelope.salt; nonce = $envelope.nonce
                tag = $envelope.tag; ciphertext = $envelope.ciphertext
            }
        }
        Mock -ModuleName Strongbox Set-Secret { }
        Mock -ModuleName Strongbox Set-SecretInfo { }

        Pull-StrongboxSecret -Name 'tools.ProjExample'

        Should -Invoke -ModuleName Strongbox Invoke-RestMethod -Times 1 -ParameterFilter {
            $Uri -like '*scope=project*' -and $Uri -like '*project=owner/myapp*'
        }
        Should -Invoke -ModuleName Strongbox Set-Secret -Times 1 -ParameterFilter {
            $Name -eq 'tools.ProjExample::owner/myapp'
        }
    }

    It 'Push-StrongboxSecret does not throw on a malformed scope: project entry with no project value' {
        @(
            [pscustomobject]@{
                oldName = 'A'; newName = 'tools.Malformed'; usedBy = @('x'); purpose = 'p'; status = 'keep'
                scope = 'project'; synced = $true; syncVersion = 0
            }
        ) | ConvertTo-Json | Set-Content -LiteralPath $manifestPath
        Mock -ModuleName Strongbox Get-Secret { 'plaintext' }
        Mock -ModuleName Strongbox Invoke-RestMethod {
            [pscustomobject]@{ name = 'tools.Malformed'; version = 1 }
        }

        { Push-StrongboxSecret } | Should -Not -Throw
        Should -Invoke -ModuleName Strongbox Invoke-RestMethod -Times 1 -ParameterFilter {
            $Uri -eq 'http://127.0.0.1:8080/secrets/tools.Malformed'
        }
    }
}
