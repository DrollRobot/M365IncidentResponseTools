<#
.SYNOPSIS
    Pre-import dependency check. Called automatically via ScriptsToProcess during Import-Module.

.DESCRIPTION
    Delegates to Install-Dependencies.ps1 -Check -Quiet, which is silent when all modules
    are satisfied and lists missing modules with the install command when they are not.

    If any modules are missing, throws to abort the import cleanly. This prevents
    PowerShell's default "required module not found" error from appearing in addition
    to the guidance already printed by Install-Dependencies.ps1.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
param()

$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
$InstallScript = Join-Path -Path $ModuleRoot -ChildPath 'Install-Dependencies.ps1'

if (-not (Test-Path -LiteralPath $InstallScript)) {
    return
}

& $InstallScript -Check -Quiet

if ((Test-Path variable:LASTEXITCODE) -and $LASTEXITCODE -eq 1) {
    $Yellow = @{ForegroundColor = 'Yellow' }
    Write-Host @Yellow 'Required modules are missing. To install them, run:'
    Write-Host @Yellow ".\$InstallScript"
    throw 'Module import aborted: required modules are missing.'
}
$Global:IRT_LoadStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
