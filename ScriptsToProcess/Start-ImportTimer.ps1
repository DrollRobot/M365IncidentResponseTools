<#
.SYNOPSIS
    Starts the module-load stopwatch. Called automatically via ScriptsToProcess
    during Import-Module.

.NOTES
    Sets $Global:IRT_LoadStopwatch immediately after the dependency check passes so the timer
    captures RequiredModules loading and psm1 execution time. The stopwatch is read and cleared
    at the end of M365IncidentResponseTools.psm1.

    Set $VerbosePreference = 'Continue' before importing to see the elapsed time.
#>
param()

$Global:IRT_LoadStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
