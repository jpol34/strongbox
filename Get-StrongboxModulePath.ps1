function Get-StrongboxModulePath {
    <#
    .SYNOPSIS
        The per-user PowerShell module directory Install-StrongboxModule.ps1 installs into and
        Uninstall-Strongbox.ps1 removes from - kept in one place so the two can't disagree.
    .DESCRIPTION
        Windows' user module path isn't on $env:PSModulePath by default, so Install/Uninstall
        register/deregister it there. Linux/macOS's ~/.local/share/powershell/Modules is already
        on pwsh's default PSModulePath - nothing to register.
    #>
    if ($IsWindows) { Join-Path $HOME 'Documents\PowerShell\Modules' } else { Join-Path $HOME '.local/share/powershell/Modules' }
}
