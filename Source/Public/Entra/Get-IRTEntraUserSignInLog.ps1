function Get-IRTEntraUserSignInLog {
    <#
    .SYNOPSIS
    Downloads user sign-in logs.

    .DESCRIPTION
    Retrieves Entra ID user sign-in logs via Microsoft Graph for one or more users, a set
    of IP addresses, or all users in the tenant. Enriches each log entry with IP
    geolocation data and human-readable Entra error descriptions, then exports results to
    an Excel workbook.

    A thin wrapper that resolves the target users, builds the user-specific filter and
    naming, and hands off to the shared Invoke-IRTSignInLogQuery engine (chunking,
    throttle/retry, export). For service principal sign-ins, see Get-IRTEntraSPSignInLog.

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
    Include non-interactive sign-ins alongside the interactive ones. By default Graph
    returns only interactive sign-ins; with this switch the pull covers both types
    (use the SignInEventTypes column to tell them apart). Because non-interactive
    sign-ins are far more numerous, the default date range drops to 3 days.

    .PARAMETER DeviceCode
    Limit results to device code sign-ins: the redemption leg (authenticationProtocol)
    and the downstream token use Entra carries forward on originalTransferMethod.

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
    Get-IRTEntraUserSignInLog
    Downloads the last 30 days of sign-in logs for the user in the global session.

    .EXAMPLE
    Get-IRTEntraUserSignInLog -UserObject $User -Days 90
    Downloads 90 days of sign-in logs for a specific user.

    .EXAMPLE
    Get-IRTEntraUserSignInLog -IpAddress '203.0.113.5' -Days 14
    Finds all sign-ins from a specific IP over the last 14 days.

    .EXAMPLE
    Get-IRTEntraUserSignInLog -NonInteractive
    Downloads interactive and non-interactive sign-ins (3-day default) for the global user.

    .OUTPUTS
    None. Results are exported to an Excel workbook.

    .NOTES
    Version: 2.0.0
    2.0.0 - Renamed from Get-IRTEntraSignInLog. The query/chunk/throttle/export engine
            was extracted into the shared private Invoke-IRTSignInLogQuery; this function
            is now a user-specific wrapper around it (parallel to Get-IRTEntraSPSignInLog).
    1.5.0 - -NonInteractive now returns BOTH interactive and non-interactive sign-ins
            (previously non-interactive only). The SignInEventTypes column (surfaced
            by Show-IRTEntraUserSignInLog) distinguishes them. The 3-day default range
            still applies whenever non-interactive logs are included.
    1.4.0 - -DeviceCode now also matches originalTransferMethod, which Entra carries
            forward onto the downstream token use that follows a device code
            redemption, via a server-side OR filter.
    1.3.0 - File names now start with EntraSignInLog plus short filter flags
            (_NI_ non-interactive, _DC_ device code) and a clearer subject token
            (user / AllUsers / IP); the redundant domain section was dropped.
            Titles spell out scope, device code, and an absolute "start to end"
            or relative "N days from start" date range.
    1.2.3 - Fixed -DeviceCode filter referencing an undefined variable, so the
            authenticationProtocol filter never applied.
    1.2.2 - Fixed chunk-boundary off-by-one that produced a degenerate zero-width
            trailing chunk when the date range was an exact multiple of ChunkDays.
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
        [switch] $DeviceCode,

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
                # use a distinct loop variable: reusing the [string[]]-typed $IpAddress
                # parameter as the loop var re-coerces each element back into a
                # single-element String[], which then leaks downstream as the subject.
                foreach ($Ip in $IpAddress) {
                    [void]$ScriptUserObjects.Add(
                        [pscustomobject]@{
                            UserPrincipalName = $Ip
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
        $RangeType = $DateRange.RangeType
    }

    process {

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            $FilterStrings = [System.Collections.Generic.List[string]]::new()

            #region FILTERS

            # users. $Target drives progress messages; $FileNameSubject is the
            # file-name token; $ScopeText is the subject phrase used in the title.
            switch ( $ParameterSet ) {
                'UserObject' {
                    $Target = $ScriptUserObject.UserPrincipalName -split '@' |
                        Select-Object -First 1
                    $FileNameSubject = $Target
                    $ScopeText = $ScriptUserObject.UserPrincipalName
                    $FilterStrings.Add( "UserId eq '$($ScriptUserObject.Id)'" )
                }
                'IpAddress' {
                    $Target = $ScriptUserObject.UserPrincipalName
                    $FileNameSubject = $Target
                    $ScopeText = "IP ${Target}"
                    $FilterStrings.Add( "ipAddress eq '$($ScriptUserObject.UserPrincipalName)'" )
                }
                'AllUsers' {
                    $Target = $DomainName
                    $FileNameSubject = 'AllUsers'
                    $ScopeText = "All Users in ${DomainName}"
                    # don't add a user filter
                }
            }

            # build file names # must be after target is set
            # the name is sections joined with underscores: always EntraSignInLog, then
            # short flags for active filters (NI = incl. non-interactive, DC = device code), the
            # subject (user / AllUsers / IP), and the timestamp. The domain is omitted -
            # the output folder is already named for the domain.
            $NameSections = [System.Collections.Generic.List[string]]::new()
            $NameSections.Add( 'EntraSignInLog' )
            if ( $NonInteractive ) { $NameSections.Add( 'NI' ) }
            if ( $DeviceCode ) { $NameSections.Add( 'DC' ) }
            # the prefix is reused as the worksheet tab name in the Show- function
            $FileNamePrefix = $NameSections -join '_'
            $NameSections.Add( $FileNameSubject )
            $NameSections.Add( (Get-Date -Format 'yy-MM-dd_HH-mm') )
            $FileNameBase = $NameSections -join '_'

            # build spreadsheet title - mirrors the file name: a base label, then a
            # comma-separated list of the subject and any active filters, then the date
            # range (absolute "start to end" or relative "N days from start").
            $TitleDateFormat = "M/d/yy h:mmtt"
            $TitleStartDate = $StartDateUtc.ToLocalTime().ToString($TitleDateFormat)
            $TitleEndDate = $EndDateUtc.ToLocalTime().ToString($TitleDateFormat)
            $TitleSections = [System.Collections.Generic.List[string]]::new()
            $TitleSections.Add( $ScopeText )
            if ( $NonInteractive ) { $TitleSections.Add( 'Incl. Non-Interactive' ) }
            if ( $DeviceCode ) { $TitleSections.Add( 'Device Code' ) }
            $TitleScope = $TitleSections -join ', '
            if ( $RangeType -eq 'Absolute' ) {
                $DateText = "${TitleStartDate} to ${TitleEndDate}"
            }
            else {
                $DateText = "${Days} days from ${TitleStartDate}"
            }
            $SheetTitle = "Entra sign in logs. ${TitleScope}. ${DateText}."

            # additional filters
            # non-interactive: Graph returns only interactive sign-ins unless asked
            # otherwise, so include both event types explicitly. The outer parentheses
            # keep the OR from binding loosely against the and-joined clauses.
            if ( $NonInteractive ) {
                $FilterStrings.Add(
                    "(signInEventTypes/any(t: t eq 'interactiveUser')" +
                    " or signInEventTypes/any(t: t eq 'nonInteractiveUser'))" )
            }
            # device code: match the redemption leg (authenticationProtocol) and the
            # downstream token use Entra carries forward on originalTransferMethod. The
            # parentheses keep the OR from binding loosely against the and-joined clauses.
            if ( $DeviceCode ) {
                $FilterStrings.Add(
                    "(authenticationProtocol eq 'devicecode'" +
                    " or originalTransferMethod eq 'deviceCodeFlow')" )
            }

            # noun phrase for the "Retrieving N days of <label> logs" progress message
            $LogTypeLabel = if ( $NonInteractive ) {
                'interactive and non-interactive sign-in'
            }
            else {
                'sign-in'
            }

            #region QUERY LOGS

            # hand off to the shared engine (chunking, throttle/retry, export, Show)
            $QueryParams = @{
                BaseFilter           = $FilterStrings
                StartDateUtc         = $StartDateUtc
                EndDateUtc           = $EndDateUtc
                Days                 = $Days
                Target               = $Target
                LogTypeLabel         = $LogTypeLabel
                FileNamePrefix       = $FileNamePrefix
                FileNameBase         = $FileNameBase
                Title                = $SheetTitle
                ShowCommand          = 'Show-IRTEntraUserSignInLog'
                ChunkDays            = $ChunkDays
                ChunkDelaySeconds    = $ChunkDelaySeconds
                ThrottleDelaySeconds = $ThrottleDelaySeconds
                Beta                 = $Beta
                Excel                = $Excel
                IpInfo               = $IpInfo
                Open                 = $Open
                Xml                  = $Xml
            }
            Invoke-IRTSignInLogQuery @QueryParams
        }
    }
}
