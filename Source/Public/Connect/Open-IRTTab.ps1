function Open-IRTTab {
    <#
    .SYNOPSIS
    Opens a new terminal tab (Windows Terminal or tmux) and loads the module.

    .DESCRIPTION
    Opens a new tab in the current Windows Terminal window, or a new window in the
    current tmux session on Linux and macOS, and imports M365IncidentResponseTools.
    If an active IRT session exists, also calls Connect-IRT to connect to the same
    tenant. The new tab opens in the background, without taking focus.

    Must be run from within Windows Terminal (detected via the WT_SESSION
    environment variable) or tmux (detected via TMUX).

    .PARAMETER Title
    Title for the new terminal tab. Defaults to '[IRT]'.

    .PARAMETER Quiet
    When set, silently returns without error if the current console is neither
    Windows Terminal nor tmux. Useful when calling from a profile or script that
    may run in multiple console hosts.

    .EXAMPLE
    ```powershell
    Open-IRTTab
    ```
    Opens a new tab. Connects to the current tenant if a session is active.

    .EXAMPLE
    ```powershell
    Open-IRTTab -Quiet
    ```
    Opens a new tab if in Windows Terminal or tmux; silently does nothing otherwise.

    .EXAMPLE
    ```powershell
    Open-IRTTab -Title '[IRT] Secondary'
    ```
    Opens a new tab with a custom title.

    .OUTPUTS
    None

    .NOTES
    Version: 1.2.0
    1.2.0 - Opens a tmux window when run inside tmux, on Linux and macOS.
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
        Import-IRTModule -Name 'PSFramework'

        $InTmux = $env:TMUX -and (Get-Command -Name 'tmux' -ErrorAction Ignore)
        if (-not $env:WT_SESSION -and -not $InTmux) {
            if (-not $Quiet) {
                $Msg = 'This command must be run from within Windows Terminal, ' +
                'or tmux on Linux and macOS.'
                Write-Error $Msg
            }
            return
        }

        $ModuleName = $MyInvocation.MyCommand.Module.Name
        $HasSession = $Global:IRT_Session -and $Global:IRT_Session.TenantId

        if ($HasSession) {
            $TenantId = $Global:IRT_Session.TenantId
            $Cloud = $Global:IRT_Session.Cloud
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

        $PwshArgs = @('pwsh', '-NoExit', '-EncodedCommand', $Encoded)
        if ($env:WT_SESSION) {
            $WtArgs = @(
                '--window', '0',
                'new-tab',
                '--startingDirectory', $PWD.Path,
                '--no-focus',
                '--title', $Title,
                '--'
            ) + $PwshArgs
            Write-PSFMessage -Level 8 -Message 'Opening a Windows Terminal tab.'
            & wt $WtArgs
        } else {
            # -d keeps focus here, like Windows Terminal's --no-focus
            $TmuxArgs = @('new-window', '-d', '-n', $Title, '-c', $PWD.Path) + $PwshArgs
            Write-PSFMessage -Level 8 -Message 'Opening a tmux window.'
            & tmux $TmuxArgs
        }
    }
}
