#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Get-IRTTenantOwner's cache path.

.DESCRIPTION
    All tests are offline. Update-IRTToken, Import-IRTModule, Write-IRT, and
    Write-PSFMessage are mocked, and Get-TenantOidc is mocked so no discovery request
    is made. -SkipGraph keeps Graph out of every test. $Global:IRT_TenantInfoTable is
    saved before the tests and put back afterwards, since other functions and test
    files read it.

-- cache hit (regression) -------------------------------------------------

    With -Cached, a tenant already in the cache is returned from it with no live
    lookup. The cache entry used to be stored in $cached, which PowerShell treats as
    the same variable as the [switch] $Cached parameter, so every cache hit threw
    "Cannot convert value ... to type SwitchParameter". A bulk lookup then lost every
    tenant ID in the call, not just the cached one.

-- cache miss -------------------------------------------------------------

    With -Cached, a tenant not yet in the cache still gets a live lookup.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Get-IRTTenantOwner' -Tag 'unit' {

        BeforeAll {
            $script:SavedTable = $Global:IRT_TenantInfoTable
        }

        AfterAll {
            $Global:IRT_TenantInfoTable = $script:SavedTable
        }

        BeforeEach {
            Mock Update-IRTToken { }
            Mock Import-IRTModule { }
            Mock Write-IRT { }
            Mock Write-PSFMessage { }
            Mock Get-TenantOidc { $null }

            $script:CachedTid = '22222222-2222-2222-2222-222222222222'
            $script:UncachedTid = '33333333-3333-3333-3333-333333333333'
            $Global:IRT_TenantInfoTable = @{
                $script:CachedTid = [pscustomobject]@{
                    TenantId            = $script:CachedTid
                    DisplayName         = 'Fabrikam'
                    DefaultDomain       = 'fabrikam.com'
                    FederationBrandName = ''
                    Cloud               = 'Commercial'
                    GraphHost           = 'graph.microsoft.com'
                    TokenEndpoint       = 'https://login.microsoftonline.com/x/oauth2/v2.0/token'
                    CachedAt            = '2026-01-01T00:00:00Z'
                }
            }
        }

        # -------------------------------------------------------------------
        Context 'cache hit' {

            It 'returns a cached tenant with -Cached instead of throwing' -Tag 'regression' {
                $Params = @{
                    TenantId  = $script:CachedTid
                    Cached    = $true
                    Quiet     = $true
                    SkipGraph = $true
                }
                $Result = Get-IRTTenantOwner @Params
                $Result.DefaultDomain | Should -Be 'fabrikam.com'
                $Result.Source | Should -Be 'Cache'
            }

            It 'makes no live lookup for a cached tenant' {
                $Params = @{
                    TenantId  = $script:CachedTid
                    Cached    = $true
                    Quiet     = $true
                    SkipGraph = $true
                }
                $null = Get-IRTTenantOwner @Params
                Should -Invoke Get-TenantOidc -Times 0 -Exactly
            }

            It 'returns every tenant when a cache hit comes first' -Tag 'regression' {
                $Params = @{
                    TenantId  = @($script:CachedTid, $script:UncachedTid)
                    Cached    = $true
                    Quiet     = $true
                    SkipGraph = $true
                }
                @(Get-IRTTenantOwner @Params).Count | Should -Be 2
            }
        }

        # -------------------------------------------------------------------
        Context 'cache miss' {

            It 'looks up a tenant that is not cached' {
                $Params = @{
                    TenantId  = $script:UncachedTid
                    Cached    = $true
                    Quiet     = $true
                    SkipGraph = $true
                }
                $Result = Get-IRTTenantOwner @Params
                Should -Invoke Get-TenantOidc -Times 1 -Exactly
                $Result.Exists | Should -BeFalse
            }
        }
    }
}
