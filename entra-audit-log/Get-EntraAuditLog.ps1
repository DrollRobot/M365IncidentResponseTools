New-Alias -Name "EALog" -Value "Get-EntraAuditLog" -Force
New-Alias -Name "EALogs" -Value "Get-EntraAuditLog" -Force
New-Alias -Name "GetEALog" -Value "Get-EntraAuditLog" -Force
New-Alias -Name "GetEALogs" -Value "Get-EntraAuditLog" -Force
function Get-EntraAuditLog {
    <#
	.SYNOPSIS
	Downloads user sign in logs.

	.NOTES
	Version: 1.1.0
	#>
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

        #region BEGIN

        # constants
        $Function = $MyInvocation.MyCommand.Name
        # $ParameterSet = $PSCmdlet.ParameterSetName
        $FilterStrings = [System.Collections.Generic.List[string]]::new()
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $FileNameDateString = Get-Date -Format $FileNameDateFormat
        $FileNamePrefix = 'EntraAuditLogs'
        $Blue = @{ForegroundColor = 'Blue'}
        $Red = @{ForegroundColor = 'Red'}

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
            Write-Host @Blue "`n${Function}: Retrieving ${Days} days of Entra audit logs for ${UserEmail}." | Out-Host
            Write-Verbose "Filter string: ${FilterString}" | Out-Host
            # Write-Host @Blue "This can take up to 5 minutes, depending on the number of logs." | Out-Host

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
                Write-Host @Blue "${Function}: Retrieved ${Count} logs."
            }
            else {
                Write-Host @Red "${Function}: Retrieved 0 logs."
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
                Write-Host @Blue "`n${Function}: Saving logs to: ${XmlOutputPath}"
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