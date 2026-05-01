New-Alias -Name "SILog" -Value "Get-SignInLog" 
New-Alias -Name "SILogs" -Value "Get-SignInLog" 
New-Alias -Name "GetSILog" -Value "Get-SignInLog" 
New-Alias -Name "GetSILogs" -Value "Get-SignInLog" 
function Get-SignInLog {
    <#
	.SYNOPSIS
	Downloads user sign in logs.

	.NOTES
	Version: 1.1.2
    1.1.2 - Added graceful exit when no logs are found.
    1.1.1 - Added test timers.
	#>
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
        [boolean] $IpInfo = $true,
        [boolean] $Open = $true,
        [switch] $Test,
        [boolean] $Xml = $Global:IRT_Config.ExportXml
    )

    begin {

        #region BEGIN

        # constants
        $Function = $MyInvocation.MyCommand.Name
        $ParameterSet = $PSCmdlet.ParameterSetName
        if ($Test -or $Script:Test) {
            $Script:Test = $true
            # start stopwatch
            $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        }

        # colors
        $Blue = @{ForegroundColor = 'Blue'}
        # $Green = @{ForegroundColor = 'Green'}
        # $Red = @{ForegroundColor = 'Red'}
        # $Magenta = @{ForegroundColor = 'Magenta'}
        $Yellow = @{ForegroundColor = 'Yellow'}

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
                        Write-Host @Red "${Function}: No user objects passed or found in global variables."
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
                Write-Host @Blue "`nRetrieving ${Days} days of noninteractive sign-in logs for ${Target}." | Out-Host
            }
            else {
                Write-Host @Blue "`nRetrieving ${Days} days of sign-in logs for ${Target}." | Out-Host
            }
            if ($Script:Test) {
                Write-Host @Yellow "${Function}: Filter string: '${FilterString}'" | Out-Host
            }
            # Write-Host @Blue "This can take up to 5 minutes, depending on the number of logs." | Out-Host

            # query logs
            if ($Script:Test) {
                $TestText = "Querying sign in logs"
                $TimerStart = $Stopwatch.Elapsed
                Write-Host @Yellow "${Function}: ${TestText} started at $(Get-Date -Format 'hh:mm:sstt')" | Out-Host
            }

            if ($Beta) { # default is to use beta, which returns more information
                $GetProperties = @(
                    'AppDisplayName'
                    'AuthenticationProtocol'
                    'CorrelationID'
                    'CreatedDateTime'
                    'DeviceDetail'
                    'IpAddress'
                    'Location'
                    'ResourceId'
                    'Status'
                    # 'UniqueTokenIdentifier'
                    'UserAgent'
                    'UserPrincipalName'
                )
                $GetParams = @{
                    Filter = $FilterString
                    Property = $GetProperties
                    All = $true
                }
                [System.Collections.Generic.List[PSObject]]$Logs = Get-MgBetaAuditLogSignIn @GetParams |
                    Select-Object $GetProperties
            }
            else { # if $Beta = $false
                $GetProperties = @(
                    'AppDisplayName'
                    'CorrelationID'
                    'CreatedDateTime'
                    'DeviceDetail'
                    'IpAddress'
                    'Location'
                    'ResourceId'
                    'Status'
                    'UniqueTokenIdentifier'
                    'UserAgent'
                    'UserPrincipalName'
                )
                $GetParams = @{
                    Filter = $FilterString
                    Property = $GetProperties
                    All = $true
                }
                [System.Collections.Generic.List[PSObject]]$Logs = Get-MgAuditLogSignIn @GetParams |
                    Select-Object $GetProperties
            }

            if ($Script:Test) {
                $ElapsedString = ($StopWatch.Elapsed - $TimerStart).ToString('mm\:ss')
                Write-Host @Yellow "${Function}: ${TestText} took ${ElapsedString}" | Out-Host
            }

            if (($Logs | Measure-Object).Count -eq 0 ) {
                Write-Host @Red "${Function}: No logs found for ${Target} for past ${Days} days. Exiting." | Out-Host
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
                Write-Host @Blue "Retrieved ${LogCount} logs."

                # export to xml
                if ($Xml) {
                    if ($Script:Test) {
                        $TestText = "Exporting to xml"
                        $TimerStart = $Stopwatch.Elapsed
                        Write-Host @Yellow "${Function}: ${TestText} started at $(Get-Date -Format 'hh:mm:sstt')" | Out-Host
                    }

                    Write-Host @Blue "`nSaving logs to: ${XmlOutputPath}"
                    $Logs | Export-Clixml -Depth 10 -Path $XmlOutputPath

                    if ($Script:Test) {
                        $ElapsedString = ($StopWatch.Elapsed - $TimerStart).ToString('mm\:ss')
                        Write-Host @Yellow "${Function}: ${TestText} took ${ElapsedString}" | Out-Host
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
                Write-Host @Red "Retrieved 0 logs."
            }
        }
    }
}