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
    [OutputType([hashtable])]
    [CmdletBinding()]
    param (
        [switch] $Cached,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [ValidateSet('objects', 'tablebyid', 'none')]
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
                Write-PSFMessage -Level 8 -Message (
                    "${FunctionName}: Cache hit - returning $($Global:IRT_Users.Count) " +
                    "user(s) (Return=$Return)")
                switch ( $Return ) {
                    'objects' { return $Global:IRT_Users }
                    'tablebyid' { return $Global:IRT_UsersById }
                    'none' { return }
                }
            }
            Write-PSFMessage -Level 8 -Message (
                "${FunctionName}: -Cached requested but cache is empty; querying Graph.")
        }

        # get client domain name
        $DomainName = Get-DefaultDomain

        # query graph
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Get-MgUser [$($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))]")
        $Objects = Get-MgUser -All -Property $GetProperties | Select-Object $GetProperties

        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Graph returned $($Objects.Count) user(s) [$Elapsed]")

        # store in global variables
        $Global:IRT_Users = $Objects
        $Global:IRT_UsersById = [hashtable]::Synchronized(@{})
        foreach ( $o in $Objects ) {
            if ( $o.Id ) { $Global:IRT_UsersById[$o.Id] = $o }
        }
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Index built - $($Global:IRT_UsersById.Count) entry/entries.")

        # export to file
        if ($Xml) {
            $FileName = "Users_Raw_${DomainName}_${FileNameDate}.xml"
            $XmlOutputPath = Join-Path -Path $CurrentPath -ChildPath $FileName
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-PSFMessage -Level 8 -Message (
                "${FunctionName}: Export-Clixml -> $XmlOutputPath [$Elapsed]")
            $Objects | Export-Clixml -Depth 5 -Path $XmlOutputPath
        }

        # return
        switch ( $Return ) {
            'objects' { return $Global:IRT_Users }
            'tablebyid' { return $Global:IRT_UsersById }
            'none' { return }
        }
    }
}
