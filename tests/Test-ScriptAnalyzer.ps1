<#
.SYNOPSIS
    Runs PSScriptAnalyzer against all PowerShell files in a directory.
.DESCRIPTION
    Does not work in the VS Code PowerShell Extension terminal due to assembly
    conflicts with the extension's bundled PSScriptAnalyzer. Run in a standard
    pwsh terminal instead (the VS Code integrated terminal works fine).
.PARAMETER Path
    Root directory to search. Defaults to the current directory.
.PARAMETER Recurse
    Search subdirectories recursively.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[CmdletBinding()]
param(
    [string] $Path = (Get-Location).Path,
    [switch] $Recurse
)

# Rules to suppress entirely (entire rule category is not relevant to this project).
$ExcludeRules = @(
    'PSAvoidGlobalVars'
    'PSAvoidUsingEmptyCatchBlock'
)

# Conditions to filter out specific results after analysis.
# Each entry is a scriptblock that receives a result object; return $true to exclude it.
# Example: { $_.RuleName -eq 'PSUseShouldProcessForStateChangingFunctions' -and $_.ScriptName -eq 'Set-IRTDeviceEnabled.ps1' }
$ExcludeResults = @(
    # { condition }
)

# The PS Extension terminal hosts its own PSScriptAnalyzer assembly, which conflicts
# with the installed module. Detect and skip rather than error out.
if ($host.Name -eq 'Visual Studio Code Host') {
    Write-Warning "PSScriptAnalyzer cannot run in the VS Code PowerShell Extension terminal."
    Write-Warning "Run .\tests\Invoke-AllTests.ps1 in the integrated terminal (pwsh) instead."
    return
}

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Write-Warning "PSScriptAnalyzer is not installed. Run: Install-Module PSScriptAnalyzer -Repository PSGallery -Scope CurrentUser"
    return
}

$AnalyzerParams = @{
    Path        = $Path
    Recurse     = $Recurse.IsPresent
    ExcludeRule = $ExcludeRules
}

Write-Host "Running PSScriptAnalyzer against $Path (recurse: $($Recurse.IsPresent))..." -ForegroundColor Cyan
Write-Host "This could take multiple minutes. Please wait..." -ForegroundColor Cyan
Write-Host ("NOTE FOR AI: Do not poll or call get_terminal_output. Wait for terminal " +
    "completion notification.") -ForegroundColor Yellow
try {
    $Results = Invoke-ScriptAnalyzer @AnalyzerParams
}
catch {
    Write-Warning "PSScriptAnalyzer failed: $_"
    Write-Warning "If running in the VS Code PowerShell Extension terminal, switch to the integrated pwsh terminal."
    return
}

foreach ($Condition in $ExcludeResults) {
    $Results = $Results | Where-Object { -not (& $Condition $_) }
}

if (-not $Results) {
    Write-Host "PSScriptAnalyzer found no issues."
    return
}

if (($Results | Measure-Object).Count -gt 0){
    Write-Host "Results" -ForegroundColor Cyan
    $Results | Format-Table -AutoSize
    Write-Host "Results grouped by rule:" -ForegroundColor Cyan
    $Results | Group-Object RuleName | Format-Table Count, Name, Group -AutoSize
}

Write-Host "$(($Results | Measure-Object).Count) issue(s) found."
