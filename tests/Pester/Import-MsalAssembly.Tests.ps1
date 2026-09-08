#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Import-MsalAssembly dependency handling, load failure
    surfacing, and return value.

.DESCRIPTION
    Import-MsalAssembly loads Microsoft.Identity.Client from the DLL bundled
    with Microsoft.Graph.Authentication. The module does not ship its own copy:
    only one Microsoft.Identity.Client can bind per load context, so IRT
    deliberately reuses the one the Graph SDK provides.

    Assemblies cannot be unloaded from a running process, so the "already
    loaded" short circuit would make every later branch unreachable in-session.
    Get-LoadedAssembly exists to be mocked here, which is what lets the load
    path be tested no matter what the rest of the suite has loaded.

-- already-loaded short circuit --------------------------------------------

    When the assembly is present the function returns it immediately, without
    importing Graph or calling Add-Type.

-- dependency import -------------------------------------------------------

    Get-Module only reports modules already imported into the session, so
    reading Microsoft.Graph.Authentication's ModuleBase without importing it
    first yields $null and builds a broken DLL path. The function must import
    the module before reading ModuleBase, and must throw a message naming the
    dependency if it still cannot be loaded.

-- return value ------------------------------------------------------------

    Callers use the returned assembly to reach MSAL types, and
    Import-MsalExtensionAssembly gates on its version, so the function returns
    the loaded assembly rather than the DLL path.
#>

InModuleScope M365IncidentResponseTools {

    BeforeAll {
        $script:MsalName = 'Microsoft.Identity.Client'
        # Extensions.Msal 4.66.x requires at least this MSAL version.
        $script:MsalFloor = [version]'4.61.3'

        # Stands in for a loaded assembly without touching the AppDomain.
        function New-StubAssembly {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test-only factory helper; ShouldProcess is not applicable.')]
            param([string] $Name = 'Microsoft.Identity.Client')
            [pscustomobject]@{ FullName = "$Name, Version=4.82.1.0" } |
                Add-Member -MemberType ScriptMethod -Name GetName -Value {
                    [pscustomobject]@{
                        Name    = ($this.FullName -split ',')[0]
                        Version = [version]'4.82.1.0'
                    }
                } -PassThru
        }

        function New-StubGraphModule {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test-only factory helper; ShouldProcess is not applicable.')]
            param([string] $ModuleBase = 'TestDrive:\GraphAuth')
            [pscustomobject]@{ ModuleBase = $ModuleBase; Version = [version]'2.38.1' }
        }
    }

    Describe 'Import-MsalAssembly' -Tag 'unit' {

        Context 'already-loaded short circuit' {

            BeforeEach {
                Mock Get-LoadedAssembly { New-StubAssembly }
                Mock Import-IRTModule { }
                Mock Add-Type { }
            }

            It 'returns the already-loaded assembly' {
                $Assembly = Import-MsalAssembly
                $Assembly.GetName().Name | Should -BeExactly $script:MsalName
            }

            It 'does not import Graph' {
                $null = Import-MsalAssembly
                Should -Invoke Import-IRTModule -Times 0 -Exactly -ParameterFilter {
                    $Name -contains 'Microsoft.Graph.Authentication'
                }
            }

            It 'does not call Add-Type' {
                $null = Import-MsalAssembly
                Should -Invoke Add-Type -Times 0 -Exactly
            }
        }

        Context 'dependency import' {

            BeforeEach {
                # Force the load path: nothing is loaded yet.
                Mock Get-LoadedAssembly { $null }
                Mock Import-IRTModule { }
                Mock Add-Type { }
            }

            It 'imports Graph before reading ModuleBase' {
                # Regression: the function used to call Get-Module without
                # importing first, so an un-imported dependency produced a null
                # ModuleBase and a "not found at expected path: " error naming
                # no path at all.
                Mock Get-Module { $null }

                { Import-MsalAssembly } | Should -Throw

                Should -Invoke Import-IRTModule -Times 1 -Exactly -ParameterFilter {
                    $Name -contains 'Microsoft.Graph.Authentication'
                }
            }

            It 'throws naming the dependency when Graph is absent' {
                Mock Get-Module { $null }

                { Import-MsalAssembly } |
                    Should -Throw -ExpectedMessage '*Microsoft.Graph.Authentication*'
            }

            It 'throws naming the path when the bundled DLL is absent' {
                Mock Get-Module { New-StubGraphModule }

                { Import-MsalAssembly } |
                    Should -Throw -ExpectedMessage '*MSAL assembly not found at expected path*'
            }
        }

        Context 'load failure surfacing' {

            BeforeEach {
                Mock Get-LoadedAssembly { $null }
                Mock Import-IRTModule { }
                Mock Get-Module { New-StubGraphModule }
                Mock Test-Path { $true }
                Mock Add-Type { throw 'simulated assembly load failure' }
            }

            It 'throws when Add-Type fails' {
                { Import-MsalAssembly } |
                    Should -Throw -ExpectedMessage '*Failed to load MSAL assembly*'
            }

            It 'includes the underlying error in the message' {
                { Import-MsalAssembly } |
                    Should -Throw -ExpectedMessage '*simulated assembly load failure*'
            }
        }

        Context 'return value' {

            It 'returns the assembly the probe reports after loading' {
                Mock Import-IRTModule { }
                Mock Get-Module { New-StubGraphModule }
                Mock Test-Path { $true }
                Mock Add-Type { }
                # Absent on the first probe, present once Add-Type has run.
                $script:ProbeCalls = 0
                Mock Get-LoadedAssembly {
                    $script:ProbeCalls++
                    if ($script:ProbeCalls -eq 1) { $null } else { New-StubAssembly }
                }

                $Assembly = Import-MsalAssembly
                $Assembly | Should -Not -BeNullOrEmpty
                $Assembly.GetName().Name | Should -BeExactly $script:MsalName
                Should -Invoke Add-Type -Times 1 -Exactly
            }
        }
    }

    Describe 'Import-MsalAssembly against the real AppDomain' -Tag 'integration' {

        It 'returns a core MSAL assembly meeting the Extensions floor' {
            $Assembly = Import-MsalAssembly
            $Assembly.GetName().Name | Should -BeExactly $script:MsalName
            [version]$Assembly.GetName().Version |
                Should -BeGreaterOrEqual $script:MsalFloor
        }

        It 'is idempotent across repeated calls' {
            $First = Import-MsalAssembly
            $Second = Import-MsalAssembly
            $Second.FullName | Should -BeExactly $First.FullName
        }
    }
}
