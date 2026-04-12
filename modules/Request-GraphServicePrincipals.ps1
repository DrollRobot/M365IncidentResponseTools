function Request-GraphServicePrincipals {
    <#
	.SYNOPSIS
    Gets serviceprincipal information from local file, or from graph if local file doesn't exist
	
	.NOTES
	Version: 1.1.0
    1.1.0 - Added creating table by app id in global variable
	#>
    [CmdletBinding()]
    param (
        [switch] $ForceRefresh,
	    [ValidateSet('objects','tablebyappid','none')]
        [string] $Return = 'objects'
    )

    begin {

        function Get-ServicePrincipalStuff {
            # get client domain name
            $DefaultDomain = Get-MgDomain | Where-Object { $_.IsDefault -eq $true }
            $DomainName = $DefaultDomain.Id -split '\.' | Select-Object -First 1
            $FileName = "ServicePrincipals_Raw_${DomainName}_${FileNameDate}.xml"

            # get sp objects
            $Objects = Get-MgServicePrincipal -All | Select-Object $GetProperties

            # output to file
            $Objects | Export-Clixml -Depth 10 -Path $FileName

            # create global variable 
            $Global:IRT_ServicePrincipals = $Objects

            # create hashtable by app id
            $Global:IRT_ServicePrincipalsByAppId = @{}
            foreach ($o in $Objects) {
                $AppId = $o.AppId
                if ($AppId) {
                    $Global:IRT_ServicePrincipalsByAppId["$AppId"] = $o
                }
            }
        }

        # variables
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $FileNameDate = (Get-Date).ToString( $FileNameDateFormat )
        $GetProperties = @(
            'AdditionalProperties'
            'AppDescription'
            'AppId'
            'AppOwnerOrganizationId'
            'Description'
            'DisplayName'
            'Id'
        )
    }

    process {

        # check if global variable already exists.
        $Variable = Get-Variable -Scope Global -Name "IRT_ServicePrincipals" -ErrorAction SilentlyContinue
        if ($Variable) { # if variable exists
            if ($ForceRefresh) { # if -ForceRefresh, remove variables then recreate
                # clear existing variables
                Remove-Variable -Scope Global -Name "IRT_ServicePrincipals*"
                Get-ServicePrincipalStuff
            }
            # if variable exists and no -ForceRefresh, no action needed
        }
        else { # if no variable, make file and variables
            Get-ServicePrincipalStuff
        }

        switch ($Return) {
            'objects' { return $Global:IRT_ServicePrincipals }
            'tablebyappid' { return $Global:IRT_ServicePrincipalsByAppId }
            'none' { return }
        }       
    }
}