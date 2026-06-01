function Open-Browser {
    <#
    .SYNOPSIS
    Simplifies opening browser windows

    .NOTES
    Version 1.03
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

        # pull default browser from registry
        $RegPath = 'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\Shell\' +
        'Associations\UrlAssociations\https\UserChoice'
        $ProgId = Get-ItemProperty -Path $RegPath | Select-Object -ExpandProperty ProgId

        switch -Regex ($ProgId) {
            '^Firefox' {
                $Browser = 'firefox'
            }
            '^MSEdge' {
                $Browser = 'msedge'
            }
            '^Chrome' {
                $Browser = 'chrome'
            }
            '^Brave' {
                $Browser = 'brave'
            }
        }
    }

    switch ( $Browser ) {
        'msedge' {
            if ( $Private ) {
                Start-Process $Browser -ArgumentList @('--inprivate', $Url)
            } else {
                Start-Process $Browser $Url
            }
        }
        'firefox' {
            if ( $Private ) {
                Start-Process $Browser -ArgumentList @('-private-window', $Url)
            } else {
                Start-Process $Browser $Url
            }
        }
        { $_ -in 'chrome', 'brave' } {
            if ( $Private ) {
                Start-Process $Browser -ArgumentList @('--incognito', $Url)
            } else {
                Start-Process $Browser $Url
            }
        }
    }
}
