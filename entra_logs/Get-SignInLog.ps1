function Get-SignInLog {
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

    .PARAMETER Test
    Enable stopwatch timing output.

    .PARAMETER Xml
    Export raw XML alongside the Excel file. Defaults to IRT_Config.ExportXml.

    .EXAMPLE
    Get-SignInLog
    Downloads the last 30 days of sign-in logs for the user in the global session.

    .EXAMPLE
    Get-SignInLog -UserObject $User -Days 90
    Downloads 90 days of sign-in logs for a specific user.

    .EXAMPLE
    Get-SignInLog -IpAddress '203.0.113.5' -Days 14
    Finds all sign-ins from a specific IP over the last 14 days.

    .OUTPUTS
    None. Results are exported to an Excel workbook.

    .NOTES
    Version: 1.1.2
    1.1.2 - Added graceful exit when no logs are found.
    1.1.1 - Added test timers.
    #>
    [Alias('GetSILog', 'GetSILogs', 'SILog', 'SILogs')]
    [CmdletBinding(DefaultParameterSetName = 'UserObject')]
    param (
        [Parameter(Position = 0,ParameterSetName='UserObject')]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [Parameter(ParameterSetName='AllUsers')]
        [switch] $AllUsers,

        [Parameter(ParameterSetName='IpAddress')]
        [string[]] $IpAddress,

        # relative date range
        [int] $Days, # default value set at #DEFAULTDAYS
        # absolute date range
        [string] $Start,
        [string] $End,

        [switch] $NonInteractive,

        [boolean] $Beta = $true,
        [boolean] $Excel = $true,
        [boolean] $IpInfo = $Global:IRT_Config.IpInfoAvailable,
        [boolean] $Open = $true,
        [switch] $Test,
        [boolean] $Xml = $Global:IRT_Config.ExportXml
    )

    begin {

        #region BEGIN

        # constants
        $ParameterSet = $PSCmdlet.ParameterSetName
        if ($Test -or $Script:Test) {
            $Script:Test = $true
            # start stopwatch
            $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        }

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
                    $ScriptUserObjects = Get-IRTUserObject

                    # if none found, exit
                    if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                        Write-IRT "No user objects passed or found in global variables." -Level Error
                        return
                    }
                    if (($ScriptUserObjects | Measure-Object).Count -eq 0) {
                        $ErrorParams = @{
                            Category    = 'InvalidArgument'
                            Message     = "No -UserObject argument used, no `$Global:IRT_UserObjects present."
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
        $DefaultDomain = Get-MgDomain | Where-Object { $_.IsDefault -eq $true }
        $DomainName = $DefaultDomain.Id -split '\.' | Select-Object -First 1

        #region DATE RANGE

        # API bug with filters may be fixed?
        # https://github.com/microsoftgraph/msgraph-sdk-powershell/issues/3146#issuecomment-2752675332
        $DefaultDays = if ($NonInteractive) { 3 } else { 30 } # DEFAULTDAYS

        $DateRangeParams = @{
            Days        = $Days
            Start       = $Start
            End         = $End
            DefaultDays = $DefaultDays
        }
        $DateRange = Resolve-IRTDateRange @DateRangeParams
        $DateRangeType = $DateRange.RangeType
        $Days          = $DateRange.Days
        $StartDateUtc  = $DateRange.StartUtc
        $EndDateUtc    = $DateRange.EndUtc
    }

    process {

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            $FilterStrings = [System.Collections.Generic.List[string]]::new()

            #region FILTERS

            # users
            switch ( $ParameterSet ) {
                'UserObject' {
                    $Target = $ScriptUserObject.UserPrincipalName -split '@' | Select-Object -First 1
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
            $FileNameBase = "${FileNamePrefix}_${Days}Days_${DomainName}_${Target}_${FileNameDateString}"
            $XmlOutputPath = "${FileNameBase}.xml"

            # build spreadsheet title
            $TitleDateFormat = "M/d/yy h:mmtt"
            $TitleStartDate = $StartDateUtc.ToLocalTime().ToString($TitleDateFormat)
            $TitleEndDate = $EndDateUtc.ToLocalTime().ToString($TitleDateFormat)
            $TitleType = if ($FileNamePrefix -eq 'NonInteractiveLogs') { 'Non-Interactive' } else { 'Interactive' }
            $SheetTitle = "${TitleType} sign-in logs for ${Target}. Covers ${Days} days, ${TitleStartDate} to ${TitleEndDate}."

            # time range
            if ($DateRangeType -eq 'Relative') {
                if ($Days -ne 30) { # don't use filter if date range is maximum
                    $FilterStrings.Add( "createdDateTime ge $($DateRange.StartString)" )
                }
            }
            elseif ($DateRangeType -eq 'Absolute') {
                $FilterStrings.Add( "createdDateTime ge $($DateRange.StartString)" )
                $FilterStrings.Add( "createdDateTime le $($DateRange.EndString)" )
            }

            # non interactive
            if ( $NonInteractive ) {
                $FilterStrings.Add( "signInEventTypes/any(t: t eq 'NonInteractiveUser')" )
            }
            $FilterString = $FilterStrings -join " and "

            #region QUERY LOGS
            # user messages
            if ( $NonInteractive ) {
                Write-IRT "Retrieving ${Days} days of noninteractive sign-in logs for ${Target}."
            }
            else {
                Write-IRT "Retrieving ${Days} days of sign-in logs for ${Target}."
            }
            if ($Script:Test) {
                Write-IRT "Filter string: '${FilterString}'" -Level Warn
            }
            # Write-Host @Blue "This can take up to 5 minutes, depending on the number of logs." | Out-Host

            # query logs
            if ($Script:Test) {
                $TestText = "Querying sign in logs"
                $TimerStart = $Stopwatch.Elapsed
            }

            if ($Beta) { # default is to use beta, which returns more information
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
                $GetParams = @{
                    Filter = $FilterString
                    # Property = $GetProperties
                    All = $true
                }
                [System.Collections.Generic.List[PSObject]]$Logs = Get-MgBetaAuditLogSignIn @GetParams # | Select-Object $GetProperties
            }
            else { # if $Beta = $false
                # $GetProperties = @( # FIXME going to see how much slower pulling all properties is
                #     'AppDisplayName'
                #     'CorrelationID'
                #     'CreatedDateTime'
                #     'DeviceDetail'
                #     'IpAddress'
                #     'Location'
                #     'ResourceId'
                #     'Status'
                #     'UniqueTokenIdentifier'
                #     'UserAgent'
                #     'UserPrincipalName'
                # )
                $GetParams = @{
                    Filter = $FilterString
                    # Property = $GetProperties
                    All = $true
                }
                [System.Collections.Generic.List[PSObject]]$Logs = Get-MgAuditLogSignIn @GetParams # | Select-Object $GetProperties
            }

            if ($Script:Test) {
                $ElapsedString = ($StopWatch.Elapsed - $TimerStart).ToString('mm\:ss')
                Write-IRT "${TestText} took ${ElapsedString}" -Level Warn
            }

            if (($Logs | Measure-Object).Count -eq 0 ) {
                Write-IRT "No logs found for ${Target} for past ${Days} days. Exiting." -Level Error
                continue
            }

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
                    if ($Script:Test) {
                        $TestText = "Exporting to xml"
                        $TimerStart = $Stopwatch.Elapsed
                    }

                    Write-IRT "Saving logs to: ${XmlOutputPath}"
                    $Logs | Export-Clixml -Depth 10 -Path $XmlOutputPath

                    if ($Script:Test) {
                        $ElapsedString = ($StopWatch.Elapsed - $TimerStart).ToString('mm\:ss')
                        Write-IRT "${TestText} took ${ElapsedString}" -Level Warn
                    }
                }

                # export excel spreadsheet
                if ($Excel) {
                    $Params = @{
                        Logs   = $Logs
                        IpInfo = $IpInfo
                        Open   = $Open
                    }
                    Show-SignInLog @Params
                }
            }
            else {
                Write-IRT "Retrieved 0 logs." -Level Error
            }
        }
    }
}
