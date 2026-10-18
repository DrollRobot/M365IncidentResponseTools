function Request-GraphServicePrincipal {
    <#
    .SYNOPSIS
    Requests service principals from Microsoft Graph. Caches in global variable.

    .DESCRIPTION
    Internal helper. Fetches all Entra ID service principals from Microsoft Graph and
    caches the result in a session-scoped global variable keyed by app ID and object ID.
    Used by Get-IRTUserServicePrincipal, Find-IRTRiskyServicePrincipal, and Get-IRTAdminRole
    to resolve service principal identities without repeated Graph requests.

    .NOTES
    Version: 2.1.0
    2.1.0 - A fetch that returns a Graph error is no longer cached.
    #>
    [OutputType([hashtable])]
    [CmdletBinding()]
    param (
        [switch] $Cached,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [ValidateSet('objects', 'tablebyappid', 'tablebyid', 'none')]
        [string] $Return = 'objects'
    )

    begin {
        Import-IRTModule -Name 'Microsoft.Graph.Applications', 'PSFramework'
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
                Write-PSFMessage -Level 8 -Message (
                    "${FunctionName}: Cache hit - returning " +
                    "$($Global:IRT_ServicePrincipals.Count) SP(s) (Return=$Return)")
                switch ($Return) {
                    'objects' { return $Global:IRT_ServicePrincipals }
                    'tablebyappid' { return $Global:IRT_ServicePrincipalsByAppId }
                    'tablebyid' { return $Global:IRT_ServicePrincipalsById }
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
            "${FunctionName}: Get-MgServicePrincipal [$Elapsed]")
        $Objects = Get-MgServicePrincipal -All -ErrorVariable GraphErrors |
            Select-Object ($GetProperties)

        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Graph returned $($Objects.Count) SP(s) [$Elapsed]")

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

        $SPsByAppId = [hashtable]::Synchronized(@{})
        $SPsById = [hashtable]::Synchronized(@{})
        foreach ($o in $Objects) {
            if ($o.AppId) { $SPsByAppId[$o.AppId] = $o }
            if ($o.Id) { $SPsById[$o.Id] = $o }
        }
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Indexes built - " +
            "$($SPsByAppId.Count) by AppId, $($SPsById.Count) by Id.")

        # store in global variables. Graph errors don't stop this function, so a failed
        # fetch would otherwise be cached and returned by every later -Cached call.
        if ($GraphErrors) {
            Write-PSFMessage -Level 8 -Message (
                "${FunctionName}: Graph returned an error; result not cached.")
        }
        else {
            $Global:IRT_ServicePrincipals = $Objects
            $Global:IRT_ServicePrincipalsByAppId = $SPsByAppId
            $Global:IRT_ServicePrincipalsById = $SPsById
        }

        # export to file
        if ($Xml) {
            $FileName = "ServicePrincipals_Raw_${DomainName}_${FileNameDate}.xml"
            $XmlOutputPath = Join-Path -Path $CurrentPath -ChildPath $FileName
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-PSFMessage -Level 8 -Message (
                "${FunctionName}: Export-Clixml -> $XmlOutputPath [$Elapsed]")
            $Objects | Export-Clixml -Depth 10 -Path $XmlOutputPath
        }

        # return
        switch ($Return) {
            'objects' { return $Objects }
            'tablebyappid' { return $SPsByAppId }
            'tablebyid' { return $SPsById }
            'none' { return }
        }
    }
}
