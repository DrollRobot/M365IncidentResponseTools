#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Get-IRTEntraSignInLog: user resolution, date chunking,
    filter construction, throttle/timeout retry, and output plumbing.

.DESCRIPTION
    All tests are offline. The Microsoft Graph SDK cmdlets (Get-MgBetaAuditLogSignIn,
    Get-MgAuditLogSignIn) and internal IRT helpers (Update-IRTToken, Import-IRTModule,
    Write-IRT, Write-PSFMessage, Get-DefaultDomain, Get-GlobalUserObject,
    Resolve-DateRange, Show-IRTEntraSignInLog) are mocked so no network I/O occurs.
    Start-Sleep and Export-Clixml are mocked so retry/backoff paths and the XML
    export run instantly without real waits or file writes.

    The Graph SDK cmdlets only materialise after their modules are imported, and the
    function's Import-IRTModule call is mocked away here, so thin global stubs are
    created in BeforeAll. The stubs declare -Filter and -All so Mock can bind those
    parameters and test bodies can inspect the filter strings the function builds.
    All Mocks use -ModuleName M365IncidentResponseTools so the intercepts apply to
    calls made from within the module.

    New-SignInRecord is a test-only factory that creates minimal sign-in records,
    each with a unique Id and a CreatedDateTime used to verify the descending sort.

    Date ranges are mocked to a fixed 30-day UTC span so chunk boundaries are
    deterministic: -ChunkDays 1 yields 30 chunks, 7 yields 5, 10 yields 3, and the
    default 30 yields a single chunk.

-- regression coverage for fixes shipped 2026-06-24 ---------------------

    * Chunk math: chunk count and contiguous, gap-free coverage of the full range.
    * Per-chunk token refresh: Update-IRTToken runs once per chunk (plus once in begin).
    * Throttle backoff: Retry-After is honored and printed when present; exponential
      backoff from -ThrottleDelaySeconds is used when it is absent.
    * Timeout: a chunk that keeps timing out is skipped (not fatal) after retries.
    * Inter-chunk delay: -ChunkDelaySeconds pauses between chunks but not after the last.
#>

# Graph SDK cmdlets only exist after their modules import; Import-IRTModule is mocked
# here so they never load. Declare thin global stubs with the parameters the function
# passes so Mock can discover them and bind -Filter for inspection.
BeforeAll {
    $script:Mod = 'M365IncidentResponseTools'

    # params exist only so Mock can bind -Filter for inspection; reference them
    # to satisfy PSReviewUnusedParameter
    function global:Get-MgBetaAuditLogSignIn {
        param([string] $Filter, $All)
        $null = $Filter, $All
    }
    function global:Get-MgAuditLogSignIn {
        param([string] $Filter, $All)
        $null = $Filter, $All
    }

    function global:New-SignInRecord {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test-only factory; ShouldProcess is not applicable.')]
        param(
            [datetime] $CreatedDateTime = ([datetime]'2024-01-15T00:00:00Z'),
            [string]   $Id
        )
        if (-not $Id) { $Id = [string][guid]::NewGuid() }
        [pscustomobject]@{
            Id              = $Id
            CreatedDateTime = $CreatedDateTime
            IpAddress       = '1.1.1.1'
        }
    }

    # fixed, deterministic 30-day UTC window for chunk-boundary math
    $script:RangeEnd = [datetime]::SpecifyKind([datetime]'2024-02-01T00:00:00', 'Utc')
    $script:RangeStart = $script:RangeEnd.AddDays(-30)
    $script:EndString = $script:RangeEnd.ToString('yyyy-MM-ddTHH:mm:ssZ')
    $script:StartString = $script:RangeStart.ToString('yyyy-MM-ddTHH:mm:ssZ')

    $script:TestUser = [pscustomobject]@{
        Id                = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        UserPrincipalName = 'alice@contoso.com'
    }
}

AfterAll {
    @('Get-MgBetaAuditLogSignIn', 'Get-MgAuditLogSignIn', 'New-SignInRecord') |
        ForEach-Object { Remove-Item -Path "Function:\$_" -ErrorAction SilentlyContinue }
}

Describe 'Get-IRTEntraSignInLog' -Tag 'unit' {

    BeforeEach {
        $Mod = 'M365IncidentResponseTools'

        Mock Update-IRTToken { } -ModuleName $Mod
        Mock Import-IRTModule { } -ModuleName $Mod
        Mock Write-IRT { } -ModuleName $Mod
        Mock Write-PSFMessage { } -ModuleName $Mod
        Mock Start-Sleep { } -ModuleName $Mod
        Mock Export-Clixml { } -ModuleName $Mod
        Mock Get-DefaultDomain { 'contoso.com' } -ModuleName $Mod
        Mock Get-GlobalUserObject { $script:TestUser } -ModuleName $Mod

        # captured side effects
        $script:CapturedFilters = [System.Collections.Generic.List[string]]::new()
        $script:CapturedLogs = $null
        Mock Show-IRTEntraSignInLog { param($Logs) $script:CapturedLogs = $Logs } -ModuleName $Mod

        # deterministic 30-day absolute range
        Mock Resolve-DateRange {
            [pscustomobject]@{
                RangeType = 'Absolute'
                Days      = 30
                StartUtc  = $script:RangeStart
                EndUtc    = $script:RangeEnd
            }
        } -ModuleName $Mod

        # default: every chunk returns one record and records its filter
        Mock Get-MgBetaAuditLogSignIn {
            $script:CapturedFilters.Add($Filter)
            New-SignInRecord
        } -ModuleName $Mod
        Mock Get-MgAuditLogSignIn {
            $script:CapturedFilters.Add($Filter)
            New-SignInRecord
        } -ModuleName $Mod
    }

    # -------------------------------------------------------------------
    Context 'user resolution' {

        It 'uses an explicitly passed -UserObject' {
            Get-IRTEntraSignInLog -UserObject $script:TestUser -Excel $false -Xml $false
            Should -Invoke Get-GlobalUserObject -Times 0 -ModuleName $script:Mod
            $F = { $Filter -match "UserId eq '$($script:TestUser.Id)'" }
            $IA = @{ ModuleName = $script:Mod; ParameterFilter = $F }
            Should -Invoke Get-MgBetaAuditLogSignIn @IA
        }

        It 'falls back to Get-GlobalUserObject when -UserObject is omitted' {
            Get-IRTEntraSignInLog -Excel $false -Xml $false
            Should -Invoke Get-GlobalUserObject -Times 1 -ModuleName $script:Mod
        }

        It 'writes an error and runs no query when no users are found' {
            Mock Get-GlobalUserObject { } -ModuleName $script:Mod
            Get-IRTEntraSignInLog -Excel $false -Xml $false
            $F = { $Level -eq 'Error' -and $Message -match 'No user objects' }
            $IA = @{ ModuleName = $script:Mod; ParameterFilter = $F }
            Should -Invoke Write-IRT @IA
            Should -Invoke Get-MgBetaAuditLogSignIn -Times 0 -ModuleName $script:Mod
        }

        It 'queries once per IP address in the IpAddress parameter set' {
            Get-IRTEntraSignInLog -IpAddress '1.2.3.4', '5.6.7.8' -Excel $false -Xml $false
            $IA = @{ ModuleName = $script:Mod }
            Should -Invoke Get-MgBetaAuditLogSignIn -Times 2 -Exactly @IA
            $Hit1 = $script:CapturedFilters | Where-Object { $_ -match "ipAddress eq '1.2.3.4'" }
            $Hit2 = $script:CapturedFilters | Where-Object { $_ -match "ipAddress eq '5.6.7.8'" }
            $Hit1 | Should -Not -BeNullOrEmpty
            $Hit2 | Should -Not -BeNullOrEmpty
        }

        It 'queries once per user for multiple -UserObject values' {
            $User2 = [pscustomobject]@{
                Id                = 'ffffffff-0000-1111-2222-333333333333'
                UserPrincipalName = 'bob@contoso.com'
            }
            $Users = @($script:TestUser, $User2)
            Get-IRTEntraSignInLog -UserObject $Users -Excel $false -Xml $false
            $IA = @{ ModuleName = $script:Mod }
            Should -Invoke Get-MgBetaAuditLogSignIn -Times 2 -Exactly @IA
        }

        It 'adds no user filter in the AllUsers parameter set' {
            Get-IRTEntraSignInLog -AllUsers -Excel $false -Xml $false
            $script:CapturedFilters.Count | Should -Be 1
            $script:CapturedFilters[0] | Should -Not -Match 'UserId eq'
            $script:CapturedFilters[0] | Should -Not -Match 'ipAddress eq'
        }
    }

    # -------------------------------------------------------------------
    Context 'date range and DefaultDays' {

        It 'requests a 30-day default for interactive logs' {
            Get-IRTEntraSignInLog -AllUsers -Excel $false -Xml $false
            $IA = @{ ModuleName = $script:Mod; ParameterFilter = { $DefaultDays -eq 30 } }
            Should -Invoke Resolve-DateRange @IA
        }

        It 'requests a 3-day default for non-interactive logs' {
            Get-IRTEntraSignInLog -AllUsers -NonInteractive -Excel $false -Xml $false
            $IA = @{ ModuleName = $script:Mod; ParameterFilter = { $DefaultDays -eq 3 } }
            Should -Invoke Resolve-DateRange @IA
        }
    }

    # -------------------------------------------------------------------
    Context 'date chunking' {

        It 'runs a single query when ChunkDays covers the whole range' {
            Get-IRTEntraSignInLog -AllUsers -ChunkDays 30 -Excel $false -Xml $false
            $IA = @{ ModuleName = $script:Mod }
            Should -Invoke Get-MgBetaAuditLogSignIn -Times 1 -Exactly @IA
        }

        It 'collapses a sub-second residue past an exact ChunkDays multiple into one chunk' {
            # Production reads the clock twice, so the real span runs a few ms past an
            # exact ChunkDays multiple. Before the boundary fix that residue produced an
            # extra zero-width trailing chunk; with ChunkDays 30 it must stay one chunk.
            Mock Resolve-DateRange {
                [pscustomobject]@{
                    RangeType = 'Absolute'
                    Days      = 30
                    StartUtc  = $script:RangeStart
                    EndUtc    = $script:RangeEnd.AddMilliseconds(50)
                }
            } -ModuleName $script:Mod
            Get-IRTEntraSignInLog -AllUsers -ChunkDays 30 -Excel $false -Xml $false
            $IA = @{ ModuleName = $script:Mod }
            Should -Invoke Get-MgBetaAuditLogSignIn -Times 1 -Exactly @IA
        }

        It 'keeps a residue-laden range at the correct chunk count (no degenerate tail)' {
            # Same sub-second residue, but ChunkDays 10 over ~30 days must yield exactly
            # 3 chunks, not 4 -- the residue must not spill into an extra trailing chunk.
            Mock Resolve-DateRange {
                [pscustomobject]@{
                    RangeType = 'Absolute'
                    Days      = 30
                    StartUtc  = $script:RangeStart
                    EndUtc    = $script:RangeEnd.AddMilliseconds(50)
                }
            } -ModuleName $script:Mod
            Get-IRTEntraSignInLog -AllUsers -ChunkDays 10 -Excel $false -Xml $false
            $IA = @{ ModuleName = $script:Mod }
            Should -Invoke Get-MgBetaAuditLogSignIn -Times 3 -Exactly @IA
        }

        It 'splits a 30-day range into 30 chunks with -ChunkDays 1' {
            Get-IRTEntraSignInLog -AllUsers -ChunkDays 1 -Excel $false -Xml $false
            $IA = @{ ModuleName = $script:Mod }
            Should -Invoke Get-MgBetaAuditLogSignIn -Times 30 -Exactly @IA
        }

        It 'splits a 30-day range into 5 chunks with -ChunkDays 7' {
            Get-IRTEntraSignInLog -AllUsers -ChunkDays 7 -Excel $false -Xml $false
            $IA = @{ ModuleName = $script:Mod }
            Should -Invoke Get-MgBetaAuditLogSignIn -Times 5 -Exactly @IA
        }

        It 'produces contiguous, gap-free chunks covering the full range' {
            Get-IRTEntraSignInLog -AllUsers -ChunkDays 7 -Excel $false -Xml $false

            # parse the ge/le bounds out of each chunk filter
            $Pattern = 'createdDateTime ge (\S+) and createdDateTime le (\S+)'
            $Bounds = foreach ($f in $script:CapturedFilters) {
                if ($f -match $Pattern) {
                    [pscustomobject]@{ Ge = $Matches[1]; Le = $Matches[2] }
                }
            }
            # newest first: highest Le first
            $Sorted = $Bounds | Sort-Object Le -Descending

            # newest chunk ends at the range end; oldest chunk starts at the range start
            $Sorted[0].Le | Should -Be $script:EndString
            $Sorted[-1].Ge | Should -Be $script:StartString

            # each chunk's start equals the next (older) chunk's end -- no gaps/overlaps
            for ($i = 0; $i -lt $Sorted.Count - 1; $i++) {
                $Sorted[$i].Ge | Should -Be $Sorted[$i + 1].Le
            }
        }

        It 'every chunk filter carries explicit createdDateTime bounds' {
            Get-IRTEntraSignInLog -AllUsers -ChunkDays 7 -Excel $false -Xml $false
            foreach ($f in $script:CapturedFilters) {
                $f | Should -Match 'createdDateTime ge '
                $f | Should -Match 'createdDateTime le '
            }
        }
    }

    # -------------------------------------------------------------------
    Context 'filter construction' {

        It 'filters by UserId in the UserObject parameter set' {
            $P = @{ UserObject = $script:TestUser; ChunkDays = 30; Excel = $false; Xml = $false }
            Get-IRTEntraSignInLog @P
            $script:CapturedFilters[0] | Should -Match "UserId eq '$($script:TestUser.Id)'"
        }

        It 'adds the non-interactive event-type clause with -NonInteractive' {
            $P = @{ AllUsers = $true; NonInteractive = $true; ChunkDays = 30 }
            Get-IRTEntraSignInLog @P -Excel $false -Xml $false
            $script:CapturedFilters[0] | Should -Match 'signInEventTypes/any'
        }

        It 'omits the non-interactive clause for interactive logs' {
            Get-IRTEntraSignInLog -AllUsers -ChunkDays 30 -Excel $false -Xml $false
            $script:CapturedFilters[0] | Should -Not -Match 'signInEventTypes'
        }
    }

    # -------------------------------------------------------------------
    Context 'endpoint selection' {

        It 'uses the beta endpoint by default' {
            Get-IRTEntraSignInLog -AllUsers -ChunkDays 30 -Excel $false -Xml $false
            $IA = @{ ModuleName = $script:Mod }
            Should -Invoke Get-MgBetaAuditLogSignIn -Times 1 -Exactly @IA
            Should -Invoke Get-MgAuditLogSignIn -Times 0 -ModuleName $script:Mod
        }

        It 'uses the v1.0 endpoint when -Beta $false' {
            Get-IRTEntraSignInLog -AllUsers -Beta $false -ChunkDays 30 -Excel $false -Xml $false
            $IA = @{ ModuleName = $script:Mod }
            Should -Invoke Get-MgAuditLogSignIn -Times 1 -Exactly @IA
            Should -Invoke Get-MgBetaAuditLogSignIn -Times 0 -ModuleName $script:Mod
        }
    }

    # -------------------------------------------------------------------
    Context 'per-chunk token refresh' {

        It 'refreshes the token once in begin plus once per chunk' {
            # 30-day range / ChunkDays 10 = 3 chunks; begin(1) + 3 = 4 refreshes
            Get-IRTEntraSignInLog -AllUsers -ChunkDays 10 -Excel $false -Xml $false
            $IA = @{ ModuleName = $script:Mod }
            Should -Invoke Update-IRTToken -Times 4 -Exactly @IA
        }
    }

    # -------------------------------------------------------------------
    Context 'throttle retry and backoff' {

        It 'honors and prints a Retry-After value parsed from the message' {
            $script:Calls = 0
            Mock Get-MgBetaAuditLogSignIn {
                $script:Calls++
                if ($script:Calls -eq 1) {
                    throw 'TooManyRequests: please try again in 5 seconds.'
                }
                New-SignInRecord
            } -ModuleName $script:Mod

            Get-IRTEntraSignInLog -AllUsers -ChunkDays 30 -Excel $false -Xml $false

            $IA = @{ ModuleName = $script:Mod; ParameterFilter = { $Seconds -eq 5 } }
            Should -Invoke Start-Sleep -Times 1 -Exactly @IA
            $F = { $Level -eq 'Warn' -and $Message -match 'Retry-After of 5s' }
            $IB = @{ ModuleName = $script:Mod; ParameterFilter = $F }
            Should -Invoke Write-IRT @IB
        }

        It 'uses exponential backoff from the base when no Retry-After is given' {
            $script:Calls = 0
            Mock Get-MgBetaAuditLogSignIn {
                $script:Calls++
                if ($script:Calls -le 2) { throw '429 TooManyRequests' }
                New-SignInRecord
            } -ModuleName $script:Mod

            $P = @{ AllUsers = $true; ChunkDays = 30; ThrottleDelaySeconds = 60 }
            Get-IRTEntraSignInLog @P -Excel $false -Xml $false

            # retry 1 -> 60s, retry 2 -> 120s
            $I60 = @{ ModuleName = $script:Mod; ParameterFilter = { $Seconds -eq 60 } }
            $I120 = @{ ModuleName = $script:Mod; ParameterFilter = { $Seconds -eq 120 } }
            Should -Invoke Start-Sleep -Times 1 -Exactly @I60
            Should -Invoke Start-Sleep -Times 1 -Exactly @I120
        }

        It 'rethrows once throttle retries are exhausted' {
            Mock Get-MgBetaAuditLogSignIn { throw '429 TooManyRequests' } -ModuleName $script:Mod
            $P = @{ AllUsers = $true; ChunkDays = 30; Excel = $false; Xml = $false }
            { Get-IRTEntraSignInLog @P } | Should -Throw
        }
    }

    # -------------------------------------------------------------------
    Context 'timeout retry and skip' {

        It 'retries a timed-out chunk then succeeds' {
            $script:Calls = 0
            Mock Get-MgBetaAuditLogSignIn {
                $script:Calls++
                if ($script:Calls -eq 1) {
                    throw 'The request was canceled due to the configured HttpClient.Timeout'
                }
                New-SignInRecord
            } -ModuleName $script:Mod

            Get-IRTEntraSignInLog -AllUsers -ChunkDays 30 -Excel $false -Xml $false

            $IA = @{ ModuleName = $script:Mod; ParameterFilter = { $Seconds -eq 5 } }
            Should -Invoke Start-Sleep -Times 1 -Exactly @IA
            $F = { $Level -eq 'Warn' -and $Message -match 'timed out' }
            $IB = @{ ModuleName = $script:Mod; ParameterFilter = $F }
            Should -Invoke Write-IRT @IB
        }

        It 'skips a persistently timing-out chunk without throwing' {
            Mock Get-MgBetaAuditLogSignIn {
                throw 'The request was canceled due to the configured HttpClient.Timeout'
            } -ModuleName $script:Mod

            $P = @{ AllUsers = $true; ChunkDays = 30; Excel = $false; Xml = $false }
            { Get-IRTEntraSignInLog @P } | Should -Not -Throw
            $F = { $Level -eq 'Error' -and $Message -match 'Skipping' }
            $IA = @{ ModuleName = $script:Mod; ParameterFilter = $F }
            Should -Invoke Write-IRT @IA
            Should -Invoke Show-IRTEntraSignInLog -Times 0 -ModuleName $script:Mod
        }
    }

    # -------------------------------------------------------------------
    Context 'unexpected errors' {

        It 'rethrows errors that are neither throttle nor timeout' {
            Mock Get-MgBetaAuditLogSignIn {
                throw 'Some unexpected failure'
            } -ModuleName $script:Mod
            $P = @{ AllUsers = $true; ChunkDays = 30; Excel = $false; Xml = $false }
            { Get-IRTEntraSignInLog @P } | Should -Throw
        }
    }

    # -------------------------------------------------------------------
    Context 'inter-chunk delay' {

        It 'pauses between chunks but not after the last one' {
            # 3 chunks -> 2 inter-chunk pauses
            $P = @{ AllUsers = $true; ChunkDays = 10; ChunkDelaySeconds = 2 }
            Get-IRTEntraSignInLog @P -Excel $false -Xml $false
            $IA = @{ ModuleName = $script:Mod; ParameterFilter = { $Seconds -eq 2 } }
            Should -Invoke Start-Sleep -Times 2 -Exactly @IA
        }

        It 'does not pause between chunks when -ChunkDelaySeconds is 0' {
            $P = @{ AllUsers = $true; ChunkDays = 10; ChunkDelaySeconds = 0 }
            Get-IRTEntraSignInLog @P -Excel $false -Xml $false
            Should -Invoke Start-Sleep -Times 0 -ModuleName $script:Mod
        }
    }

    # -------------------------------------------------------------------
    Context 'output' {

        It 'writes a no-logs error and skips export when nothing is returned' {
            Mock Get-MgBetaAuditLogSignIn { @() } -ModuleName $script:Mod
            Get-IRTEntraSignInLog -AllUsers -ChunkDays 30 -Excel $true -Xml $false
            $F = { $Level -eq 'Error' -and $Message -match 'No logs found' }
            $IA = @{ ModuleName = $script:Mod; ParameterFilter = $F }
            Should -Invoke Write-IRT @IA
            Should -Invoke Show-IRTEntraSignInLog -Times 0 -ModuleName $script:Mod
        }

        It 'calls Show-IRTEntraSignInLog once when logs are found and -Excel is on' {
            Get-IRTEntraSignInLog -AllUsers -ChunkDays 30 -Excel $true -Xml $false
            $IA = @{ ModuleName = $script:Mod }
            Should -Invoke Show-IRTEntraSignInLog -Times 1 -Exactly @IA
        }

        It 'does not call Show-IRTEntraSignInLog when -Excel is off' {
            Get-IRTEntraSignInLog -AllUsers -ChunkDays 30 -Excel $false -Xml $false
            Should -Invoke Show-IRTEntraSignInLog -Times 0 -ModuleName $script:Mod
        }

        It 'exports XML when -Xml is on' {
            Get-IRTEntraSignInLog -AllUsers -ChunkDays 30 -Excel $false -Xml $true
            Should -Invoke Export-Clixml -ModuleName $script:Mod
        }

        It 'inserts a metadata object at the head of the results' {
            Get-IRTEntraSignInLog -AllUsers -ChunkDays 30 -Excel $true -Xml $false
            $script:CapturedLogs[0].Metadata | Should -BeTrue
            $script:CapturedLogs[0].FileName | Should -Match 'SignInLogs_'
        }

        It 'uses non-interactive naming and title metadata with -NonInteractive' {
            $P = @{ AllUsers = $true; NonInteractive = $true; ChunkDays = 30 }
            Get-IRTEntraSignInLog @P -Excel $true -Xml $false
            $script:CapturedLogs[0].FileName | Should -Match 'NonInteractiveLogs_'
            $script:CapturedLogs[0].Title | Should -Match 'Non-Interactive'
        }

        It 'sorts merged results newest first' {
            # one chunk returning records out of chronological order
            Mock Get-MgBetaAuditLogSignIn {
                $script:CapturedFilters.Add($Filter)
                New-SignInRecord -CreatedDateTime ([datetime]'2024-01-10T00:00:00Z')
                New-SignInRecord -CreatedDateTime ([datetime]'2024-01-20T00:00:00Z')
                New-SignInRecord -CreatedDateTime ([datetime]'2024-01-05T00:00:00Z')
            } -ModuleName $script:Mod

            Get-IRTEntraSignInLog -AllUsers -ChunkDays 30 -Excel $true -Xml $false

            # index 0 is metadata; the rest are sorted descending by CreatedDateTime
            $Records = $script:CapturedLogs | Select-Object -Skip 1
            $Dates = $Records.CreatedDateTime
            $SortedDates = $Dates | Sort-Object -Descending
            $Dates | Should -Be $SortedDates
        }
    }
}
