New-Alias -Name "EALog" -Value "Get-EntraAuditLogs" -Force
New-Alias -Name "EALogs" -Value "Get-EntraAuditLogs" -Force
New-Alias -Name "GetEALog" -Value "Get-EntraAuditLogs" -Force
New-Alias -Name "GetEALogs" -Value "Get-EntraAuditLogs" -Force
New-Alias -Name "Get-EntraAuditLog" -Value "Get-EntraAuditLogs" -Force
function Get-EntraAuditLogs {
    <#
	.SYNOPSIS
	Downloads user sign in logs.	
	
	.NOTES
	Version: 1.1.0
	#>
    [CmdletBinding()]
    param (
        [Parameter( Position = 0 )]
        [Alias( 'UserObject' )]
        [psobject[]] $UserObjects,

        [int] $Days = 30,
        [switch] $AllUsers,
        [switch] $Beta,
        [switch] $Script,
        [boolean] $Open = $true,
        [switch] $Test
    )

    begin {

        #region BEGIN

        # constants
        # $Function = $MyInvocation.MyCommand.Name
        # $ParameterSet = $PSCmdlet.ParameterSetName
        $FilterStrings = [System.Collections.Generic.List[string]]::new()
        $XmlPaths = [System.Collections.Generic.List[string]]::new()
        $DateString = Get-Date -Format "yy-MM-dd_HH-mm"
        $QueryStart = ( Get-Date ).AddDays( $Days * -1 ).ToString( "yyyy-MM-ddTHH:mm:ssZ" )

        # colors
        $Blue = @{ ForegroundColor = 'Blue' }
        # $Green = @{ ForegroundColor = 'Green' }
        # $Red = @{ ForegroundColor = 'Red' }
        # $Magenta = @{ ForegroundColor = 'Magenta' }

        # if -AllUsers wasn't user, find user objects
        if ( -not $AllUsers ) {

            # if user objects not passed directly, find global
            if ( -not $UserObjects -or $UserObjects.Count -eq 0 ) {
        
                # get from global variables
                $ScriptUserObjects = Get-IRTUserObjects
                                
                # if none found, exit
                if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                    throw "No user objects passed or found in global variables."
                }
            }
            else {
                $ScriptUserObjects = $UserObjects
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
        $DefaultDomain = Get-MgDomain | Where-Object { $_.IsDefault -eq $true }
        $DomainName = $DefaultDomain.Id -split '\.' | Select-Object -First 1
    }

    process {

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            # variables
            $UserEmail = $ScriptUserObject.UserPrincipalName
            $UserName = $UserEmail -split '@' | Select-Object -First 1
            $UserId = $ScriptUserObject.Id 

            # build file names
            $XmlOutputPath = "EntraAuditLogs_${Days}Days_${DomainName}_${UserName}_${DateString}.xml"

            # build filter string
            if ( -not $AllUsers ) {
                $FilterStrings.Add( "targetResources/any(t:t/Id eq '${UserId}')" )
            }
            if ($Days -ne 30) {
                $FilterStrings.Add( "activityDateTime ge ${QueryStart}" )
            }
            $FilterString = $FilterStrings -join " and "

            ### get logs
            # user messages
            Write-Host @Blue "`nRetrieving ${Days} days of Entra audit logs for ${UserEmail}." | Out-Host
            Write-Verbose "Filter string: ${FilterString}" | Out-Host
            # Write-Host @Blue "This can take up to 5 minutes, depending on the number of logs." | Out-Host

            # query logs
            $GetParams = @{
                All    = $true
                Filter = $FilterString
            }
            if ( $Beta ) {
                $Logs = Get-MgBetaAuditLogDirectoryAudit @GetParams
            }
            else {
                $Logs = Get-MgAuditLogDirectoryAudit @GetParams
            }

            # show count
            $Count = @( $Logs ).Count
            if ( $Count -gt 0 ) {
                Write-Host @Blue "Retrieved ${Count} logs."
            }
            else {
                Write-Host @Red "Retrieved 0 logs."
                return
            }

            # export to xml
            Write-Host @Blue "`nSaving logs to: ${XmlOutputPath}"
            $Logs | Export-Clixml -Depth 10 -Path $XmlOutputPath
            
            if ( $Script -or $Open ) {
                $XmlPaths.Add( $XmlOutputPath )
            }
        }

        if ( $Script ) {
            return $XmlPaths
        }

        if ( $Open ) {
            foreach ( $XmlPath in $XmlPaths ) {
                $ShowParams = @{
                    XmlPath = $XmlPath
                    Open = $Open
                }
                Show-EntraAuditLogs @ShowParams
            }
        }
    }
}