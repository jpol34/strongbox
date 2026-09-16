function Get-StrongboxSecretHeaders {
    <#
    .SYNOPSIS
        Emit a JSON object of HTTP headers to stdout, for use as an MCP headersHelper.
    #>
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Header,
        [string] $Prefix = ''
    )
    $value = Get-StrongboxSecret -Name $Name
    @{ $Header = "$Prefix$value" } | ConvertTo-Json -Compress
}
