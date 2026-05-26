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

# All analyzer configuration lives here.
# PSScriptAnalyzer reads: ExcludeRules, Rules (and any other native keys).
$AnalyzerSettings = @{
    ExcludeRules = @(
        'PSAvoidGlobalVars'
        'PSAvoidUsingEmptyCatchBlock'
    )
    Rules        = @{
        PSAvoidUsingPositionalParameters = @{
            Enable           = $true
            CommandAllowList = @('Write-IRT')
        }
    }
}

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

Get-Module PSScriptAnalyzer | Select-Object Path, Version | Format-List
Write-Host "Running PSScriptAnalyzer against $Path..." -ForegroundColor Cyan
Write-Host "This could take multiple minutes. Please wait..." -ForegroundColor Cyan
Write-Host ("NOTE FOR AI: Do not poll or call get_terminal_output. Wait for terminal " +
    "completion notification.") -ForegroundColor Yellow
$InvokeParams = @{
    Path     = $Path
    Recurse  = $Recurse.IsPresent
    Settings = $AnalyzerSettings
    Verbose  = $true
}
try {
    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    # 4>&1 merges the verbose stream into output so we can capture it.
    $AllOutput = Invoke-ScriptAnalyzer @InvokeParams 4>&1
    $Stopwatch.Stop()
    $Results   = $AllOutput | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] }
    $FileCount = ($AllOutput | Where-Object {
        $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -like 'Analyzing file: *'
    }).Count
    Write-Host ("Completed in {0:F1}s." -f $Stopwatch.Elapsed.TotalSeconds) -ForegroundColor Cyan
}
catch {
    Write-Warning "PSScriptAnalyzer failed: $_"
    Write-Warning "If running in the VS Code PowerShell Extension terminal, switch to the integrated pwsh terminal."
    return
}

if (-not $Results) {
    Write-Host "All $FileCount file(s) checked. No PSScriptAnalyzer issues found."
    return
}

if (($Results | Measure-Object).Count -gt 0){

    Write-Host "Results" -ForegroundColor Cyan
    $Results | Format-Table -AutoSize

    if (($Results | Measure-Object).Count -gt 5){
        Write-Host "Results grouped by rule:" -ForegroundColor Cyan
        $Results | Group-Object RuleName | Format-Table Count, Name, Group -AutoSize
    }
}

Write-Host "$(($Results | Measure-Object).Count) issue(s) found."
