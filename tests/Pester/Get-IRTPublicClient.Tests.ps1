#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Get-IRTPublicClient app pooling and cache registration.

.DESCRIPTION
    All tests are offline. Building a PublicClientApplication makes no network
    calls, so the real MSAL builder runs (Import-MsalAssembly loads the DLL
    bundled with Microsoft.Graph.Authentication from disk). Register-MsalCache
    and Write-IRT are mocked, and $Global:IRT_Config token-cache settings are
    saved/restored around every test.

-- guard rails -------------------------------------------------------------

    Without a session (or with a pre-Apps session shape) the factory cannot
    resolve the authority or store the app; it must throw with guidance.

-- app pooling --------------------------------------------------------------

    One app per client ID, stored in $Global:IRT_Session.Apps: a second call
    for the same client ID must return the SAME instance (and not re-register
    the cache); different client IDs get different apps.

-- cache registration --------------------------------------------------------

    EnableTokenCache=false (the default): never registers. true: registers
    exactly once per client ID, honoring a -MsalCachePath override. A
    registration failure must surface as error-level operator output with
    remediation, while the app itself still works (in-memory cache).
#>

InModuleScope M365IncidentResponseTools {

    BeforeAll {
        $script:TestTenant = 'aaaaaaaa-0000-0000-0000-aaaaaaaaaaaa'
        $script:ClientA = '11111111-1111-1111-1111-111111111111'
        $script:ClientB = '22222222-2222-2222-2222-222222222222'

        function New-TestSession {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test-only factory helper; ShouldProcess is not applicable.')]
            param()
            [pscustomobject]@{
                TenantId      = $script:TestTenant
                ClientId      = $null
                Cloud         = 'Commercial'
                CloudConfig   = [pscustomobject]@{
                    LoginHost = 'https://login.microsoftonline.com'
                    Graph     = 'https://graph.microsoft.com'
                }
                Apps          = [hashtable]::Synchronized(@{})
                StickyAccount = [hashtable]::Synchronized(@{})
                Graph         = $null
                Exchange      = $null
                IPPS          = $null
            }
        }
    }

    Describe 'Get-IRTPublicClient' {

        BeforeEach {
            $script:SavedSession = (
                Get-Variable -Name IRT_Session -Scope Global -ErrorAction SilentlyContinue
            )?.Value
            $script:SavedEnableCache = $Global:IRT_Config.EnableTokenCache
            $script:SavedCachePath = $Global:IRT_Config.MsalCachePath
            $Global:IRT_Session = New-TestSession
            $Global:IRT_Config.EnableTokenCache = $false

            Mock Register-MsalCache { }
            Mock Write-IRT { }
        }
        AfterEach {
            $Global:IRT_Session = $script:SavedSession
            $Global:IRT_Config.EnableTokenCache = $script:SavedEnableCache
            $Global:IRT_Config.MsalCachePath = $script:SavedCachePath
        }

        # -------------------------------------------------------------------
        Context 'guard rails' {

            It 'throws when there is no active session' {
                $Global:IRT_Session = $null
                { Get-IRTPublicClient -ClientId $script:ClientA } |
                    Should -Throw -ExpectedMessage '*Run Connect-IRT first*'
            }

            It 'throws when the session has no Apps store (pre-3.0 shape)' {
                $Global:IRT_Session = [pscustomobject]@{
                    TenantId    = $script:TestTenant
                    CloudConfig = [pscustomobject]@{
                        LoginHost = 'https://login.microsoftonline.com'
                    }
                    Apps        = $null
                }
                { Get-IRTPublicClient -ClientId $script:ClientA } |
                    Should -Throw -ExpectedMessage '*Apps store*'
            }
        }

        # -------------------------------------------------------------------
        Context 'app pooling (one app per client ID)' {

            It 'builds a real MSAL app with the requested client ID' {
                $App = Get-IRTPublicClient -ClientId $script:ClientA
                $App.AppConfig.ClientId | Should -Be $script:ClientA
            }

            It 'stores the app in the session Apps store' {
                $App = Get-IRTPublicClient -ClientId $script:ClientA
                $Global:IRT_Session.Apps[$script:ClientA] | Should -Be $App
            }

            It 'returns the SAME instance on a second call' {
                $First = Get-IRTPublicClient -ClientId $script:ClientA
                $Second = Get-IRTPublicClient -ClientId $script:ClientA
                $Second | Should -Be $First
            }

            It 'returns whatever the Apps store holds (no rebuild)' {
                # The shared-app invariant: Exchange and IPPS resolve to the same
                # client ID and must receive the same pooled object.
                $Marker = [pscustomobject]@{ Marker = 'pooled-app' }
                $Global:IRT_Session.Apps[$script:ClientA] = $Marker
                Get-IRTPublicClient -ClientId $script:ClientA | Should -Be $Marker
            }

            It 'builds distinct apps for distinct client IDs' {
                $AppA = Get-IRTPublicClient -ClientId $script:ClientA
                $AppB = Get-IRTPublicClient -ClientId $script:ClientB
                $AppA | Should -Not -Be $AppB
                $Global:IRT_Session.Apps.Count | Should -Be 2
            }
        }

        # -------------------------------------------------------------------
        Context 'cache registration' {

            It 'does not register the cache when EnableTokenCache is $false' {
                $null = Get-IRTPublicClient -ClientId $script:ClientA
                Should -Invoke Register-MsalCache -Times 0
            }

            It 'registers exactly once per client ID when EnableTokenCache is $true' {
                $Global:IRT_Config.EnableTokenCache = $true
                $null = Get-IRTPublicClient -ClientId $script:ClientA
                $null = Get-IRTPublicClient -ClientId $script:ClientA
                Should -Invoke Register-MsalCache -Times 1 -Exactly
            }

            It 'honors a -MsalCachePath override' {
                $Global:IRT_Config.EnableTokenCache = $true
                $GetParams = @{
                    ClientId      = $script:ClientA
                    MsalCachePath = 'C:\Temp\test-isolated-cache.bin'
                }
                $null = Get-IRTPublicClient @GetParams
                Should -Invoke Register-MsalCache -Times 1 -Exactly -ParameterFilter {
                    $CachePath -eq 'C:\Temp\test-isolated-cache.bin'
                }
            }

            It 'surfaces a registration failure as error-level operator output' {
                $Global:IRT_Config.EnableTokenCache = $true
                Mock Register-MsalCache { throw 'DPAPI says no' }
                $null = Get-IRTPublicClient -ClientId $script:ClientA
                Should -Invoke Write-IRT -Times 1 -ParameterFilter {
                    $Level -eq 'Error' -and $Message -match 'could NOT be attached'
                }
                Should -Invoke Write-IRT -Times 1 -ParameterFilter {
                    $Level -eq 'Error' -and $Message -match 're-prompted|prompted to sign in'
                }
            }

            It 'still returns and pools a working app after a registration failure' {
                $Global:IRT_Config.EnableTokenCache = $true
                Mock Register-MsalCache { throw 'DPAPI says no' }
                $App = Get-IRTPublicClient -ClientId $script:ClientA
                $App.AppConfig.ClientId | Should -Be $script:ClientA
                $Global:IRT_Session.Apps[$script:ClientA] | Should -Be $App
            }
        }
    }
}
