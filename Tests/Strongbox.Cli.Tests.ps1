#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    # bin/strongbox.ps1 is a script, not a module - dot-sourcing it with no args runs the full
    # command dispatch once (harmlessly hits the 'help' default branch) and leaves its functions
    # defined in this scope, so they can be called/mocked directly, the same way the module's own
    # tests mock Strongbox's public functions.
    $cliScript = Join-Path $PSScriptRoot '..' 'bin' 'strongbox.ps1'
    . $cliScript
}

Describe 'Resolve-StrongboxSetValue' {
    It 'returns the positional value unchanged when one is given' {
        Resolve-StrongboxSetValue -Name 'tools.Example' -PositionalValue 'abc' `
            -ArgList @('tools.Example', 'abc') -PositionalValueGiven | Should -Be 'abc'
    }

    It "reads from stdin when the positional value is '-'" {
        Mock Read-StrongboxStdinValue { 'piped-value' }
        Resolve-StrongboxSetValue -Name 'tools.Example' -PositionalValue '-' `
            -ArgList @('tools.Example', '-') -PositionalValueGiven | Should -Be 'piped-value'
        Should -Invoke Read-StrongboxStdinValue -Times 1
    }

    It 'prompts interactively when no value is given at all' {
        Mock Test-InteractiveTerminal { $true }
        $secure = ConvertTo-SecureString -String 'typed-value' -AsPlainText -Force
        Mock Read-Host { $secure }
        Resolve-StrongboxSetValue -Name 'tools.Example' -ArgList @('tools.Example') | Should -Be 'typed-value'
        Should -Invoke Read-Host -Times 1
    }

    It 'refuses to prompt in a non-interactive session without --real' {
        Mock Test-InteractiveTerminal { $false }
        Mock Read-Host { }
        { Resolve-StrongboxSetValue -Name 'personal.Example' -ArgList @('personal.Example') } |
            Should -Throw '*--real*'
        Should -Invoke Read-Host -Times 0
    }

    It 'reads from the clipboard when --from-clipboard is passed, and clears it after' {
        Mock Assert-ClipboardReadAllowed { }
        Mock Get-StrongboxClipboard { 'clipboard-value' }
        Mock Set-StrongboxClipboard { }

        Resolve-StrongboxSetValue -Name 'tools.Example' -ArgList @('tools.Example', '--from-clipboard') |
            Should -Be 'clipboard-value'

        Should -Invoke Set-StrongboxClipboard -Times 1 -ParameterFilter { $Value -eq '' }
    }

    It "does not mistake '--from-clipboard' sitting where a positional value would be for a literal value" {
        # $Rest = @('tools.Example', '--from-clipboard') - the '--from-clipboard' token must route
        # to the clipboard branch, not be treated as PositionalValue. Exercises the real dispatch
        # helper (Test-StrongboxPositionalValueGiven), not a duplicated expression.
        Mock Assert-ClipboardReadAllowed { }
        Mock Get-StrongboxClipboard { 'clipboard-value' }
        Mock Set-StrongboxClipboard { }
        $rest = @('tools.Example', '--from-clipboard')
        $positionalGiven = Test-StrongboxPositionalValueGiven -Rest $rest

        $positionalGiven | Should -BeFalse
        Resolve-StrongboxSetValue -Name 'tools.Example' `
            -PositionalValue $(if ($positionalGiven) { $rest[1] }) `
            -ArgList $rest -PositionalValueGiven:$positionalGiven | Should -Be 'clipboard-value'
    }

    It 'throws when the clipboard is empty' {
        Mock Assert-ClipboardReadAllowed { }
        Mock Get-StrongboxClipboard { $null }
        { Resolve-StrongboxSetValue -Name 'tools.Example' -ArgList @('tools.Example', '--from-clipboard') } |
            Should -Throw
    }

    It 'enforces the clipboard-read gate via Assert-ClipboardReadAllowed' {
        Mock Assert-ClipboardReadAllowed { throw "Refusing to read the clipboard for 'personal.Example' in a non-interactive session without --real." }
        { Resolve-StrongboxSetValue -Name 'personal.Example' -ArgList @('personal.Example', '--from-clipboard') } |
            Should -Throw '*without --real*'
    }
}

Describe 'Test-StrongboxPositionalValueGiven' {
    It 'is true for an ordinary literal value' {
        Test-StrongboxPositionalValueGiven -Rest @('tools.Example', 'abc') | Should -BeTrue
    }

    It "is true for the '-' stdin sentinel" {
        Test-StrongboxPositionalValueGiven -Rest @('tools.Example', '-') | Should -BeTrue
    }

    It 'is true for a literal value that happens to start with -- (not a recognized flag name)' {
        Test-StrongboxPositionalValueGiven -Rest @('tools.Example', '--abc123token') | Should -BeTrue
    }

    It 'is false when the next token is a recognized flag (value omitted)' {
        Test-StrongboxPositionalValueGiven -Rest @('tools.Example', '--owner') | Should -BeFalse
        Test-StrongboxPositionalValueGiven -Rest @('tools.Example', '--from-clipboard') | Should -BeFalse
    }

    It 'is false when no second element exists at all' {
        Test-StrongboxPositionalValueGiven -Rest @('tools.Example') | Should -BeFalse
    }
}

Describe 'Assert-ClipboardReadAllowed' {
    It 'always allows the sandbox secret name' {
        Mock Test-InteractiveTerminal { $false }
        { Assert-ClipboardReadAllowed -Name 'tools.StrongboxSelfTest' -ArgList @() } | Should -Not -Throw
    }

    It 'allows a real name in an interactive terminal' {
        Mock Test-InteractiveTerminal { $true }
        { Assert-ClipboardReadAllowed -Name 'personal.Example' -ArgList @() } | Should -Not -Throw
    }

    It 'throws for a real name non-interactively without --real' {
        Mock Test-InteractiveTerminal { $false }
        { Assert-ClipboardReadAllowed -Name 'personal.Example' -ArgList @() } | Should -Throw '*--real*'
    }

    It 'allows a real name non-interactively with --real' {
        Mock Test-InteractiveTerminal { $false }
        { Assert-ClipboardReadAllowed -Name 'personal.Example' -ArgList @('--real') } | Should -Not -Throw
    }
}

Describe 'ConvertFrom-StrongboxSecureString' {
    It 'round-trips a known value' {
        $secure = ConvertTo-SecureString -String 'round-trip-me' -AsPlainText -Force
        ConvertFrom-StrongboxSecureString -SecureString $secure | Should -Be 'round-trip-me'
    }
}
