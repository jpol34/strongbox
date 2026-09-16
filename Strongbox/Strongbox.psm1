$public = Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1'
$private = Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1'

foreach ($file in @($private) + @($public)) {
    . $file.FullName
}

Export-ModuleMember -Function $public.BaseName
