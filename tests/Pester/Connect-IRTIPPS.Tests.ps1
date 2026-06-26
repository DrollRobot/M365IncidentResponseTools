#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline branch tests for Connect-IRTIPPS.

.DESCRIPTION
    All tests are offline. Get-IRTAccessToken, Get-ConnectionInformation,
    Connect-IPPSSession, Disconnect-ExchangeOnline, and Write-IRT are mocked.
    The connection registry is simulated with a script-scoped list, the same
    pattern as Connect-IRTExchange.Tests.ps1, so the ConnectionId diffing and
    scoped-disconnect logic is exercised for real.

    There is intentionally no aud-validation context: the search-only audience
    (dataservice.o365filtering.com) is identical across clouds, so the
    connector performs no audience check (cloud-correctness is enforced by
    account selection inside Get-IRTAccessToken).

-- fresh connect -----------------------------------------------------------

    No existing IPPS connection: mint (forwarding -SearchOnly), bind via
    Connect-IPPSSession with the compliance ConnectionUri and
    -EnableSearchOnlySession when SearchOnly, record the new ConnectionId.

-- SearchOnly handling ------------------------------------------------------

    A token issued for the search-only audience won't authenticate against the
    full audience and vice versa, so a SearchOnly-mode change must force a
    reconnect even when an apparently healthy connection exists.

-- already connected --------------------------------------------------------

    A healthy compliance-URI connection for the tenant with a fresh bound
    token and unchanged SearchOnly: no reconnect. An Exchange connection must
    NOT count as an IPPS connection.

-- scoped reconnect ---------------------------------------------------------

    Replacing an IPPS connection must disconnect only the OLD IPPS
    ConnectionId, never the Exchange connection, and never unscoped.
#>

InModuleScope M365IncidentResponseTools {

    BeforeAll {
        $script:TestTenant = 'aaaaaaaa-0000-0000-0000-aaaaaaaaaaaa'
        $script:IppsUri = 'https://nam02b.ps.compliance.protection.outlook.com/powershell'

        function New-TestSession {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test-only factory helper; ShouldProcess is not applicable.')]
            param(
                [object] $IPPS = $null
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
                Graph         = $null
                Exchange      = $null
                IPPS          = $IPPS
            }
        }

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

        function New-TestConnection {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test-only factory helper; ShouldProcess is not applicable.')]
            param(
                [string] $ConnectionId = ([guid]::NewGuid().ToString()),
                [string] $TenantID = $script:TestTenant,
                [string] $ConnectionUri = $script:IppsUri,
                [string] $State = 'Connected',
                [string] $UserPrincipalName = 'admin@customer.com'
            )
            [pscustomobject]@{
                ConnectionId      = $ConnectionId
                TenantID          = $TenantID
                ConnectionUri     = $ConnectionUri
                State             = $State
                UserPrincipalName = $UserPrincipalName
            }
        }
    }

    Describe 'Connect-IRTIPPS' {

        BeforeEach {
            $script:SavedSession = (
                Get-Variable -Name IRT_Session -Scope Global -ErrorAction SilentlyContinue
            )?.Value
            $Global:IRT_Session = New-TestSession

            $script:Connections = @()
            Mock Get-ConnectionInformation { $script:Connections }
            Mock Connect-IPPSSession {
                $script:NewConnectionId = [guid]::NewGuid().ToString()
                $script:Connections += New-TestConnection -ConnectionId $script:NewConnectionId
            }
            Mock Disconnect-ExchangeOnline {
                $script:Connections = @($script:Connections |
                        Where-Object { $_.ConnectionId -notin $ConnectionId })
            }
            Mock Get-IRTAccessToken { New-TokenResult }
            Mock Write-IRT { }
        }
        AfterEach {
            $Global:IRT_Session = $script:SavedSession
        }

        # -------------------------------------------------------------------
        Context 'fresh connect (no existing connection)' {

            It 'forwards -SearchOnly to Get-IRTAccessToken' {
                $null = Connect-IRTIPPS -TenantId $script:TestTenant -Cloud Commercial
                Should -Invoke Get-IRTAccessToken -Times 1 -Exactly -ParameterFilter {
                    $Service -eq 'IPPS' -and $SearchOnly -eq $true
                }
            }

            It 'binds via Connect-IPPSSession with the compliance URI and search-only flag' {
                $null = Connect-IRTIPPS -TenantId $script:TestTenant -Cloud Commercial
                Should -Invoke Connect-IPPSSession -Times 1 -Exactly -ParameterFilter {
                    $AccessToken -eq 'good-token' -and
                    $UserPrincipalName -eq 'admin@customer.com' -and
                    $ConnectionUri -match 'compliance\.protection\.outlook\.com' -and
                    $EnableSearchOnlySession -eq $true
                }
            }

            It 'omits -EnableSearchOnlySession when SearchOnly is $false' {
                $ConnectParams = @{
                    TenantId   = $script:TestTenant
                    Cloud      = 'Commercial'
                    SearchOnly = $false
                }
                $null = Connect-IRTIPPS @ConnectParams
                Should -Invoke Connect-IPPSSession -Times 1 -Exactly -ParameterFilter {
                    -not $EnableSearchOnlySession
                }
            }

            It 'records the NEW ConnectionId and SearchOnly mode in the metadata' {
                $Result = Connect-IRTIPPS -TenantId $script:TestTenant -Cloud Commercial
                $Result.ConnectionId | Should -Be $script:NewConnectionId
                $Result.SearchOnly | Should -BeTrue
                $Result.BoundTokenExpiry | Should -BeOfType [System.DateTime]
            }
        }

        # -------------------------------------------------------------------
        Context 'already connected (healthy connection, same token)' {

            BeforeEach {
                $script:FixedExpiresOn = [System.DateTimeOffset]::UtcNow.AddMinutes(50)
                $script:ExistingId = [guid]::NewGuid().ToString()
                $script:Connections = @(
                    New-TestConnection -ConnectionId $script:ExistingId
                )
                $Global:IRT_Session = New-TestSession -IPPS ([pscustomobject]@{
                        UserPrincipalName = 'admin@customer.com'
                        BoundTokenExpiry  = $script:FixedExpiresOn.UtcDateTime
                        ConnectionId      = $script:ExistingId
                        SearchOnly        = $true
                        TenantId          = $script:TestTenant
                    })
                Mock Get-IRTAccessToken { New-TokenResult -ExpiresOn $script:FixedExpiresOn }
            }

            It 'does not reconnect' {
                $null = Connect-IRTIPPS -TenantId $script:TestTenant -Cloud Commercial
                Should -Invoke Connect-IPPSSession -Times 0
            }

            It 'tells the operator it is already connected' {
                $null = Connect-IRTIPPS -TenantId $script:TestTenant -Cloud Commercial
                Should -Invoke Write-IRT -Times 1 -ParameterFilter {
                    $Message -match 'Already connected'
                }
            }

            It 'reports the live connection account, not a freshly-acquired token' {
                # No rebind: the session still holds the previously-bound token, so
                # the reported UPN must come from the live connection - not a token
                # silently acquired as a different account (the decoupling bug).
                $script:Connections[0].UserPrincipalName = 'bound@customer.com'
                Mock Get-IRTAccessToken {
                    New-TokenResult -Username 'fresh@customer.com' -ExpiresOn $script:FixedExpiresOn
                }
                $Result = Connect-IRTIPPS -TenantId $script:TestTenant -Cloud Commercial
                $Result.UserPrincipalName | Should -Be 'bound@customer.com'
            }

            It 'reconnects when the SearchOnly mode changes' {
                # The session connection was search-only; asking for the full
                # audience must force a reconnect even though it looks healthy.
                $ConnectParams = @{
                    TenantId   = $script:TestTenant
                    Cloud      = 'Commercial'
                    SearchOnly = $false
                }
                $null = Connect-IRTIPPS @ConnectParams
                Should -Invoke Connect-IPPSSession -Times 1
            }

            It 'reconnects when the bound token is stale (<5 min)' {
                $Global:IRT_Session.IPPS.BoundTokenExpiry = [datetime]::UtcNow.AddMinutes(2)
                $null = Connect-IRTIPPS -TenantId $script:TestTenant -Cloud Commercial
                Should -Invoke Connect-IPPSSession -Times 1
            }

            It 'reconnects when -Force is set' {
                $null = Connect-IRTIPPS -TenantId $script:TestTenant -Cloud Commercial -Force
                Should -Invoke Connect-IPPSSession -Times 1
            }

            It 'an Exchange connection does not count as an IPPS connection' {
                $script:Connections = @(
                    New-TestConnection -ConnectionUri 'https://outlook.office365.com'
                )
                $null = Connect-IRTIPPS -TenantId $script:TestTenant -Cloud Commercial
                Should -Invoke Connect-IPPSSession -Times 1
            }
        }

        # -------------------------------------------------------------------
        Context 'scoped reconnect cleanup' {

            BeforeEach {
                $script:OldId = [guid]::NewGuid().ToString()
                $script:ExoId = [guid]::NewGuid().ToString()
                $ExoConnParams = @{
                    ConnectionId  = $script:ExoId
                    ConnectionUri = 'https://outlook.office365.com'
                }
                $script:Connections = @(
                    (New-TestConnection -ConnectionId $script:OldId),
                    (New-TestConnection @ExoConnParams)
                )
                $Global:IRT_Session = New-TestSession -IPPS ([pscustomobject]@{
                        UserPrincipalName = 'admin@customer.com'
                        BoundTokenExpiry  = [datetime]::UtcNow.AddMinutes(2)  # stale
                        ConnectionId      = $script:OldId
                        SearchOnly        = $true
                        TenantId          = $script:TestTenant
                    })
            }

            It 'disconnects the replaced IPPS connection by ConnectionId' {
                $null = Connect-IRTIPPS -TenantId $script:TestTenant -Cloud Commercial
                Should -Invoke Disconnect-ExchangeOnline -Times 1 -Exactly -ParameterFilter {
                    $ConnectionId -eq $script:OldId
                }
            }

            It 'never issues an unscoped disconnect' {
                $null = Connect-IRTIPPS -TenantId $script:TestTenant -Cloud Commercial
                Should -Invoke Disconnect-ExchangeOnline -Times 0 -ParameterFilter {
                    -not $ConnectionId
                }
            }

            It 'leaves the Exchange connection alone' {
                $null = Connect-IRTIPPS -TenantId $script:TestTenant -Cloud Commercial
                Should -Invoke Disconnect-ExchangeOnline -Times 0 -ParameterFilter {
                    $ConnectionId -eq $script:ExoId
                }
                $script:Connections.ConnectionId | Should -Contain $script:ExoId
            }

            It 'the new connection survives the cleanup' {
                $Result = Connect-IRTIPPS -TenantId $script:TestTenant -Cloud Commercial
                $script:Connections.ConnectionId | Should -Contain $Result.ConnectionId
                $script:Connections.ConnectionId | Should -Not -Contain $script:OldId
            }
        }
    }
}
