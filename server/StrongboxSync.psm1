# Pode's runspace pool only carries over functions it can see either by statically parsing the
# main server scriptblock's own text, or by module import - not by dot-sourcing loose files at
# server-setup time. Packaging the storage/device helpers as a real module (like the Strongbox
# module itself) is what makes them callable from inside Add-PodeRoute scriptblocks.
$private = Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -Recurse

foreach ($file in $private) {
    . $file.FullName
}

Export-ModuleMember -Function $private.BaseName
