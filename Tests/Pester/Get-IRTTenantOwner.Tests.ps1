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

-- domain input -----------------------------------------------------------

    A domain is resolved to its tenant GUID through OIDC discovery, and that GUID is
    what the output and cache use. The discovery result is reused, so a domain costs
    one OIDC call, not two. With -Cached, a domain matching a cached default domain is
    returned with no lookup. A domain OIDC cannot resolve is reported as not found.

-- failed Graph lookup ----------------------------------------------------

    A failed cross-tenant lookup still returns what OIDC found, and is kept quiet with
    -Quiet. As a temporary workaround it is reported with an Error-level message while
    IRT_TEST_STRICT_ERRORS is '1'. Get-MgContext and Invoke-MgGraphRequest are global
    stubs mocked in the module, and Error-level messages are captured for the check.
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

        # -------------------------------------------------------------------
        Context 'domain input' {

            It 'resolves a domain to its tenant GUID' {
                Mock Get-TenantOidc {
                    [pscustomobject]@{
                        TenantId       = $script:UncachedTid
                        Cloud          = 'Commercial'
                        msgraph_host   = 'graph.microsoft.com'
                        token_endpoint = 'https://login.microsoftonline.com/x/oauth2/v2.0/token'
                    }
                }
                $Result = Get-IRTTenantOwner -TenantId 'contoso.com' -Quiet -SkipGraph
                $Result.TenantId | Should -Be $script:UncachedTid
                $Result.Exists | Should -BeTrue
                $Result.Cloud | Should -Be 'Commercial'
                Should -Invoke Get-TenantOidc -Times 1 -Exactly -ParameterFilter {
                    $TenantId -eq 'contoso.com'
                }
            }

            It 'returns a cached tenant by default domain with no lookup' {
                $Params = @{
                    Domain    = 'fabrikam.com'
                    Cached    = $true
                    Quiet     = $true
                    SkipGraph = $true
                }
                $Result = Get-IRTTenantOwner @Params
                $Result.TenantId | Should -Be $script:CachedTid
                $Result.Source | Should -Be 'Cache'
                Should -Invoke Get-TenantOidc -Times 0 -Exactly
            }

            It 'returns the cached entry when a domain resolves to a cached GUID' {
                Mock Get-TenantOidc { [pscustomobject]@{ TenantId = $script:CachedTid } }
                $Params = @{
                    TenantId  = 'fabrikam.onmicrosoft.com'
                    Cached    = $true
                    Quiet     = $true
                    SkipGraph = $true
                }
                $Result = Get-IRTTenantOwner @Params
                $Result.DisplayName | Should -Be 'Fabrikam'
                $Result.Source | Should -Be 'Cache'
            }

            It 'reports a domain OIDC cannot resolve as not found' {
                $Result = Get-IRTTenantOwner -TenantId 'nope.invalid' -Quiet -SkipGraph
                $Result.TenantId | Should -Be 'nope.invalid'
                $Result.Exists | Should -BeFalse
            }
        }

        # -------------------------------------------------------------------
        Context 'failed Graph lookup' {

            BeforeAll {
                # params exist only so Mock can bind them
                function global:Get-MgContext { [CmdletBinding()] param() }
                function global:Invoke-MgGraphRequest {
                    [CmdletBinding()] param([string] $Method, [string] $Uri)
                    $null = $Method, $Uri
                }

                # no session, so the lookup is never skipped as cross-cloud
                $GvParams = @{ Scope = 'Global'; Name = 'IRT_Session'; ErrorAction = 'Ignore' }
                $script:SavedSession = Get-Variable @GvParams
                Remove-Variable -Scope Global -Name 'IRT_Session' -ErrorAction Ignore
                $script:SavedStrict = $env:IRT_TEST_STRICT_ERRORS
            }

            AfterAll {
                $Stubs = 'Function:\Get-MgContext', 'Function:\Invoke-MgGraphRequest'
                Remove-Item -Path $Stubs -ErrorAction Ignore
                if ($script:SavedSession) {
                    Set-Variable -Scope Global -Name 'IRT_Session' -Value $script:SavedSession.Value
                }
                $env:IRT_TEST_STRICT_ERRORS = $script:SavedStrict
            }

            BeforeEach {
                Mock Get-MgContext { [pscustomobject]@{ Account = 'admin@contoso.com' } }
                Mock Get-TenantOidc {
                    [pscustomobject]@{ TenantId = $script:UncachedTid; Cloud = 'Commercial' }
                }
                Mock Invoke-MgGraphRequest { throw 'Forbidden' }

                $script:Errors = [System.Collections.Generic.List[string]]::new()
                Mock Write-IRT -ParameterFilter { $Level -eq 'Error' } {
                    $script:Errors.Add($Message)
                }
            }

            It 'keeps the failure quiet on a normal run' {
                $env:IRT_TEST_STRICT_ERRORS = $null

                $Result = Get-IRTTenantOwner -TenantId $script:UncachedTid -Quiet

                $Result.Source | Should -Be 'PublicEndpoints'
                $script:Errors | Should -BeNullOrEmpty
            }

            It 'reports the failure during a live test run' {
                $env:IRT_TEST_STRICT_ERRORS = '1'

                $null = Get-IRTTenantOwner -TenantId $script:UncachedTid -Quiet

                $script:Errors.Count | Should -Be 1
                $script:Errors[0] | Should -Match 'Forbidden'
            }
        }
    }
}
