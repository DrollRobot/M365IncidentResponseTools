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
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [ValidateSet('objects','tablebyappid','tablebyid','none')]
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
            $GvParams = @{
                Scope       = 'Global'
                Name        = 'IRT_ServicePrincipals'
                ErrorAction = 'SilentlyContinue'
            }
            $Variable = Get-Variable @GvParams
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
        $DomainName = Get-IRTDefaultDomain

        # query graph
        Write-Verbose "${FunctionName}: Get-MgServicePrincipal $($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))"
        $Objects = Get-MgServicePrincipal -All | Select-Object ($GetProperties)

        # extract CreatedDateTime from AdditionalProperties
        foreach ($o in $Objects) {
            if ($o.AdditionalProperties['createdDateTime']) {
                $CreatedDateTime = [datetime]::Parse($o.AdditionalProperties['createdDateTime'])
                $AmParams = @{
                    NotePropertyName  = 'CreatedDateTime'
                    NotePropertyValue = $CreatedDateTime
                    Force             = $true
                }
                $o | Add-Member @AmParams
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
            Write-Verbose "${FunctionName}: Export-Clixml $($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))"
            $Objects | Export-Clixml -Depth 10 -Path $XmlOutputPath
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
