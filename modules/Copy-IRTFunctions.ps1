function Copy-IRTFunctions {
    <#
    .SYNOPSIS
    Copies the contents of the IRT helper functions to the clipboard.

    .DESCRIPTION
    Reads files from a hardcoded list of internal module paths and any
    additional paths supplied via -Path, then concatenates their contents into
    a single string with a header line showing each file's full path. The
    combined text is sent to the clipboard via Set-Clipboard.

    Hardcoded paths:
      - onprem_ad\*  (all files in the onprem_ad folder)

    When -Path is supplied, each entry is resolved as either a .ps1 file or a
    directory whose .ps1 files are collected. Use -Recurse to walk
    subdirectories for the extra paths.

    .PARAMETER Path
    One or more additional file or directory paths to include. Accepts pipeline
    input. Directories are scanned for .ps1 files.

    .PARAMETER Recurse
    Recurse into subdirectories when expanding directory paths supplied via
    -Path.

    .EXAMPLE
    Copy-IRTFunctions

    Copies the hardcoded IRT helper files to the clipboard.

    .EXAMPLE
    Copy-IRTFunctions -Path .\signin_logs

    Copies hardcoded files plus all .ps1 files in the signin_logs folder.

    .NOTES
    Version: 1.0.3
    #>
    [Alias('CopyIRTFunctions', 'CopyIRT')]
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName', 'PSPath')]
        [string[]] $Path,

        [switch] $Recurse
    )

    begin {
        $ModuleRoot = Split-Path -Path $PSScriptRoot -Parent

        $HardcodedPaths = @(
            @{ Path = Join-Path $ModuleRoot 'modules' 'Write-IRT.ps1'; IsDirectory = $false }
            @{ Path = Join-Path $ModuleRoot 'onprem_ad'; IsDirectory = $true }
        )

        $Files = [System.Collections.Generic.List[System.IO.FileSystemInfo]]::new()

        foreach ($Target in $HardcodedPaths) {
            if (-not (Test-Path -LiteralPath $Target.Path)) {
                Write-Warning "Hardcoded path not found: $($Target.Path)"
                continue
            }

            if ($Target.IsDirectory) {
                foreach ($C in (Get-ChildItem -LiteralPath $Target.Path -File)) {
                    $Files.Add($C)
                }
            }
            else {
                $Files.Add((Get-Item -LiteralPath $Target.Path))
            }
        }
    }

    process {
        foreach ($P in $Path) {
            $Resolved = Resolve-Path -Path $P -ErrorAction SilentlyContinue
            if (-not $Resolved) {
                Write-Warning "Path not found: $P"
                continue
            }

            foreach ($R in $Resolved) {
                $Item = Get-Item -LiteralPath $R.Path -ErrorAction SilentlyContinue
                if (-not $Item) { continue }

                if ($Item.PSIsContainer) {
                    $GciParams = @{
                        LiteralPath = $Item.FullName
                        File        = $true
                        Filter      = '*.ps1'
                        Recurse     = [bool] $Recurse
                    }
                    foreach ($C in (Get-ChildItem @GciParams)) { $Files.Add($C) }
                }
                else {
                    $Files.Add($Item)
                }
            }
        }
    }

    end {
        if ($Files.Count -eq 0) {
            Write-Warning 'No files found to copy.'
            return
        }

        # Resolve current color values (or fallbacks) at copy-time so the pasted
        # code carries the user's preferences onto the remote machine.
        $infoColor  = if ($Global:IRT_Config?.InfoColor)  { $Global:IRT_Config.InfoColor }  else { 'DarkCyan' }
        $warnColor  = if ($Global:IRT_Config?.WarnColor)  { $Global:IRT_Config.WarnColor }  else { 'Yellow'   }
        $errorColor = if ($Global:IRT_Config?.ErrorColor) { $Global:IRT_Config.ErrorColor } else { 'Red'      }

        $bootstrap = @"
# ---- IRT color config (auto-prepended by Copy-IRTFunctions) ----
if (-not `$Global:IRT_Config) {
    `$Global:IRT_Config = [PSCustomObject]@{
        InfoColor  = '$infoColor'
        WarnColor  = '$warnColor'
        ErrorColor = '$errorColor'
    }
}
# ----------------------------------------------------------------

"@

        $Builder = [System.Text.StringBuilder]::new()
        $null = $Builder.AppendLine($bootstrap)
        foreach ($F in $Files) {
            $null = $Builder.AppendLine("===== $($F.FullName) =====")
            $Content = Get-Content -LiteralPath $F.FullName -Raw -ErrorAction SilentlyContinue
            if ($null -ne $Content) {
                $null = $Builder.AppendLine($Content)
            }
            $null = $Builder.AppendLine()
        }

        Set-Clipboard -Value $Builder.ToString()
        Write-IRT "Copied contents of $($Files.Count) file(s) to clipboard."
    }
}
