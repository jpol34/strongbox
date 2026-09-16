$script:StrongboxProjectScopeCache = @{}

function Resolve-StrongboxProjectScope {
    <#
    .SYNOPSIS
        Resolves the current project's repo slug by walking up from $PWD to the nearest .git.
    .DESCRIPTION
        Returns $null when no .git directory is found between $PWD and the filesystem root, which
        means the caller is not inside any repo and only global-scoped secrets apply. When a repo
        is found, the slug is everything after the host in 'origin's URL (e.g. owner/repo, or a
        full nested path like group/subgroup/repo) - falling back to the repo folder's name when
        there's no origin remote or the URL has no parseable host segment.

        Result is memoized per $PWD for the life of the process - callers like
        Import-StrongboxSecretEnv loop over many names from the same directory, and each call
        would otherwise re-walk the filesystem and re-shell out to git for an answer that can't
        change mid-loop.
    #>
    param()

    if ($script:StrongboxProjectScopeCache.ContainsKey($PWD.Path)) {
        return $script:StrongboxProjectScopeCache[$PWD.Path]
    }

    $result = $null
    $dir = Get-Item -LiteralPath $PWD
    while ($dir) {
        $gitPath = Join-Path $dir.FullName '.git'
        if (Test-Path -LiteralPath $gitPath) {
            $remoteUrl = git -C $dir.FullName remote get-url origin 2>$null
            if ($LASTEXITCODE -eq 0 -and $remoteUrl) {
                $trimmed = ($remoteUrl.Trim().TrimEnd('/')) -replace '\.git$', ''
                if ($trimmed -match '^(?:\w+://[^/]+/|[^/:]+:)(.+)$') {
                    $result = $matches[1]
                } else {
                    $result = ($trimmed -split '[/\\]')[-1]
                }
            } else {
                $result = $dir.Name
            }
            break
        }
        $dir = $dir.Parent
    }

    $script:StrongboxProjectScopeCache[$PWD.Path] = $result
    return $result
}
