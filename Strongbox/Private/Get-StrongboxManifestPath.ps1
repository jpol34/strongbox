function Get-StrongboxManifestPath {
    <#
    .SYNOPSIS
        Resolve manifest.json's location. Installed copies of this module carry a
        manifest-path.txt pointer (written by Install-StrongboxModule.ps1) to the canonical
        local-admin/strongbox/manifest.json, since only the Strongbox/ subfolder itself gets
        copied onto $PSModulePath. Falls back to the dev-checkout-relative path when run directly
        from the source tree (no pointer file yet).
    #>
    $pointerFile = Join-Path $PSScriptRoot '..' 'manifest-path.txt'
    if (Test-Path -LiteralPath $pointerFile) {
        return (Get-Content -LiteralPath $pointerFile -Raw).Trim()
    }
    Join-Path $PSScriptRoot '..' '..' 'manifest.json'
}
