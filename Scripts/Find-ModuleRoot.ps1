function Find-ModuleRoot {
    <#
    .SYNOPSIS
        Locates the nearest PowerShell module root above a given path.

    .DESCRIPTION
        Walks up the directory tree from the given starting path, looking for a
        directory that contains a .psd1 manifest with the same name as the
        directory. That is the conventional layout for a PowerShell module root.

        Accepts either a file or directory path as the starting point. When a
        file path is given, the search begins from its parent directory.

    .PARAMETER Path
        The path to start searching from. Defaults to the current directory.

    .EXAMPLE
        Find-ModuleRoot -Path $PSScriptRoot

        Returns the module root above the calling script's directory.

    .OUTPUTS
        PSCustomObject with properties Name (string) and Path (string), or
        $null if no module root is found before reaching the filesystem root.
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
        $ManifestParams = @{
            Path     = Join-Path -Path $current.FullName -ChildPath "$($current.Name).psd1"
            PathType = 'Leaf'
        }
        if (Test-Path @ManifestParams) {
            return [PSCustomObject]@{
                Name = $current.Name
                Path = $current.FullName
            }
        }

        # Git-worktree layout: the checkout folder name (e.g. ...-wt\<slug>) does
        # not match the module name. Recognize the root by a manifest with a
        # same-named root module file beside it instead.
        $GciParams = @{
            Path        = $current.FullName
            Filter      = '*.psd1'
            File        = $true
            ErrorAction = 'SilentlyContinue'
        }
        $Candidates = @(Get-ChildItem @GciParams |
                Where-Object {
                    $Psm1Name = "$($_.BaseName).psm1"
                    $Psm1Params = @{
                        Path     = Join-Path -Path $current.FullName -ChildPath $Psm1Name
                        PathType = 'Leaf'
                    }
                    Test-Path @Psm1Params
                })
        if ($Candidates.Count -eq 1) {
            return [PSCustomObject]@{
                Name = $Candidates[0].BaseName
                Path = $current.FullName
            }
        }

        $current = $current.Parent
    }

    return $null
}
