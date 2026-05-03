function Get-EntraAuditLog {
    <#
    .SYNOPSIS
    Downloads Entra ID (Azure AD) audit log events for one or more users.

    .DESCRIPTION
    Queries the Entra ID directory audit log via Microsoft Graph for activity related
    to the specified users over a configurable date range. Results are exported to an
    Excel workbook. Use -AllUsers to pull the full tenant audit log regardless of user.

    Date range defaults to the last 30 days when no -Days, -Start, or -End is specified.

    .PARAMETER UserObject
    One or more user objects to query. Falls back to global session objects if omitted.

    .PARAMETER Days
    Number of days back to search. Cannot be used with -Start / -End.

    .PARAMETER Start
    Start of date range (parseable date string). Used with -End for an absolute range.

    .PARAMETER End
    End of date range (parseable date string). Used with -Start for an absolute range.

    .PARAMETER AllUsers
    Pull the full tenant audit log without filtering by user.

    .PARAMETER Beta
    Use the Microsoft Graph beta endpoint instead of v1.0.

    .PARAMETER Open
    Open the Excel file immediately after export. Default: $true.

    .PARAMETER Xml
    Export raw XML alongside the Excel file. Defaults to IRT_Config.ExportXml.

    .PARAMETER Cached
    Use pre-cached Graph data instead of making new API calls.

    .EXAMPLE
    Get-EntraAuditLog
    Downloads the last 30 days of Entra audit events for the user in the global session.

    .EXAMPLE
    Get-EntraAuditLog -UserObject $User -Days 90
    Downloads 90 days of audit events for a specific user.

    .EXAMPLE
    Get-EntraAuditLog -AllUsers -Start '2026-04-01' -End '2026-04-30'
    Downloads all tenant audit events for April 2026.

    .OUTPUTS
    None. Results are exported to an Excel workbook.

    .NOTES
    Version: 1.1.0
    #>
    [Alias('EALog', 'EALogs', 'GetEALog', 'GetEALogs')]
    [CmdletBinding()]
    param (
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [int] $Days, # default set at DEFAULTDAYS
        [string] $Start,
        [string] $End,

        [switch] $AllUsers,
        [switch] $Beta,
        [boolean] $Open = $true,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [switch] $Cached
    )

    begin {
        $FilterStrings = [System.Collections.Generic.List[string]]::new()
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $FileNameDateString = Get-Date -Format $FileNameDateFormat
        $FileNamePrefix = 'EntraAuditLogs'

        # parse date ranges
        $DateRangeParams = @{
            Days        = $Days
            Start       = $Start
            End         = $End
            DefaultDays = 30 #DEFAULTDAYS
        }
        $DateRange = Resolve-IRTDateRange @DateRangeParams
        $Days         = $DateRange.Days
        $StartDateUtc = $DateRange.StartUtc
        $EndDateUtc   = $DateRange.EndUtc

        # if -AllUsers wasn't user, find user objects
        if (-not $AllUsers) {

            # if user objects not passed directly, find global
            if ( -not $UserObject -or $UserObject.Count -eq 0 ) {

                # get from global variables
                $ScriptUserObjects = Get-IRTUserObject

                # if none found, exit
                if (-not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0) {
                    throw "No user objects passed or found in global variables."
                }
            }
            else {
                $ScriptUserObjects = $UserObject
            }
        }
        # if -AllUsers was used, create fake user object user loop will happen
        else {

            $ScriptUserObjects = @(
                [pscustomobject]@{
                    UserPrincipalName = 'AllUsers'
                }
            )
        }

        # get client domain name
        $DefaultDomain = Get-MgDomain | Where-Object {$_.IsDefault -eq $true}
        $DomainName = $DefaultDomain.Id -split '\.' | Select-Object -First 1
    }

    process {

        foreach ($ScriptUserObject in $ScriptUserObjects) {

            # variables
            $UserEmail = $ScriptUserObject.UserPrincipalName
            $UserName = $UserEmail -split '@' | Select-Object -First 1
            $UserId = $ScriptUserObject.Id

            # build file names
            $XmlOutputPath = "${FileNamePrefix}_${Days}Days_${DomainName}_${UserName}_${FileNameDateString}.xml"

            # build filter string
            if (-not $AllUsers) {
                $FilterStrings.Add("targetResources/any(t:t/Id eq '${UserId}')")
            }
            if ($DateRange.RangeType -eq 'Relative') {
                if ($Days -ne 30) { # don't use filter if date range is maximum
                    $FilterStrings.Add( "activityDateTime ge $($DateRange.StartString)" )
                }
            }
            elseif ($DateRange.RangeType -eq 'Absolute') {
                $FilterStrings.Add( "activityDateTime ge $($DateRange.StartString)" )
                $FilterStrings.Add( "activityDateTime le $($DateRange.EndString)" )
            }
            $FilterString = $FilterStrings -join " and "

            ### get logs
            # user messages
            Write-IRT "Retrieving ${Days} days of Entra audit logs for ${UserEmail}."
            if ($Script:Test) {
                Write-IRT "Filter string: ${FilterString}" -Level Warn
            }

            # query logs
            $GetParams = @{
                All    = $true
                Filter = $FilterString
            }
            if ($Beta) {
                [System.Collections.Generic.List[PSObject]]$Logs = Get-MgBetaAuditLogDirectoryAudit @GetParams
            }
            else {
                [System.Collections.Generic.List[PSObject]]$Logs = Get-MgAuditLogDirectoryAudit @GetParams
            }

            # show count
            $Count = ($Logs | Measure-Object).Count
            if ($Count -gt 0) {
                Write-IRT "Retrieved ${Count} logs."
            }
            else {
                Write-IRT "Retrieved 0 logs." -Level Warn
                continue
            }

            # add metadata to results
            $Logs.Insert(0,
                [pscustomobject]@{
                    Metadata       = $true
                    UserObject     = $ScriptUserObject
                    UserEmail      = $UserEmail
                    UserName       = $UserName
                    StartDate      = $StartDateUtc.ToLocalTime()
                    EndDate        = $EndDateUtc.ToLocalTime()
                    Days           = $Days
                    DomainName     = $DomainName
                    FileNamePrefix = $FileNamePrefix
                }
            )

            # export to xml
            if ($Xml) {
                Write-IRT "Saving logs to: ${XmlOutputPath}"
                $Logs | Export-Clixml -Depth 10 -Path $XmlOutputPath
            }

            $ShowParams = @{
                Logs   = $Logs
                Open   = $Open
                Cached = $Cached
            }
            Show-EntraAuditLog @ShowParams
        }
    }
}
