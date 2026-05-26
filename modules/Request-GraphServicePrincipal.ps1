function Request-GraphServicePrincipal {
    <#
    .SYNOPSIS
    Requests service principals from Microsoft Graph. Caches in global variable.

    .DESCRIPTION
    Internal helper. Fetches all Entra ID service principals from Microsoft Graph and
    caches the result in a session-scoped global variable keyed by app ID and object ID.
    Used by Get-UserServicePrincipal, Find-RiskyServicePrincipal, and Get-AdminRole to resolve
    service principal identities without repeated Graph requests.

    .NOTES
    Version: 2.0.0
    #>
    [OutputType([hashtable])]
    [CmdletBinding()]
    param (
        [switch] $Cached,
        [switch] $Test,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [ValidateSet('objects','tablebyappid','tablebyid','none')]
        [string] $Return = 'objects'
    )

    begin {

        # variables
        $CurrentPath = Get-Location
        $FileNameDateFormat = "yy-MM-dd_HH-mm"
        $FileNameDate = ( Get-Date ).ToString( $FileNameDateFormat )
        $GetProperties = @(
            'AccountEnabled'
            'AdditionalProperties'
            'AppDescription'
            'AppDisplayName'
            'AppId'
            'AppOwnerOrganizationId'
            'Description'
            'DisplayName'
            'Id'
            'ReplyUrls'
            'ServicePrincipalType'
            'SignInAudience'
        )
    }

    process {

        # return cached data if available
        if ($Cached) {
            $Variable = Get-Variable -Scope Global -Name 'IRT_ServicePrincipals' -ErrorAction SilentlyContinue
            if ($Variable) {
                switch ($Return) {
                    'objects'      {return $Global:IRT_ServicePrincipals}
                    'tablebyappid' {return $Global:IRT_ServicePrincipalsByAppId}
                    'tablebyid'    {return $Global:IRT_ServicePrincipalsById}
                    'none'         {return}
                }
            }
        }

        # get client domain name
        $DefaultDomain = Get-MgDomain | Where-Object {$_.IsDefault -eq $true}
        $DomainName = $DefaultDomain.Id -split '\.' | Select-Object -First 1

        # query graph
        $Objects = Get-MgServicePrincipal -All | Select-Object ($GetProperties)

        # extract CreatedDateTime from AdditionalProperties
        foreach ($o in $Objects) {
            if ($o.AdditionalProperties['createdDateTime']) {
                $CreatedDateTime = [datetime]::Parse($o.AdditionalProperties['createdDateTime'])
                $o | Add-Member -NotePropertyName 'CreatedDateTime' -NotePropertyValue $CreatedDateTime -Force
            }
        }

        # store in global variables
        $Global:IRT_ServicePrincipals = $Objects
        $Global:IRT_ServicePrincipalsByAppId = [hashtable]::Synchronized(@{})
        $Global:IRT_ServicePrincipalsById = [hashtable]::Synchronized(@{})
        foreach ($o in $Objects) {
            if ($o.AppId) {$Global:IRT_ServicePrincipalsByAppId[$o.AppId] = $o}
            if ($o.Id)    {$Global:IRT_ServicePrincipalsById[$o.Id] = $o}
        }

        # export to file
        if ($Xml) {
            $FileName = "ServicePrincipals_Raw_${DomainName}_${FileNameDate}.xml"
            $XmlOutputPath = Join-Path -Path $CurrentPath -ChildPath $FileName
            if ($Test) {
                $ExportTime = Measure-Command { $Objects | Export-Clixml -Depth 10 -Path $XmlOutputPath }
                Write-IRT "Export-Clixml took $( $ExportTime.TotalSeconds ) seconds"
            }
            else {
                $Objects | Export-Clixml -Depth 10 -Path $XmlOutputPath
            }
        }

        # return
        switch ($Return) {
            'objects'      {return $Global:IRT_ServicePrincipals}
            'tablebyappid' {return $Global:IRT_ServicePrincipalsByAppId}
            'tablebyid'    {return $Global:IRT_ServicePrincipalsById}
            'none'         {return}
        }
    }
}

# TESTING
# Request-GraphServicePrincipal
