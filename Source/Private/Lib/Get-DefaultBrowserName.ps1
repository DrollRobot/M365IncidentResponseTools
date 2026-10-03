function Get-DefaultBrowserName {
    <#
    .SYNOPSIS
    Returns which supported browser opens web links on this device, if it can tell.

    .DESCRIPTION
    Reads the default browser from the platform: the https UserChoice in the Windows
    registry, or xdg-settings on Linux. Returns one of the names Open-Browser accepts
    (msedge, chrome, firefox, brave), or nothing when the default is another browser
    or cannot be read. macOS keeps the default in a binary plist, so nothing is read
    there.

    .PARAMETER Platform
    The platform to read the default for. Defaults to the current one; set for tests.

    .EXAMPLE
    ```powershell
    Get-DefaultBrowserName
    ```
    Returns 'firefox' when Firefox is the default browser.

    .OUTPUTS
    [string] the browser name, or nothing.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [ValidateSet('Windows', 'Linux', 'MacOS')]
        [string] $Platform = $(
            if ($IsWindows) { 'Windows' } elseif ($IsMacOS) { 'MacOS' } else { 'Linux' }
        )
    )

    $Id = $null
    if ($Platform -eq 'Windows') {
        $RegPath = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\Shell\' +
        'Associations\UrlAssociations\https\UserChoice'
        $Choice = Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue
        if ($Choice) { $Id = $Choice.ProgId }
    }
    elseif ($Platform -eq 'Linux' -and (Get-Command -Name 'xdg-settings' -ErrorAction Ignore)) {
        $Id = & xdg-settings get default-web-browser 2>$null
    }
    Write-Information -Tags 'Trace' -MessageData "Default browser id on ${Platform}: '$Id'"

    # Windows ProgIds (FirefoxURL-..., MSEdgeHTM, ChromeHTML, BraveHTML) and Linux
    # desktop file names (firefox.desktop, microsoft-edge.desktop, ...).
    switch -Regex ($Id) {
        '^firefox' { return 'firefox' }
        '^(msedge|microsoft-edge)' { return 'msedge' }
        '^(chrome|google-chrome|chromium)' { return 'chrome' }
        '^brave' { return 'brave' }
    }
}
