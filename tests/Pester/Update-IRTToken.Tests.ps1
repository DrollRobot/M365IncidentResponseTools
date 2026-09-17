#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Tests for Update-IRTToken bound-token expiry detection and per-service refresh.

.DESCRIPTION
    All tests are offline. The private connectors (Connect-IRTGraph,
    Connect-IRTExchange, Connect-IRTIPPS), Connect-IRTRunspaceExchange, and
    Write-IRT are mocked throughout so no network I/O occurs. $Global:IRT_Session
    (plus the worker globals IRT_IsRunspaceWorker / IRT_RunspaceExo) is saved
    before each test and restored afterwards, so the test suite is safe to run
    while actively connected to a tenant.

    Session objects are constructed with New-SvcObject (a BeforeAll helper)
    using a signed ExpiresInMinutes value: positive = future, negative = past.
    This lets each context describe the token state declaratively without
    repeating DateTime arithmetic in every test.

-- no IRT session ($Global:IRT_Session is $null) -------------------------

    Update-IRTToken must detect a missing session before trying to read any
    service slot. When SkipIfNeverConnected is not set it must write one
    error per requested service so the operator knows exactly which services
    need connecting. When SkipIfNeverConnected is set it must return silently.

-- service slot is null in the session -----------------------------------

    A session object can exist while individual service slots are $null (e.g.
    the user connected Graph-only). The function must not treat a null slot as
    a reason to refresh -- there is nothing to refresh -- and it must not call
    a connector for a service that was never connected.

-- token is healthy (BoundTokenExpiry > 5 minutes from now) --------------

    The function should never call a connector when all requested bound tokens
    are well within their validity window. This is the hot path on every
    domain-function call; spurious refreshes here would cause unnecessary
    latency and could trigger MSAL rate limits.

-- token is expiring within the 5-minute threshold ----------------------

    MSAL's AcquireTokenSilent uses the refresh token (making a network call
    for a fresh access token) only when the cached token is within ~5 minutes
    of expiry. Update-IRTToken uses the same window so that the connector call
    actually yields a genuinely new token rather than the same near-expired
    cached one.

-- token is already expired (BoundTokenExpiry in the past) ---------------

    An expired token has TotalMinutes < 0. The function must still trigger a
    refresh (expired < threshold) and PassThru must report $false unless the
    connector mock actually returns a fresh session object.

-- connector throws ------------------------------------------------------

    If a connector raises a terminating error the try/catch must absorb it and
    write a human-readable "Token refresh failed" message. The exception must
    never propagate to the caller, because Update-IRTToken is called at the
    top of domain functions where an unhandled error would abort the entire
    operation. The old session slot must survive the failed refresh.

-- per-service refresh ---------------------------------------------------

    Refresh is scoped: ONLY the stale service's connector is invoked. With
    Graph expiring and Exchange healthy, exactly one Connect-IRTGraph call and
    zero Connect-IRTExchange calls must be made. The connector's return value
    replaces only that service's slot; an empty return must never wipe it.

-- runspace worker mode ($Global:IRT_IsRunspaceWorker) -------------------

    Workers never re-bind shared session state. Graph is a no-op (the parent
    keeps the process-wide binding fresh). Exchange delegates to
    Connect-IRTRunspaceExchange when the runspace-local bound token
    ($Global:IRT_RunspaceExo.BoundTokenExpiry) is missing or stale, and is a
    no-op when it is healthy. IPPS is always skipped.
#>

# ---------------------------------------------------------------------------
# All tests run inside InModuleScope so that Mock intercepts Write-IRT and the
# private connectors as they are called from within Update-IRTToken, not from
# the outer session scope.
# ---------------------------------------------------------------------------
InModuleScope M365IncidentResponseTools {

    BeforeAll {
        # New-SvcObject creates a minimal service-session object for
        # $Global:IRT_Session.Graph / .Exchange / .IPPS. Update-IRTToken only
        # reads .BoundTokenExpiry as a [datetime] (plus .Scopes for Graph and
        # .SearchOnly for IPPS when building a refresh call).
        # ExpiresInMinutes is signed: positive = future, negative = past.
        function New-SvcObject {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test-only factory helper; ShouldProcess is not applicable.')]
            param(
                [int]    $ExpiresInMinutes,
                [string] $Account = 'test@contoso.com'
            )
            [pscustomobject]@{
                BoundTokenExpiry  = [datetime]::UtcNow.AddMinutes($ExpiresInMinutes)
                Account           = $Account
                UserPrincipalName = $Account
                Scopes            = $null
                SearchOnly        = $true
                ConnectionId      = $null
            }
        }

        # New-IrtSession assembles a full $Global:IRT_Session object from
        # individual service objects (or $null for absent services).
        function New-IrtSession {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test-only factory helper; ShouldProcess is not applicable.')]
            param(
                [string] $TenantId = 'aaaaaaaa-0000-0000-0000-aaaaaaaaaaaa',
                [object] $Graph = $null,
                [object] $Exchange = $null,
                [object] $IPPS = $null
            )
            [pscustomobject]@{
                TenantId      = $TenantId
                ClientId      = $null
                Cloud         = 'Commercial'
                Apps          = [hashtable]::Synchronized(@{})
                StickyAccount = [hashtable]::Synchronized(@{})
                Graph         = $Graph
                Exchange      = $Exchange
                IPPS          = $IPPS
            }
        }
    }

    Describe 'Update-IRTToken' -Tag 'unit' {

        # Save and restore the auth globals around every test so the suite
        # is safe to run while the developer is actively connected to a tenant.
        BeforeEach {
            $script:SavedSession = (
                Get-Variable -Name IRT_Session -Scope Global -ErrorAction SilentlyContinue
            )?.Value
            $script:SavedWorker = (
                Get-Variable -Name IRT_IsRunspaceWorker -Scope Global -ErrorAction SilentlyContinue
            )?.Value
            $script:SavedRunspaceExo = (
                Get-Variable -Name IRT_RunspaceExo -Scope Global -ErrorAction SilentlyContinue
            )?.Value
            $Global:IRT_IsRunspaceWorker = $false
            $Global:IRT_RunspaceExo = $null
        }
        AfterEach {
            $Global:IRT_Session = $script:SavedSession
            $Global:IRT_IsRunspaceWorker = $script:SavedWorker
            $Global:IRT_RunspaceExo = $script:SavedRunspaceExo
        }

        # -------------------------------------------------------------------
        Context 'no IRT session ($Global:IRT_Session is $null)' {

            BeforeEach { $Global:IRT_Session = $null }

            It 'writes an error for each requested service when SkipIfNeverConnected is not set' {
                # Two services requested -> exactly two Error-level Write-IRT calls.
                Mock Write-IRT { }
                Update-IRTToken -Service 'Graph', 'Exchange'
                Should -Invoke Write-IRT -Times 2 -ParameterFilter { $Level -eq 'Error' }
            }

            It 'writes no output when SkipIfNeverConnected is set' {
                Mock Write-IRT { }
                Update-IRTToken -SkipIfNeverConnected
                Should -Invoke Write-IRT -Times 0
            }

            It 'returns nothing even with -PassThru' {
                # The function hits an early return before the PassThru block.
                $result = Update-IRTToken -SkipIfNeverConnected -PassThru
                $result | Should -BeNullOrEmpty
            }

            It 'does not call any connector' {
                Mock Connect-IRTGraph { }
                Mock Connect-IRTExchange { }
                Mock Connect-IRTIPPS { }
                Update-IRTToken -SkipIfNeverConnected
                Should -Invoke Connect-IRTGraph -Times 0
                Should -Invoke Connect-IRTExchange -Times 0
                Should -Invoke Connect-IRTIPPS -Times 0
            }
        }

        # -------------------------------------------------------------------
        Context 'session exists but the requested service slot is $null' {

            BeforeEach {
                $Global:IRT_Session = New-IrtSession -Graph $null
            }

            It 'writes an error when SkipIfNeverConnected is not set' {
                Mock Write-IRT { }
                Update-IRTToken -Service 'Graph'
                Should -Invoke Write-IRT -Times 1 -ParameterFilter { $Level -eq 'Error' }
            }

            It 'writes no error when SkipIfNeverConnected is set' {
                Mock Write-IRT { }
                Update-IRTToken -Service 'Graph' -SkipIfNeverConnected
                Should -Invoke Write-IRT -Times 0
            }

            It '-PassThru returns $false for the missing service' {
                $result = Update-IRTToken -Service 'Graph' -SkipIfNeverConnected -PassThru
                $result.Graph | Should -BeFalse
            }

            It 'does not call the connector when the only requested service is missing' {
                # A null slot causes continue in the loop; no refresh fires.
                Mock Connect-IRTGraph { }
                Update-IRTToken -Service 'Graph' -SkipIfNeverConnected
                Should -Invoke Connect-IRTGraph -Times 0
            }
        }

        # -------------------------------------------------------------------
        Context 'token is healthy (BoundTokenExpiry more than 5 minutes away)' {

            BeforeEach {
                $Global:IRT_Session = New-IrtSession -Graph (New-SvcObject -ExpiresInMinutes 60)
                Mock Connect-IRTGraph { }
            }

            It 'does not call the connector' {
                Update-IRTToken -Service 'Graph'
                Should -Invoke Connect-IRTGraph -Times 0
            }

            It '-PassThru returns $true for the service' {
                $result = Update-IRTToken -Service 'Graph' -PassThru
                $result.Graph | Should -BeTrue
            }

            It '-PassThru returns a hashtable' {
                # Callers key into the result with $result['Graph'], which requires
                # the return type to be [hashtable] and not $null or an array.
                $result = Update-IRTToken -Service 'Graph' -PassThru
                $result | Should -BeOfType [hashtable]
            }
        }

        # -------------------------------------------------------------------
        Context 'token is expiring within the 5-minute threshold' {

            # 3 minutes: within the 5-minute refresh window, but still future
            # (TotalMinutes > 0), so PassThru must report $true even when the
            # connector mock returns nothing (the slot is left untouched).
            BeforeEach {
                $Global:IRT_Session = New-IrtSession -Graph (New-SvcObject -ExpiresInMinutes 3)
                Mock Connect-IRTGraph { }
                Mock Write-IRT { }
            }

            It 'calls the connector exactly once with -Force' {
                Update-IRTToken -Service 'Graph'
                Should -Invoke Connect-IRTGraph -Times 1 -Exactly -ParameterFilter { $Force }
            }

            It 'writes a status message before refreshing' {
                Update-IRTToken -Service 'Graph'
                Should -Invoke Write-IRT -Times 1 -ParameterFilter { $Message -match 'refreshing' }
            }

            It '-PassThru returns $true because the token has not yet passed its expiry' {
                $result = Update-IRTToken -Service 'Graph' -PassThru
                $result.Graph | Should -BeTrue
            }

            It 'an empty connector return does not wipe the session slot' {
                Update-IRTToken -Service 'Graph'
                $Global:IRT_Session.Graph | Should -Not -BeNullOrEmpty
            }
        }

        # -------------------------------------------------------------------
        Context 'token is already expired (BoundTokenExpiry in the past)' {

            BeforeEach {
                $Global:IRT_Session = New-IrtSession -Graph (New-SvcObject -ExpiresInMinutes -30)
                Mock Write-IRT { }
            }

            It 'calls the connector' {
                Mock Connect-IRTGraph { }
                Update-IRTToken -Service 'Graph'
                Should -Invoke Connect-IRTGraph -Times 1 -ParameterFilter { $Force }
            }

            It '-PassThru returns $false when the connector returns nothing' {
                # The mock does nothing; BoundTokenExpiry remains -30 minutes in
                # the past. PassThru checks TotalMinutes > 0, which is $false.
                Mock Connect-IRTGraph { }
                $result = Update-IRTToken -Service 'Graph' -PassThru
                $result.Graph | Should -BeFalse
            }

            It '-PassThru returns $true when the connector returns fresh metadata' {
                # Simulate what Connect-IRTGraph does: return a new metadata object
                # with a future BoundTokenExpiry, which replaces the session slot.
                Mock Connect-IRTGraph {
                    [pscustomobject]@{
                        Account          = 'test@contoso.com'
                        Scopes           = $null
                        BoundTokenExpiry = [datetime]::UtcNow.AddHours(1)
                        TenantId         = 'aaaaaaaa-0000-0000-0000-aaaaaaaaaaaa'
                    }
                }
                $result = Update-IRTToken -Service 'Graph' -PassThru
                $result.Graph | Should -BeTrue
            }
        }

        # -------------------------------------------------------------------
        Context 'connector throws' {

            BeforeEach {
                $Global:IRT_Session = New-IrtSession -Graph (New-SvcObject -ExpiresInMinutes 2)
                Mock Connect-IRTGraph { throw 'MSAL auth failed' }
                Mock Write-IRT { }
            }

            It 'writes a token-refresh-failed error' {
                Update-IRTToken -Service 'Graph'
                Should -Invoke Write-IRT -Times 1 -ParameterFilter {
                    $Level -eq 'Error' -and $Message -match 'refresh failed'
                }
            }

            It 'does not propagate the exception to the caller' {
                { Update-IRTToken -Service 'Graph' } | Should -Not -Throw
            }

            It 'leaves the old session slot intact' {
                Update-IRTToken -Service 'Graph'
                $Global:IRT_Session.Graph | Should -Not -BeNullOrEmpty
            }
        }

        # -------------------------------------------------------------------
        Context '-Service parameter scopes which services are checked' {

            BeforeEach {
                $IrtParams = @{
                    Graph    = New-SvcObject -ExpiresInMinutes 60
                    Exchange = New-SvcObject -ExpiresInMinutes 60
                    IPPS     = New-SvcObject -ExpiresInMinutes 60
                }
                $Global:IRT_Session = New-IrtSession @IrtParams
                Mock Connect-IRTGraph { }
                Mock Connect-IRTExchange { }
                Mock Connect-IRTIPPS { }
            }

            It '-PassThru contains only the requested service key when one service is specified' {
                $result = Update-IRTToken -Service 'Graph' -PassThru
                $result.Keys | Should -Contain 'Graph'
                $result.Keys | Should -HaveCount 1
                $result.ContainsKey('Exchange') | Should -BeFalse
                $result.ContainsKey('IPPS') | Should -BeFalse
            }

            It '-PassThru contains all three keys when all three services are requested' {
                $result = Update-IRTToken -Service 'Graph', 'Exchange', 'IPPS' -PassThru
                $result.ContainsKey('Graph') | Should -BeTrue
                $result.ContainsKey('Exchange') | Should -BeTrue
                $result.ContainsKey('IPPS') | Should -BeTrue
            }
        }

        # -------------------------------------------------------------------
        Context 'one service expiring, another healthy (per-service refresh)' {

            BeforeEach {
                $IrtParams = @{
                    Graph    = New-SvcObject -ExpiresInMinutes 2
                    Exchange = New-SvcObject -ExpiresInMinutes 60
                }
                $Global:IRT_Session = New-IrtSession @IrtParams
                Mock Connect-IRTGraph { }
                Mock Connect-IRTExchange { }
                Mock Write-IRT { }
            }

            It 'refreshes ONLY the stale service' {
                Update-IRTToken -Service 'Graph', 'Exchange'
                Should -Invoke Connect-IRTGraph -Times 1 -Exactly
                Should -Invoke Connect-IRTExchange -Times 0
            }

            It '-PassThru reports the healthy service as $true' {
                $result = Update-IRTToken -Service 'Graph', 'Exchange' -PassThru
                $result.Exchange | Should -BeTrue
            }

            It '-PassThru reports the expiring (but not yet expired) service as $true' {
                $result = Update-IRTToken -Service 'Graph', 'Exchange' -PassThru
                $result.Graph | Should -BeTrue
            }
        }

        # -------------------------------------------------------------------
        Context 'IPPS refresh forwards SearchOnly' {

            BeforeEach {
                $Ipps = New-SvcObject -ExpiresInMinutes 2
                $Global:IRT_Session = New-IrtSession -IPPS $Ipps
                Mock Connect-IRTIPPS { }
                Mock Write-IRT { }
            }

            It 'passes the session SearchOnly value to the connector' {
                Update-IRTToken -Service 'IPPS'
                Should -Invoke Connect-IRTIPPS -Times 1 -ParameterFilter {
                    $SearchOnly -eq $true
                }
            }
        }

        # -------------------------------------------------------------------
        Context 'runspace worker mode' {

            BeforeEach {
                $IrtParams = @{
                    Graph    = New-SvcObject -ExpiresInMinutes 2
                    Exchange = New-SvcObject -ExpiresInMinutes 60
                    IPPS     = New-SvcObject -ExpiresInMinutes 2
                }
                $Global:IRT_Session = New-IrtSession @IrtParams
                $Global:IRT_IsRunspaceWorker = $true
                Mock Connect-IRTGraph { }
                Mock Connect-IRTExchange { }
                Mock Connect-IRTIPPS { }
                Mock Connect-IRTRunspaceExchange { }
                Mock Write-IRT { }
            }

            It 'never calls the parent connectors, even for stale tokens' {
                Update-IRTToken -Service 'Graph', 'Exchange', 'IPPS'
                Should -Invoke Connect-IRTGraph -Times 0
                Should -Invoke Connect-IRTExchange -Times 0
                Should -Invoke Connect-IRTIPPS -Times 0
            }

            It 'calls Connect-IRTRunspaceExchange when the runspace token is missing' {
                $Global:IRT_RunspaceExo = $null
                Update-IRTToken -Service 'Exchange'
                Should -Invoke Connect-IRTRunspaceExchange -Times 1 -Exactly
            }

            It 'calls Connect-IRTRunspaceExchange when the runspace token is stale' {
                $Global:IRT_RunspaceExo = @{
                    ConnectionId     = [guid]::NewGuid()
                    BoundTokenExpiry = [datetime]::UtcNow.AddMinutes(2)
                }
                Update-IRTToken -Service 'Exchange'
                Should -Invoke Connect-IRTRunspaceExchange -Times 1 -Exactly
            }

            It 'does not call Connect-IRTRunspaceExchange when the runspace token is healthy' {
                $Global:IRT_RunspaceExo = @{
                    ConnectionId     = [guid]::NewGuid()
                    BoundTokenExpiry = [datetime]::UtcNow.AddMinutes(50)
                }
                Update-IRTToken -Service 'Exchange'
                Should -Invoke Connect-IRTRunspaceExchange -Times 0
            }

            It '-PassThru reads Exchange status from the runspace-local global' {
                $Global:IRT_RunspaceExo = @{
                    ConnectionId     = [guid]::NewGuid()
                    BoundTokenExpiry = [datetime]::UtcNow.AddMinutes(50)
                }
                $result = Update-IRTToken -Service 'Exchange' -PassThru
                $result.Exchange | Should -BeTrue
            }

            It 'swallows a Connect-IRTRunspaceExchange failure and writes an error' {
                $Global:IRT_RunspaceExo = $null
                Mock Connect-IRTRunspaceExchange { throw 'silent acquisition failed' }
                { Update-IRTToken -Service 'Exchange' } | Should -Not -Throw
                Should -Invoke Write-IRT -Times 1 -ParameterFilter {
                    $Level -eq 'Error' -and $Message -match 'refresh failed'
                }
            }
        }
    }
}
