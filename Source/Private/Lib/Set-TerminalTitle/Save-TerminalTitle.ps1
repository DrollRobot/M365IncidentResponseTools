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