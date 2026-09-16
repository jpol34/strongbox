function Get-StrongboxSyncQueryScope {
    <#
    .SYNOPSIS
        Reads ?scope=&project= off the current request, defaulting to global/no-project.
    #>
    param()
    [pscustomobject]@{
        Scope   = if ($WebEvent.Query['scope']) { $WebEvent.Query['scope'] } else { 'global' }
        Project = if ($WebEvent.Query['project']) { $WebEvent.Query['project'] } else { '' }
    }
}
