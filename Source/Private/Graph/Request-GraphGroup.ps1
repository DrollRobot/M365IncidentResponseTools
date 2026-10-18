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
    Version: 2.1.0
    2.1.0 - A group list fetch that returns a Graph error is no longer cached.
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
        Import-IRTModule -Name 'Microsoft.Graph.Groups', 'PSFramework'
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
                Write-PSFMessage -Level 8 -Message (
                    "${FunctionName}: Cache hit - returning $($Global:IRT_Groups.Count) " +
                    "group(s) (Return=$Return)")
                switch ( $Return ) {
                    'objects' { return $Global:IRT_Groups }
                    'tablebyid' { return $Global:IRT_GroupsById }
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
            "${FunctionName}: Get-MgGroup [$($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))]")
        $Params = @{
            All           = $true
            Property      = $GetProperties
            ErrorVariable = 'GraphErrors'
        }
        $Objects = Get-MgGroup @Params | Select-Object $GetProperties
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Graph returned $($Objects.Count) group(s) " +
            "[$($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))]")

        # fetch all members for each group (ExpandProperty is limited to 20)
        foreach ( $o in $Objects ) {
            Write-PSFMessage -Level 9 -Message (
                "${FunctionName}: Get-MgGroupMember for '$($o.DisplayName)' ($($o.Id))")
            $Members = Get-MgGroupMember -GroupId $o.Id -All
            $o | Add-Member -NotePropertyName 'Members' -NotePropertyValue $Members
        }
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Member fetch complete " +
            "[$($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))]")

        $GroupsById = [hashtable]::Synchronized(@{})
        foreach ( $o in $Objects ) {
            if ( $o.Id ) { $GroupsById[$o.Id] = $o }
        }
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Index built - $($GroupsById.Count) entry/entries.")

        # store in global variables. Graph errors don't stop this function, so a failed
        # group list fetch would otherwise be cached and returned by every later -Cached
        # call. A failed member fetch for one group is left alone: some groups hide
        # their membership, and that one group should not block the whole cache.
        if ( $GraphErrors ) {
            Write-PSFMessage -Level 8 -Message (
                "${FunctionName}: Graph returned an error; result not cached.")
        }
        else {
            $Global:IRT_Groups = $Objects
            $Global:IRT_GroupsById = $GroupsById
        }

        # export to file
        if ($Xml) {
            $FileName = "Groups_Raw_${DomainName}_${FileNameDate}.xml"
            $XmlOutputPath = Join-Path -Path $CurrentPath -ChildPath $FileName
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-PSFMessage -Level 8 -Message (
                "${FunctionName}: Export-Clixml -> $XmlOutputPath [$Elapsed]")
            $Objects | Export-Clixml -Depth 5 -Path $XmlOutputPath
        }

        # return
        switch ( $Return ) {
            'objects' { return $Objects }
            'tablebyid' { return $GroupsById }
            'none' { return }
        }
    }
}
