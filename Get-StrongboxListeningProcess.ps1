function Get-StrongboxListeningProcess {
    <#
    .SYNOPSIS
        Returns the process listening on 127.0.0.1:<Port>, or $null.
    #>
    param([Parameter(Mandatory)][int] $Port)
    $ownerPid = if ($IsWindows) {
        Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
            Where-Object LocalAddress -eq '127.0.0.1' | Select-Object -First 1 -ExpandProperty OwningProcess
    } else {
        # `ss -ltnp` output: "LISTEN 0 128 127.0.0.1:443 ... users:(("pwsh",pid=1234,fd=9))" -
        # scoped to 127.0.0.1 (not just ":$Port") so an unrelated process on a LAN interface or
        # 0.0.0.0 doesn't count as "already running" here. Select-Object -First 1 before -match
        # keeps $line a single string, since -match only populates $matches against a scalar.
        $line = (ss -ltnp 2>$null) -split "`n" | Where-Object { $_ -match "127\.0\.0\.1:$Port\s" } | Select-Object -First 1
        if ($line -match 'pid=(\d+)') { [int]$matches[1] }
    }
    if (-not $ownerPid) { return $null }
    Get-Process -Id $ownerPid -ErrorAction SilentlyContinue
}
