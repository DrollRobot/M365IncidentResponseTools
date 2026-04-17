function Request-GraphGroups {
    <#
	.SYNOPSIS
    Requests groups from Microsoft Graph. Caches in global variable.
	
	.NOTES
	Version: 2.0.0
	#>
    [CmdletBinding()]
    param (
        [switch] $Cached,
        [switch] $Test,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [ValidateSet('objects','tablebyid','none')]
        [string] $Return = 'objects'
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
    }

    process {

        # return cached data if available
        if ( $Cached ) {
            $Variable = Get-Variable -Scope Global -Name 'IRT_Groups' -ErrorAction SilentlyContinue
            if ( $Variable ) {
                switch ( $Return ) {
                    'objects'   { return $Global:IRT_Groups }
                    'tablebyid' { return $Global:IRT_GroupsById }
                    'none'      { return }
                }
            }
        }

        # get client domain name
        $DefaultDomain = Get-MgDomain | Where-Object { $_.IsDefault -eq $true }
        $DomainName = $DefaultDomain.Id -split '\.' | Select-Object -First 1

        # query graph
        $Params = @{
            All = $true
            Property = $GetProperties
            ExpandProperty = $ExpandProperty
        }
        $Objects = Get-MgGroup @Params | Select-Object $GetProperties

        # store in global variables
        $Global:IRT_Groups = $Objects
        $Global:IRT_GroupsById = @{}
        foreach ( $o in $Objects ) {
            if ( $o.Id ) { $Global:IRT_GroupsById[$o.Id] = $o }
        }

        # export to file
        if ($Xml) {
            $FileName = "Groups_Raw_${DomainName}_${FileNameDate}.xml"
            $XmlOutputPath = Join-Path -Path $CurrentPath -ChildPath $FileName
            if ( $Test ) {
                $ExportTime = Measure-Command { $Objects | Export-Clixml -Depth 5 -Path $XmlOutputPath }
                Write-Host "Export-Clixml took $( $ExportTime.TotalSeconds ) seconds" -ForegroundColor Cyan
            }
            else {
                $Objects | Export-Clixml -Depth 5 -Path $XmlOutputPath
            }
        }

        # return
        switch ( $Return ) {
            'objects'   { return $Global:IRT_Groups }
            'tablebyid' { return $Global:IRT_GroupsById }
            'none'      { return }
        }
    }
}