function Assert-StrongboxSyncDeviceAuth {
    <#
    .SYNOPSIS
        Validates the current request's device bearer token.
    .DESCRIPTION
        Writes a 401 response and returns $null when the token is missing or unrecognized -
        callers must return immediately when this returns $null. Only POST /devices skips this
        check, since it's how a device gets its first token.
    #>
    param([Parameter(Mandatory)][string] $DbPath)
    $auth = [string]$WebEvent.Request.Headers['Authorization']
    if (-not $auth.StartsWith('Bearer ')) {
        Set-PodeResponseStatus -Code 401
        Write-PodeJsonResponse -Value @{ error = 'unauthorized' }
        return $null
    }
    $device = Test-StrongboxSyncDeviceToken -DbPath $DbPath -Token $auth.Substring(7)
    if (-not $device) {
        Set-PodeResponseStatus -Code 401
        Write-PodeJsonResponse -Value @{ error = 'unauthorized' }
        return $null
    }
    return $device
}
