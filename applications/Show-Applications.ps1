New-Alias -Name 'ShowApps' -Value 'Show-Applications' -Force
function Show-Applications {
    <#
	.SYNOPSIS
	
	
	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
        [string] $Search
    )

    begin {

        # variables
        $TenantId = ( Get-MgContext ).TenantId
        $Apps = Get-MgApplication -All
        $ServicePrincipals = Get-MgServicePrincipal -All

        # colors
        $Blue = @{ ForegroundColor = 'Blue' }
    }

    process {

        Write-Host @Blue "`nTenant ID: ${TenantId}`n"

        ### APPS

        if ( $Search ) {
            Write-Host @Blue "Applications matching: ${Search}"
            $MatchingApps = $Apps | Where-Object { $_.DisplayName -match $Search }
        }
        else {
            Write-Host @Blue "All applications:"
            $MatchingApps = $Apps
        }

        $OutputTable = [System.Collections.Generic.List[pscustomobject]]::new()

        foreach ( $App in $MatchingApps ) {

            # change date to local time
            $CreatedDateTime = $App.CreatedDateTime
            if ( $CreatedDateTime ) {
                $CreatedDateTime = $CreatedDateTime.ToLocalTime()
            }

            # display app
            $OutputTable.Add( [pscustomobject]@{
                CreatedDateTime = $CreatedDateTime
                DisplayName = $App.DisplayName
                SignInAudience = $App.SignInAudience
                AppId = $App.AppId
                Id = $App.Id
            } )
        }

        if ( $Search ) {
            $OutputTable | Format-List
        }
        else {
            $OutputTable | Format-Table
        }

        ### SERVICE PRINCIPALS
        
        if ( $Search ) {
            Write-Host @Blue "Service principals matching: ${Search}"
            $MatchingServicePrincipals = $ServicePrincipals | Where-Object { $_.DisplayName -match $Search }
        }
        else {
            Write-Host @Blue "All service principals:"
            $MatchingServicePrincipals = $ServicePrincipals
        }

        $OutputTable = [System.Collections.Generic.List[pscustomobject]]::new()

        foreach ( $ServicePrincipal in $MatchingServicePrincipals ) {

            # change date to local time
            $CreatedDateTime = $ServicePrincipal.AdditionalProperties.createdDateTime
            if ( $CreatedDateTime ) {
                $CreatedDateTime = [datetime]::Parse( $CreatedDateTime ).ToLocalTime()
            }

            # display sp
            $OutputTable.Add( [pscustomobject]@{
                CreatedDateTime = $CreatedDateTime
                DisplayName = $ServicePrincipal.DisplayName
                AppDisplayName = $ServicePrincipal.AppDisplayName
                ServicePrincipalType = $ServicePrincipal.ServicePrincipalType
                SignInAudience = $ServicePrincipal.SignInAudience
                ReplyUrls = $ServicePrincipal.ReplyUrls
                AppOwnerOrganizationId = $ServicePrincipal.AppOwnerOrganizationId
                AppId = $ServicePrincipal.AppId
                Id = $ServicePrincipal.Id
            } )
        }

        if ( $Search ) {
            $OutputTable | Format-List
        }
        else {
            $OutputTable | Format-Table
        }
    }
}