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
    Version: 2.1.0
    2.1.0 - A fetch that returns a Graph error is no longer cached.
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
        Import-IRTModule -Name 'Microsoft.Graph.Identity.SignIns', 'PSFramework'
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
                Write-PSFMessage -Level 8 -Message (
                    "${FunctionName}: Cache hit - returning $($Global:IRT_Oauth2Grants.Count) " +
                    "grant(s) (Return=$Return)")
                switch ( $Return ) {
                    'objects' { return $Global:IRT_Oauth2Grants }
                    'tablebyclientid' { return $Global:IRT_Oauth2GrantsByClientId }
                    'none' { return }
                }
            }
            Write-PSFMessage -Level 8 -Message (
                "${FunctionName}: -Cached requested but cache is empty; querying Graph.")
        }

        # get client domain name
        $DomainName = Get-DefaultDomain

        # query graph
        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Get-MgOauth2PermissionGrant [$Elapsed]")
        $Objects = Get-MgOauth2PermissionGrant -All -ErrorVariable GraphErrors

        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Graph returned $($Objects.Count) grant(s) [$Elapsed]")

        $GrantsByClientId = [hashtable]::Synchronized(@{})
        foreach ( $o in $Objects ) {
            $ClientId = $o.ClientId
            if ( $ClientId ) {
                if ( -not $GrantsByClientId.ContainsKey( $ClientId ) ) {
                    $GrantsByClientId[$ClientId] = @()
                }
                $GrantsByClientId[$ClientId] += $o
            }
        }
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Index built - $($GrantsByClientId.Count) unique client(s).")

        # store in global variables. Graph errors don't stop this function, so a failed
        # fetch would otherwise be cached and returned by every later -Cached call.
        if ( $GraphErrors ) {
            Write-PSFMessage -Level 8 -Message (
                "${FunctionName}: Graph returned an error; result not cached.")
        }
        else {
            $Global:IRT_Oauth2Grants = $Objects
            $Global:IRT_Oauth2GrantsByClientId = $GrantsByClientId
        }

        # export to file
        if ($Xml) {
            $FileName = "Oauth2Grants_Raw_${DomainName}_${FileNameDate}.xml"
            $XmlOutputPath = Join-Path -Path $CurrentPath -ChildPath $FileName
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-PSFMessage -Level 8 -Message (
                "${FunctionName}: Export-Clixml -> $XmlOutputPath [$Elapsed]")
            $Objects | Export-Clixml -Depth 5 -Path $XmlOutputPath
        }

        # return
        switch ( $Return ) {
            'objects' { return $Objects }
            'tablebyclientid' { return $GrantsByClientId }
            'none' { return }
        }
    }
}
