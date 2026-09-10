#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Get-IRTUnifiedAuditLog paging and ResultLimit behaviour.

.DESCRIPTION
    All tests are offline. External Exchange cmdlets (Search-UnifiedAuditLog,
    Get-AcceptedDomain) and internal IRT helpers (Update-IRTToken, Write-IRT,
    Resolve-DateRange, Show-IRTUnifiedAuditLog) are mocked so no network I/O
    occurs.

    Get-AcceptedDomain and Search-UnifiedAuditLog are EXO proxy cmdlets that
    only materialise after Connect-ExchangeOnline. Global stubs are created in
    BeforeAll so Mock can discover them via the regular (global) session state.
    All Mocks use -ModuleName M365IncidentResponseTools so the intercepts apply
    to calls made from within the module (rather than InModuleScope, which
    discovers commands only through the module's own session state and cannot
    find external commands that were never imported by the module itself).

    New-UALPage is a test-only factory that creates minimal UAL record objects.
    By default each record gets a random unique Identity so the deduplication
    pass inside the function does not collapse the set. -StartId makes the
    identities deterministic, which is what lets a test hand back the same
    records twice.

    Every record carries ResultIndex and ResultCount exactly as a live tenant
    returns them under SessionCommand ReturnLargeSet: page-relative, so a full
    page reads ResultIndex 1..5000 with ResultCount 5000 no matter how much of
    the result set is still outstanding. That is deliberate - it keeps the
    fixture honest about why those fields cannot be used to detect the end of a
    search.

-- paging stops at ResultLimit ------------------------------------------

    The paging while loop requires ($AllLogs.Count -lt $ResultLimit). When the
    first page returns exactly 5000 records and ResultLimit is 5000, the count
    equals $ResultLimit before the loop body runs, so Search-UnifiedAuditLog is
    called once per query and a Warn is written.

-- paging continues naturally -------------------------------------------

    When the first Search-UnifiedAuditLog call returns a full 5000-record page
    and the continuation call (SessionId present) returns fewer than 5000, the
    function pages twice and no ResultLimit warning is written.
    The two separate mocks use ParameterFilter on $SessionId to distinguish
    first calls (no SessionId) from continuation calls (SessionId present).

-- no logs across all queries -------------------------------------------

    When Search-UnifiedAuditLog returns empty for every query, $AllLogs stays
    at 0 and the function writes a warning then returns without calling
    Show-IRTUnifiedAuditLog.

-- UserObject query count -----------------------------------------------

    The UserObject parameter set runs 4 queries per user by default: a UserIds
    query plus three FreeText queries. This context verifies the loop iterates
    all four entries.

-- Excel export ---------------------------------------------------------

    When logs are found and -Excel $true is passed, Show-IRTUnifiedAuditLog
    is called exactly once.

-- PassThru -------------------------------------------------------------

    With -PassThru the function emits the record collection to the pipeline in
    addition to (or instead of) writing files. -NoEnumerate keeps it as a single
    collection, and the metadata row the XML export would have written is at
    index 0.

-- RecordType expansion -------------------------------------------------

    Search-UnifiedAuditLog accepts a single -RecordType per call, so the
    function multiplies its query table by the number of record types given.
    AllUsers with two record types makes two calls; UserObject (4 base
    queries) with one record type makes four calls, each carrying RecordType.
    Without -RecordType no call carries the parameter.

-- ResultIndex/ResultCount must not end paging ---------------------------

    Regression guard, and the reason New-UALPage stamps those fields
    page-relative. An earlier build stopped paging once the highest ResultIndex
    on a page reached ResultCount. Because a full page always reports
    ResultIndex 1..5000 against ResultCount 5000, that ended every search after
    page one: a live 7-day pull returned 4682 records where the correct answer
    was at least 6243. Full pages carrying those fields must keep paging.

-- paging stops on a full page of records already served ----------------

    A ReturnLargeSet search does not end with a short page: once the set is
    exhausted the service keeps returning full 5000-record pages of records it
    has already served. A loop watching only the page size therefore pages until
    ResultLimit or a session timeout - on a real 34k-record pull that was 46
    wasted pages ending in a 401. A full page that contributes no record the
    query has not already served is the end-of-set signal.

-- ResultLimit counts deduplicated records -------------------------------

    Regression guard. Records are deduplicated as pages arrive, so
    -ResultLimit measures real records. Counting raw records instead would let
    overlapping pages spend the limit on repeats and cut the pull short,
    silently dropping audit records an analyst needs.

-- HighCompleteness ------------------------------------------------------

    The switch is only forwarded to Search-UnifiedAuditLog when the caller asks
    for it. Sending -HighCompleteness:$false would still bind the parameter,
    which fails outright on ExchangeOnlineManagement builds that predate it, so
    the default path must not carry the parameter at all.
#>

# EXO proxy cmdlets only exist after Connect-ExchangeOnline. Create thin global
# stubs so Mock can discover them via Get-Command in the test session.
# New-UALPage is also global so it is accessible inside Mock body scriptblocks.
BeforeAll {
    function global:Get-AcceptedDomain { }
    # Parameter names mirror the real cmdlet so Mock -ParameterFilter can bind
    # them by name (e.g. $RecordType, $SessionId).
    function global:Search-UnifiedAuditLog {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSReviewUnusedParameter', '',
            Justification = 'Stub exists only so Mock can bind parameters by name.')]
        param(
            $ResultSize,
            $SessionCommand,
            $Formatted,
            $StartDate,
            $EndDate,
            $UserIds,
            $FreeText,
            $Operations,
            $RecordType,
            $SessionId,
            [switch] $HighCompleteness
        )
    }

    function global:New-UALPage {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test-only factory; ShouldProcess is not applicable.')]
        param(
            [int]    $Count,
            [string] $SessionId = 'test-session-1',
            # -1 keeps identities random and therefore unique per call
            [int]    $StartId = -1
        )
        $Base = [datetime]'2024-01-01'
        0..($Count - 1) | ForEach-Object {
            $Id = [string][guid]::NewGuid()
            if ($StartId -ge 0) { $Id = "rec-$($StartId + $_)" }
            [pscustomobject]@{
                Identity     = $Id
                SessionId    = $SessionId
                CreationDate = $Base.AddSeconds($_)
                # page-relative, as a live tenant returns them
                ResultIndex  = $_ + 1
                ResultCount  = $Count
            }
        }
    }
}

AfterAll {
    @('Get-AcceptedDomain', 'Search-UnifiedAuditLog', 'New-UALPage') | ForEach-Object {
        Remove-Item -Path "Function:\$_" -ErrorAction SilentlyContinue
    }
}

Describe 'Get-IRTUnifiedAuditLog' -Tag 'unit' {

    BeforeEach {
        $Mod = 'M365IncidentResponseTools'
        Mock Update-IRTToken { } -ModuleName $Mod
        Mock Write-IRT { } -ModuleName $Mod
        Mock Write-PSFMessage { } -ModuleName $Mod
        Mock Get-AcceptedDomain {
            [pscustomobject]@{ Default = $true; DomainName = 'contoso.com' }
        } -ModuleName $Mod
        Mock Resolve-DateRange {
            [pscustomobject]@{
                Days     = 30
                StartUtc = [datetime]::UtcNow.AddDays(-30)
                EndUtc   = [datetime]::UtcNow
            }
        } -ModuleName $Mod
        Mock Show-IRTUnifiedAuditLog { } -ModuleName $Mod
    }

    # -------------------------------------------------------------------
    Context 'paging stops at ResultLimit' {

        BeforeEach {
            Mock Search-UnifiedAuditLog {
                New-UALPage -Count 5000
            } -ModuleName M365IncidentResponseTools
        }

        It 'calls Search-UnifiedAuditLog exactly once when ResultLimit equals the page size' {
            $Params = @{
                AllUsers    = $true
                ResultLimit = 5000
                Excel       = $false
                Xml         = $false
            }
            Get-IRTUnifiedAuditLog @Params
            $InvokeArgs = @{ ModuleName = 'M365IncidentResponseTools' }
            Should -Invoke Search-UnifiedAuditLog -Times 1 -Exactly @InvokeArgs
        }

        It 'writes a Warn containing ResultLimit when paging is cut short' {
            $Params = @{
                AllUsers    = $true
                ResultLimit = 5000
                Excel       = $false
                Xml         = $false
            }
            Get-IRTUnifiedAuditLog @Params
            $Filter = { $Level -eq 'Warn' -and $Message -match 'ResultLimit' }
            Should -Invoke Write-IRT -ModuleName M365IncidentResponseTools -ParameterFilter $Filter
        }
    }

    # -------------------------------------------------------------------
    Context 'paging continues until the page is not full' {

        BeforeEach {
            # First call returns a full page to trigger paging; subsequent
            # calls return a partial page to signal end of results.
            # $script: scope persists across the BeforeEach/Mock boundary.
            $script:UALPageCallCount = 0
            Mock Search-UnifiedAuditLog {
                $script:UALPageCallCount++
                if ($script:UALPageCallCount -eq 1) { New-UALPage -Count 5000 }
                else { New-UALPage -Count 200 }
            } -ModuleName M365IncidentResponseTools
        }

        It 'calls Search-UnifiedAuditLog twice for a single query' {
            $Params = @{
                AllUsers    = $true
                ResultLimit = 50000
                Excel       = $false
                Xml         = $false
            }
            Get-IRTUnifiedAuditLog @Params
            $InvokeArgs = @{ ModuleName = 'M365IncidentResponseTools' }
            Should -Invoke Search-UnifiedAuditLog -Times 2 -Exactly @InvokeArgs
        }

        It 'does not write a ResultLimit warning when paging ends naturally' {
            $Params = @{
                AllUsers    = $true
                ResultLimit = 50000
                Excel       = $false
                Xml         = $false
            }
            Get-IRTUnifiedAuditLog @Params
            $Filter = { $Level -eq 'Warn' -and $Message -match 'ResultLimit' }
            $InvokeArgs = @{ ModuleName = 'M365IncidentResponseTools'; ParameterFilter = $Filter }
            Should -Invoke Write-IRT -Times 0 @InvokeArgs
        }
    }

    # -------------------------------------------------------------------
    Context 'no logs returned across all queries' {

        BeforeEach {
            Mock Search-UnifiedAuditLog { @() } -ModuleName M365IncidentResponseTools
        }

        It 'writes a zero-logs warning' {
            $Params = @{
                AllUsers = $true
                Excel    = $false
                Xml      = $false
            }
            Get-IRTUnifiedAuditLog @Params
            $Filter = { $Level -eq 'Warn' -and $Message -match '0 total logs' }
            Should -Invoke Write-IRT -ModuleName M365IncidentResponseTools -ParameterFilter $Filter
        }

        It 'does not call Show-IRTUnifiedAuditLog when there are no logs' {
            $Params = @{
                AllUsers = $true
                Excel    = $true
                Xml      = $false
            }
            Get-IRTUnifiedAuditLog @Params
            Should -Invoke Show-IRTUnifiedAuditLog -Times 0 -ModuleName M365IncidentResponseTools
        }
    }

    # -------------------------------------------------------------------
    Context 'UserObject parameter set runs 4 queries per user' {

        BeforeEach {
            Mock Search-UnifiedAuditLog { @() } -ModuleName M365IncidentResponseTools
        }

        It 'makes 4 Search-UnifiedAuditLog calls for a single UserObject' {
            $User = [pscustomobject]@{
                Id                = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
                UserPrincipalName = 'user@contoso.com'
            }
            $Params = @{
                UserObject = $User
                Excel      = $false
                Xml        = $false
            }
            Get-IRTUnifiedAuditLog @Params
            $InvokeArgs = @{ ModuleName = 'M365IncidentResponseTools' }
            Should -Invoke Search-UnifiedAuditLog -Times 4 -Exactly @InvokeArgs
        }
    }

    # -------------------------------------------------------------------
    Context 'Excel export is called when logs are found' {

        BeforeEach {
            Mock Search-UnifiedAuditLog {
                New-UALPage -Count 100
            } -ModuleName M365IncidentResponseTools
        }

        It 'calls Show-IRTUnifiedAuditLog exactly once when Excel is enabled' {
            $Params = @{
                AllUsers = $true
                Excel    = $true
                Xml      = $false
            }
            Get-IRTUnifiedAuditLog @Params
            $InvokeArgs = @{ ModuleName = 'M365IncidentResponseTools' }
            Should -Invoke Show-IRTUnifiedAuditLog -Times 1 -Exactly @InvokeArgs
        }
    }

    # -------------------------------------------------------------------
    Context '-RecordType runs every query once per record type' {

        BeforeEach {
            Mock Search-UnifiedAuditLog { @() } -ModuleName M365IncidentResponseTools
        }

        It 'makes 2 calls for AllUsers with 2 record types' {
            $Params = @{
                AllUsers   = $true
                RecordType = 'MicrosoftTeams', 'ExchangeItem'
                Excel      = $false
                Xml        = $false
            }
            Get-IRTUnifiedAuditLog @Params
            $InvokeArgs = @{ ModuleName = 'M365IncidentResponseTools' }
            Should -Invoke Search-UnifiedAuditLog -Times 2 -Exactly @InvokeArgs
        }

        It 'passes each requested record type to Search-UnifiedAuditLog' {
            $Params = @{
                AllUsers   = $true
                RecordType = 'MicrosoftTeams', 'ExchangeItem'
                Excel      = $false
                Xml        = $false
            }
            Get-IRTUnifiedAuditLog @Params
            $TeamsArgs = @{
                ModuleName      = 'M365IncidentResponseTools'
                ParameterFilter = { $RecordType -eq 'MicrosoftTeams' }
            }
            $ExchangeArgs = @{
                ModuleName      = 'M365IncidentResponseTools'
                ParameterFilter = { $RecordType -eq 'ExchangeItem' }
            }
            Should -Invoke Search-UnifiedAuditLog -Times 1 -Exactly @TeamsArgs
            Should -Invoke Search-UnifiedAuditLog -Times 1 -Exactly @ExchangeArgs
        }

        It 'makes 4 calls for a UserObject with 1 record type, all carrying it' {
            $User = [pscustomobject]@{
                Id                = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
                UserPrincipalName = 'user@contoso.com'
            }
            $Params = @{
                UserObject = $User
                RecordType = 'MicrosoftTeams'
                Excel      = $false
                Xml        = $false
            }
            Get-IRTUnifiedAuditLog @Params
            $Filter = { $RecordType -eq 'MicrosoftTeams' }
            $InvokeArgs = @{ ModuleName = 'M365IncidentResponseTools'; ParameterFilter = $Filter }
            Should -Invoke Search-UnifiedAuditLog -Times 4 -Exactly @InvokeArgs
        }

        It 'does not pass RecordType when the parameter is omitted' {
            $Params = @{
                AllUsers = $true
                Excel    = $false
                Xml      = $false
            }
            Get-IRTUnifiedAuditLog @Params
            $Filter = { $PSBoundParameters.ContainsKey('RecordType') }
            $InvokeArgs = @{ ModuleName = 'M365IncidentResponseTools'; ParameterFilter = $Filter }
            Should -Invoke Search-UnifiedAuditLog -Times 0 -Exactly @InvokeArgs
        }
    }

    # -------------------------------------------------------------------
    Context 'a query that fails after all retries inserts a data-gap marker' {

        BeforeEach {
            # every attempt throws; Start-Sleep is mocked so the backoff is instant
            Mock Search-UnifiedAuditLog {
                throw 'simulated UAL failure'
            } -ModuleName M365IncidentResponseTools
            Mock Start-Sleep { } -ModuleName M365IncidentResponseTools
        }

        It 'retries MaxRetry (3) times before giving up on the query' {
            $Params = @{
                AllUsers             = $true
                Excel                = $true
                Xml                  = $false
                ThrottleDelaySeconds = 1
            }
            Get-IRTUnifiedAuditLog @Params -ErrorAction SilentlyContinue
            $InvokeArgs = @{ ModuleName = 'M365IncidentResponseTools' }
            Should -Invoke Search-UnifiedAuditLog -Times 3 -Exactly @InvokeArgs
        }

        It 'passes a DATA MISSING marker through to Show-IRTUnifiedAuditLog' {
            $Params = @{
                AllUsers             = $true
                Excel                = $true
                Xml                  = $false
                ThrottleDelaySeconds = 1
            }
            Get-IRTUnifiedAuditLog @Params -ErrorAction SilentlyContinue
            $Filter = { $Log | Where-Object { $_.IRTDataGap } }
            $InvokeArgs = @{ ModuleName = 'M365IncidentResponseTools'; ParameterFilter = $Filter }
            Should -Invoke Show-IRTUnifiedAuditLog -Times 1 -Exactly @InvokeArgs
        }
    }

    Context 'a query refused with only a warning is treated as a failure' {

        BeforeEach {
            # EXO reports some refusals (401s from the sync-search path) as a
            # WARNING plus an empty result rather than a terminating error. That
            # must not be reported to the analyst as "no audit activity".
            Mock Search-UnifiedAuditLog {
                Write-Warning ('Failed to process request via Sync Search mode, ' +
                    'returning HttpRequestException. Exception: Unauthorized , ' +
                    'Reason: Unauthorized.')
                @()
            } -ModuleName M365IncidentResponseTools
            Mock Start-Sleep { } -ModuleName M365IncidentResponseTools
        }

        It 'retries MaxRetry (3) times instead of accepting the empty result' {
            $Params = @{
                AllUsers             = $true
                Excel                = $true
                Xml                  = $false
                ThrottleDelaySeconds = 1
            }
            Get-IRTUnifiedAuditLog @Params -ErrorAction SilentlyContinue
            $InvokeArgs = @{ ModuleName = 'M365IncidentResponseTools' }
            Should -Invoke Search-UnifiedAuditLog -Times 3 -Exactly @InvokeArgs
        }

        It 'passes a DATA MISSING marker through to Show-IRTUnifiedAuditLog' {
            $Params = @{
                AllUsers             = $true
                Excel                = $true
                Xml                  = $false
                ThrottleDelaySeconds = 1
            }
            Get-IRTUnifiedAuditLog @Params -ErrorAction SilentlyContinue
            $Filter = { $Log | Where-Object { $_.IRTDataGap } }
            $InvokeArgs = @{ ModuleName = 'M365IncidentResponseTools'; ParameterFilter = $Filter }
            Should -Invoke Show-IRTUnifiedAuditLog -Times 1 -Exactly @InvokeArgs
        }
    }

    Context 'an unrelated warning does not turn an empty result into a failure' {

        BeforeEach {
            # A tenant with no matching activity is a legitimate empty result and
            # must still be reported once, without retries or a gap marker.
            Mock Search-UnifiedAuditLog {
                Write-Warning 'Some unrelated advisory warning.'
                @()
            } -ModuleName M365IncidentResponseTools
            Mock Start-Sleep { } -ModuleName M365IncidentResponseTools
        }

        It 'runs the query once and does not retry' {
            $Params = @{
                AllUsers             = $true
                Excel                = $true
                Xml                  = $false
                ThrottleDelaySeconds = 1
            }
            Get-IRTUnifiedAuditLog @Params -ErrorAction SilentlyContinue
            $InvokeArgs = @{ ModuleName = 'M365IncidentResponseTools' }
            Should -Invoke Search-UnifiedAuditLog -Times 1 -Exactly @InvokeArgs
        }

        It 'inserts no data-gap marker' {
            $Params = @{
                AllUsers             = $true
                Excel                = $true
                Xml                  = $false
                ThrottleDelaySeconds = 1
            }
            Get-IRTUnifiedAuditLog @Params -ErrorAction SilentlyContinue
            $Filter = { $Log | Where-Object { $_.IRTDataGap } }
            $InvokeArgs = @{ ModuleName = 'M365IncidentResponseTools'; ParameterFilter = $Filter }
            Should -Invoke Show-IRTUnifiedAuditLog -Times 0 -Exactly @InvokeArgs
        }
    }

    # -------------------------------------------------------------------
    Context 'PassThru' {

        BeforeEach {
            Mock Search-UnifiedAuditLog {
                New-UALPage -Count 10
            } -ModuleName M365IncidentResponseTools
        }

        It 'emits nothing by default' {
            $Params = @{
                AllUsers = $true
                Excel    = $false
                Xml      = $false
            }
            $Result = Get-IRTUnifiedAuditLog @Params
            $Result | Should -BeNullOrEmpty
        }

        It 'emits one collection with the metadata row at index 0' {
            $Params = @{
                AllUsers = $true
                Excel    = $false
                Xml      = $false
                PassThru = $true
            }
            $Result = Get-IRTUnifiedAuditLog @Params
            $Result.Count | Should -Be 11
            $Result[0].Metadata | Should -BeTrue
            $Result[0].FileNamePrefix | Should -Be 'UnifiedAuditLogs'
        }

        It 'does not export when -Excel and -Xml are false' {
            $Params = @{
                AllUsers = $true
                Excel    = $false
                Xml      = $false
                PassThru = $true
            }
            $null = Get-IRTUnifiedAuditLog @Params
            $InvokeArgs = @{ ModuleName = 'M365IncidentResponseTools' }
            Should -Invoke Show-IRTUnifiedAuditLog -Times 0 -Exactly @InvokeArgs
        }
    }

    # -------------------------------------------------------------------
    Context 'page-relative ResultIndex/ResultCount does not end paging' -Tag 'regression' {

        BeforeEach {
            # Three full pages of distinct records, each reporting ResultIndex
            # 1..5000 against ResultCount 5000 exactly as a live tenant does,
            # then a short page. Reading those fields as an end-of-set marker
            # would stop this after one call and lose 10000 records.
            $script:UALPageCallCount = 0
            Mock Search-UnifiedAuditLog {
                $script:UALPageCallCount++
                if ($script:UALPageCallCount -gt 3) { New-UALPage -Count 200 }
                else {
                    New-UALPage -Count 5000 -StartId (($script:UALPageCallCount - 1) * 5000)
                }
            } -ModuleName M365IncidentResponseTools
        }

        It 'keeps paging through full pages until a short page arrives' {
            $Params = @{
                AllUsers    = $true
                ResultLimit = 50000
                Excel       = $false
                Xml         = $false
            }
            Get-IRTUnifiedAuditLog @Params
            $InvokeArgs = @{ ModuleName = 'M365IncidentResponseTools' }
            Should -Invoke Search-UnifiedAuditLog -Times 4 -Exactly @InvokeArgs
        }

        It 'keeps every record from every page' {
            $Params = @{
                AllUsers    = $true
                ResultLimit = 50000
                Excel       = $false
                Xml         = $false
            }
            Get-IRTUnifiedAuditLog @Params
            $Filter = { $Message -match 'Total retrieved 15200 logs' }
            $InvokeArgs = @{ ModuleName = 'M365IncidentResponseTools'; ParameterFilter = $Filter }
            Should -Invoke Write-IRT -Times 1 -Exactly @InvokeArgs
        }
    }

    # -------------------------------------------------------------------
    Context 'paging stops on a full page of records already served' -Tag 'regression' {

        BeforeEach {
            # Same 5000 identities on every call and no ResultIndex/ResultCount,
            # which is the worst case: nothing but the duplicate check can tell
            # the pull is finished. The short page after 10 calls is only a
            # backstop so a regression fails the assertion instead of hanging.
            $script:UALPageCallCount = 0
            Mock Search-UnifiedAuditLog {
                $script:UALPageCallCount++
                if ($script:UALPageCallCount -gt 10) { New-UALPage -Count 10 }
                else { New-UALPage -Count 5000 -StartId 0 }
            } -ModuleName M365IncidentResponseTools
        }

        It 'stops after the first page that adds nothing new' {
            $Params = @{
                AllUsers    = $true
                ResultLimit = 50000
                Excel       = $false
                Xml         = $false
            }
            Get-IRTUnifiedAuditLog @Params
            $InvokeArgs = @{ ModuleName = 'M365IncidentResponseTools' }
            Should -Invoke Search-UnifiedAuditLog -Times 2 -Exactly @InvokeArgs
        }

        It 'warns that the result set was treated as exhausted' {
            $Params = @{
                AllUsers    = $true
                ResultLimit = 50000
                Excel       = $false
                Xml         = $false
            }
            Get-IRTUnifiedAuditLog @Params
            $Filter = { $Level -eq 'Warn' -and $Message -match 'all already seen' }
            $InvokeArgs = @{ ModuleName = 'M365IncidentResponseTools'; ParameterFilter = $Filter }
            Should -Invoke Write-IRT -Times 1 -Exactly @InvokeArgs
        }
    }

    # -------------------------------------------------------------------
    Context 'ResultLimit counts deduplicated records' -Tag 'regression' {

        BeforeEach {
            # Pages overlap by half, so the raw record count runs at twice the
            # rate of the real one. Counting raw records against ResultLimit
            # would cut the pull short and silently drop real audit records.
            $script:UALPageCallCount = 0
            Mock Search-UnifiedAuditLog {
                $script:UALPageCallCount++
                if ($script:UALPageCallCount -gt 10) { New-UALPage -Count 10 }
                else {
                    New-UALPage -Count 5000 -StartId (($script:UALPageCallCount - 1) * 2500)
                }
            } -ModuleName M365IncidentResponseTools
        }

        It 'pages until 10000 unique records are collected, not 10000 raw' {
            $Params = @{
                AllUsers    = $true
                ResultLimit = 10000
                Excel       = $false
                Xml         = $false
            }
            Get-IRTUnifiedAuditLog @Params
            $InvokeArgs = @{ ModuleName = 'M365IncidentResponseTools' }
            Should -Invoke Search-UnifiedAuditLog -Times 3 -Exactly @InvokeArgs
        }

        It 'reports the deduplicated total alongside the raw record count' {
            $Params = @{
                AllUsers    = $true
                ResultLimit = 10000
                Excel       = $false
                Xml         = $false
            }
            Get-IRTUnifiedAuditLog @Params
            $Filter = { $Message -match 'Total retrieved 10000 logs \(15000 records' }
            $InvokeArgs = @{ ModuleName = 'M365IncidentResponseTools'; ParameterFilter = $Filter }
            Should -Invoke Write-IRT -Times 1 -Exactly @InvokeArgs
        }
    }

    # -------------------------------------------------------------------
    Context '-HighCompleteness is only sent when asked for' {

        BeforeEach {
            Mock Search-UnifiedAuditLog { @() } -ModuleName M365IncidentResponseTools
        }

        It 'omits the parameter entirely by default' {
            $Params = @{
                AllUsers = $true
                Excel    = $false
                Xml      = $false
            }
            Get-IRTUnifiedAuditLog @Params
            $Filter = { $PSBoundParameters.ContainsKey('HighCompleteness') }
            $InvokeArgs = @{ ModuleName = 'M365IncidentResponseTools'; ParameterFilter = $Filter }
            Should -Invoke Search-UnifiedAuditLog -Times 0 -Exactly @InvokeArgs
        }

        It 'passes the switch when the caller sets it' {
            $Params = @{
                AllUsers         = $true
                HighCompleteness = $true
                Excel            = $false
                Xml              = $false
            }
            Get-IRTUnifiedAuditLog @Params
            $Filter = { $HighCompleteness.IsPresent }
            $InvokeArgs = @{ ModuleName = 'M365IncidentResponseTools'; ParameterFilter = $Filter }
            Should -Invoke Search-UnifiedAuditLog -Times 1 -Exactly @InvokeArgs
        }
    }
}
