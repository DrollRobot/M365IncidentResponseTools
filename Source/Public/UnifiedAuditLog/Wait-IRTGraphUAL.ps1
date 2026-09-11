function Wait-IRTGraphUAL {
    <#
    .SYNOPSIS
    Waits for audit search jobs to finish, then downloads them.

    .DESCRIPTION
    Polls the Graph audit search jobs until every focused group has finished, then hands
    each one to Receive-IRTGraphUAL and plays a sound.

    The service schedules these jobs in batches, so expect roughly 35 minutes regardless
    of how large the search is. Polling is deliberately unhurried for the same reason:
    every 30 seconds for the first five minutes, then every minute.

    Ctrl+C is safe. The jobs run server-side and keep going, and re-running this command
    picks them back up. Nothing is lost by stopping the wait.

    Each tick reprints the status of every group being watched. Groups that are not
    focused are still listed, dimmed, so a long wait does not hide other work in progress.

    .PARAMETER Group
    One or more group ids to wait for. With none given, a single outstanding search is
    followed automatically and several produce a menu to choose from, including an option
    to follow all of them.

    .PARAMETER All
    Also list audit searches this module did not create, such as ones made in the Purview
    portal. They appear in the status table for context but cannot be waited on or
    downloaded, since there is no way to know how to rebuild their output.

    .PARAMETER PollSeconds
    Override the poll interval, in seconds. By default the interval starts at 30 seconds
    and rises to 60 after the first five minutes.

    .PARAMETER TimeoutMinutes
    Give up waiting after this many minutes. Zero, the default, waits indefinitely.
    Whatever has finished is still downloaded.

    .PARAMETER NoReceive
    Report completion without downloading anything.

    .PARAMETER Audio
    Play a sound when the wait ends. Default: $true.

    .PARAMETER Excel
    Export results to an Excel workbook. Default: $true.

    .PARAMETER Xml
    Export raw records to XML. Defaults to IRT_Config.ExportXml.

    .PARAMETER Cached
    Use pre-cached Graph data where available when building the workbook.

    .EXAMPLE
    ```powershell
    Wait-IRTGraphUAL
    ```
    Waits for every outstanding search, then downloads them.

    .EXAMPLE
    ```powershell
    Wait-IRTGraphUAL -Group '3f9a1c2b'
    ```
    Waits for one group.

    .EXAMPLE
    ```powershell
    Wait-IRTGraphUAL -All
    ```
    Also lists searches created outside this module, for context.

    .EXAMPLE
    ```powershell
    Wait-IRTGraphUAL -TimeoutMinutes 60 -Audio $false
    ```
    Waits up to an hour without a completion sound.

    .OUTPUTS
    None. Results are exported by Receive-IRTGraphUAL.

    .NOTES
    Version: 1.1.0
    1.1.0 - Removed -ResultLimit, along with the download cap it passed on.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost', '',
        Justification = 'Interactive status table, consistent with Get-IRTEmailSearch.')]
    [CmdletBinding()]
    param(
        [Alias('GroupId')]
        [string[]] $Group,

        [switch] $All,

        [ValidateRange(5, 3600)]
        [int] $PollSeconds,

        [ValidateRange(0, 10080)]
        [int] $TimeoutMinutes = 0,

        [switch] $NoReceive,

        [boolean] $Audio = $true,

        [boolean] $Excel = $true,

        [boolean] $Xml = $Global:IRT_Config.ExportXml,

        [switch] $Cached
    )

    Import-IRTModule -Name 'PSFramework'
    $FunctionName = $MyInvocation.MyCommand.Name
    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $Terminal = @('succeeded', 'failed', 'cancelled')

    $Jobs = Get-GraphUALJob -All:$All
    if (($Jobs | Measure-Object).Count -eq 0) {
        Write-IRT 'No outstanding audit searches.' -Level Warn
        return
    }

    # explicit -Group wins; otherwise pick automatically when there is only one, and
    # offer a menu when there is a real choice
    $Focus = Select-GraphUALFocus -Jobs $Jobs -Group $Group
    if (($Focus | Measure-Object).Count -eq 0) {
        Write-IRT 'Nothing selected.' -Level Warn
        return
    }

    $Focused = @($Jobs | Where-Object { $_.GroupId -in $Focus })
    if ($Focused.Count -eq 0) {
        Write-IRT "No audit searches found for group(s): $($Focus -join ', ')" -Level Warn
        return
    }

    Write-IRT ("Watching $(@($Focus).Count) group(s), $($Focused.Count) job(s). " +
        'Ctrl+C is safe; the jobs keep running.')

    $Deadline = $TimeoutMinutes -gt 0 ? (Get-Date).AddMinutes($TimeoutMinutes) : $null
    $TimedOut = $false
    $Completed = $false

    try {
        while ($true) {

            $Jobs = Get-GraphUALJob -All:$All
            $Focused = @($Jobs | Where-Object { $_.GroupId -in $Focus })

            # the group should not disappear mid-wait, but a listing failure or an
            # expired job would do it; treat that as done rather than looping forever
            if ($Focused.Count -eq 0) { $Completed = $true; break }

            Show-GraphUALStatus -Jobs $Jobs -Focus $Focus -Elapsed $Stopwatch.Elapsed

            $Pending = @($Focused | Where-Object { $_.Status -notin $Terminal })
            if ($Pending.Count -eq 0) { $Completed = $true; break }

            if ($Deadline -and (Get-Date) -gt $Deadline) {
                $TimedOut = $true
                Write-IRT ("Timed out after ${TimeoutMinutes} minute(s) with " +
                    "$($Pending.Count) job(s) still running. They keep going; re-run " +
                    'Wait-IRTGraphUAL to pick them up.') -Level Warn
                break
            }

            # the service batches these jobs and nothing finishes quickly, so polling
            # hard buys nothing; ease off after the first few minutes
            $Interval = $PollSeconds
            if (-not $Interval) {
                $Interval = $Stopwatch.Elapsed.TotalMinutes -lt 5 ? 30 : 60
            }
            Start-Sleep -Seconds $Interval
        }
    }
    finally {
        if (-not $Completed -and -not $TimedOut) {
            Write-IRT ('Stopped waiting. The jobs keep running server-side; ' +
                'collect them later with Wait-IRTGraphUAL.') -Level Warn
        }
    }

    if (-not $Completed) { return }

    $Elapsed = $Stopwatch.Elapsed.ToString('hh\:mm\:ss')
    Write-IRT "All watched audit searches finished after ${Elapsed}."
    Write-PSFMessage -Level 8 -Message "${FunctionName}: focus complete after $Elapsed."

    if ($Audio) {
        try { [System.Media.SystemSounds]::Asterisk.Play() }
        catch { Write-PSFMessage -Level 9 -Message "${FunctionName}: no audio device." }
    }

    if ($NoReceive) {
        Write-IRT 'Skipping download (-NoReceive). Use Receive-IRTGraphUAL when ready.'
        return
    }

    foreach ($CurrentGroup in $Focus) {
        $ReceiveParams = @{
            Group  = $CurrentGroup
            Excel  = $Excel
            Xml    = $Xml
            Cached = $Cached
        }
        Receive-IRTGraphUAL @ReceiveParams
    }
}
