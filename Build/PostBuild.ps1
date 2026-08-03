<#
.SYNOPSIS
    Project-specific build steps that run after ModuleBuilder is invoked.

.DESCRIPTION
    Build.ps1 is intentionally generic and reusable across any ModuleBuilder project.
    Put anything specific to this project here: normalizing the generated artifacts,
    copying extra files, updating docs, etc.

    This script is invoked automatically by Build.ps1 if it exists in the Build\ folder.
    Delete or rename it to skip the post-build phase entirely.

    Current job: normalize the end of the generated .psm1/.psd1. ModuleBuilder emits the
    flat .psm1 with a trailing blank line after the final #EndRegion marker. The repo's
    pre-commit end-of-file-fixer hook strips that blank line, which counts as "files were
    modified by this hook" and fails the commit -- so every build-then-commit cycle (the
    release script in particular) aborted on an artifact the build itself had just dirtied.
    Trimming here means the build emits what the hook already considers clean.

.EXAMPLE
    .\Build\PostBuild.ps1

    Trims trailing blank lines from the built artifacts. Normally invoked by Build.ps1
    rather than run directly.

.OUTPUTS
    None. Writes progress to the host.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Repair-FileEnding {
    <#
    .SYNOPSIS
        Rewrites a text file so it ends with exactly one newline.

    .DESCRIPTION
        Strips every trailing CR, LF, space and tab, then appends a single newline in
        whichever style the file already uses (CRLF if its first line break is CRLF,
        otherwise LF). Operates on raw bytes so the file's encoding and byte-order mark
        are preserved untouched, and only writes when the content would actually change.

        Matches what the pre-commit end-of-file-fixer hook does, so a file passed through
        this function no longer trips that hook.

    .PARAMETER Path
        Full path to the file to normalize. A missing file is ignored.

    .EXAMPLE
        Repair-FileEnding -Path 'C:\repo\MyModule.psm1'

        Trims the trailing blank line ModuleBuilder leaves at the end of the module.

    .OUTPUTS
        None. Writes a line to the host when the file was changed.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }

    $Bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($Bytes.Length -eq 0) { return }

    # Walk back past CR (0x0D), LF (0x0A), space (0x20) and tab (0x09).
    $Trailing = [byte[]] @(0x0D, 0x0A, 0x20, 0x09)
    $Last = $Bytes.Length - 1
    while ($Last -ge 0 -and $Trailing -contains $Bytes[$Last]) { $Last-- }

    # Whitespace-only file: nothing meaningful to anchor a newline to, so leave it.
    if ($Last -lt 0) { return }

    # Match the file's existing line-ending style rather than imposing one.
    $Eol = [byte[]] @(0x0A)
    $FirstLf = [Array]::IndexOf($Bytes, [byte]0x0A)
    if ($FirstLf -gt 0 -and $Bytes[$FirstLf - 1] -eq 0x0D) { $Eol = [byte[]] @(0x0D, 0x0A) }

    $New = [byte[]]::new($Last + 1 + $Eol.Length)
    [Array]::Copy($Bytes, 0, $New, 0, $Last + 1)
    [Array]::Copy($Eol, 0, $New, $Last + 1, $Eol.Length)

    # The only edit is at the tail, so comparing length plus the final bytes is enough.
    $Changed = $New.Length -ne $Bytes.Length
    if (-not $Changed) {
        for ($i = 0; $i -lt $Eol.Length; $i++) {
            if ($New[$New.Length - 1 - $i] -ne $Bytes[$Bytes.Length - 1 - $i]) {
                $Changed = $true
                break
            }
        }
    }
    if (-not $Changed) { return }

    [System.IO.File]::WriteAllBytes($Path, $New)
    $FileName = Split-Path -Path $Path -Leaf
    Write-Host "   Trimmed trailing blank lines from $FileName" -ForegroundColor Cyan
}

$RepoRoot = Split-Path -Path $PSScriptRoot -Parent
$SourcePath = Join-Path -Path $RepoRoot -ChildPath 'Source'

# Module name comes from the source manifest, the same way Build.ps1 derives it
# (ModuleBuilder's own Build.psd1 is not the module manifest).
$SrcManifest = Get-ChildItem -Path $SourcePath -Filter '*.psd1' |
    Where-Object Name -ne 'Build.psd1' |
    Select-Object -First 1
if (-not $SrcManifest) { throw "No source manifest found under $SourcePath" }
$ModuleName = $SrcManifest.BaseName

# Build.psd1's BuildToRoot decides where the artifacts landed: repo root when $true,
# otherwise a versioned folder under OutputDirectory.
$BuildPsd1Path = Join-Path -Path $SourcePath -ChildPath 'Build.psd1'
$BuildConfig = @{}
if (Test-Path -LiteralPath $BuildPsd1Path) {
    $BuildConfig = Import-PowerShellDataFile -Path $BuildPsd1Path
}

$ArtifactDirs = @()
if ($BuildConfig.BuildToRoot -eq $true) {
    $ArtifactDirs += $RepoRoot
}
else {
    $OutputDirectory = if ($BuildConfig.OutputDirectory) {
        $OutDirJoin = Join-Path -Path $SourcePath -ChildPath $BuildConfig.OutputDirectory
        [System.IO.Path]::GetFullPath($OutDirJoin)
    }
    else {
        Join-Path -Path $RepoRoot -ChildPath 'Output'
    }
    if (Test-Path -LiteralPath $OutputDirectory) {
        $ModuleDir = Join-Path -Path $OutputDirectory -ChildPath $ModuleName
        if (Test-Path -LiteralPath $ModuleDir) {
            $ArtifactDirs += (Get-ChildItem -Path $ModuleDir -Directory).FullName
            $ArtifactDirs += $ModuleDir
        }
    }
}

foreach ($Dir in $ArtifactDirs) {
    foreach ($Extension in @('psm1', 'psd1')) {
        Repair-FileEnding -Path (Join-Path -Path $Dir -ChildPath "$ModuleName.$Extension")
    }
}
