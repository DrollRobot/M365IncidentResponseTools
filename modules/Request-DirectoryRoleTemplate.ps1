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
        [ValidateSet('objects','tablebyid','none')]
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
                switch ( $Return ) {
                    'objects'   { return $Global:IRT_DirectoryRoleTemplates }
                    'tablebyid' { return $Global:IRT_DirectoryRoleTemplatesById }
                    'none'      { return }
                }
            }
        }

        # get client domain name
        $DomainName = Get-IRTDefaultDomain

        # query graph
        Write-Verbose "${FunctionName}: Get-MgDirectoryRoleTemplate $($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))"
        $GdrtParams = @{
            All      = $true
            Property = $GetProperties
        }
        $Objects = Get-MgDirectoryRoleTemplate @GdrtParams | Select-Object $GetProperties

        # store in global variables
        $Global:IRT_DirectoryRoleTemplates = $Objects
        $Global:IRT_DirectoryRoleTemplatesById = [hashtable]::Synchronized(@{})
        foreach ( $o in $Objects ) {
            if ( $o.Id ) { $Global:IRT_DirectoryRoleTemplatesById[$o.Id] = $o }
        }

        # export to file
        if ($Xml) {
            $FileName = "DirectoryRoleTemplates_Raw_${DomainName}_${FileNameDate}.xml"
            $XmlOutputPath = Join-Path -Path $CurrentPath -ChildPath $FileName
            Write-Verbose "${FunctionName}: Export-Clixml $($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))"
            $Objects | Export-Clixml -Depth 5 -Path $XmlOutputPath
        }

        # return
        switch ( $Return ) {
            'objects'   { return $Global:IRT_DirectoryRoleTemplates }
            'tablebyid' { return $Global:IRT_DirectoryRoleTemplatesById }
            'none'      { return }
        }
    }
}
