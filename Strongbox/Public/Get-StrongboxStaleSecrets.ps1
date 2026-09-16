function Get-StrongboxStaleSecrets {
    <#
    .SYNOPSIS
        Lists only the secrets past their RotationDays policy - the same staleness check the web
        UI shows as a badge, exposed as a reusable function so it's visible without the UI open
        (e.g. from a scheduled task or a Claude Code slash command).
    #>
    Get-StrongboxSecretList | Where-Object Stale
}
