function Request-GraphUser {
    <#
    .SYNOPSIS
    Requests users from Microsoft Graph. Caches in global variable.

    .DESCRIPTION
    Internal helper. Fetches all Entra ID users from Microsoft Graph and caches the
    result in a session-scoped global variable keyed by object ID. Subsequent callers
    that pass -Cached skip the API call. Used by the playbook and admin role functions
    to resolve user identities without repeated Graph requests.

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
    }

    process {

        # return cached data if available
        if ( $Cached ) {
            $Variable = Get-Variable -Scope Global -Name 'IRT_Users' -ErrorAction SilentlyContinue
            if ( $Variable ) {
                switch ( $Return ) {
                    'objects'   { return $Global:IRT_Users }
                    'tablebyid' { return $Global:IRT_UsersById }
                    'none'      { return }
                }
            }
        }

        # get client domain name
        $DefaultDomain = Get-MgDomain | Where-Object { $_.IsDefault -eq $true }
        $DomainName = $DefaultDomain.Id -split '\.' | Select-Object -First 1

        # query graph
        $Objects = Get-MgUser -All -Property $GetProperties | Select-Object $GetProperties

        # store in global variables
        $Global:IRT_Users = $Objects
        $Global:IRT_UsersById = @{}
        foreach ( $o in $Objects ) {
            if ( $o.Id ) { $Global:IRT_UsersById[$o.Id] = $o }
        }

        # export to file
        if ($Xml) {
            $FileName = "Users_Raw_${DomainName}_${FileNameDate}.xml"
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
            'objects'   { return $Global:IRT_Users }
            'tablebyid' { return $Global:IRT_UsersById }
            'none'      { return }
        }
    }
}