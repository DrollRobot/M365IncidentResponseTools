function Open-Browser {
    <#
    .SYNOPSIS
    Opens a URL in a chosen browser, optionally in a private window.

    .DESCRIPTION
    Opens the URL in the named browser on Windows, Linux, or macOS. 'default' uses the
    browser that opens web links on this device when it is one of the supported ones,
    so -Private still applies. When the default cannot be identified, or the named
    browser is not installed, the URL goes to the system's own handler instead
    (warning that -Private could not be honored).

    .PARAMETER Browser
    The browser: msedge, chrome, firefox, brave, or default.

    .PARAMETER Url
    The URL to open.

    .PARAMETER Private
    Open a private (InPrivate or incognito) window.

    .EXAMPLE
    ```powershell
    Open-Browser -Browser 'default' -Url 'https://portal.azure.com' -Private
    ```
    Opens the portal in a private window of the default browser.

    .OUTPUTS
    None.

    .NOTES
    Version 1.04
    #>

    [CmdletBinding()]
    param(
        [Parameter(mandatory = $true)]
        [ValidateSet('msedge', 'chrome', 'firefox', 'brave', 'default')]
        [string]$Browser,
        [string]$Url,
        [switch]$Private
    )

    if ($Browser -eq 'default') {
        $Detected = Get-DefaultBrowserName
        if ($Detected) { $Browser = $Detected }
    }
    Write-Information -Tags 'Trace' -MessageData "Opening '$Url' in $Browser (private: $Private)."

    if ($Browser -ne 'default') {
        $Launch = Resolve-BrowserLaunch -Browser $Browser -Url $Url -Private:$Private
        if ($Launch) {
            Start-Process -FilePath $Launch.FilePath -ArgumentList $Launch.ArgumentList
            return
        }
        $Msg = "$Browser was not found on this device; opening the page with the " +
        'default handler.'
        Write-Warning $Msg
    }

    if ($Private) {
        $Msg = 'The default handler opens the page in a normal window, not a ' +
        'private one.'
        Write-Warning $Msg
    }
    Start-Process -FilePath $Url
}
