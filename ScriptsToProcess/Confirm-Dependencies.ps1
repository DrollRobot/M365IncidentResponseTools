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

# Skip the check if dependencies were already verified earlier in this session.
# Start-IRTPlaybook seeds this global into each child runspace's InitialSessionState
# (before the module is imported) so the playbook's parallel runspaces don't each
# repeat the disk-scanning Get-Module -ListAvailable check.
$GvParams = @{
    Name        = 'IRT_DependenciesChecked'
    Scope       = 'Global'
    ValueOnly   = $true
    ErrorAction = 'SilentlyContinue'
}
$DependenciesChecked = Get-Variable @GvParams

if (-not $DependenciesChecked) {
    $ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
    $InstallScript = Join-Path -Path $ModuleRoot -ChildPath 'Install-Dependencies.ps1'

    if (-not (Test-Path -LiteralPath $InstallScript)) {
        return
    }

    & $InstallScript -Check -Quiet

    if ((Test-Path variable:LASTEXITCODE) -and $LASTEXITCODE -eq 1) {
        & $InstallScript -Check
        throw 'Module import aborted: required modules are missing.'
    }

    # prevent banner from showing again in this session
    $Global:IRT_DependenciesChecked = $true 
}
