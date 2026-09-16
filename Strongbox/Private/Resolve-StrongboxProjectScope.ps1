function Resolve-StrongboxProjectScope {
    <#
    .SYNOPSIS
        Resolves the current project's repo slug by walking up from $PWD to the nearest .git.
    .DESCRIPTION
        Returns $null when no .git directory is found between $PWD and the filesystem root, which
        means the caller is not inside any repo and only global-scoped secrets apply. When a repo
        is found, the slug is parsed from 'origin's URL (owner/repo, or just repo if the URL has
        no owner segment) - falling back to the repo folder's name when there's no origin remote.
    #>
    param()

    $dir = Get-Item -LiteralPath $PWD
    while ($dir) {
        $gitPath = Join-Path $dir.FullName '.git'
        if (Test-Path -LiteralPath $gitPath) {
            $remoteUrl = git -C $dir.FullName remote get-url origin 2>$null
            if ($LASTEXITCODE -eq 0 -and $remoteUrl) {
                $trimmed = ($remoteUrl.Trim().TrimEnd('/')) -replace '\.git$', ''
                if ($trimmed -match '[:/]([^/]+/[^/]+)$') {
                    return $matches[1]
                }
                return ($trimmed -split '[/\\]')[-1]
            }
            return $dir.Name
        }
        $dir = $dir.Parent
    }
    return $null
}
