#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline branch tests for Connect-IRTGraph.

.DESCRIPTION
    All tests are offline. Get-IRTAccessToken, Get-TokenPayload, Get-MgContext,
    Connect-MgGraph, Disconnect-MgGraph, Invoke-MgGraphRequest,
    Test-GraphAdminConsent, Invoke-AdminConsent, and Write-IRT are mocked, so
    no MSAL, network, or browser activity occurs. Live behavior is covered by
    the Online-tagged tests in Connect-IRT.Tests.ps1.

-- fresh connect (no existing MgContext) ----------------------------------

    With no context, the connector must bind the freshly-minted token via
    Connect-MgGraph (with the cloud's Graph environment), skip the disconnect
    (nothing to disconnect), and return the new metadata shape.

-- cloud (aud) validation -------------------------------------------------

    The token audience is the authoritative cloud signal. An unparseable or
    non-URL (GUID) audience must be ignored rather than punished with a
    re-auth loop. A positively-wrong audience must trigger exactly one
    -ForceRefresh re-acquisition; if the audience is STILL wrong afterwards,
    the authority itself is misconfigured and the connector must throw.

-- already connected (NeedConnect = $false) --------------------------------

    With a healthy matching context (same tenant, environment, full scopes)
    and no newer token in hand, the connector must verify liveness with a
    real (mocked) Graph call and then NOT reconnect.

-- reconnect triggers ------------------------------------------------------

    Each of these must independently force a re-bind: a failed liveness
    check, a newer token than the one bound, missing scopes on the existing
    context, and -Force.

-- admin consent -----------------------------------------------------------

    Missing tenant-wide consent must drive Invoke-AdminConsent with exactly
    the missing scopes. A failed consent CHECK must warn and continue (never
    block connection on a transient Graph error).
#>

InModuleScope M365IncidentResponseTools {

    BeforeAll {
        $script:TestTenant = 'aaaaaaaa-0000-0000-0000-aaaaaaaaaaaa'

        function New-TestSession {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test-only factory helper; ShouldProcess is not applicable.')]
            param(
                [object] $Graph = $null
            )
            [pscustomobject]@{
                TenantId      = $script:TestTenant
                ClientId      = $null
                Cloud         = 'Commercial'
                CloudConfig   = [pscustomobject]@{
                    LoginHost      = 'https://login.microsoftonline.com'
                    Graph          = 'https://graph.microsoft.com'
                    GraphEnv       = 'Global'
                    Exchange       = 'https://outlook.office365.com/.default'
                    ExchangeEnv    = 'O365Default'
                    IPPS           = 'https://ps.compliance.protection.outlook.com/powershell'
                    IPPSSearchOnly = 'https://dataservice.o365filtering.com/.default'
                }
                Apps          = [hashtable]::Synchronized(@{})
                StickyAccount = [hashtable]::Synchronized(@{})
                Graph         = $Graph
                Exchange      = $null
                IPPS          = $null
            }
        }

        # AuthenticationResult-shaped stub. The token string doubles as the
        # routing key for the Get-TokenPayload mock (which aud it maps to).
        function New-TokenResult {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test-only factory helper; ShouldProcess is not applicable.')]
            param(
                [string] $AccessToken = 'good-token',
                [string] $Username = 'admin@customer.com',
                [System.DateTimeOffset] $ExpiresOn = [System.DateTimeOffset]::UtcNow.AddMinutes(55)
            )
            [pscustomobject]@{
                AccessToken = $AccessToken
                ExpiresOn   = $ExpiresOn
                Account     = [pscustomobject]@{
                    Username      = $Username
                    HomeAccountId = [pscustomobject]@{
                        Identifier = "$Username.home"
                        TenantId   = $script:TestTenant
                    }
                }
            }
        }

        # MgContext-shaped stub with full default scopes (the healthy case).
        function New-MgContextStub {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test-only factory helper; ShouldProcess is not applicable.')]
            param(
                [string]   $TenantId = $script:TestTenant,
                [string]   $Environment = 'Global',
                [string[]] $Scopes = (Get-IRTGraphDefaultScope)
            )
            [pscustomobject]@{
                TenantId    = $TenantId
                Environment = $Environment
                Scopes      = $Scopes
                Account     = 'admin@customer.com'
            }
        }
    }

    Describe 'Connect-IRTGraph' {

        BeforeEach {
            $script:SavedSession = (
                Get-Variable -Name IRT_Session -Scope Global -ErrorAction SilentlyContinue
            )?.Value
            $Global:IRT_Session = New-TestSession

            # Default healthy mocks; individual contexts override as needed.
            Mock Get-IRTAccessToken { New-TokenResult }
            Mock Get-TokenPayload { [pscustomobject]@{ aud = 'https://graph.microsoft.com' } }
            Mock Get-MgContext { $null }
            Mock Connect-MgGraph { }
            Mock Disconnect-MgGraph { }
            Mock Invoke-MgGraphRequest { [pscustomobject]@{ value = @() } }
            Mock Test-GraphAdminConsent { @() }
            Mock Invoke-AdminConsent { }
            Mock Write-IRT { }
        }
        AfterEach {
            $Global:IRT_Session = $script:SavedSession
        }

        # -------------------------------------------------------------------
        Context 'fresh connect (no existing MgContext)' {

            It 'binds the token via Connect-MgGraph with the cloud environment' {
                $null = Connect-IRTGraph -TenantId $script:TestTenant -Cloud Commercial
                Should -Invoke Connect-MgGraph -Times 1 -Exactly -ParameterFilter {
                    $Environment -eq 'Global'
                }
            }

            It 'does not disconnect when there was no context' {
                $null = Connect-IRTGraph -TenantId $script:TestTenant -Cloud Commercial
                Should -Invoke Disconnect-MgGraph -Times 0
            }

            It 'returns the new metadata shape' {
                $Result = Connect-IRTGraph -TenantId $script:TestTenant -Cloud Commercial
                $Result.Account | Should -Be 'admin@customer.com'
                $Result.TenantId | Should -Be $script:TestTenant
                $Result.BoundTokenExpiry | Should -BeOfType [System.DateTime]
                $Result.Scopes | Should -Contain 'AuditLog.Read.All'
            }

            It 'includes -AdditionalScope in the returned scope list' {
                $ConnectParams = @{
                    TenantId        = $script:TestTenant
                    Cloud           = 'Commercial'
                    AdditionalScope = 'Custom.Extra.Scope'
                }
                $Result = Connect-IRTGraph @ConnectParams
                $Result.Scopes | Should -Contain 'Custom.Extra.Scope'
            }
        }

        # -------------------------------------------------------------------
        Context 'cloud (aud) validation' {

            It 'skips validation when the audience cannot be decoded' {
                Mock Get-TokenPayload { [pscustomobject]@{ aud = $null } }
                $null = Connect-IRTGraph -TenantId $script:TestTenant -Cloud Commercial
                Should -Invoke Get-IRTAccessToken -Times 1 -Exactly
            }

            It 'skips validation when the audience is a GUID, not a URL' {
                Mock Get-TokenPayload {
                    [pscustomobject]@{ aud = '00000003-0000-0000-c000-000000000000' }
                }
                $null = Connect-IRTGraph -TenantId $script:TestTenant -Cloud Commercial
                Should -Invoke Get-IRTAccessToken -Times 1 -Exactly
            }

            It 're-acquires with -ForceRefresh on audience mismatch, then succeeds' {
                # Wrong-cloud token first; the forced refresh returns a correct one.
                Mock Get-IRTAccessToken {
                    if ($ForceRefresh) { New-TokenResult -AccessToken 'right-token' }
                    else { New-TokenResult -AccessToken 'wrong-token' }
                }
                Mock Get-TokenPayload {
                    if ($Token -eq 'wrong-token') {
                        [pscustomobject]@{ aud = 'https://graph.microsoft.us' }
                    } else {
                        [pscustomobject]@{ aud = 'https://graph.microsoft.com' }
                    }
                }
                $null = Connect-IRTGraph -TenantId $script:TestTenant -Cloud Commercial
                Should -Invoke Get-IRTAccessToken -Times 1 -Exactly -ParameterFilter {
                    $ForceRefresh -eq $true
                }
            }

            It 'throws when the audience is still wrong after the forced refresh' {
                Mock Get-TokenPayload {
                    [pscustomobject]@{ aud = 'https://graph.microsoft.us' }
                }
                { Connect-IRTGraph -TenantId $script:TestTenant -Cloud Commercial } |
                    Should -Throw -ExpectedMessage '*still does not match*'
            }
        }

        # -------------------------------------------------------------------
        Context 'already connected (healthy context, same token)' {

            BeforeEach {
                # Session expiry equals the minted token's expiry: MSAL returned
                # the same cached token, so no re-bind is needed.
                $script:FixedExpiresOn = [System.DateTimeOffset]::UtcNow.AddMinutes(50)
                $Global:IRT_Session = New-TestSession -Graph ([pscustomobject]@{
                        Account          = 'admin@customer.com'
                        Scopes           = $null
                        BoundTokenExpiry = $script:FixedExpiresOn.UtcDateTime
                        TenantId         = $script:TestTenant
                    })
                Mock Get-IRTAccessToken { New-TokenResult -ExpiresOn $script:FixedExpiresOn }
                Mock Get-MgContext { New-MgContextStub }
            }

            It 'does not reconnect' {
                $null = Connect-IRTGraph -TenantId $script:TestTenant -Cloud Commercial
                Should -Invoke Connect-MgGraph -Times 0
            }

            It 'verifies the existing connection with a live call' {
                $null = Connect-IRTGraph -TenantId $script:TestTenant -Cloud Commercial
                Should -Invoke Invoke-MgGraphRequest -Times 1
            }

            It 'tells the operator it is already connected' {
                $null = Connect-IRTGraph -TenantId $script:TestTenant -Cloud Commercial
                Should -Invoke Write-IRT -Times 1 -ParameterFilter {
                    $Message -match 'Already connected'
                }
            }

            It 'preserves the bound account instead of a fresh unbound acquisition' {
                # No reconnect happens, so a token minted for a different account
                # must NOT be stamped onto the session - the label has to track
                # whatever is actually bound (here, the prior admin@customer.com).
                Mock Get-IRTAccessToken {
                    New-TokenResult -Username 'new@fresh.com' -ExpiresOn $script:FixedExpiresOn
                }
                $Result = Connect-IRTGraph -TenantId $script:TestTenant -Cloud Commercial
                $Result.Account | Should -Be 'admin@customer.com'
            }

            It 'reconnects when the live verification fails' {
                Mock Invoke-MgGraphRequest { throw '401 InvalidAuthenticationToken' }
                $null = Connect-IRTGraph -TenantId $script:TestTenant -Cloud Commercial
                Should -Invoke Disconnect-MgGraph -Times 1
                Should -Invoke Connect-MgGraph -Times 1
            }

            It 'reconnects when MSAL hands back a newer token than the bound one' {
                $Newer = $script:FixedExpiresOn.AddMinutes(30)
                Mock Get-IRTAccessToken { New-TokenResult -ExpiresOn $Newer }
                $null = Connect-IRTGraph -TenantId $script:TestTenant -Cloud Commercial
                Should -Invoke Connect-MgGraph -Times 1
            }

            It 'reconnects when the existing context is missing a requested scope' {
                Mock Get-MgContext { New-MgContextStub -Scopes @('User.ReadWrite.All') }
                $null = Connect-IRTGraph -TenantId $script:TestTenant -Cloud Commercial
                Should -Invoke Connect-MgGraph -Times 1
            }

            It 'reconnects when the context belongs to a different tenant' {
                Mock Get-MgContext {
                    New-MgContextStub -TenantId 'bbbbbbbb-0000-0000-0000-bbbbbbbbbbbb'
                }
                $null = Connect-IRTGraph -TenantId $script:TestTenant -Cloud Commercial
                Should -Invoke Connect-MgGraph -Times 1
            }

            It 'reconnects when -Force is set' {
                $null = Connect-IRTGraph -TenantId $script:TestTenant -Cloud Commercial -Force
                Should -Invoke Connect-MgGraph -Times 1
            }
        }

        # -------------------------------------------------------------------
        Context 'admin consent' {

            It 'drives Invoke-AdminConsent with exactly the missing scopes' {
                Mock Test-GraphAdminConsent { @('AuditLog.Read.All', 'Domain.Read.All') }
                $null = Connect-IRTGraph -TenantId $script:TestTenant -Cloud Commercial
                Should -Invoke Invoke-AdminConsent -Times 1 -Exactly -ParameterFilter {
                    $Scope -contains 'AuditLog.Read.All' -and
                    $Scope -contains 'Domain.Read.All' -and
                    $Scope.Count -eq 2
                }
            }

            It 'does not drive consent when nothing is missing' {
                $null = Connect-IRTGraph -TenantId $script:TestTenant -Cloud Commercial
                Should -Invoke Invoke-AdminConsent -Times 0
            }

            It 're-acquires (forced) and re-binds after driving the consent flow' {
                # The token bound before the grant has a pre-consent scope claim;
                # the session must not keep it for the rest of its lifetime.
                Mock Test-GraphAdminConsent { @('Domain.Read.All') }
                $null = Connect-IRTGraph -TenantId $script:TestTenant -Cloud Commercial
                Should -Invoke Get-IRTAccessToken -Times 1 -ParameterFilter {
                    $ForceRefresh -eq $true
                }
                # Initial bind plus the post-consent re-bind.
                Should -Invoke Connect-MgGraph -Times 2 -Exactly
            }

            It 'does not force-refresh when consent was already granted' {
                $null = Connect-IRTGraph -TenantId $script:TestTenant -Cloud Commercial
                Should -Invoke Get-IRTAccessToken -Times 0 -ParameterFilter {
                    $ForceRefresh -eq $true
                }
            }

            It 'warns and continues when the consent check itself fails' {
                Mock Test-GraphAdminConsent { throw 'Graph timeout' }
                { Connect-IRTGraph -TenantId $script:TestTenant -Cloud Commercial } |
                    Should -Not -Throw
                Should -Invoke Invoke-AdminConsent -Times 0
            }
        }
    }
}
