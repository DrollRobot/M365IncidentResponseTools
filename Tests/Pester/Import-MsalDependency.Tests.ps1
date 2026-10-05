#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline and AppDomain tests for Import-MsalDependency's choice of which
    Microsoft.IdentityModel.Abstractions DLL to load.

.DESCRIPTION
    MSAL needs Microsoft.IdentityModel.Abstractions, which .NET cannot find on
    its own under Graph 2.41+. Only one version loads per session, and an older
    loaded version cannot satisfy a newer reference, so the function must load
    the highest version that Graph or Exchange ships.

-- already-loaded short circuit --------------------------------------------

    Whatever is already loaded wins; the function must not try to load another.

-- version selection -------------------------------------------------------

    Regression: loading Graph 2.41.1's 8.18 when ExchangeOnlineManagement 3.10.1
    ships 8.19.2 made Connect-ExchangeOnline fail with "The located assembly's
    manifest definition does not match the assembly reference."

    Get-AssemblyFileVersion is mocked so no real DLLs are needed.

-- against the real AppDomain ----------------------------------------------

    After loading, the loaded version must be at least as high as every copy
    the installed Graph and Exchange modules ship, and Exchange's own reference
    must resolve.
#>

InModuleScope M365IncidentResponseTools {

    BeforeAll {
        $script:AbsName = 'Microsoft.IdentityModel.Abstractions'
        $script:GraphBase = 'TestDrive:\Graph'
        $script:ExoBase = 'TestDrive:\Exo'
        $script:GraphDll = "$script:GraphBase\Dependencies\$script:AbsName.dll"
        $script:GraphCoreDll = "$script:GraphBase\Dependencies\Core\$script:AbsName.dll"
        $script:ExoDll = "$script:ExoBase\netCore\$script:AbsName.dll"
    }

    Describe 'Import-MsalDependency' -Tag 'unit' {

        Context 'already-loaded short circuit' {

            BeforeEach {
                Mock Get-LoadedAssembly {
                    [pscustomobject]@{ FullName = "$script:AbsName, Version=8.19.2.0" }
                }
                Mock Import-IRTModule { }
                Mock Add-Type { }
            }

            It 'returns $null' {
                Import-MsalDependency | Should -BeNullOrEmpty
            }

            It 'does not call Add-Type' {
                $null = Import-MsalDependency
                Should -Invoke Add-Type -Times 0 -Exactly
            }

            It 'does not import Graph or Exchange' {
                $null = Import-MsalDependency
                Should -Invoke Import-IRTModule -Times 0 -Exactly -ParameterFilter {
                    $Name -contains 'ExchangeOnlineManagement'
                }
            }
        }

        Context 'version selection' {

            BeforeEach {
                Mock Get-LoadedAssembly { $null }
                Mock Import-IRTModule { }
                Mock Get-Module -ParameterFilter {
                    $Name -eq 'Microsoft.Graph.Authentication'
                } -MockWith { [pscustomobject]@{ ModuleBase = $script:GraphBase } }
                Mock Get-Module -ParameterFilter {
                    $Name -eq 'ExchangeOnlineManagement'
                } -MockWith { [pscustomobject]@{ ModuleBase = $script:ExoBase } }
                # Graph 2.41.1 + Exchange 3.10.1 layout: no copy in Graph's Core\.
                Mock Test-Path {
                    param($LiteralPath)
                    $LiteralPath -ne $script:GraphCoreDll
                }
                Mock Get-AssemblyFileVersion { [version]'8.18.0.0' } -ParameterFilter {
                    $Path -eq $script:GraphDll
                }
                Mock Get-AssemblyFileVersion { [version]'8.19.2.0' } -ParameterFilter {
                    $Path -eq $script:ExoDll
                }
                Mock Add-Type { }
            }

            It 'imports Graph and Exchange before reading ModuleBase' {
                $null = Import-MsalDependency
                Should -Invoke Import-IRTModule -Times 1 -Exactly -ParameterFilter {
                    $Name -contains 'Microsoft.Graph.Authentication' -and
                    $Name -contains 'ExchangeOnlineManagement'
                }
            }

            It 'loads the Exchange copy when it is newer' {
                $Result = Import-MsalDependency

                $Result | Should -BeExactly $script:ExoDll
                Should -Invoke Add-Type -Times 1 -Exactly -ParameterFilter {
                    $Path -eq $script:ExoDll
                }
            }

            It 'loads the Graph copy when it is newer' {
                Mock Get-AssemblyFileVersion { [version]'9.0.0.0' } -ParameterFilter {
                    $Path -eq $script:GraphDll
                }

                $Result = Import-MsalDependency

                $Result | Should -BeExactly $script:GraphDll
                Should -Invoke Add-Type -Times 1 -Exactly -ParameterFilter {
                    $Path -eq $script:GraphDll
                }
            }

            It 'finds a copy in Graph''s Dependencies\Core\ folder' {
                Mock Test-Path {
                    param($LiteralPath)
                    $LiteralPath -eq $script:GraphCoreDll
                }
                Mock Get-AssemblyFileVersion { [version]'8.0.0.0' } -ParameterFilter {
                    $Path -eq $script:GraphCoreDll
                }

                Import-MsalDependency | Should -BeExactly $script:GraphCoreDll
            }

            It 'uses Graph alone when Exchange is not loaded' {
                Mock Get-Module { $null } -ParameterFilter {
                    $Name -eq 'ExchangeOnlineManagement'
                }

                Import-MsalDependency | Should -BeExactly $script:GraphDll
            }

            It 'returns $null without calling Add-Type when no copy exists' {
                Mock Test-Path { $false }

                Import-MsalDependency | Should -BeNullOrEmpty
                Should -Invoke Add-Type -Times 0 -Exactly
            }

            It 'throws naming the path when Add-Type fails' {
                Mock Add-Type { throw 'simulated assembly load failure' }

                { Import-MsalDependency } | Should -Throw -ExpectedMessage (
                    "*Failed to load MSAL dependency from '$script:ExoDll'*")
            }
        }
    }

    Describe 'Import-MsalDependency against the real AppDomain' -Tag 'integration' {

        BeforeAll {
            $null = Import-MsalAssembly

            Import-IRTModule -Name 'Microsoft.Graph.Authentication', 'ExchangeOnlineManagement'
            $DllName = "$script:AbsName.dll"
            $GraphBase = (Get-Module -Name 'Microsoft.Graph.Authentication').ModuleBase
            $GraphDeps = Join-Path -Path $GraphBase -ChildPath 'Dependencies'
            $ExoDllParams = @{
                Path                = (Get-Module -Name 'ExchangeOnlineManagement').ModuleBase
                ChildPath           = 'netCore'
                AdditionalChildPath = $DllName
            }
            $script:ExoRealDll = Join-Path @ExoDllParams
            $GraphCoreParams = @{
                Path                = $GraphDeps
                ChildPath           = 'Core'
                AdditionalChildPath = $DllName
            }
            $script:RealCandidates = @(
                Join-Path -Path $GraphDeps -ChildPath $DllName
                Join-Path @GraphCoreParams
                $script:ExoRealDll
            ) | Where-Object { Test-Path -LiteralPath $_ }
        }

        It 'has the dependency loaded' {
            Get-LoadedAssembly -Name $script:AbsName | Should -Not -BeNullOrEmpty
        }

        It 'loaded a version at least as high as every installed copy' {
            $Loaded = (Get-LoadedAssembly -Name $script:AbsName).GetName().Version
            foreach ($Candidate in $script:RealCandidates) {
                $Loaded | Should -BeGreaterOrEqual (Get-AssemblyFileVersion -Path $Candidate)
            }
        }

        It 'resolves the version Exchange references' -Tag 'regression' {
            # Regression: an older loaded copy broke Connect-ExchangeOnline.
            $Reference = [System.Reflection.AssemblyName]::GetAssemblyName($script:ExoRealDll)
            { [System.Reflection.Assembly]::Load($Reference) } | Should -Not -Throw
        }
    }
}
