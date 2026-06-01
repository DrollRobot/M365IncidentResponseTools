function Open-IRTTab {
    <#
    .SYNOPSIS
    Opens a new Windows Terminal tab and loads the module.

    .DESCRIPTION
    Opens a new tab in the current Windows Terminal window and imports
    M365IncidentResponseTools. If an active IRT session exists, also calls
    Connect-IRT to connect to the same tenant.

    Must be run from within Windows Terminal; detected via the WT_SESSION
    environment variable set by Windows Terminal in every hosted session.

    .PARAMETER Title
    Title for the new terminal tab. Defaults to '[IRT]'.

    .PARAMETER Quiet
    When set, silently returns without error if the current console is not
    Windows Terminal. Useful when calling from a profile or script that may
    run in multiple console hosts.

    .EXAMPLE
    Open-IRTTab
    Opens a new tab. Connects to the current tenant if a session is active.

    .EXAMPLE
    Open-IRTTab -Quiet
    Opens a new tab if in Windows Terminal; silently does nothing otherwise.

    .EXAMPLE
    Open-IRTTab -Title '[IRT] Secondary'
    Opens a new tab with a custom title.

    .OUTPUTS
    None

    .NOTES
    Version: 1.1.0
    1.1.0 - Requires Windows Terminal host. Opens without connecting when no
            active session exists.
    #>
    [Alias('OpenIRTTab', 'Open-Tab', 'OpenTab', 'NewIRTTab', 'New-Tab', 'NewTab', 'IRTTab')]
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [string] $Title = '[IRT]',

        [switch] $Quiet
    )

    process {
        if (-not $env:WT_SESSION) {
            if (-not $Quiet) {
                Write-Error 'This command must be run from within Windows Terminal.'
            }
            return
        }

        $ModuleName = $MyInvocation.MyCommand.Module.Name
        $HasSession = $Global:IRT_Session -and $Global:IRT_Session.TenantId

        if ($HasSession) {
            $TenantId = $Global:IRT_Session.TenantId
            $Cloud = $Global:IRT_Session.Environment
            $ClientId = $Global:IRT_Session.ClientId

            $ConnectParts = [System.Collections.Generic.List[string]]::new()
            $ConnectParts.Add("Connect-IRT -TenantId '$TenantId'")
            if ($Cloud) { $ConnectParts.Add("-Cloud $Cloud") }
            if ($ClientId) { $ConnectParts.Add("-ClientId '$ClientId'") }

            $InnerScript = "Import-Module $ModuleName; $($ConnectParts -join ' ')"
            Write-IRT "Opening new tab for tenant $TenantId"
        } else {
            $InnerScript = "Import-Module $ModuleName"
            Write-IRT 'Opening new tab (no active session; module will load without connecting)'
        }

        $Encoded = [Convert]::ToBase64String(
            [Text.Encoding]::Unicode.GetBytes($InnerScript)
        )

        $WtArgs = @(
            '--window', '0',
            'new-tab',
            '--startingDirectory', $PWD.Path,
            '--no-focus',
            '--title', $Title,
            '--',
            'pwsh', '-NoExit', '-EncodedCommand', $Encoded
        )
        & wt $WtArgs
    }
}
