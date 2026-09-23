<#
.SYNOPSIS
    Lists the command-level aliases declared on each public function.

.DESCRIPTION
    Prints one line per file under source\Public: the file's relative path and its
    [Alias()] block, or '(none)'. Run from the repository root.

.EXAMPLE
    .\ExportAllAliases.ps1

.OUTPUTS
    None. Writes to the console.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Intentional console output for interactive developer utility.')]
param()

& {
    $files = Get-ChildItem -Path source\Public -Recurse -Filter '*.ps1' | Sort-Object FullName
    foreach ($f in $files) {
        $content = Get-Content $f.FullName -Raw
        # function-level [Alias()] appears before 'param ('
        $paramIdx = $content.IndexOf("`n    param ")
        if ($paramIdx -lt 0) { $paramIdx = $content.IndexOf("`n    param(") }
        $aliasIdx = $content.IndexOf('[Alias(')
        if ($aliasIdx -lt 0 -or $aliasIdx -gt $paramIdx) {
            $rel = $f.FullName.Replace((Get-Location).Path + '\source\Public\', '')
            Write-Host "$rel -> (none)"
        } else {
            $end = $content.IndexOf(')', $aliasIdx)
            $block = $content.Substring($aliasIdx, $end - $aliasIdx + 1)
            $rel = $f.FullName.Replace((Get-Location).Path + '\source\Public\', '')
            Write-Host "$rel -> $($block -replace '\s+',' ')"
        }
    }
}
