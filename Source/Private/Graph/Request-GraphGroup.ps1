function Request-GraphGroup {
    <#
    .SYNOPSIS
    Requests groups from Microsoft Graph. Caches in global variable.

    .DESCRIPTION
    Internal helper. Fetches all Entra ID groups from Microsoft Graph and caches the
    result in a session-scoped global variable keyed by object ID. Subsequent callers
    that pass -Cached skip the API call. Used by the playbook and role-reporting functions
    to resolve group membership without repeated Graph requests.

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
            'CreatedDateTime'
            'DisplayName'
            'Description'
            'Id'
            'OnPremisesSamAccountName'
            'OnPremisesSyncEnabled'
        )

    }

    process {

        # return cached data if available
        if ( $Cached ) {
            $Variable = Get-Variable -Scope Global -Name 'IRT_Groups' -ErrorAction SilentlyContinue
            if ( $Variable ) {
                switch ( $Return ) {
                    'objects' { return $Global:IRT_Groups }
                    'tablebyid' { return $Global:IRT_GroupsById }
                    'none' { return }
                }
            }
        }

        # get client domain name
        $DomainName = Get-DefaultDomain

        # query graph
        Write-Verbose "${FunctionName}: Get-MgGroup $($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))"
        $Params = @{
            All = $true
            Property = $GetProperties
        }
        $Objects = Get-MgGroup @Params | Select-Object $GetProperties

        # fetch all members for each group (ExpandProperty is limited to 20)
        foreach ( $o in $Objects ) {
            $Members = Get-MgGroupMember -GroupId $o.Id -All
            $o | Add-Member -NotePropertyName 'Members' -NotePropertyValue $Members
        }

        # store in global variables
        $Global:IRT_Groups = $Objects
        $Global:IRT_GroupsById = [hashtable]::Synchronized(@{})
        foreach ( $o in $Objects ) {
            if ( $o.Id ) { $Global:IRT_GroupsById[$o.Id] = $o }
        }

        # export to file
        if ($Xml) {
            $FileName = "Groups_Raw_${DomainName}_${FileNameDate}.xml"
            $XmlOutputPath = Join-Path -Path $CurrentPath -ChildPath $FileName
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-Verbose "${FunctionName}: Export-Clixml $Elapsed"
            $Objects | Export-Clixml -Depth 5 -Path $XmlOutputPath
        }

        # return
        switch ( $Return ) {
            'objects' { return $Global:IRT_Groups }
            'tablebyid' { return $Global:IRT_GroupsById }
            'none' { return }
        }
    }
}
