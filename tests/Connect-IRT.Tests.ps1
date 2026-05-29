#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# ---------------------------------------------------------------------------
# Private helpers (Get-IRTTokenExpiry, Test-TokenExpired)
# These are not exported; InModuleScope is required to access them.
# ---------------------------------------------------------------------------
InModuleScope M365IncidentResponseTools {

    BeforeAll {
        # Builds a minimal base64url-encoded JWT for unit testing only.
        # The signature segment is empty; MSAL never receives this token.
        function New-TestJwt {
            param(
                [long]   $Exp,
                [switch] $OmitExp
            )
            $ToBase64Url = {
                param([string] $Text)
                [System.Convert]::ToBase64String(
                    [System.Text.Encoding]::UTF8.GetBytes($Text)
                ).TrimEnd('=').Replace('+', '-').Replace('/', '_')
            }
            $Header  = & $ToBase64Url '{"alg":"none","typ":"JWT"}'
            $Payload = if ($OmitExp) {
                & $ToBase64Url '{"sub":"test"}'
            } else {
                & $ToBase64Url "{`"sub`":`"test`",`"exp`":$Exp}"
            }
            return "$Header.$Payload."
        }
    }

    Describe 'Get-IRTTokenExpiry' {

        Context 'valid JWT with exp claim' {
            It 'returns a UTC DateTime matching the exp value' {
                $UnixExp  = 2000000000L
                $Token    = New-TestJwt -Exp $UnixExp
                $Expected = [System.DateTimeOffset]::FromUnixTimeSeconds($UnixExp).UtcDateTime
                Get-IRTTokenExpiry -Token $Token | Should -Be $Expected
            }
            It 'returns a DateTime with UTC kind' {
                $Token  = New-TestJwt -Exp 2000000000L
                $Result = Get-IRTTokenExpiry -Token $Token
                $Result.Kind | Should -Be ([System.DateTimeKind]::Utc)
            }
        }

        Context 'tokens without a usable exp claim' {
            It 'returns $null when exp is absent from the payload' {
                Get-IRTTokenExpiry -Token (New-TestJwt -OmitExp) | Should -BeNullOrEmpty
            }
            It 'returns $null for a string with no dot separators' {
                Get-IRTTokenExpiry -Token 'notajwt' | Should -BeNullOrEmpty
            }
            It 'returns $null when the payload segment is not valid base64url' {
                Get-IRTTokenExpiry -Token 'header.!!!BAD!!!.sig' | Should -BeNullOrEmpty
            }
            It 'returns $null when the payload decodes to non-JSON' {
                $BadPayload = [System.Convert]::ToBase64String(
                    [System.Text.Encoding]::UTF8.GetBytes('not json at all')
                ).TrimEnd('=').Replace('+', '-').Replace('/', '_')
                Get-IRTTokenExpiry -Token "header.$BadPayload.sig" | Should -BeNullOrEmpty
            }
        }
    }

    Describe 'Test-TokenExpired' {

        Context 'clearly expired or clearly fresh' {
            It 'returns $true for a token that expired an hour ago' {
                $Exp   = [long][System.DateTimeOffset]::UtcNow.AddHours(-1).ToUnixTimeSeconds()
                $Token = New-TestJwt -Exp $Exp
                Test-TokenExpired -Token $Token | Should -BeTrue
            }
            It 'returns $false for a token that expires two hours from now' {
                $Exp   = [long][System.DateTimeOffset]::UtcNow.AddHours(2).ToUnixTimeSeconds()
                $Token = New-TestJwt -Exp $Exp
                Test-TokenExpired -Token $Token | Should -BeFalse
            }
            It 'returns $true for a malformed / unparseable token' {
                Test-TokenExpired -Token 'garbage' | Should -BeTrue
            }
        }

        Context 'default 300-second buffer window' {
            It 'returns $true when expiry is within 3 minutes (inside buffer)' {
                $Exp   = [long][System.DateTimeOffset]::UtcNow.AddMinutes(3).ToUnixTimeSeconds()
                $Token = New-TestJwt -Exp $Exp
                Test-TokenExpired -Token $Token | Should -BeTrue
            }
            It 'returns $false when expiry is 7 minutes away (outside buffer)' {
                $Exp   = [long][System.DateTimeOffset]::UtcNow.AddMinutes(7).ToUnixTimeSeconds()
                $Token = New-TestJwt -Exp $Exp
                Test-TokenExpired -Token $Token | Should -BeFalse
            }
        }

        Context 'custom BufferSeconds' {
            It 'treats a 30-minute token as expired when buffer is 1 hour' {
                $Exp   = [long][System.DateTimeOffset]::UtcNow.AddMinutes(30).ToUnixTimeSeconds()
                $Token = New-TestJwt -Exp $Exp
                Test-TokenExpired -Token $Token -BufferSeconds 3600 | Should -BeTrue
            }
            It 'treats a 30-second token as fresh when buffer is 0' {
                $Exp   = [long][System.DateTimeOffset]::UtcNow.AddSeconds(30).ToUnixTimeSeconds()
                $Token = New-TestJwt -Exp $Exp
                Test-TokenExpired -Token $Token -BufferSeconds 0 | Should -BeFalse
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Connect-IRT: exported function -- guard conditions and orchestration
# ---------------------------------------------------------------------------
Describe 'Connect-IRT' {

    Context '-Refresh: no active session' {
        BeforeEach {
            $script:SavedSession = (
                Get-Variable -Name IRT_Session -Scope Global -ErrorAction SilentlyContinue
            )?.Value
            $Global:IRT_Session  = $null
        }
        AfterEach {
            $Global:IRT_Session = $script:SavedSession
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Connect-IRT -Refresh -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors | Should -Not -BeNullOrEmpty
        }
        It 'error message mentions "no active IRT session"' {
            $Errors = @()
            Connect-IRT -Refresh -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors[0].Exception.Message | Should -Match 'no active IRT session'
        }
    }

    Context '-Refresh: session exists but no services recorded' {
        BeforeEach {
            $script:SavedSession = (
                Get-Variable -Name IRT_Session -Scope Global -ErrorAction SilentlyContinue
            )?.Value
            $Global:IRT_Session  = [pscustomobject]@{
                TenantId    = 'aaaaaaaa-0000-0000-0000-aaaaaaaaaaaa'
                Environment = 'Commercial'
                Graph       = $null
                Exchange    = $null
                IPPS        = $null
            }
        }
        AfterEach {
            $Global:IRT_Session = $script:SavedSession
        }

        It 'writes a non-terminating error' {
            $Errors = @()
            Connect-IRT -Refresh -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors | Should -Not -BeNullOrEmpty
        }
        It 'error message mentions "no service connections"' {
            $Errors = @()
            Connect-IRT -Refresh -ErrorVariable Errors -ErrorAction SilentlyContinue
            $Errors[0].Exception.Message | Should -Match 'no service connections'
        }
    }

    Context '-Refresh: Graph-only session (mocked downstream)' {
        BeforeEach {
            $script:SavedSession  = (
                Get-Variable -Name IRT_Session -Scope Global -ErrorAction SilentlyContinue
            )?.Value
            $script:RefreshedExpiry = [System.DateTime]::UtcNow.AddHours(1)
            $Global:IRT_Session   = [pscustomobject]@{
                TenantId    = 'bbbbbbbb-0000-0000-0000-bbbbbbbbbbbb'
                Environment = 'Commercial'
                Graph       = [pscustomobject]@{
                    Token                   = 'old-graph-token'
                    TokenExpiry             = [System.DateTime]::UtcNow.AddMinutes(5)
                    Account                 = $null
                    PublicClientApplication = $null
                }
                Exchange    = $null
                IPPS        = $null
            }
            Mock -ModuleName M365IncidentResponseTools Connect-IRTGraph {
                [pscustomobject]@{
                    Token                   = 'refreshed-graph-token'
                    TokenExpiry             = $script:RefreshedExpiry
                    Account                 = $null
                    PublicClientApplication = $null
                }
            }
            Mock -ModuleName M365IncidentResponseTools Connect-IRTExchange { }
            Mock -ModuleName M365IncidentResponseTools Connect-IRTIPPS { }
            Mock -ModuleName M365IncidentResponseTools Test-IRTConnection { }
        }
        AfterEach {
            $Global:IRT_Session = $script:SavedSession
        }

        It 'invokes Connect-IRTGraph exactly once' {
            Connect-IRT -Refresh
            Should -Invoke -ModuleName M365IncidentResponseTools Connect-IRTGraph -Times 1 -Exactly
        }
        It 'passes the session TenantId to Connect-IRTGraph' {
            Connect-IRT -Refresh
            $Assert = @{
                ModuleName      = 'M365IncidentResponseTools'
                Times           = 1
                ParameterFilter = { $TenantId -eq 'bbbbbbbb-0000-0000-0000-bbbbbbbbbbbb' }
            }
            Should -Invoke Connect-IRTGraph @Assert
        }
        It 'passes Cloud = Commercial to Connect-IRTGraph' {
            Connect-IRT -Refresh
            $Assert = @{
                ModuleName      = 'M365IncidentResponseTools'
                Times           = 1
                ParameterFilter = { $Cloud -eq 'Commercial' }
            }
            Should -Invoke Connect-IRTGraph @Assert
        }
        It 'does not invoke Connect-IRTExchange when Exchange is absent from session' {
            Connect-IRT -Refresh
            Should -Invoke -ModuleName M365IncidentResponseTools Connect-IRTExchange -Times 0
        }
        It 'does not invoke Connect-IRTIPPS when IPPS is absent from session' {
            Connect-IRT -Refresh
            Should -Invoke -ModuleName M365IncidentResponseTools Connect-IRTIPPS -Times 0
        }
        It 'stores the refreshed Graph result back into the session' {
            Connect-IRT -Refresh
            $Global:IRT_Session.Graph.Token | Should -Be 'refreshed-graph-token'
        }
        It 'stores the refreshed TokenExpiry in the session' {
            Connect-IRT -Refresh
            $Global:IRT_Session.Graph.TokenExpiry | Should -Be $script:RefreshedExpiry
        }
    }
}

# ---------------------------------------------------------------------------
# Online tests -- connect automatically via $env:IRT_TEST_TENANT_ID
# Run with: .\Invoke-AllTests.ps1 -Online
# ---------------------------------------------------------------------------
Describe 'Connect-IRT session state (live)' -Tag 'Online' {

    BeforeAll {
        $TenantId = $env:IRT_TEST_TENANT_ID
        if (-not $TenantId) {
            $EnvFile = Join-Path $PSScriptRoot '.env.ps1'
            if (Test-Path $EnvFile) { . $EnvFile }
            $TenantId = $env:IRT_TEST_TENANT_ID
        }
        if (-not $TenantId) {
            throw 'Set $env:IRT_TEST_TENANT_ID or create tests/.env.ps1 before running online tests.'
        }
        Connect-IRT -TenantId $TenantId
    }

    It 'session has a non-empty TenantId' {
        $Global:IRT_Session.TenantId | Should -Not -BeNullOrEmpty
    }

    It 'Graph TokenExpiry is a future UTC DateTime' {
        if (-not $Global:IRT_Session.Graph) {
            Set-ItResult -Skipped -Because 'Graph is not connected in this session'
        }
        $Global:IRT_Session.Graph.TokenExpiry | Should -BeOfType [System.DateTime]
        $Global:IRT_Session.Graph.TokenExpiry | Should -BeGreaterThan ([System.DateTime]::UtcNow)
    }

    It 'Exchange TokenExpiry is a future UTC DateTime' {
        if (-not $Global:IRT_Session.Exchange) {
            Set-ItResult -Skipped -Because 'Exchange is not connected in this session'
        }
        $Global:IRT_Session.Exchange.TokenExpiry | Should -BeOfType [System.DateTime]
        $Global:IRT_Session.Exchange.TokenExpiry | Should -BeGreaterThan ([System.DateTime]::UtcNow)
    }

    It 'Connect-IRT -Refresh preserves the session TenantId' {
        $OriginalTenantId = $Global:IRT_Session.TenantId
        Connect-IRT -Refresh
        $Global:IRT_Session.TenantId | Should -Be $OriginalTenantId
    }

    It 'Test-IRTConnection -Quiet returns $true when both services are connected' {
        if (-not ($Global:IRT_Session.Graph -and $Global:IRT_Session.Exchange)) {
            Set-ItResult -Skipped -Because 'requires both Graph and Exchange connections'
        }
        Test-IRTConnection -Quiet | Should -BeTrue
    }
}
