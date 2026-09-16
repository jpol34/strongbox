function Resolve-StrongboxManifestScope {
    <#
    .SYNOPSIS
        Resolves a manifest entry's Scope/Project, defaulting to global.
    .DESCRIPTION
        A 'project' scope entry with no 'project' value is malformed - rather than let that
        crash the caller's whole listing/drift-check loop over one bad entry, it's treated as
        global and flagged to stderr.
    #>
    param(
        [Parameter(Mandatory)][object] $Entry
    )
    $scope = if ($Entry.scope) { $Entry.scope } else { 'global' }
    if ($scope -eq 'project' -and -not $Entry.project) {
        [Console]::Error.WriteLine("Strongbox: manifest entry '$($Entry.newName)' has scope 'project' but no 'project' value - treating as global.")
        $scope = 'global'
    }
    $project = if ($scope -eq 'project') { $Entry.project } else { $null }
    [pscustomobject]@{ Scope = $scope; Project = $project }
}
