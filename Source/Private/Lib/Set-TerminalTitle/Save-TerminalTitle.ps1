function Save-TerminalTitle {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Intentional console status message for interactive use.')]
    [CmdletBinding()]
    Param(
        [switch] $Quiet
    )

    $Global:OriginalTerminalTitle = $Host.UI.RawUI.WindowTitle

    if (-not $Quiet) {
        Write-Host 'Original terminal title saved.'
    }
}
