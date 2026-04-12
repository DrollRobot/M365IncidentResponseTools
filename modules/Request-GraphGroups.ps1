function Request-GraphGroups {
    <#
	.SYNOPSIS
    Gets group information from local file, or from graph if local file doesn't exist
	
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
            'CreatedDateTime'
            'DisplayName'
            'Description'
            'Id'
            'OnPremisesSamAccountName'
            'OnPremisesSyncEnabled'
        )
        # $ExpandProperty = @( # FIXME expand property only retrieves up to 20 members. Need to switch to Get-MgGroupMember.
        #     'Members'
        # )
        # $SelectProperties = @(
        #     $GetProperties
        #     $ExpandProperty
        # )

        # get client domain name
        $DefaultDomain = Get-MgDomain | Where-Object { $_.IsDefault -eq $true }
        $DomainName = $DefaultDomain.Id -split '\.' | Select-Object -First 1
    }

    process {

        # get files in current directory that match pattern
        $FilterString = "Groups_Raw_${DomainName}_*.xml"
        $Files = Get-ChildItem -Filter $FilterString
        if ( $Files ) {
            $File = $Files | Sort-Object 'LastWriteTime' -Descending | Select-Object -First 1
            $Groups = Import-CliXml -Path $File.FullName
        }
        else {

            # get groups
            $Params = @{
                All = $true
                Property = $GetProperties
                ExpandProperty = $ExpandProperty
            }
            $Groups = Get-MgGroup @Params | Select-Object $GetProperties

            # save to file
            $FileName = "Groups_Raw_${DomainName}_${FileNameDate}.xml"
            $XmlOutputPath = Join-Path -Path $CurrentPath -ChildPath $FileName
            $Groups | Export-Clixml -Depth 5 -Path $XmlOutputPath
        }

        return $Groups
    }
}