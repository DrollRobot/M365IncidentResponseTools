function Find-ModuleRoot {
    <#
    .SYNOPSIS
        Locates the nearest PowerShell module root above a given path.

    .DESCRIPTION
        Walks up the directory tree from the given starting path, looking for a
        directory whose name matches a .psd1 manifest it contains
        (ModuleName\ModuleName.psd1) - the conventional PowerShell module root.

        Inside a git worktree the working folder is named for the branch, not the
        module, so a worktree root (whose .git is a file, not a directory) is
        matched against the main working tree's folder name instead.

        Accepts either a file or directory path as the starting point. When a
        file path is given, the search begins from its parent directory.

    .PARAMETER Path
        The path to start searching from. Defaults to the current directory.

    .EXAMPLE
        Find-ModuleRoot -Path $PSScriptRoot

        Returns the module root above the calling script's directory.

    .OUTPUTS
        PSCustomObject with properties Name (the manifest base name) and Path (the
        module root directory), or $null if no module root is found before reaching
        the filesystem root.

    .NOTES
        Version: 1.1.0
        1.1.0 - Resolve the expected manifest name from the main working tree when
                inside a git worktree, so detection no longer fails when the
                working folder is named for the branch rather than the module.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string] $Path = (Get-Location).Path
    )

    $current = Get-Item -LiteralPath $Path
    if (-not $current.PSIsContainer) {
        $current = $current.Parent
    }

    while ($current) {
        # The conventional module root is a folder named for its manifest:
        # ModuleName\ModuleName.psd1. Inside a git worktree the working folder is
        # named for the branch, so when this directory is a linked worktree root
        # (its .git is a file, not a directory) take the expected manifest name
        # from the main working tree's folder instead.
        $ExpectedName = $current.Name
        $DotGit = Join-Path -Path $current.FullName -ChildPath '.git'
        if (Test-Path -LiteralPath $DotGit -PathType Leaf) {
            # The .git file reads: "gitdir: <mainTree>/.git/worktrees/<name>".
            $GitContent = Get-Content -LiteralPath $DotGit -TotalCount 1
            $GitDir = $GitContent -replace '^\s*gitdir:\s*', ''
            $MainTree = $GitDir -replace '[\\/]\.git[\\/]worktrees[\\/].*$', ''
            if ($MainTree -ne $GitDir) {
                $ExpectedName = Split-Path -Path $MainTree -Leaf
            }
        }

        $ManifestPath = Join-Path -Path $current.FullName -ChildPath "$ExpectedName.psd1"
        if (Test-Path -LiteralPath $ManifestPath -PathType Leaf) {
            return [PSCustomObject]@{
                Name = $ExpectedName
                Path = $current.FullName
            }
        }
        $current = $current.Parent
    }

    return $null
}
