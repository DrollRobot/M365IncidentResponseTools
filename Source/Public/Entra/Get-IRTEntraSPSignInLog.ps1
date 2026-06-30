function Get-IRTEntraSPSignInLog {
    <#
    .SYNOPSIS
    Downloads service principal sign-in logs.

    .DESCRIPTION
    Retrieves Entra ID service principal sign-in logs via Microsoft Graph for one or more
    service principals or all service principals in the tenant. Enriches each log entry
    with IP geolocation data and human-readable Entra error descriptions, then exports
    results to an Excel workbook.

    A thin wrapper that resolves the target service principals, builds the SP-specific
    filter and naming, and hands off to the shared Invoke-IRTSignInLogQuery engine
    (chunking, throttle/retry, export). For user sign-ins, see Get-IRTEntraUserSignInLog.

    Date range defaults to the last 30 days when no -Days, -Start, or -End is specified.

    Falls back to $Global:IRT_ServicePrincipalObjects if no -ServicePrincipalObject is
    passed. Use Find-IRTServicePrincipal first to populate that global variable.

    .PARAMETER ServicePrincipalObject
    One or more service principal objects whose sign-in logs to retrieve. Mutually
    exclusive with -AllServicePrincipals. Falls back to global session objects if omitted.

    .PARAMETER AllServicePrincipals
    Retrieve sign-in logs for all service principals in the tenant. Mutually exclusive
    with -ServicePrincipalObject.

    .PARAMETER Days
    Number of days back to search. Cannot be used with -Start / -End.

    .PARAMETER Start
    Start of date range (parseable date string). Used with -End for an absolute range.

    .PARAMETER End
    End of date range (parseable date string). Used with -Start for an absolute range.

    .PARAMETER ChunkDays
    Splits the requested date range into sub-queries of this many days each, querying
    newest to oldest and merging the results. Default: 30. Pass a smaller value to break
    large pulls into windows small enough to return before Graph's per-request timeout.

    .PARAMETER ChunkDelaySeconds
    Seconds to pause between chunk queries to reduce throttling on multi-chunk pulls.
    Default: 2. Only applies when the range spans more than one chunk.

    .PARAMETER ThrottleDelaySeconds
    Base backoff (seconds) used when Graph throttles a request but does not return a
    Retry-After value. Backoff grows exponentially per retry. Default: 60.

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
    Find-IRTServicePrincipal MyApp
    Get-IRTEntraSPSignInLog
    Two-step workflow: find the SP then download its sign-in logs.

    .EXAMPLE
    Get-IRTEntraSPSignInLog -ServicePrincipalObject $SP -Days 90
    Downloads 90 days of sign-in logs for a specific service principal.

    .EXAMPLE
    Get-IRTEntraSPSignInLog -AllServicePrincipals -Days 7
    Downloads 7 days of sign-in logs for all service principals in the tenant.

    .OUTPUTS
    None. Results are exported to an Excel workbook.

    .NOTES
    Version: 2.0.0
    2.0.0 - Renamed from Get-IRTServicePrincipalSignInLog. Now a thin wrapper over the
            shared Invoke-IRTSignInLogQuery engine (parallel to Get-IRTEntraUserSignInLog),
            gaining chunking and throttle/timeout retry. Resolution falls back to globals
            via the new Get-GlobalServicePrincipalObject helper.
    1.0.0 - Initial version.
    #>
    [Alias('GetSPSILog', 'GetSPSILogs', 'SPSILog', 'SPSILogs')]
    [CmdletBinding(DefaultParameterSetName = 'ServicePrincipalObject')]
    param (
        [Parameter(Position = 0, ParameterSetName = 'ServicePrincipalObject')]
        [Alias('ServicePrincipalObjects')]
        [psobject[]] $ServicePrincipalObject,

        [Parameter(ParameterSetName = 'AllServicePrincipals')]
        [switch] $AllServicePrincipals,

        # relative date range
        [int] $Days,
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

        # resolve service principal objects
        switch ($ParameterSet) {
            'ServicePrincipalObject' {
                if (($ServicePrincipalObject | Measure-Object).Count -gt 0) {
                    $ScriptSPObjects = $ServicePrincipalObject
                }
                else {
                    $ScriptSPObjects = @(Get-GlobalServicePrincipalObject)
                    if (-not $ScriptSPObjects -or $ScriptSPObjects.Count -eq 0) {
                        $Msg = 'No service principal objects passed or found in global variables.'
                        Write-IRT $Msg -Level Error
                        return
                    }
                }
            }
            'AllServicePrincipals' {
                $null = $AllServicePrincipals  # switch controls parameter set
                $ScriptSPObjects = @(
                    [pscustomobject]@{
                        DisplayName = 'AllServicePrincipals'
                        Id          = $null
                    }
                )
            }
        }

        # get client domain name
        $DomainName = Get-DefaultDomain

        #region DATE RANGE

        $DefaultDays = 30

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
    }

    process {

        foreach ($ScriptSPObject in $ScriptSPObjects) {

            $FilterStrings = [System.Collections.Generic.List[string]]::new()

            #region FILTERS

            switch ($ParameterSet) {
                'ServicePrincipalObject' {
                    $Target = $ScriptSPObject.DisplayName
                    $FilterStrings.Add( "servicePrincipalId eq '$($ScriptSPObject.Id)'" )
                }
                'AllServicePrincipals' {
                    $Target = $DomainName
                    # don't add a service principal filter
                }
            }

            # restrict to service principal sign-in events
            $FilterStrings.Add( "signInEventTypes/any(t: t eq 'servicePrincipal')" )

            # build file names -- must be after target is set
            $FileNamePrefix = 'SPSignInLogs'
            $FileNameDateString = Get-Date -Format 'yy-MM-dd_HH-mm'
            $FileNameBase =
            "${FileNamePrefix}_${Days}Days_${DomainName}_${Target}_${FileNameDateString}"

            # build spreadsheet title
            $TitleDateFormat = 'M/d/yy h:mmtt'
            $TitleStartDate = $StartDateUtc.ToLocalTime().ToString($TitleDateFormat)
            $TitleEndDate = $EndDateUtc.ToLocalTime().ToString($TitleDateFormat)
            $SheetTitle = "Service principal sign-in logs for ${Target}." +
            " Covers ${Days} days, ${TitleStartDate} to ${TitleEndDate}."

            #region QUERY LOGS

            # hand off to the shared engine (chunking, throttle/retry, export, Show)
            $QueryParams = @{
                BaseFilter           = $FilterStrings
                StartDateUtc         = $StartDateUtc
                EndDateUtc           = $EndDateUtc
                Days                 = $Days
                Target               = $Target
                LogTypeLabel         = 'service principal sign-in'
                FileNamePrefix       = $FileNamePrefix
                FileNameBase         = $FileNameBase
                Title                = $SheetTitle
                ShowCommand          = 'Show-IRTEntraSPSignInLog'
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
