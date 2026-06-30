function Initialize-IRTFileLogging {
    <#
    .SYNOPSIS
    Enables or disables PSFramework file logging from the LogFolderPath config value.

    .DESCRIPTION
    Reads $Global:IRT_Config.LogFolderPath and configures the PSFramework 'logfile'
    logging provider to match:

      - When LogFolderPath is set, the provider is enabled and every Write-PSFMessage
        call (all levels) is written to <LogFolderPath>\IRT-<date>.log. A new file is
        written per day and files older than 30 days are deleted automatically. There
        is no size limit and no compression.
      - When LogFolderPath is blank/null, the provider is disabled.

    Called at module import (from Suffix.ps1) and again by Set-IRTConfig whenever the
    log folder setting changes, so a change takes effect immediately without reimporting
    the module. Wrapped so a bad path cannot break module import or the config menu.

    The caller skips this for runspace workers: PSFramework's logging queue is process
    wide, so the main session's provider already captures worker messages.

    .EXAMPLE
    Initialize-IRTFileLogging
    Applies the current LogFolderPath setting to the logfile provider.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param()

    Import-IRTModule -Name 'PSFramework'

    $InstanceName = 'M365IRT'
    $LogFolder = $Global:IRT_Config.LogFolderPath

    # No folder configured: make sure file logging is off, then done.
    if ([string]::IsNullOrWhiteSpace($LogFolder)) {
        try {
            Set-PSFLoggingProvider -Name logfile -InstanceName $InstanceName -Enabled $false
        }
        catch {
            # The instance was never created - nothing to disable.
        }
        return
    }

    try {
        # The provider creates the folder if able, but create it up front so a bad
        # path surfaces here as a warning rather than silently producing no logs.
        if (-not (Test-Path -Path $LogFolder)) {
            $null = New-Item -ItemType Directory -Path $LogFolder -Force
        }

        # One file per day (%Date% resolves to yyyy-MM-dd). The glob matches every
        # dated file and feeds the age-based cleanup (LogRetentionTime).
        $DatedLogPath = Join-Path -Path $LogFolder -ChildPath 'IRT-%Date%.log'
        $LogRotateGlob = Join-Path -Path $LogFolder -ChildPath 'IRT-*.log'

        $LoggingParams = @{
            Name             = 'logfile'
            InstanceName     = $InstanceName
            FilePath         = $DatedLogPath
            FileType         = 'TXT'
            Enabled          = $true
            LogRotatePath    = $LogRotateGlob
            LogRetentionTime = '30d'
            MutexName        = 'M365IRT-LogFile'
        }
        Set-PSFLoggingProvider @LoggingParams
    }
    catch {
        Write-PSFMessage -Level Warning -Message (
            "Failed to enable file logging in '$LogFolder': $_")
    }
}
