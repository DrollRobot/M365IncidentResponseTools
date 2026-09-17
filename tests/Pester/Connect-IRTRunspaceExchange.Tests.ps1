#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline branch tests for Connect-IRTRunspaceExchange.

.DESCRIPTION
    All tests are offline. Get-IRTAccessToken, Get-ConnectionInformation,
    Connect-ExchangeOnline, and Disconnect-ExchangeOnline are mocked with the
    same simulated connection registry used in Connect-IRTExchange.Tests.ps1.
    The runspace-local tracking global ($Global:IRT_RunspaceExo) is saved and
    restored around every test.

-- guard rails -------------------------------------------------------------

    Without an injected session the worker cannot resolve the cloud config;
    the function must throw with guidance pointing at the parent session.

-- fast path (healthy runspace connection) ----------------------------------

    When this runspace already holds a live connection for the right tenant
    with >5 minutes left on the bound token, the call must be a complete
    no-op: no token minted, no connect, no disconnect.

-- reconnect paths -----------------------------------------------------------

    A stale bound token, a dead connection, or no prior state must each mint
    silently (always -Silent; a worker can never prompt) and establish a new
    connection, updating $Global:IRT_RunspaceExo and disconnecting only the
    connection this runspace previously owned.

-- failure propagation -------------------------------------------------------

    Silent acquisition failures must propagate as terminating errors (the
    worker step fails loudly rather than hanging on a hidden prompt).
#>

InModuleScope M365IncidentResponseTools {

    BeforeAll {
        $script:TestTenant = 'aaaaaaaa-0000-0000-0000-aaaaaaaaaaaa'

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
                IPPS          = $null
            }
        }

        function New-TokenResult {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test-only factory helper; ShouldProcess is not applicable.')]
            param(
                [string] $Username = 'admin@customer.com'
            )
            [pscustomobject]@{
                AccessToken = 'fresh-runspace-token'
                ExpiresOn   = [System.DateTimeOffset]::UtcNow.AddMinutes(55)
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
                [string] $ConnectionUri = 'https://outlook.office365.com',
                [string] $State = 'Connected'
            )
            [pscustomobject]@{
                ConnectionId  = $ConnectionId
                TenantID      = $TenantID
                ConnectionUri = $ConnectionUri
                State         = $State
            }
        }
    }

    Describe 'Connect-IRTRunspaceExchange' -Tag 'unit' {

        BeforeEach {
            $script:SavedSession = (
                Get-Variable -Name IRT_Session -Scope Global -ErrorAction SilentlyContinue
            )?.Value
            $script:SavedRunspaceExo = (
                Get-Variable -Name IRT_RunspaceExo -Scope Global -ErrorAction SilentlyContinue
            )?.Value
            $Global:IRT_Session = New-TestSession
            $Global:IRT_RunspaceExo = $null

            # Simulated EXO connection registry; -ConnectionId filtering matches
            # the real cmdlet's behavior so the fast path can verify liveness.
            $script:Connections = @()
            Mock Get-ConnectionInformation {
                if ($ConnectionId) {
                    $script:Connections | Where-Object { $_.ConnectionId -in $ConnectionId }
                } else {
                    $script:Connections
                }
            }
            Mock Connect-ExchangeOnline {
                $script:NewConnectionId = [guid]::NewGuid().ToString()
                $script:Connections += New-TestConnection -ConnectionId $script:NewConnectionId
            }
            Mock Disconnect-ExchangeOnline {
                $script:Connections = @($script:Connections |
                        Where-Object { $_.ConnectionId -notin $ConnectionId })
            }
            Mock Get-IRTAccessToken { New-TokenResult }
        }
        AfterEach {
            $Global:IRT_Session = $script:SavedSession
            $Global:IRT_RunspaceExo = $script:SavedRunspaceExo
        }

        # -------------------------------------------------------------------
        Context 'guard rails' {

            It 'throws when no session was injected into the runspace' {
                $Global:IRT_Session = $null
                { Connect-IRTRunspaceExchange } |
                    Should -Throw -ExpectedMessage '*parent session*'
            }
        }

        # -------------------------------------------------------------------
        Context 'fast path: healthy runspace connection' {

            BeforeEach {
                $script:LiveId = [guid]::NewGuid().ToString()
                $script:Connections = @(New-TestConnection -ConnectionId $script:LiveId)
                $Global:IRT_RunspaceExo = @{
                    ConnectionId     = $script:LiveId
                    BoundTokenExpiry = [datetime]::UtcNow.AddMinutes(50)
                }
            }

            It 'is a complete no-op' {
                Connect-IRTRunspaceExchange
                Should -Invoke Get-IRTAccessToken -Times 0
                Should -Invoke Connect-ExchangeOnline -Times 0
                Should -Invoke Disconnect-ExchangeOnline -Times 0
            }

            It 'leaves the tracking global unchanged' {
                $Before = $Global:IRT_RunspaceExo
                Connect-IRTRunspaceExchange
                $Global:IRT_RunspaceExo | Should -Be $Before
            }
        }

        # -------------------------------------------------------------------
        Context 'reconnect paths' {

            It 'connects fresh when there is no prior runspace state' {
                Connect-IRTRunspaceExchange
                Should -Invoke Connect-ExchangeOnline -Times 1 -Exactly -ParameterFilter {
                    $AccessToken -eq 'fresh-runspace-token' -and
                    $UserPrincipalName -eq 'admin@customer.com' -and
                    $ExchangeEnvironmentName -eq 'O365Default'
                }
            }

            It 'always mints silently (a worker can never prompt)' {
                Connect-IRTRunspaceExchange
                Should -Invoke Get-IRTAccessToken -Times 1 -Exactly -ParameterFilter {
                    $Service -eq 'Exchange' -and $Silent -eq $true
                }
            }

            It 'updates the tracking global with the new ConnectionId and expiry' {
                Connect-IRTRunspaceExchange
                $Global:IRT_RunspaceExo.ConnectionId | Should -Be $script:NewConnectionId
                $Global:IRT_RunspaceExo.BoundTokenExpiry |
                    Should -BeGreaterThan ([datetime]::UtcNow)
            }

            It 'reconnects when the bound token is stale (<5 min)' {
                $StaleId = [guid]::NewGuid().ToString()
                $script:Connections = @(New-TestConnection -ConnectionId $StaleId)
                $Global:IRT_RunspaceExo = @{
                    ConnectionId     = $StaleId
                    BoundTokenExpiry = [datetime]::UtcNow.AddMinutes(2)
                }
                Connect-IRTRunspaceExchange
                Should -Invoke Connect-ExchangeOnline -Times 1
            }

            It 'reconnects when the tracked connection is dead' {
                $DeadId = [guid]::NewGuid().ToString()
                $script:Connections = @(
                    New-TestConnection -ConnectionId $DeadId -State 'Broken'
                )
                $Global:IRT_RunspaceExo = @{
                    ConnectionId     = $DeadId
                    BoundTokenExpiry = [datetime]::UtcNow.AddMinutes(50)
                }
                Connect-IRTRunspaceExchange
                Should -Invoke Connect-ExchangeOnline -Times 1
            }

            It 'disconnects only the connection this runspace previously owned' {
                $StaleId = [guid]::NewGuid().ToString()
                $OtherId = [guid]::NewGuid().ToString()
                $script:Connections = @(
                    (New-TestConnection -ConnectionId $StaleId),
                    (New-TestConnection -ConnectionId $OtherId)
                )
                $Global:IRT_RunspaceExo = @{
                    ConnectionId     = $StaleId
                    BoundTokenExpiry = [datetime]::UtcNow.AddMinutes(2)
                }
                Connect-IRTRunspaceExchange
                Should -Invoke Disconnect-ExchangeOnline -Times 1 -Exactly -ParameterFilter {
                    $ConnectionId -eq $StaleId
                }
                $script:Connections.ConnectionId | Should -Contain $OtherId
            }
        }

        # -------------------------------------------------------------------
        Context 'failure propagation' {

            It 'propagates a silent acquisition failure as a terminating error' {
                Mock Get-IRTAccessToken { throw 'Silent Exchange token acquisition failed' }
                { Connect-IRTRunspaceExchange } |
                    Should -Throw -ExpectedMessage '*Silent Exchange token acquisition failed*'
            }

            It 'throws the re-run guidance when the result has no token' {
                Mock Get-IRTAccessToken { [pscustomobject]@{ AccessToken = $null } }
                { Connect-IRTRunspaceExchange } |
                    Should -Throw -ExpectedMessage '*Re-run Connect-IRT*'
            }
        }
    }
}
