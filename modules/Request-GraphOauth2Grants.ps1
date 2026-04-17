function Request-GraphOauth2Grants {
    <#
	.SYNOPSIS
    Requests OAuth2 permission grants from Microsoft Graph. Caches in global variable.
	
	.NOTES
	Version: 2.0.0
	#>
    [CmdletBinding()]
    param (
        [switch] $Cached,
        [switch] $Test,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [ValidateSet('objects','tablebyclientid','none')]
        [string] $Return = 'objects'
    )

    begin {

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
            $Variable = Get-Variable -Scope Global -Name 'IRT_Oauth2Grants' -ErrorAction SilentlyContinue
            if ( $Variable ) {
                switch ( $Return ) {
                    'objects'          { return $Global:IRT_Oauth2Grants }
                    'tablebyclientid'  { return $Global:IRT_Oauth2GrantsByClientId }
                    'none'             { return }
                }
            }
        }

        # get client domain name
        $DefaultDomain = Get-MgDomain | Where-Object { $_.IsDefault -eq $true }
        $DomainName = $DefaultDomain.Id -split '\.' | Select-Object -First 1

        # query graph
        $Objects = Get-MgOauth2PermissionGrant -All # -Property $GetProperties | Select-Object $GetProperties # get all properties

        # store in global variables
        $Global:IRT_Oauth2Grants = $Objects
        $Global:IRT_Oauth2GrantsByClientId = @{}
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
            'objects'          { return $Global:IRT_Oauth2Grants }
            'tablebyclientid'  { return $Global:IRT_Oauth2GrantsByClientId }
            'none'             { return }
        }
    }
}