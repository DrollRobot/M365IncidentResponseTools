function Resolve-BrowserLaunch {
    <#
    .SYNOPSIS
    Works out the command that opens a URL in a given browser on this platform.

    .DESCRIPTION
    Returns the FilePath and ArgumentList for Start-Process. Windows resolves the short
    browser names itself through App Paths. Linux names each browser differently
    (google-chrome, microsoft-edge, brave-browser), so the first one installed is used.
    macOS launches the application bundle through 'open'. With -Private, each browser's
    own private-window flag goes before the URL.

    .PARAMETER Browser
    The browser: msedge, chrome, firefox, or brave.

    .PARAMETER Url
    The URL to open.

    .PARAMETER Private
    Open a private (InPrivate or incognito) window.

    .PARAMETER Platform
    The platform to build the command for. Defaults to the current one; set for tests.

    .EXAMPLE
    ```powershell
    $Launch = Resolve-BrowserLaunch -Browser 'chrome' -Url 'https://example.com' -Private
    Start-Process -FilePath $Launch.FilePath -ArgumentList $Launch.ArgumentList
    ```
    Opens the page in an incognito Chrome window.

    .OUTPUTS
    [hashtable] with FilePath and ArgumentList, or nothing when the browser is not
    installed (Linux only; elsewhere the platform reports a missing browser itself).

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('msedge', 'chrome', 'firefox', 'brave')]
        [string] $Browser,

        [Parameter(Mandatory)]
        [string] $Url,

        [switch] $Private,

        [ValidateSet('Windows', 'Linux', 'MacOS')]
        [string] $Platform = $(
            if ($IsWindows) { 'Windows' } elseif ($IsMacOS) { 'MacOS' } else { 'Linux' }
        )
    )

    $PrivateFlag = @{
        msedge  = '--inprivate'
        chrome  = '--incognito'
        brave   = '--incognito'
        firefox = '-private-window'
    }
    $BrowserArgs = @()
    if ($Private) { $BrowserArgs += $PrivateFlag[$Browser] }
    $BrowserArgs += $Url

    switch ($Platform) {
        'Windows' {
            return @{ FilePath = $Browser; ArgumentList = $BrowserArgs }
        }
        'MacOS' {
            $AppName = @{
                msedge  = 'Microsoft Edge'
                chrome  = 'Google Chrome'
                firefox = 'Firefox'
                brave   = 'Brave Browser'
            }
            $OpenArgs = @('-na', $AppName[$Browser], '--args') + $BrowserArgs
            return @{ FilePath = 'open'; ArgumentList = $OpenArgs }
        }
        'Linux' {
            $Candidates = @{
                msedge  = @('microsoft-edge', 'microsoft-edge-stable')
                chrome  = @(
                    'google-chrome', 'google-chrome-stable', 'chromium', 'chromium-browser'
                )
                firefox = @('firefox')
                brave   = @('brave-browser', 'brave')
            }
            foreach ($Name in $Candidates[$Browser]) {
                if (Get-Command -Name $Name -CommandType Application -ErrorAction Ignore) {
                    Write-Information -Tags 'Trace' -MessageData "Found $Browser as '$Name'."
                    return @{ FilePath = $Name; ArgumentList = $BrowserArgs }
                }
            }
            Write-Information -Tags 'Trace' -MessageData "$Browser is not installed."
        }
    }
}
