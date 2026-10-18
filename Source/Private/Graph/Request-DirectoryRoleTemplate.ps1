function Request-DirectoryRoleTemplate {
    <#
    .SYNOPSIS
    Requests directory role templates from Microsoft Graph. Caches in global variable.

    .DESCRIPTION
    Internal helper. Fetches all Entra ID directory role templates from Microsoft Graph
    and caches the result in a session-scoped global variable. Used alongside
    Request-DirectoryRole to resolve role display names during admin role reporting.

    .NOTES
    Version: 2.1.0
    2.1.0 - A fetch that returns a Graph error is no longer cached.
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
        Import-IRTModule -Name 'Microsoft.Graph.Identity.DirectoryManagement', 'PSFramework'
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
                    "${FunctionName}: Cache hit - returning " +
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
            All           = $true
            Property      = $GetProperties
            ErrorVariable = 'GraphErrors'
        }
        $Objects = Get-MgDirectoryRoleTemplate @GdrtParams | Select-Object $GetProperties

        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Graph returned $($Objects.Count) template(s) [$Elapsed]")

        $TemplatesById = [hashtable]::Synchronized(@{})
        foreach ( $o in $Objects ) {
            if ( $o.Id ) { $TemplatesById[$o.Id] = $o }
        }
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Index built - $($TemplatesById.Count) entry/entries.")

        # store in global variables. Graph errors don't stop this function, so a failed
        # fetch would otherwise be cached and returned by every later -Cached call.
        if ( $GraphErrors ) {
            Write-PSFMessage -Level 8 -Message (
                "${FunctionName}: Graph returned an error; result not cached.")
        }
        else {
            $Global:IRT_DirectoryRoleTemplates = $Objects
            $Global:IRT_DirectoryRoleTemplatesById = $TemplatesById
        }

        # export to file
        if ($Xml) {
            $FileName = "DirectoryRoleTemplates_Raw_${DomainName}_${FileNameDate}.xml"
            $XmlOutputPath = Join-Path -Path $CurrentPath -ChildPath $FileName
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-PSFMessage -Level 8 -Message (
                "${FunctionName}: Export-Clixml -> $XmlOutputPath [$Elapsed]")
            $Objects | Export-Clixml -Depth 5 -Path $XmlOutputPath
        }

        # return
        switch ( $Return ) {
            'objects' { return $Objects }
            'tablebyid' { return $TemplatesById }
            'none' { return }
        }
    }
}
