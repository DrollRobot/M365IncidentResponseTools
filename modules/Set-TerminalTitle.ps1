[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidGlobalVars', '',
    Justification = 'Portable script; intentional global state for terminal title save/restore.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingWriteHost', '',
    Justification = 'Portable script; no logging dependency.')]
param()

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


function Set-TerminalTitle {
    [CmdletBinding()]
    Param(
        [Parameter(Position = 0)]
        [string] $Title,
        [switch] $Original,
        [switch] $Quiet
    )

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
