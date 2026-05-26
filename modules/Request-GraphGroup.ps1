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
                    'objects'   { return $Global:IRT_Groups }
                    'tablebyid' { return $Global:IRT_GroupsById }
                    'none'      { return }
                }
            }
        }

        # get client domain name
        $DefaultDomain = Get-MgDomain | Where-Object { $_.IsDefault -eq $true }
        $DomainName = $DefaultDomain.Id -split '\.' | Select-Object -First 1

        # query graph
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
            if ( $Test ) {
                $ExportTime = Measure-Command {
                    $Objects | Export-Clixml -Depth 5 -Path $XmlOutputPath
                }
                Write-IRT "Export-Clixml took $( $ExportTime.TotalSeconds ) seconds"
            }
            else {
                $Objects | Export-Clixml -Depth 5 -Path $XmlOutputPath
            }
        }

        # return
        switch ( $Return ) {
            'objects'   { return $Global:IRT_Groups }
            'tablebyid' { return $Global:IRT_GroupsById }
            'none'      { return }
        }
    }
}
