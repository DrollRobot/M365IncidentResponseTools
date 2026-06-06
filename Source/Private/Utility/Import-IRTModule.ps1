function Import-IRTModule {
    <#
    .SYNOPSIS
        Imports the specified module(s) into the current session if not already loaded.

    .DESCRIPTION
        Supports lazy-loading of dependency modules by importing only the modules a
        function actually needs at call time. Modules already present in the session are
        skipped, so repeated calls incur no reload cost. Version correctness is assumed to
        have been validated at module import time; this function only ensures the modules
        are loaded into the current session.

    .PARAMETER Name
        One or more module names to ensure are imported. Specify the exact submodule a
        function requires (e.g. Microsoft.Graph.Users) rather than a meta-module
        (e.g. Microsoft.Graph) to avoid loading unneeded dependencies.

    .EXAMPLE
        Import-IRTModule -Name Microsoft.Graph.Users

        Ensures the Microsoft.Graph.Users module is loaded.

    .EXAMPLE
        Import-IRTModule -Name ExchangeOnlineManagement, Microsoft.Graph.Users

        Ensures both modules are loaded, importing only those not already present.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $Name
    )

    foreach ($module in $Name) {
        if (Get-Module -Name $module) {
            Write-PSFMessage -Level 8 -Message "Module already loaded, skipping: $module"
            continue
        }

        Write-PSFMessage -Level 8 -Message "Importing module: $module"
        Import-Module -Name $module -ErrorAction Stop
    }
}
