#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Get-IRTAccessToken guard rails, client-ID resolution,
    candidate-loop behavior, and sticky-account recording.

.DESCRIPTION
    All tests are offline. Get-IRTPublicClient and Select-IRTMsalAccount are
    mocked; the MSAL PublicClientApplication is replaced by a stub object whose
    GetAccountsAsync / AcquireTokenSilent script-methods return completed .NET
    Tasks, so the production GetAwaiter().GetResult() call chain executes for
    real without any network I/O. Live token acquisition is covered by the
    Online-tagged tests in Connect-IRT.Tests.ps1.

-- guard rails ------------------------------------------------------------

    Without an active session there is no tenant, cloud config, or app store;
    the function must throw with guidance rather than failing deeper in MSAL.

-- client-ID resolution ----------------------------------------------------

    Parameter > session override > service default. Exchange and IPPS resolve
    to the SAME client ID - the invariant that makes them share one MSAL app
    and makes IPPS silent after any Exchange auth.

-- silent candidate loop ---------------------------------------------------

    Every candidate returned by Select-IRTMsalAccount is tried before any
    interactive fallback: a failure on the first candidate must not abort the
    loop. On success the winning account is recorded as sticky for the client
    ID. With -Silent and no working candidate, the function throws instead of
    prompting.

-- runspace worker mode ----------------------------------------------------

    $Global:IRT_IsRunspaceWorker forces -Silent so a worker can never open a
    hidden browser prompt.
#>

InModuleScope M365IncidentResponseTools {

    BeforeAll {
        $script:GraphClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'
        $script:ExoClientId = 'fb78d390-0c51-40cd-8e17-fdbfab77341b'
        # A tenant other than the session's target, for wrong-tenant token tests.
        $script:WrongTenant = 'bbbbbbbb-0000-0000-0000-bbbbbbbbbbbb'

        # New-TestSession builds a minimal $Global:IRT_Session for the token
        # authority: tenant, cloud endpoints, app store, sticky store.
        function New-TestSession {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test-only factory helper; ShouldProcess is not applicable.')]
            param(
                [string] $ClientId = $null
            )
            [pscustomobject]@{
                TenantId      = 'aaaaaaaa-0000-0000-0000-aaaaaaaaaaaa'
                ClientId      = $ClientId
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

        # New-StubApp fabricates the minimal PublicClientApplication surface the
        # function touches. GetAccountsAsync returns a completed Task (so the
        # real GetAwaiter().GetResult() chain works); AcquireTokenSilent records
        # the account it was called with and returns a builder whose
        # ExecuteAsync yields per-account results from $script:SilentOutcomes
        # (a hashtable of Username -> AuthenticationResult-shaped object, or
        # 'throw' to simulate MsalUiRequiredException).
        function New-StubApp {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test-only factory helper; ShouldProcess is not applicable.')]
            param()
            $App = [pscustomobject]@{}
            $App | Add-Member -MemberType ScriptMethod -Name GetAccountsAsync -Value {
                $List = [System.Collections.Generic.List[object]]::new()
                [System.Threading.Tasks.Task]::FromResult($List)
            }
            $App | Add-Member -MemberType ScriptMethod -Name AcquireTokenSilent -Value {
                param($Scopes, $Account)
                $script:SilentCalls += @($Account.Username)
                $script:SilentScopes = @($Scopes)
                $Username = $Account.Username
                $Builder = [pscustomobject]@{}
                $Builder | Add-Member -MemberType ScriptMethod -Name WithForceRefresh -Value {
                    param($Force)
                    $script:ForceRefreshUsed = [bool]$Force
                    $this
                }
                $AddParams = @{
                    MemberType = 'ScriptMethod'
                    Name       = 'ExecuteAsync'
                    Value      = {
                        $Outcome = $script:SilentOutcomes[$this.Username]
                        if ($Outcome -eq 'throw') {
                            [System.Threading.Tasks.Task]::FromException[object](
                                [System.Exception]::new('MsalUiRequiredException (stub)'))
                        } else {
                            [System.Threading.Tasks.Task]::FromResult[object]($Outcome)
                        }
                    }
                }
                $Builder | Add-Member -NotePropertyName Username -NotePropertyValue $Username
                $Builder | Add-Member @AddParams
                $Builder
            }
            $App | Add-Member -MemberType ScriptMethod -Name AcquireTokenInteractive -Value {
                param($Scopes)
                $script:InteractiveScopes = @($Scopes)
                $Builder = [pscustomobject]@{}
                $Builder | Add-Member -MemberType ScriptMethod -Name ExecuteAsync -Value {
                    param($CancellationToken)
                    $null = $CancellationToken  # accepted to match the real signature
                    [System.Threading.Tasks.Task]::FromResult[object]($script:InteractiveOutcome)
                }
                $Builder
            }
            return $App
        }

        # New-StubResult fabricates an AuthenticationResult-shaped object.
        function New-StubResult {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test-only factory helper; ShouldProcess is not applicable.')]
            param(
                [string] $Username,
                # Tenant the token was issued for (AuthenticationResult.TenantId).
                # Defaults to the session test tenant so existing tests pass the
                # tenant check unchanged; override to simulate a wrong-tenant token.
                [string] $TenantId = 'aaaaaaaa-0000-0000-0000-aaaaaaaaaaaa'
            )
            [pscustomobject]@{
                AccessToken = "token-for-$Username"
                ExpiresOn   = [System.DateTimeOffset]::UtcNow.AddHours(1)
                TenantId    = $TenantId
                Account     = [pscustomobject]@{
                    Username      = $Username
                    HomeAccountId = [pscustomobject]@{
                        Identifier = "$Username.home"
                        TenantId   = $TenantId
                    }
                }
            }
        }

        # New-TestCandidate fabricates an IAccount-shaped candidate.
        function New-TestCandidate {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test-only factory helper; ShouldProcess is not applicable.')]
            param(
                [string] $Username
            )
            [pscustomobject]@{
                Username      = $Username
                Environment   = 'login.microsoftonline.com'
                HomeAccountId = [pscustomobject]@{
                    Identifier = "$Username.home"
                    TenantId   = 'aaaaaaaa-0000-0000-0000-aaaaaaaaaaaa'
                }
            }
        }
    }

    Describe 'Get-IRTAccessToken' {

        BeforeEach {
            $script:SavedSession = (
                Get-Variable -Name IRT_Session -Scope Global -ErrorAction SilentlyContinue
            )?.Value
            $script:SavedWorker = (
                Get-Variable -Name IRT_IsRunspaceWorker -Scope Global -ErrorAction SilentlyContinue
            )?.Value
            $Global:IRT_IsRunspaceWorker = $false
            $script:SilentCalls = @()
            $script:SilentOutcomes = @{}
            $script:SilentScopes = @()
            $script:InteractiveScopes = @()
            $script:InteractiveOutcome = $null
            $script:ForceRefreshUsed = $false
        }
        AfterEach {
            $Global:IRT_Session = $script:SavedSession
            $Global:IRT_IsRunspaceWorker = $script:SavedWorker
        }

        # -------------------------------------------------------------------
        Context 'guard rails' {

            It 'throws when there is no active session' {
                $Global:IRT_Session = $null
                { Get-IRTAccessToken -Service Graph } |
                    Should -Throw -ExpectedMessage '*Run Connect-IRT first*'
            }
        }

        # -------------------------------------------------------------------
        Context 'client-ID resolution' {

            BeforeEach {
                $Global:IRT_Session = New-TestSession
                Mock Get-IRTPublicClient { New-StubApp }
                Mock Select-IRTMsalAccount { @() }
            }

            It 'uses the Graph CLI Tools client ID for Graph' {
                { Get-IRTAccessToken -Service Graph -Silent } | Should -Throw
                Should -Invoke Get-IRTPublicClient -Times 1 -ParameterFilter {
                    $ClientId -eq $script:GraphClientId
                }
            }

            It 'uses the EXO client ID for Exchange' {
                { Get-IRTAccessToken -Service Exchange -Silent } | Should -Throw
                Should -Invoke Get-IRTPublicClient -Times 1 -ParameterFilter {
                    $ClientId -eq $script:ExoClientId
                }
            }

            It 'uses the SAME EXO client ID for IPPS (shared app invariant)' {
                { Get-IRTAccessToken -Service IPPS -Silent } | Should -Throw
                Should -Invoke Get-IRTPublicClient -Times 1 -ParameterFilter {
                    $ClientId -eq $script:ExoClientId
                }
            }

            It 'prefers the session ClientId override over the service default' {
                $Global:IRT_Session = New-TestSession -ClientId 'session-override-id'
                { Get-IRTAccessToken -Service Graph -Silent } | Should -Throw
                Should -Invoke Get-IRTPublicClient -Times 1 -ParameterFilter {
                    $ClientId -eq 'session-override-id'
                }
            }

            It 'prefers the -ClientId parameter over the session override' {
                $Global:IRT_Session = New-TestSession -ClientId 'session-override-id'
                { Get-IRTAccessToken -Service Graph -Silent -ClientId 'param-id' } |
                    Should -Throw
                Should -Invoke Get-IRTPublicClient -Times 1 -ParameterFilter {
                    $ClientId -eq 'param-id'
                }
            }
        }

        # -------------------------------------------------------------------
        Context 'silent candidate loop' {

            BeforeEach {
                $Global:IRT_Session = New-TestSession
                Mock Get-IRTPublicClient { New-StubApp }
            }

            It 'returns the first candidate''s token when silent acquisition succeeds' {
                Mock Select-IRTMsalAccount { @(New-TestCandidate -Username 'admin@a.com') }
                $script:SilentOutcomes['admin@a.com'] = New-StubResult -Username 'admin@a.com'

                $Result = Get-IRTAccessToken -Service Exchange -Silent
                $Result.AccessToken | Should -Be 'token-for-admin@a.com'
            }

            It 'falls through to the next candidate when the first fails' {
                Mock Select-IRTMsalAccount {
                    @(
                        (New-TestCandidate -Username 'wrong@b.com'),
                        (New-TestCandidate -Username 'right@a.com')
                    )
                }
                $script:SilentOutcomes['wrong@b.com'] = 'throw'
                $script:SilentOutcomes['right@a.com'] = New-StubResult -Username 'right@a.com'

                $Result = Get-IRTAccessToken -Service Exchange -Silent
                $Result.AccessToken | Should -Be 'token-for-right@a.com'
                $script:SilentCalls | Should -Be @('wrong@b.com', 'right@a.com')
            }

            It 'records the winning account as sticky for the client ID' {
                Mock Select-IRTMsalAccount { @(New-TestCandidate -Username 'admin@a.com') }
                $script:SilentOutcomes['admin@a.com'] = New-StubResult -Username 'admin@a.com'

                $null = Get-IRTAccessToken -Service Exchange -Silent
                $Global:IRT_Session.StickyAccount[$script:ExoClientId] |
                    Should -Be 'admin@a.com.home'
            }

            It 'throws (instead of prompting) when -Silent and every candidate fails' {
                Mock Select-IRTMsalAccount { @(New-TestCandidate -Username 'wrong@b.com') }
                $script:SilentOutcomes['wrong@b.com'] = 'throw'

                { Get-IRTAccessToken -Service Exchange -Silent } |
                    Should -Throw -ExpectedMessage '*interactive auth is not allowed*'
            }

            It 'throws (instead of prompting) when -Silent and there are no candidates' {
                Mock Select-IRTMsalAccount { @() }
                { Get-IRTAccessToken -Service Exchange -Silent } |
                    Should -Throw -ExpectedMessage '*interactive auth is not allowed*'
            }

            It 'rejects a wrong-tenant token and tries the next candidate' {
                Mock Select-IRTMsalAccount {
                    @(
                        (New-TestCandidate -Username 'wrong@b.com'),
                        (New-TestCandidate -Username 'right@a.com')
                    )
                }
                $Bad = New-StubResult -Username 'wrong@b.com' -TenantId $script:WrongTenant
                $script:SilentOutcomes['wrong@b.com'] = $Bad
                $script:SilentOutcomes['right@a.com'] = New-StubResult -Username 'right@a.com'

                $Result = Get-IRTAccessToken -Service Exchange -Silent
                $Result.AccessToken | Should -Be 'token-for-right@a.com'
                $script:SilentCalls | Should -Be @('wrong@b.com', 'right@a.com')
                $Global:IRT_Session.StickyAccount[$script:ExoClientId] |
                    Should -Be 'right@a.com.home'
            }

            It 'throws and records no sticky when every candidate is wrong-tenant' {
                Mock Select-IRTMsalAccount { @(New-TestCandidate -Username 'wrong@b.com') }
                $Bad = New-StubResult -Username 'wrong@b.com' -TenantId $script:WrongTenant
                $script:SilentOutcomes['wrong@b.com'] = $Bad

                { Get-IRTAccessToken -Service Exchange -Silent } |
                    Should -Throw -ExpectedMessage '*interactive auth is not allowed*'
                $Global:IRT_Session.StickyAccount.ContainsKey($script:ExoClientId) |
                    Should -BeFalse
            }

            It 'accepts a token whose TenantId is absent (unverifiable, not punished)' {
                Mock Select-IRTMsalAccount { @(New-TestCandidate -Username 'admin@a.com') }
                $Outcome = New-StubResult -Username 'admin@a.com'
                $Outcome.TenantId = $null
                $script:SilentOutcomes['admin@a.com'] = $Outcome

                $Result = Get-IRTAccessToken -Service Exchange -Silent
                $Result.AccessToken | Should -Be 'token-for-admin@a.com'
            }
        }

        # -------------------------------------------------------------------
        Context 'scope construction' {

            BeforeEach {
                $Global:IRT_Session = New-TestSession
                Mock Get-IRTPublicClient { New-StubApp }
                Mock Select-IRTMsalAccount { @(New-TestCandidate -Username 'admin@a.com') }
                $script:SilentOutcomes['admin@a.com'] = New-StubResult -Username 'admin@a.com'
            }

            It 'prefixes Graph scopes with the cloud Graph base URL' {
                $null = Get-IRTAccessToken -Service Graph -Silent
                $script:SilentScopes |
                    Should -Contain 'https://graph.microsoft.com/AuditLog.Read.All'
                $BadScopes = @($script:SilentScopes |
                        Where-Object { $_ -notlike 'https://graph.microsoft.com/*' })
                $BadScopes | Should -HaveCount 0
            }

            It 'includes -AdditionalScope in the Graph scope set, prefixed' {
                $TokenParams = @{
                    Service         = 'Graph'
                    Silent          = $true
                    AdditionalScope = 'Custom.Extra.Scope'
                }
                $null = Get-IRTAccessToken @TokenParams
                $script:SilentScopes |
                    Should -Contain 'https://graph.microsoft.com/Custom.Extra.Scope'
            }

            It 'uses the session Graph scope list when one is recorded' {
                $Global:IRT_Session.Graph = [pscustomobject]@{
                    Scopes = @('Only.This.Scope')
                }
                $null = Get-IRTAccessToken -Service Graph -Silent
                $script:SilentScopes | Should -Be @('https://graph.microsoft.com/Only.This.Scope')
            }

            It 'uses the cloud Exchange .default scope for Exchange' {
                $null = Get-IRTAccessToken -Service Exchange -Silent
                $script:SilentScopes | Should -Be @('https://outlook.office365.com/.default')
            }

            It 'uses the search-only audience for IPPS by default' {
                $null = Get-IRTAccessToken -Service IPPS -Silent
                $script:SilentScopes |
                    Should -Be @('https://dataservice.o365filtering.com/.default')
            }

            It 'uses the Exchange audience for IPPS when -SearchOnly is $false' {
                $null = Get-IRTAccessToken -Service IPPS -SearchOnly $false -Silent
                $script:SilentScopes | Should -Be @('https://outlook.office365.com/.default')
            }
        }

        # -------------------------------------------------------------------
        Context '-ForceRefresh' {

            BeforeEach {
                $Global:IRT_Session = New-TestSession
                Mock Get-IRTPublicClient { New-StubApp }
                Mock Select-IRTMsalAccount { @(New-TestCandidate -Username 'admin@a.com') }
                $script:SilentOutcomes['admin@a.com'] = New-StubResult -Username 'admin@a.com'
            }

            It 'applies WithForceRefresh to the silent request when set' {
                $null = Get-IRTAccessToken -Service Exchange -Silent -ForceRefresh
                $script:ForceRefreshUsed | Should -BeTrue
            }

            It 'does not force-refresh by default' {
                $null = Get-IRTAccessToken -Service Exchange -Silent
                $script:ForceRefreshUsed | Should -BeFalse
            }
        }

        # -------------------------------------------------------------------
        Context 'interactive fallback' {

            BeforeEach {
                $Global:IRT_Session = New-TestSession
                Mock Get-IRTPublicClient { New-StubApp }
                Mock Select-IRTMsalAccount { @() }
                Mock Write-IRT { }
                $script:InteractiveOutcome = New-StubResult -Username 'newuser@a.com'
            }

            It 'falls back to interactive auth and returns its result' {
                $Result = Get-IRTAccessToken -Service Exchange
                $Result.AccessToken | Should -Be 'token-for-newuser@a.com'
            }

            It 'warns the operator that a browser window opened' {
                $null = Get-IRTAccessToken -Service Exchange
                Should -Invoke Write-IRT -Times 1 -ParameterFilter {
                    $Level -eq 'Warn' -and $Message -match 'browser window'
                }
            }

            It 'requests the same scopes interactively as it would silently' {
                $null = Get-IRTAccessToken -Service Exchange
                $script:InteractiveScopes | Should -Be @('https://outlook.office365.com/.default')
            }

            It 'records the interactively signed-in account as sticky' {
                $null = Get-IRTAccessToken -Service Exchange
                $Global:IRT_Session.StickyAccount[$script:ExoClientId] |
                    Should -Be 'newuser@a.com.home'
            }

            It 'tries interactive only after every silent candidate failed' {
                Mock Select-IRTMsalAccount { @(New-TestCandidate -Username 'wrong@b.com') }
                $script:SilentOutcomes['wrong@b.com'] = 'throw'
                $Result = Get-IRTAccessToken -Service Exchange
                $script:SilentCalls | Should -Be @('wrong@b.com')
                $Result.AccessToken | Should -Be 'token-for-newuser@a.com'
            }

            It 'throws when the interactive token is for the wrong tenant' {
                $script:InteractiveOutcome =
                New-StubResult -Username 'newuser@b.com' -TenantId $script:WrongTenant
                { Get-IRTAccessToken -Service Exchange } |
                    Should -Throw -ExpectedMessage '*does not match the requested tenant*'
            }
        }

        # -------------------------------------------------------------------
        Context 'runspace worker mode' {

            BeforeEach {
                $Global:IRT_Session = New-TestSession
                $Global:IRT_IsRunspaceWorker = $true
                Mock Get-IRTPublicClient { New-StubApp }
                Mock Select-IRTMsalAccount { @() }
            }

            It 'forces silent mode: throws instead of prompting even without -Silent' {
                { Get-IRTAccessToken -Service Exchange } |
                    Should -Throw -ExpectedMessage '*interactive auth is not allowed*'
            }
        }
    }
}
