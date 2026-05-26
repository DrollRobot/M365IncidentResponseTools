function Request-DirectoryRole {
    <#
    .SYNOPSIS
    Requests directory roles from Microsoft Graph. Caches in global variable.

    .DESCRIPTION
    Internal helper. Fetches all Entra ID directory roles (with their members) from
    Microsoft Graph and caches the result in a session-scoped global variable. Subsequent
    callers that pass -Cached skip the API call and read from the cache. Used by
    Get-AdminRole and the incident response playbook to avoid redundant Graph requests.

    .NOTES
    Version: 2.0.0
    #>
    [OutputType([hashtable])]
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
            'DisplayName'
            'Id'
            'RoleTemplateId'
        )
        $ExpandProperties = @( 'Members' )
    }

    process {

        # return cached data if available
        if ( $Cached ) {
            $Variable = Get-Variable -Scope Global -Name 'IRT_DirectoryRoles' -ErrorAction SilentlyContinue
            if ( $Variable ) {
                switch ( $Return ) {
                    'objects'   { return $Global:IRT_DirectoryRoles }
                    'tablebyid' { return $Global:IRT_DirectoryRolesById }
                    'none'      { return }
                }
            }
        }

        # get client domain name
        $DefaultDomain = Get-MgDomain | Where-Object { $_.IsDefault -eq $true }
        $DomainName = $DefaultDomain.Id -split '\.' | Select-Object -First 1

        # query graph
        $Objects = Get-MgDirectoryRole -All -Property $GetProperties -ExpandProperty $ExpandProperties | Select-Object ( $GetProperties + $ExpandProperties )

        # store in global variables
        $Global:IRT_DirectoryRoles = $Objects
        $Global:IRT_DirectoryRolesById = [hashtable]::Synchronized(@{})
        foreach ( $o in $Objects ) {
            if ( $o.Id ) { $Global:IRT_DirectoryRolesById[$o.Id] = $o }
        }

        # export to file
        if ($Xml) {
            $FileName = "DirectoryRoles_Raw_${DomainName}_${FileNameDate}.xml"
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
            'objects'   { return $Global:IRT_DirectoryRoles }
            'tablebyid' { return $Global:IRT_DirectoryRolesById }
            'none'      { return }
        }
    }
}
