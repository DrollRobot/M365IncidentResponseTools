function Request-DirectoryRoleTemplate {
    <#
    .SYNOPSIS
    Requests directory role templates from Microsoft Graph. Caches in global variable.

    .DESCRIPTION
    Internal helper. Fetches all Entra ID directory role templates from Microsoft Graph
    and caches the result in a session-scoped global variable. Used alongside
    Request-DirectoryRole to resolve role display names during admin role reporting.

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
            'Id'
        )
    }

    process {

        # return cached data if available
        if ( $Cached ) {
            $GvParams = @{
                Scope       = 'Global'
                Name        = 'IRT_DirectoryRoleTemplates'
                ErrorAction = 'SilentlyContinue'
            }
            $Variable = Get-Variable @GvParams
            if ( $Variable ) {
                Write-PSFMessage -Level 8 -Message (
                    "${FunctionName}: Cache hit — returning " +
                    "$($Global:IRT_DirectoryRoleTemplates.Count) template(s) (Return=$Return)")
                switch ( $Return ) {
                    'objects' { return $Global:IRT_DirectoryRoleTemplates }
                    'tablebyid' { return $Global:IRT_DirectoryRoleTemplatesById }
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
            "${FunctionName}: Get-MgDirectoryRoleTemplate [$Elapsed]")
        $GdrtParams = @{
            All      = $true
            Property = $GetProperties
        }
        $Objects = Get-MgDirectoryRoleTemplate @GdrtParams | Select-Object $GetProperties

        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Graph returned $($Objects.Count) template(s) [$Elapsed]")

        # store in global variables
        $Global:IRT_DirectoryRoleTemplates = $Objects
        $Global:IRT_DirectoryRoleTemplatesById = [hashtable]::Synchronized(@{})
        foreach ( $o in $Objects ) {
            if ( $o.Id ) { $Global:IRT_DirectoryRoleTemplatesById[$o.Id] = $o }
        }
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Index built — " +
            "$($Global:IRT_DirectoryRoleTemplatesById.Count) entry/entries.")

        # export to file
        if ($Xml) {
            $FileName = "DirectoryRoleTemplates_Raw_${DomainName}_${FileNameDate}.xml"
            $XmlOutputPath = Join-Path -Path $CurrentPath -ChildPath $FileName
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-PSFMessage -Level 8 -Message (
                "${FunctionName}: Export-Clixml → $XmlOutputPath [$Elapsed]")
            $Objects | Export-Clixml -Depth 5 -Path $XmlOutputPath
        }

        # return
        switch ( $Return ) {
            'objects' { return $Global:IRT_DirectoryRoleTemplates }
            'tablebyid' { return $Global:IRT_DirectoryRoleTemplatesById }
            'none' { return }
        }
    }
}
