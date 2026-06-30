function Invoke-IRTSignInLogQuery {
    <#
    .SYNOPSIS
    Runs a chunked, throttle-aware Entra sign-in log query and exports the result.

    .DESCRIPTION
    Shared engine behind the public sign-in log wrappers (Get-IRTEntraUserSignInLog and
    Get-IRTEntraSPSignInLog). Given a pre-built OData base filter (everything except the
    createdDateTime bounds), a resolved date range, a naming/title bundle, and the name of
    a Show- function to render with, it:

      - splits the range into ChunkDays-sized windows, newest to oldest
      - refreshes the Graph token per chunk and retries on throttle / timeout
      - accumulates results, sorts newest-first, and prepends the metadata row
      - optionally writes a raw XML export
      - hands the result to the supplied Show- command to build the Excel workbook

    This function is private and carries no knowledge of users vs service principals - the
    wrappers own object resolution, filter construction, and naming.

    .PARAMETER BaseFilter
    OData filter clauses common to every chunk (subject + event-type / device-code),
    WITHOUT the createdDateTime bounds, which are added per chunk. May be empty.

    .PARAMETER StartDateUtc
    Range start (UTC), already resolved by the caller.

    .PARAMETER EndDateUtc
    Range end (UTC), already resolved by the caller.

    .PARAMETER Days
    Length of the range in days, for progress and chunk messages.

    .PARAMETER Target
    Subject label used in progress messages and the no-logs notice.

    .PARAMETER LogTypeLabel
    Noun phrase slotted into "Retrieving N days of <label> logs for <target>." e.g.
    'sign-in', 'interactive and non-interactive sign-in', 'service principal sign-in'.

    .PARAMETER FileNamePrefix
    Metadata prefix; reused as the worksheet tab name by the Show- function.

    .PARAMETER FileNameBase
    Base file name (no extension) for the XML export and the Excel workbook.

    .PARAMETER Title
    Worksheet title string.

    .PARAMETER ShowCommand
    Name of the Show- function to dispatch the assembled logs to.

    .PARAMETER ChunkDays
    Split the range into sub-queries of this many days each.

    .PARAMETER ChunkDelaySeconds
    Seconds to pause between chunk queries. Only applies across multiple chunks.

    .PARAMETER ThrottleDelaySeconds
    Base backoff (seconds) when Graph throttles without a Retry-After value.

    .PARAMETER Beta
    Use the Microsoft Graph beta endpoint.

    .PARAMETER Excel
    Hand the result to the Show- command for an Excel workbook.

    .PARAMETER IpInfo
    Passed through to the Show- command to enrich IP addresses.

    .PARAMETER Open
    Passed through to the Show- command to open the workbook after export.

    .PARAMETER Xml
    Also write a raw XML export alongside the workbook.

    .OUTPUTS
    None. Results are exported via the Show- command and optional XML.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param (
        [System.Collections.Generic.List[string]] $BaseFilter =
            [System.Collections.Generic.List[string]]::new(),

        [Parameter(Mandatory)] [datetime] $StartDateUtc,
        [Parameter(Mandatory)] [datetime] $EndDateUtc,
        [Parameter(Mandatory)] [int] $Days,

        [Parameter(Mandatory)] [string] $Target,
        [string] $LogTypeLabel = 'sign-in',
        [Parameter(Mandatory)] [string] $FileNamePrefix,
        [Parameter(Mandatory)] [string] $FileNameBase,
        [Parameter(Mandatory)] [string] $Title,
        [Parameter(Mandatory)] [string] $ShowCommand,

        [int] $ChunkDays = 30,
        [int] $ChunkDelaySeconds = 2,
        [int] $ThrottleDelaySeconds = 60,
        [boolean] $Beta = $true,
        [boolean] $Excel = $true,
        [boolean] $IpInfo = $false,
        [boolean] $Open = $true,
        [boolean] $Xml = $false
    )

    # the wrappers import these too, but import here as well so the engine is
    # self-sufficient (and so each external cmdlet it calls is explicitly referenced)
    $ImportParams = @{
        Name = @(
            'Microsoft.Graph.Beta.Reports'
            'Microsoft.Graph.Reports'
            'PSFramework'
        )
    }
    Import-IRTModule @ImportParams

    $FunctionName = $MyInvocation.MyCommand.Name
    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $XmlOutputPath = "${FileNameBase}.xml"

    #region DATE CHUNKS

    # build non-overlapping date chunks, newest to oldest, clamped to the range
    $DateChunks = [System.Collections.Generic.List[hashtable]]::new()
    $ChunkEnd = $EndDateUtc
    while ($ChunkEnd -gt $StartDateUtc) {
        $ProposedStart = $ChunkEnd.AddDays(-$ChunkDays)
        # Snap to the range start once the proposed start lands within a second of it,
        # so a range that is an exact multiple of ChunkDays doesn't leave a degenerate
        # sub-second trailing chunk.
        $ReachedStart = ($ProposedStart - $StartDateUtc).TotalSeconds -le 1
        $ChunkStart = $ReachedStart ? $StartDateUtc : $ProposedStart
        $DateChunks.Add(@{ Start = $ChunkStart; End = $ChunkEnd })
        $ChunkEnd = $ChunkStart # newest-first; halves meet at the boundary
    }
    $ChunkCount = $DateChunks.Count
    $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
    if ($ChunkCount -gt 1) {
        $ChunkMsg = "Date range is $Days days, split into $ChunkCount ${ChunkDays}-day chunks."
        Write-IRT $ChunkMsg
        Write-PSFMessage -Level 8 -Message "${FunctionName}: $ChunkMsg [$Elapsed]"
    }
    else {
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Date range is $Days days (single chunk). [$Elapsed]")
    }

    #region QUERY LOGS

    Write-IRT "Retrieving ${Days} days of ${LogTypeLabel} logs for ${Target}."

    # accumulate logs across all date chunks
    $Logs = [System.Collections.Generic.List[PSObject]]::new()
    $MaxRetry = 3
    $ChunkIndex = 0
    foreach ($Chunk in $DateChunks) {
        $ChunkIndex++

        # refresh token each chunk; a long multi-chunk run can outlive the
        # token's 5-minute refresh window and start failing with 401s
        Update-IRTToken -Service 'Graph'

        # build this chunk's filter: base filters + explicit date bounds
        $ChunkFilterStrings = [System.Collections.Generic.List[string]]::new()
        foreach ( $f in $BaseFilter ) { $ChunkFilterStrings.Add( $f ) }
        $ChunkStartString = $Chunk.Start.ToString('yyyy-MM-ddTHH:mm:ssZ')
        $ChunkEndString = $Chunk.End.ToString('yyyy-MM-ddTHH:mm:ssZ')
        $ChunkFilterStrings.Add( "createdDateTime ge $ChunkStartString" )
        $ChunkFilterStrings.Add( "createdDateTime le $ChunkEndString" )
        $FilterString = $ChunkFilterStrings -join " and "

        # chunk progress message
        if ( $ChunkCount -gt 1 ) {
            $ChunkStartLocal = $Chunk.Start.ToLocalTime().ToString('M/d/yy h:mmtt')
            $ChunkEndLocal = $Chunk.End.ToLocalTime().ToString('M/d/yy h:mmtt')
            Write-IRT ("Chunk ${ChunkIndex} of ${ChunkCount}:" +
                " ${ChunkStartLocal} to ${ChunkEndLocal}.")
        }
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Filter string: '${FilterString}'")
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Get-MgAuditLogSignIn [$Elapsed]")

        $GetParams = @{
            Filter = $FilterString
            All = $true
        }

        # query logs, retrying on Graph timeout / throttling
        $RetryCount = 0
        while ($true) {
            try {
                if ($Beta) { # default is beta, which returns more information
                    $ChunkLogs = Get-MgBetaAuditLogSignIn @GetParams
                }
                else {
                    $ChunkLogs = Get-MgAuditLogSignIn @GetParams
                }
                break
            }
            catch {
                $Message = $_.Exception.Message
                $IsTimeout = $Message -match
                'HttpClient\.Timeout|request was canceled|task was canceled'
                $IsThrottle = $Message -match 'TooManyRequests|429'

                if ($IsThrottle -and $RetryCount -lt $MaxRetry) {
                    $RetryCount++

                    # determine server-requested Retry-After, if any: prefer the
                    # response header object, then fall back to the message text
                    $RetryAfter = $null
                    try {
                        $Delta = $_.Exception.Response.Headers.RetryAfter.Delta
                        if ($null -ne $Delta) { $RetryAfter = [int]$Delta.TotalSeconds }
                    }
                    catch { $RetryAfter = $null }
                    if (-not $RetryAfter -and
                        $Message -match 'try again (?:in|after)[^0-9]*([0-9]+)\s*second') {
                        $RetryAfter = [int]$Matches[1]
                    }

                    if ($RetryAfter) {
                        # honor and surface the server's requested delay
                        $Wait = $RetryAfter
                        Write-IRT ("Throttled by Graph. Honoring Retry-After of" +
                            " ${Wait}s (retry ${RetryCount}/${MaxRetry})...") -Level Warn
                    }
                    else {
                        # no Retry-After: exponential backoff from the base
                        $Factor = [Math]::Pow(2, $RetryCount - 1)
                        $Wait = [int]($ThrottleDelaySeconds * $Factor)
                        Write-IRT ("Throttled by Graph (no Retry-After). Backing off" +
                            " ${Wait}s (retry ${RetryCount}/${MaxRetry})...") -Level Warn
                    }
                    Start-Sleep -Seconds $Wait
                    continue
                }
                elseif ($IsTimeout -and $RetryCount -lt $MaxRetry) {
                    $RetryCount++
                    Write-IRT ("Request timed out. Retrying" +
                        " (${RetryCount}/${MaxRetry})...") -Level Warn
                    Start-Sleep -Seconds 5
                    continue
                }
                elseif ($IsTimeout) {
                    Write-IRT ("Chunk still timing out after ${MaxRetry} retries." +
                        " Skipping - re-run with a smaller -ChunkDays.") -Level Error
                    $ChunkLogs = $null
                    break
                }
                else {
                    throw
                }
            }
        }

        # accumulate this chunk's results
        foreach ( $l in $ChunkLogs ) { $Logs.Add( $l ) }

        # brief pause between chunks to avoid tripping throttle limits
        if ( $ChunkDelaySeconds -gt 0 -and $ChunkIndex -lt $ChunkCount ) {
            Start-Sleep -Seconds $ChunkDelaySeconds
        }
    }

    if (($Logs | Measure-Object).Count -eq 0 ) {
        Write-IRT "No logs found for ${Target} for past ${Days} days. Exiting." -Level Error
        return
    }

    # sort newest first (chunks are concatenated newest-first; safety net)
    $Logs = [System.Collections.Generic.List[PSObject]](
        $Logs | Sort-Object -Property CreatedDateTime -Descending)

    # add metadata to results
    $Logs.Insert(0,
        [pscustomobject]@{
            Metadata = $true
            FileNamePrefix = $FileNamePrefix
            FileName = $FileNameBase
            Title = $Title
        }
    )

    #region OUTPUT

    # show count, export
    $LogCount = ($Logs | Measure-Object).Count
    if ($LogCount -gt 0) {
        Write-IRT "Retrieved ${LogCount} logs."

        # export to xml
        if ($Xml) {
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-PSFMessage -Level 8 -Message "${FunctionName}: Export-Clixml [$Elapsed]"
            Write-IRT "Saving logs to: ${XmlOutputPath}"
            $Logs | Export-Clixml -Depth 10 -Path $XmlOutputPath
        }

        # export excel spreadsheet via the supplied Show- command
        if ($Excel) {
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-PSFMessage -Level 8 -Message "${FunctionName}: ${ShowCommand} [$Elapsed]"
            $ShowParams = @{
                Logs   = $Logs
                IpInfo = $IpInfo
                Open   = $Open
            }
            & $ShowCommand @ShowParams
        }
    }
    else {
        Write-IRT "Retrieved 0 logs." -Level Error
    }
}
