#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Get-IRTAppDataPath and the config functions that use it.

.DESCRIPTION
    Get-IRTAppDataPath resolves the per-user folder for the module's config and caches
    with [Environment]::GetFolderPath, so it works on every platform. The config tests
    point it at $TestDrive and check that Import-IRTConfig, Set-IRTConfig, and
    Open-IRTConfig all use the same config file.

-- Get-IRTAppDataPath ------------------------------------------------------

    'resolves on every platform'
        $env:APPDATA exists only on Windows; building paths from it left the module
        without a config on Linux and macOS.

    'keeps the Windows folder the module has always used'
        Existing configs and caches must not move.

-- config file -------------------------------------------------------------

    'Import, Set -Reset, and Open use one config.json'
        Import-IRTConfig wrote Config.json while the others used config.json, which
        names two different files on a case-sensitive filesystem.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Get-IRTAppDataPath' -Tag 'unit' {

        It 'puts the module folder under the roaming application data folder' {
            $RoamingBase = [Environment]::GetFolderPath('ApplicationData')
            $Expected = Join-Path -Path $RoamingBase -ChildPath 'M365IncidentResponseTools'
            Get-IRTAppDataPath | Should -Be $Expected
        }

        It 'uses the machine-local folder with -Local' {
            $LocalBase = [Environment]::GetFolderPath('LocalApplicationData')
            $Expected = Join-Path -Path $LocalBase -ChildPath 'M365IncidentResponseTools'
            Get-IRTAppDataPath -Local | Should -Be $Expected
        }

        It 'appends -ChildPath segments below the module folder' {
            $Expected = Join-Path -Path (Get-IRTAppDataPath) -ChildPath 'a'
            $Expected = Join-Path -Path $Expected -ChildPath 'b.json'
            Get-IRTAppDataPath -ChildPath 'a', 'b.json' | Should -Be $Expected
        }

        It 'resolves on every platform' -Tag 'regression' {
            $Path = Get-IRTAppDataPath -ChildPath 'config.json'
            [System.IO.Path]::IsPathRooted($Path) | Should -BeTrue
        }

        It 'keeps the Windows folder the module has always used' -Tag 'regression' {
            if (-not $IsWindows) {
                Set-ItResult -Skipped -Because 'APPDATA exists only on Windows'
                return
            }
            $Expected = Join-Path -Path $env:APPDATA -ChildPath 'M365IncidentResponseTools'
            Get-IRTAppDataPath | Should -Be $Expected
            $LocalParams = @{
                Path      = $env:LOCALAPPDATA
                ChildPath = 'M365IncidentResponseTools'
            }
            Get-IRTAppDataPath -Local | Should -Be (Join-Path @LocalParams)
        }
    }

    Describe 'config file location' -Tag 'integration' {

        BeforeAll {
            $script:SavedConfig = $Global:IRT_Config
            $script:FakeRoot = Join-Path -Path $TestDrive -ChildPath 'AppData'
            Mock Get-IRTAppDataPath {
                $Path = $script:FakeRoot
                foreach ($Segment in $ChildPath) {
                    $Path = Join-Path -Path $Path -ChildPath $Segment
                }
                $Path
            }
            Mock Write-IRT {}
            Mock Invoke-Item {}
        }

        AfterAll {
            $Global:IRT_Config = $script:SavedConfig
        }

        It 'Import, Set -Reset, and Open use one config.json' -Tag 'regression' {
            $Global:IRT_Config = $null
            Import-IRTConfig -Force
            Set-IRTConfig -Reset -Confirm:$false
            Open-IRTConfig

            $ConfigFiles = @(Get-ChildItem -Path $script:FakeRoot -Filter '*.json' -File)
            $ConfigFiles | Should -HaveCount 1
            $ConfigFiles[0].Name | Should -BeExactly 'config.json'
            Should -Invoke Invoke-Item -Times 1 -Exactly -ParameterFilter {
                $Path -eq $ConfigFiles[0].FullName
            }
        }

        It 'loads the config it created' {
            $Global:IRT_Config = $null
            Import-IRTConfig -Force
            $Global:IRT_Config | Should -Not -BeNullOrEmpty
        }

        It 'defaults the tenants worksheet into the same folder' {
            $Global:IRT_Config = $null
            Import-IRTConfig -Force
            $Expected = Join-Path -Path $script:FakeRoot -ChildPath 'tenants.xlsx'
            $Global:IRT_Config.TenantsSheetPath | Should -Be $Expected
        }
    }
}
