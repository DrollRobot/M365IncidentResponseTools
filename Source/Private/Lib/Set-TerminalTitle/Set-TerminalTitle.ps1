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