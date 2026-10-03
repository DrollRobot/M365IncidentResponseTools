#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Open-Browser and the helpers it uses on each platform.

.DESCRIPTION
    Resolve-BrowserLaunch and Get-DefaultBrowserName take -Platform, so the Windows,
    Linux, and macOS behavior is checked on any host. Start-Process is mocked
    throughout, so no browser is launched.

-- Resolve-BrowserLaunch ---------------------------------------------------

    Windows keeps the short names it always used; Linux uses the first installed
    executable name; macOS goes through 'open -na'. -Private adds each browser's own
    flag ahead of the URL.

-- Get-DefaultBrowserName --------------------------------------------------

    'maps the Windows registry choice to a browser name'
    'returns nothing for a browser it does not support'

-- Open-Browser ------------------------------------------------------------

    'opens an unsupported default browser through the system handler'
        It used to open nothing at all.
#>

InModuleScope M365IncidentResponseTools {

    BeforeAll {
        $script:Url = 'https://example.com/page'
    }

    Describe 'Resolve-BrowserLaunch' -Tag 'unit' {

        It 'keeps the Windows short names with the private flag before the URL' {
            $Params = @{
                Browser  = 'chrome'
                Url      = $script:Url
                Private  = $true
                Platform = 'Windows'
            }
            $Launch = Resolve-BrowserLaunch @Params
            $Launch.FilePath | Should -Be 'chrome'
            $Launch.ArgumentList | Should -Be @('--incognito', $script:Url)
        }

        It 'passes only the URL without -Private' {
            $Launch = Resolve-BrowserLaunch -Browser 'msedge' -Url $script:Url -Platform 'Windows'
            $Launch.ArgumentList | Should -Be @($script:Url)
        }

        It 'launches macOS browsers through open -na' {
            $Params = @{
                Browser  = 'firefox'
                Url      = $script:Url
                Private  = $true
                Platform = 'MacOS'
            }
            $Launch = Resolve-BrowserLaunch @Params
            $Launch.FilePath | Should -Be 'open'
            $Expected = @('-na', 'Firefox', '--args', '-private-window', $script:Url)
            $Launch.ArgumentList | Should -Be $Expected
        }

        It 'uses the first Linux executable name that is installed' {
            Mock Get-Command { } -ParameterFilter { $Name -ne 'google-chrome-stable' }
            Mock Get-Command { [pscustomobject]@{ Name = $Name } } -ParameterFilter {
                $Name -eq 'google-chrome-stable'
            }
            $Launch = Resolve-BrowserLaunch -Browser 'chrome' -Url $script:Url -Platform 'Linux'
            $Launch.FilePath | Should -Be 'google-chrome-stable'
            $Launch.ArgumentList | Should -Be @($script:Url)
        }

        It 'returns nothing on Linux when the browser is not installed' {
            Mock Get-Command { }
            Resolve-BrowserLaunch -Browser 'brave' -Url $script:Url -Platform 'Linux' |
                Should -BeNullOrEmpty
        }
    }

    Describe 'Get-DefaultBrowserName' -Tag 'unit' {

        It 'maps the Windows registry choice <ProgId> to <Expected>' -ForEach @(
            @{ ProgId = 'FirefoxURL-308046B0AF4A39CB'; Expected = 'firefox' }
            @{ ProgId = 'MSEdgeHTM'; Expected = 'msedge' }
            @{ ProgId = 'ChromeHTML'; Expected = 'chrome' }
            @{ ProgId = 'BraveHTML'; Expected = 'brave' }
        ) {
            $Choice = [pscustomobject]@{ ProgId = $ProgId }
            Mock Get-ItemProperty { $Choice }
            Get-DefaultBrowserName -Platform 'Windows' | Should -Be $Expected
        }

        It 'returns nothing for a browser it does not support' {
            Mock Get-ItemProperty { [pscustomobject]@{ ProgId = 'OperaStable' } }
            Get-DefaultBrowserName -Platform 'Windows' | Should -BeNullOrEmpty
        }

        It 'returns nothing on Linux without xdg-settings' {
            Mock Get-Command { } -ParameterFilter { $Name -eq 'xdg-settings' }
            Get-DefaultBrowserName -Platform 'Linux' | Should -BeNullOrEmpty
        }

        It 'does not try to read the default on macOS' {
            Mock Get-ItemProperty { }
            Get-DefaultBrowserName -Platform 'MacOS' | Should -BeNullOrEmpty
            Should -Invoke Get-ItemProperty -Times 0 -Exactly
        }
    }

    Describe 'Open-Browser' -Tag 'unit' {

        BeforeEach {
            Mock Start-Process { }
            Mock Write-Warning { }
        }

        It 'launches the resolved browser' {
            Mock Resolve-BrowserLaunch { @{ FilePath = 'firefox'; ArgumentList = @('x') } }
            Open-Browser -Browser 'firefox' -Url $script:Url
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq 'firefox'
            }
        }

        It 'opens an unsupported default browser through the system handler' -Tag 'regression' {
            Mock Get-DefaultBrowserName { }
            Open-Browser -Browser 'default' -Url $script:Url
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq $script:Url
            }
        }

        It 'falls back to the system handler when the browser is not installed' {
            Mock Resolve-BrowserLaunch { }
            Open-Browser -Browser 'brave' -Url $script:Url
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq $script:Url
            }
            Should -Invoke Write-Warning -Times 1 -Exactly
        }

        It 'warns when a private window is not possible' {
            Mock Get-DefaultBrowserName { }
            Open-Browser -Browser 'default' -Url $script:Url -Private
            Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter {
                $Message -like '*not a private one*'
            }
        }
    }
}
