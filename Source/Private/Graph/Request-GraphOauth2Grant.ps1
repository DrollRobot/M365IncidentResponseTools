function Request-GraphOauth2Grant {
    <#
    .SYNOPSIS
    Requests OAuth2 permission grants from Microsoft Graph. Caches in global variable.

    .DESCRIPTION
    Internal helper. Fetches all delegated OAuth2 permission grants from Microsoft Graph
    and caches them in a session-scoped global variable keyed by client ID. Used by
    Get-IRTUserServicePrincipal and Find-IRTRiskyServicePrincipal to resolve which users
    have consented to which applications without repeated Graph requests.

    .NOTES
    Version: 2.0.0
    #>
    [OutputType([hashtable])]
    [CmdletBinding()]
    param (
        [switch] $Cached,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [ValidateSet('objects', 'tablebyclientid', 'none')]
        [string] $Return = 'objects'
    )

    begin {
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # variables
        $CurrentPath = Get-Location
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $FileNameDate = ( Get-Date ).ToString( $FileNameDateFormat )
        # $GetProperties = @(
        # )
    }

    process {

        # return cached data if available
        if ( $Cached ) {
            $GvParams = @{
                Scope       = 'Global'
                Name        = 'IRT_Oauth2Grants'
                ErrorAction = 'SilentlyContinue'
            }
            $Variable = Get-Variable @GvParams
            if ( $Variable ) {
                switch ( $Return ) {
                    'objects' { return $Global:IRT_Oauth2Grants }
                    'tablebyclientid' { return $Global:IRT_Oauth2GrantsByClientId }
                    'none' { return }
                }
            }
        }

        # get client domain name
        $DomainName = Get-DefaultDomain

        # query graph
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-Verbose "${FunctionName}: Get-MgOauth2PermissionGrant $Elapsed"
        $Objects = Get-MgOauth2PermissionGrant -All

        # store in global variables
        $Global:IRT_Oauth2Grants = $Objects
        $Global:IRT_Oauth2GrantsByClientId = [hashtable]::Synchronized(@{})
        foreach ( $o in $Objects ) {
            $ClientId = $o.ClientId
            if ( $ClientId ) {
                if ( -not $Global:IRT_Oauth2GrantsByClientId.ContainsKey( $ClientId ) ) {
                    $Global:IRT_Oauth2GrantsByClientId[$ClientId] = @()
                }
                $Global:IRT_Oauth2GrantsByClientId[$ClientId] += $o
            }
        }

        # export to file
        if ($Xml) {
            $FileName = "Oauth2Grants_Raw_${DomainName}_${FileNameDate}.xml"
            $XmlOutputPath = Join-Path -Path $CurrentPath -ChildPath $FileName
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-Verbose "${FunctionName}: Export-Clixml $Elapsed"
            $Objects | Export-Clixml -Depth 5 -Path $XmlOutputPath
        }

        # return
        switch ( $Return ) {
            'objects' { return $Global:IRT_Oauth2Grants }
            'tablebyclientid' { return $Global:IRT_Oauth2GrantsByClientId }
            'none' { return }
        }
    }
}
