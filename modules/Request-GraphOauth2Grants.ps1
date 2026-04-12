function Request-GraphOauth2Grants {
    <#
	.SYNOPSIS
    Gets oauth2 permission grant information from local file, or from graph if local file doesn't exist
	
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
        # $GetProperties = @(
        # )

        # get client domain name
        $DefaultDomain = Get-MgDomain | Where-Object { $_.IsDefault -eq $true }
        $DomainName = $DefaultDomain.Id -split '\.' | Select-Object -First 1

        $String = "Oauth2Grants_Raw_${DomainName}"
        $FilterString = "${String}_*.xml"
        $FileName = "${String}_${FileNameDate}.xml"
    }

    process {

        # get files in current directory that match pattern
        $Files = Get-ChildItem -Filter $FilterString
        if ( $Files ) {
            $File = $Files | Sort-Object 'LastWriteTime' -Descending | Select-Object -First 1
            $Objects = Import-CliXml -Path $File.FullName
        }
        else {
            $Objects = Get-MgOauth2PermissionGrant -All # -Property $GetProperties | Select-Object $GetProperties # get all properties
            $XmlOutputPath = Join-Path -Path $CurrentPath -ChildPath $FileName
            $Objects | Export-Clixml -Depth 5 -Path $XmlOutputPath
        }

        return $Objects
    }
}