function Get-IRTServicePrincipalSignInLog {
    <#
    .SYNOPSIS
    Downloads service principal sign-in logs.

    .DESCRIPTION
    Retrieves Entra ID service principal sign-in logs via Microsoft Graph for one or more
    service principals or all service principals in the tenant. Enriches each log entry
    with IP geolocation data and human-readable Entra error descriptions, then exports
    results to an Excel workbook.

    Date range defaults to the last 30 days when no -Days, -Start, or -End is specified.

    Falls back to $Global:IRT_ServicePrincipalObjects if no -ServicePrincipalObject is
    passed. Use Find-ServicePrincipal first to populate that global variable.

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
    Find-ServicePrincipal MyApp
    Get-IRTServicePrincipalSignInLog
    Two-step workflow: find the SP then download its sign-in logs.

    .EXAMPLE
    Get-IRTServicePrincipalSignInLog -ServicePrincipalObject $SP -Days 90
    Downloads 90 days of sign-in logs for a specific service principal.

    .EXAMPLE
    Get-IRTServicePrincipalSignInLog -AllServicePrincipals -Days 7
    Downloads 7 days of sign-in logs for all service principals in the tenant.

    .OUTPUTS
    None. Results are exported to an Excel workbook.

    .NOTES
    Version: 1.0.0
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

        [boolean] $Beta    = $true,
        [boolean] $Excel   = $true,
        [boolean] $IpInfo = [bool]$Global:IRT_Config.IpInfoAvailable,
        [boolean] $Open    = $true,
        [boolean] $Xml     = $Global:IRT_Config.ExportXml
    )

    begin {

        #region BEGIN

        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $ParameterSet = $PSCmdlet.ParameterSetName

        # resolve service principal objects
        switch ($ParameterSet) {
            'ServicePrincipalObject' {
                if (($ServicePrincipalObject | Measure-Object).Count -gt 0) {
                    $ScriptSPObjects = $ServicePrincipalObject
                }
                else {
                    $ScriptSPObjects = @($Global:IRT_ServicePrincipalObjects)
                    if (-not $ScriptSPObjects -or $ScriptSPObjects.Count -eq 0) {
                        $Msg = 'No service principal objects passed or found in global variables.'
                        Write-IRT $Msg -Level Error
                        return
                    }
                }
            }
            'AllServicePrincipals' {
                $null = $AllServicePrincipals
                $ScriptSPObjects = @(
                    [pscustomobject]@{
                        DisplayName = 'AllServicePrincipals'
                        Id          = $null
                    }
                )
            }
        }

        # get client domain name
        $DomainName = Get-IRTDefaultDomain

        #region DATE RANGE

        $DefaultDays = 30

        $DateRangeParams = @{
            Days        = $Days
            Start       = $Start
            End         = $End
            DefaultDays = $DefaultDays
        }
        $DateRange     = Resolve-IRTDateRange @DateRangeParams
        $DateRangeType = $DateRange.RangeType
        $Days          = $DateRange.Days
        $StartDateUtc  = $DateRange.StartUtc
        $EndDateUtc    = $DateRange.EndUtc
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
                    # no SP filter
                }
            }

            # build file names -- must be after target is set
            $FileNamePrefix     = 'SPSignInLogs'
            $FileNameDateFormat = 'yy-MM-dd_HH-mm'
            $FileNameDateString = Get-Date -Format $FileNameDateFormat
            $FileNameBase       =
                "${FileNamePrefix}_${Days}Days_${DomainName}_${Target}_${FileNameDateString}"
            $XmlOutputPath      = "${FileNameBase}.xml"

            # build spreadsheet title
            $TitleDateFormat = 'M/d/yy h:mmtt'
            $TitleStartDate  = $StartDateUtc.ToLocalTime().ToString($TitleDateFormat)
            $TitleEndDate    = $EndDateUtc.ToLocalTime().ToString($TitleDateFormat)
            $SheetTitle = "Service principal sign-in logs for ${Target}." +
                " Covers ${Days} days, ${TitleStartDate} to ${TitleEndDate}."

            # sign-in event type filter
            $FilterStrings.Add( "signInEventTypes/any(t: t eq 'servicePrincipal')" )

            # time range
            if ($DateRangeType -eq 'Relative') {
                if ($Days -ne 30) {
                    $FilterStrings.Add( "createdDateTime ge $($DateRange.StartString)" )
                }
            }
            elseif ($DateRangeType -eq 'Absolute') {
                $FilterStrings.Add( "createdDateTime ge $($DateRange.StartString)" )
                $FilterStrings.Add( "createdDateTime le $($DateRange.EndString)" )
            }

            $FilterString = $FilterStrings -join ' and '

            #region QUERY LOGS

            Write-IRT "Retrieving ${Days} days of service principal sign-in logs for ${Target}."
            Write-Verbose "${FunctionName}: Filter string: '${FilterString}'"
            Write-Verbose "${FunctionName}: Get-MgAuditLogSignIn $($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))"

            if ($Beta) {
                $GetParams = @{
                    Filter = $FilterString
                    All    = $true
                }
                [System.Collections.Generic.List[PSObject]]$Logs =
                    Get-MgBetaAuditLogSignIn @GetParams
            }
            else {
                $GetParams = @{
                    Filter = $FilterString
                    All    = $true
                }
                [System.Collections.Generic.List[PSObject]]$Logs = Get-MgAuditLogSignIn @GetParams
            }

            if (($Logs | Measure-Object).Count -eq 0) {
                Write-IRT "No logs found for ${Target} for past ${Days} days. Exiting." -Level Error
                continue
            }

            # add metadata to results
            $Logs.Insert(0,
                [pscustomobject]@{
                    Metadata       = $true
                    FileNamePrefix = $FileNamePrefix
                    FileName       = $FileNameBase
                    Title          = $SheetTitle
                }
            )

            #region OUTPUT

            $LogCount = ($Logs | Measure-Object).Count
            if ($LogCount -gt 0) {
                Write-IRT "Retrieved ${LogCount} logs."

                # export to xml
                if ($Xml) {
                    Write-Verbose "${FunctionName}: Export-Clixml $($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))"
                    Write-IRT "Saving logs to: ${XmlOutputPath}"
                    $Logs | Export-Clixml -Depth 10 -Path $XmlOutputPath
                }

                # export excel spreadsheet
                if ($Excel) {
                    Write-Verbose "${FunctionName}: Show-IRTServicePrincipalSignInLog $($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))"
                    $Params = @{
                        Logs   = $Logs
                        IpInfo = $IpInfo
                        Open   = $Open
                    }
                    Show-IRTServicePrincipalSignInLog @Params
                }
            }
            else {
                Write-IRT "Retrieved 0 logs." -Level Error
            }
        }
    }
}
