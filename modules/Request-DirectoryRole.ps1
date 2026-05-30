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
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [ValidateSet('objects','tablebyid','none')]
        [string] $Return = 'objects'
    )

    begin {
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

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
            $GvParams = @{
                Scope       = 'Global'
                Name        = 'IRT_DirectoryRoles'
                ErrorAction = 'SilentlyContinue'
            }
            $Variable = Get-Variable @GvParams
            if ( $Variable ) {
                switch ( $Return ) {
                    'objects'   { return $Global:IRT_DirectoryRoles }
                    'tablebyid' { return $Global:IRT_DirectoryRolesById }
                    'none'      { return }
                }
            }
        }

        # get client domain name
        $DomainName = Get-IRTDefaultDomain

        # query graph
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-Verbose "${FunctionName}: Get-MgDirectoryRole $Elapsed"
        $GdrParams = @{
            All            = $true
            Property       = $GetProperties
            ExpandProperty = $ExpandProperties
        }
        $Objects = Get-MgDirectoryRole @GdrParams |
            Select-Object ( $GetProperties + $ExpandProperties )

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
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-Verbose "${FunctionName}: Export-Clixml $Elapsed"
            $Objects | Export-Clixml -Depth 5 -Path $XmlOutputPath
        }

        # return
        switch ( $Return ) {
            'objects'   { return $Global:IRT_DirectoryRoles }
            'tablebyid' { return $Global:IRT_DirectoryRolesById }
            'none'      { return }
        }
    }
}
