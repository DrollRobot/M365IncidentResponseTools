function Set-TerminalTitle {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost', '',
        Justification = 'Intentional console status message for interactive use.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Terminal title change; no ShouldProcess needed.')]
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0)]
        [string] $Title,
        [switch] $Original,
        [switch] $Quiet
    )

    function Save-TerminalTitle {
        [CmdletBinding()]
        Param(
            [switch] $Quiet
        )

        $Global:OriginalTerminalTitle = $Host.UI.RawUI.WindowTitle

        if (-not $Quiet) {
            Write-Host 'Original terminal title saved.'
        }
    }

    if ($Original) {
        if ($Global:OriginalTerminalTitle) {
            $Host.UI.RawUI.WindowTitle = $Global:OriginalTerminalTitle
        } else {
            if (-not $Quiet) {
                Write-Host 'Original terminal title not saved.' -ForegroundColor Red
            }
        }
    } else {
        if (-not $Global:OriginalTerminalTitle) {
            Save-TerminalTitle -Quiet
        }
        $Host.UI.RawUI.WindowTitle = $Title
    }
}
