function Request-GraphUsers {
    <#
	.SYNOPSIS
    Gets user information from local file, or from graph if local file doesn't exist
	
	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
    )

    begin {

        # variables
        $CurrentPath = Get-Location
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $FileNameDate = ( Get-Date ).ToString( $FileNameDateFormat )
        $GetProperties = @(
            'DisplayName'
            'AccountEnabled'
            'Id'
            'Mail'
            'OnPremisesLastSyncDateTime'
            'OnPremisesSamAccountName'
            'OnPremisesSyncEnabled'
            'ProxyAddresses'
            'UserPrincipalName'
        )

        # get client domain name
        $DefaultDomain = Get-MgDomain | Where-Object { $_.IsDefault -eq $true }
        $DomainName = $DefaultDomain.Id -split '\.' | Select-Object -First 1
    }

    process {

        # get files in current directory that match pattern
        $FilterString = "Users_Raw_${DomainName}_*.xml"
        $Files = Get-ChildItem -Filter $FilterString
        if ( $Files ) {
            $File = $Files | Sort-Object 'LastWriteTime' -Descending | Select-Object -First 1
            $Users = Import-CliXml -Path $File.FullName
        }
        else {
            $Users = Get-MgUser -All -Property $GetProperties | Select-Object $GetProperties
            $FileName = "Users_Raw_${DomainName}_${FileNameDate}.xml"
            $XmlOutputPath = Join-Path -Path $CurrentPath -ChildPath $FileName
            $Users | Export-Clixml -Depth 5 -Path $XmlOutputPath
        }

        return $Users
    }
}