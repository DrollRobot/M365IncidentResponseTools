#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Import-MsalExtensionAssembly load-failure handling,
    MSAL floor enforcement, and return value.

.DESCRIPTION
    Import-MsalExtensionAssembly loads the bundled
    Microsoft.Identity.Client.Extensions.Msal DLL from Data\. Graph does not
    ship that assembly, so unlike core MSAL the module must carry its own copy.

    Assemblies cannot be unloaded from a running process, so the "already
    loaded" short circuit would make every later branch unreachable in-session.
    Get-LoadedAssembly exists to be mocked here, which is what lets the load
    path be tested no matter what the rest of the suite has loaded.

-- load failure surfacing --------------------------------------------------

    Regression: Add-Type was called without -ErrorAction Stop, so a
    non-terminating load failure left the function returning a DLL path as if
    it had succeeded. Register-MsalCache then failed one line later on a type
    literal with "Unable to find type
    [Microsoft.Identity.Client.Extensions.Msal.StorageCreationPropertiesBuilder]",
    hiding the real load error. A failed Add-Type must throw, naming the path.

-- MSAL floor --------------------------------------------------------------

    The bundled Extensions build binds against Microsoft.Identity.Client
    4.61.3 or newer, and needs core MSAL loaded first. Both conditions must
    throw with guidance rather than fail later inside MSAL.

-- return value ------------------------------------------------------------

    Returns the path to the loaded DLL, and after the call the cache builder
    type must actually resolve - the assertion the original bug broke.
#>

InModuleScope M365IncidentResponseTools {

    BeforeAll {
        $script:ExtensionName = 'Microsoft.Identity.Client.Extensions.Msal'
        $script:MsalName = 'Microsoft.Identity.Client'
        $script:BuilderType = 'Microsoft.Identity.Client.Extensions.Msal.' +
        'StorageCreationPropertiesBuilder'

        # Stands in for a loaded assembly without touching the AppDomain.
        function New-StubAssembly {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test-only factory helper; ShouldProcess is not applicable.')]
            param(
                [string] $Name = 'Microsoft.Identity.Client',
                [string] $Version = '4.82.1.0',
                [string] $Location = 'TestDrive:\stub.dll'
            )
            [pscustomobject]@{ Location = $Location } |
                Add-Member -MemberType NoteProperty -Name StubName -Value $Name -PassThru |
                Add-Member -MemberType NoteProperty -Name StubVersion -Value $Version -PassThru |
                Add-Member -MemberType ScriptMethod -Name GetName -Value {
                    [pscustomobject]@{
                        Name    = $this.StubName
                        Version = [version]$this.StubVersion
                    }
                } -PassThru
        }
    }

    Describe 'Import-MsalExtensionAssembly' -Tag 'unit' {

        Context 'already-loaded short circuit' {

            BeforeEach {
                Mock Import-IRTModule { }
                Mock Add-Type { }
                Mock Get-LoadedAssembly {
                    New-StubAssembly -Name $script:ExtensionName -Location 'TestDrive:\ext.dll'
                } -ParameterFilter { $Name -eq $script:ExtensionName }
            }

            It 'returns the location of the loaded assembly' {
                Import-MsalExtensionAssembly | Should -BeExactly 'TestDrive:\ext.dll'
            }

            It 'does not call Add-Type' {
                $null = Import-MsalExtensionAssembly
                Should -Invoke Add-Type -Times 0 -Exactly
            }
        }

        Context 'MSAL floor' {

            BeforeEach {
                Mock Import-IRTModule { }
                Mock Add-Type { }
                Mock Get-LoadedAssembly { $null } -ParameterFilter {
                    $Name -eq $script:ExtensionName
                }
            }

            It 'throws when core MSAL is not loaded' {
                Mock Get-LoadedAssembly { $null } -ParameterFilter {
                    $Name -eq $script:MsalName
                }

                { Import-MsalExtensionAssembly } |
                    Should -Throw -ExpectedMessage '*Microsoft.Identity.Client is not loaded*'
            }

            It 'throws when core MSAL is below the floor' {
                Mock Get-LoadedAssembly {
                    New-StubAssembly -Name $script:MsalName -Version '4.60.0.0'
                } -ParameterFilter { $Name -eq $script:MsalName }

                { Import-MsalExtensionAssembly } |
                    Should -Throw -ExpectedMessage '*older than the bundled Extensions.Msal*'
            }

            It 'proceeds when core MSAL meets the floor' {
                Mock Get-LoadedAssembly {
                    New-StubAssembly -Name $script:MsalName -Version '4.61.3.0'
                } -ParameterFilter { $Name -eq $script:MsalName }
                Mock Test-Path { $true }

                { Import-MsalExtensionAssembly } | Should -Not -Throw
                Should -Invoke Add-Type -Times 1 -Exactly
            }
        }

        Context 'missing bundled DLL' {

            It 'throws pointing at the incomplete build' {
                Mock Import-IRTModule { }
                Mock Add-Type { }
                Mock Get-LoadedAssembly { $null } -ParameterFilter {
                    $Name -eq $script:ExtensionName
                }
                Mock Get-LoadedAssembly {
                    New-StubAssembly -Name $script:MsalName
                } -ParameterFilter { $Name -eq $script:MsalName }
                Mock Test-Path { $false }

                { Import-MsalExtensionAssembly } |
                    Should -Throw -ExpectedMessage '*build is incomplete*'
            }
        }

        Context 'load failure surfacing' {

            BeforeEach {
                Mock Import-IRTModule { }
                Mock Get-LoadedAssembly { $null } -ParameterFilter {
                    $Name -eq $script:ExtensionName
                }
                Mock Get-LoadedAssembly {
                    New-StubAssembly -Name $script:MsalName
                } -ParameterFilter { $Name -eq $script:MsalName }
                Mock Test-Path { $true }
                Mock Add-Type { throw 'simulated assembly load failure' }
            }

            It 'throws instead of returning a path' {
                { Import-MsalExtensionAssembly } |
                    Should -Throw -ExpectedMessage '*Failed to load MSAL extensions assembly*'
            }

            It 'names the DLL path in the failure' {
                { Import-MsalExtensionAssembly } |
                    Should -Throw -ExpectedMessage "*$($script:ExtensionName).dll*"
            }

            It 'includes the underlying error in the message' {
                { Import-MsalExtensionAssembly } |
                    Should -Throw -ExpectedMessage '*simulated assembly load failure*'
            }
        }
    }

    Describe 'Import-MsalExtensionAssembly against the real AppDomain' -Tag 'integration' {

        It 'returns the path to the bundled extensions DLL' {
            $Path = Import-MsalExtensionAssembly
            $Path | Should -Not -BeNullOrEmpty
            Split-Path -Path $Path -Leaf | Should -BeExactly "$($script:ExtensionName).dll"
            Test-Path -LiteralPath $Path | Should -BeTrue
        }

        It 'leaves the cache builder type resolvable' {
            $null = Import-MsalExtensionAssembly
            ($script:BuilderType -as [type]) | Should -Not -BeNullOrEmpty
        }

        It 'is idempotent across repeated calls' {
            $First = Import-MsalExtensionAssembly
            $Second = Import-MsalExtensionAssembly
            $Second | Should -BeExactly $First
        }
    }
}
