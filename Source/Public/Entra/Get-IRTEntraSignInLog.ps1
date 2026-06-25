function Get-IRTEntraSignInLog {
    <#
    .SYNOPSIS
    Downloads user sign in logs.

    .DESCRIPTION
    Retrieves Entra ID interactive sign-in logs via Microsoft Graph for one or more users,
    a set of IP addresses, or all users in the tenant. Enriches each log entry with
    IP geolocation data and human-readable Entra error descriptions, then exports results
    to an Excel workbook.

    Date range defaults to the last 30 days when no -Days, -Start, or -End is specified.

    .PARAMETER UserObject
    One or more user objects whose sign-in logs to retrieve. Mutually exclusive with
    -AllUsers and -IpAddress. Falls back to global session objects if omitted.

    .PARAMETER AllUsers
    Retrieve sign-in logs for all users in the tenant. Mutually exclusive with -UserObject
    and -IpAddress.

    .PARAMETER IpAddress
    One or more IP addresses to filter sign-in logs by source IP. Mutually exclusive with
    -UserObject and -AllUsers.

    .PARAMETER Days
    Number of days back to search. Cannot be used with -Start / -End.

    .PARAMETER Start
    Start of date range (parseable date string). Used with -End for an absolute range.

    .PARAMETER End
    End of date range (parseable date string). Used with -Start for an absolute range.

    .PARAMETER ChunkDays
    Splits the requested date range into sub-queries of this many days each, querying
    newest to oldest and merging the results. Default: 30 (a default 30-day pull is a
    single chunk). Graph applies its 300-second HttpClient timeout per request, so very
    large pulls (e.g. -AllUsers over a wide range) can time out while the server computes
    a single page. Pass a smaller value (e.g. -ChunkDays 1) to break the request into
    windows small enough to return in time.

    .PARAMETER ChunkDelaySeconds
    Seconds to pause between chunk queries. A small pause reduces the chance of
    tripping Graph throttling limits on large multi-chunk pulls. Default: 2.
    Set to 0 to disable. Only applies when the range spans more than one chunk.

    .PARAMETER ThrottleDelaySeconds
    Base backoff (seconds) used when Graph throttles a request but does not return a
    Retry-After value. Backoff grows exponentially per retry (base, base*2, base*4...).
    When Graph does return Retry-After, that value is honored and printed instead.
    Default: 60.

    .PARAMETER NonInteractive
    Retrieve non-interactive sign-in logs instead of interactive logs.

    .PARAMETER Beta
    Use the Microsoft Graph beta endpoint. Default: $true.

    .PARAMETER Excel
    Export results to an Excel workbook. Default: $true.

    .PARAMETER IpInfo
    Enrich results with IP geolocation data. Default: $true.

    .PARAMETER Open
    Open the Excel file immediately after export. Default: $true.

    .PARAMETER Xml
    Export raw XML alongside the Excel file. Defaults to IRT_Config.ExportXml.

    .EXAMPLE
    Get-IRTEntraSignInLog
    Downloads the last 30 days of sign-in logs for the user in the global session.

    .EXAMPLE
    Get-IRTEntraSignInLog -UserObject $User -Days 90
    Downloads 90 days of sign-in logs for a specific user.

    .EXAMPLE
    Get-IRTEntraSignInLog -IpAddress '203.0.113.5' -Days 14
    Finds all sign-ins from a specific IP over the last 14 days.

    .OUTPUTS
    None. Results are exported to an Excel workbook.

    .NOTES
    Version: 1.2.1
    1.2.1 - Throttle handling: honor and print Retry-After, exponential backoff
            when absent, and an inter-chunk delay to avoid tripping limits.
    1.2.0 - Added -ChunkDays to split large queries into smaller date windows,
            with per-chunk token refresh and retry on timeout/throttle, to work
            around the Graph 300s per-request HttpClient timeout.
    1.1.2 - Added graceful exit when no logs are found.
    1.1.1 - Added test timers.
    #>
    [Alias('GetSILog', 'GetSILogs', 'SILog', 'SILogs')]
    [CmdletBinding(DefaultParameterSetName = 'UserObject')]
    param (
        [Parameter(Position = 0, ParameterSetName = 'UserObject')]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [Parameter(ParameterSetName = 'AllUsers')]
        [switch] $AllUsers,

        [Parameter(ParameterSetName = 'IpAddress')]
        [string[]] $IpAddress,

        # relative date range
        [int] $Days, # default value set at #DEFAULTDAYS
        # absolute date range
        [string] $Start,
        [string] $End,

        # split the date range into sub-queries of this many days each
        [ValidateRange(1, 3650)]
        [int] $ChunkDays = 30,

        # seconds to pause between chunk queries to avoid tripping throttle limits
        [ValidateRange(0, 3600)]
        [int] $ChunkDelaySeconds = 2,

        # base seconds for throttle backoff when Graph sends no Retry-After
        [ValidateRange(1, 3600)]
        [int] $ThrottleDelaySeconds = 60,

        [switch] $NonInteractive,

        [boolean] $Beta = $true,
        [boolean] $Excel = $true,
        [boolean] $IpInfo = [bool]$Global:IRT_Config.IpInfoAvailable,
        [boolean] $Open = $true,
        [boolean] $Xml = $Global:IRT_Config.ExportXml
    )

    begin {
        Update-IRTToken -Service 'Graph'
        $ImportParams = @{
            Name = @(
                'ImportExcel'
                'Microsoft.Graph.Beta.Reports'
                'Microsoft.Graph.Reports'
                'PSFramework'
            )
        }
        Import-IRTModule @ImportParams

        #region BEGIN

        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        # constants
        $ParameterSet = $PSCmdlet.ParameterSetName

        # create user objects depending on parameters used
        switch ( $ParameterSet ) {
            'UserObject' {
                # if users passed via script argument:
                if (($UserObject | Measure-Object).Count -gt 0) {
                    $ScriptUserObjects = $UserObject
                }
                # if not, look for global objects
                else {

                    # get from global variables
                    $ScriptUserObjects = Get-GlobalUserObject

                    # if none found, exit
                    if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                        $Msg = 'No user objects passed or found in global variables.'
                        Write-IRT $Msg -Level Error
                        return
                    }
                    if (($ScriptUserObjects | Measure-Object).Count -eq 0) {
                        $ErrorParams = @{
                            Category    = 'InvalidArgument'
                            Message     = 'No -UserObject argument used,' +
                            ' no $Global:IRT_UserObjects present.'
                            ErrorAction = 'Stop'
                        }
                        Write-Error @ErrorParams
                    }
                }
            }
            'IpAddress' {
                $ScriptUserObjects = [System.Collections.Generic.List[pscustomobject]]::new()
                foreach ($IpAddress in $IpAddress) {
                    [void]$ScriptUserObjects.Add(
                        [pscustomobject]@{
                            UserPrincipalName = $IpAddress
                        }
                    )
                }
            }
            'AllUsers' {
                $null = $AllUsers  # switch controls parameter set; value not needed
                # build user object with null principal name
                $ScriptUserObjects = @(
                    [pscustomobject]@{
                        UserPrincipalName = 'AllUsers'
                    }
                )
            }
        }

        # get client domain name
        $DomainName = Get-DefaultDomain

        #region DATE RANGE

        # API bug with filters may be fixed?
        # https://github.com/microsoftgraph/msgraph-sdk-powershell/issues/3146
        $DefaultDays = if ($NonInteractive) { 3 } else { 30 } # DEFAULTDAYS

        $DateRangeParams = @{
            Days        = $Days
            Start       = $Start
            End         = $End
            DefaultDays = $DefaultDays
        }
        $DateRange = Resolve-DateRange @DateRangeParams
        $Days = $DateRange.Days
        $StartDateUtc = $DateRange.StartUtc
        $EndDateUtc = $DateRange.EndUtc

        # build non-overlapping date chunks, newest to oldest, clamped to the range
        $DateChunks = [System.Collections.Generic.List[hashtable]]::new()
        $ChunkEnd = $EndDateUtc
        while ($ChunkEnd -gt $StartDateUtc) {
            $ProposedStart = $ChunkEnd.AddDays(-$ChunkDays)
            $ChunkStart = $ProposedStart -gt $StartDateUtc ? $ProposedStart : $StartDateUtc
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
    }

    process {

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            $FilterStrings = [System.Collections.Generic.List[string]]::new()

            #region FILTERS

            # users
            switch ( $ParameterSet ) {
                'UserObject' {
                    $Target = $ScriptUserObject.UserPrincipalName -split '@' |
                        Select-Object -First 1
                    $FilterStrings.Add( "UserId eq '$($ScriptUserObject.Id)'" )
                }
                'IpAddress' {
                    $Target = $ScriptUserObject.UserPrincipalName
                    $FilterStrings.Add( "ipAddress eq '$($ScriptUserObject.UserPrincipalName)'" )
                }
                'AllUsers' {
                    $Target = $DomainName
                    # don't add a user filter
                }
            }

            # build file names # must be after target is set
            if ( $NonInteractive ) {
                $FileNamePrefix = 'NonInteractiveLogs'
            }
            else {
                $FileNamePrefix = 'SignInLogs'
            }
            $FileNameDateFormat = "yy-MM-dd_HH-mm"
            $FileNameDateString = Get-Date -Format $FileNameDateFormat
            $FileNameBase = "${FileNamePrefix}_${Days}Days_${DomainName}" +
            "_${Target}_${FileNameDateString}"
            $XmlOutputPath = "${FileNameBase}.xml"

            # build spreadsheet title
            $TitleDateFormat = "M/d/yy h:mmtt"
            $TitleStartDate = $StartDateUtc.ToLocalTime().ToString($TitleDateFormat)
            $TitleEndDate = $EndDateUtc.ToLocalTime().ToString($TitleDateFormat)
            $TitleType = if ($NonInteractive) { 'Non-Interactive' } else { 'Interactive' }
            $SheetTitle = "${TitleType} sign-in logs for ${Target}." +
            " Covers ${Days} days, ${TitleStartDate} to ${TitleEndDate}."

            # non interactive
            if ( $NonInteractive ) {
                $FilterStrings.Add( "signInEventTypes/any(t: t eq 'NonInteractiveUser')" )
            }
            # base filters are constant per user; date bounds are added per chunk
            $BaseFilterStrings = $FilterStrings

            #region QUERY LOGS
            # user messages
            if ( $NonInteractive ) {
                Write-IRT "Retrieving ${Days} days of noninteractive sign-in logs for ${Target}."
            }
            else {
                Write-IRT "Retrieving ${Days} days of sign-in logs for ${Target}."
            }

            # $GetProperties = @( # FIXME going to see how much slower pulling all properties is
            #     'AppDisplayName'
            #     'AuthenticationProtocol'
            #     'CorrelationID'
            #     'CreatedDateTime'
            #     'DeviceDetail'
            #     'IpAddress'
            #     'Location'
            #     'ResourceId'
            #     'Status'
            #     # 'UniqueTokenIdentifier'
            #     'UserAgent'
            #     'UserPrincipalName'
            # )

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
                foreach ( $f in $BaseFilterStrings ) { $ChunkFilterStrings.Add( $f ) }
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
                    # Property = $GetProperties
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
                continue
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
                    Title = $SheetTitle
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

                # export excel spreadsheet
                if ($Excel) {
                    $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                    Write-PSFMessage -Level 8 -Message (
                        "${FunctionName}: Show-IRTEntraSignInLog [$Elapsed]")
                    $Params = @{
                        Logs   = $Logs
                        IpInfo = $IpInfo
                        Open   = $Open
                    }
                    Show-IRTEntraSignInLog @Params
                }
            }
            else {
                Write-IRT "Retrieved 0 logs." -Level Error
            }
        }
    }
}
