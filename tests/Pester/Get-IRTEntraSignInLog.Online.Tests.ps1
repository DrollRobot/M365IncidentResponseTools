#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Online tests for Get-IRTEntraSignInLog.

.DESCRIPTION
    These tests require an active Microsoft Graph session established by
    Connect-IRT. The Graph SDK cmdlets (Get-MgBetaAuditLogSignIn,
    Get-MgAuditLogSignIn) are NOT mocked; every query goes to the real Graph
    sign-in logs endpoint. The internal helpers the function relies on
    (Update-IRTToken, Import-IRTModule, Get-DefaultDomain, Resolve-DateRange)
    also run for real, so the full query / chunk / merge / sort pipeline is
    exercised end-to-end against live data.

    Only three things are mocked, and only to avoid side effects unrelated to
    the data path:
      - Show-IRTEntraSignInLog captures the -Logs argument so the test can
        inspect the records without writing an Excel workbook or invoking the
        ip_info enrichment tool.
      - Write-IRT and Write-PSFMessage suppress console noise.

    Prerequisites:
      - Connect-IRT must have completed (Graph session active). Tests.ps1 runs
        Connect-IRT.Tests.ps1 first and only proceeds here on success.
      - IRT_TEST_USER_ID must be set to a valid user GUID (see tests/.env.ps1).
        That account is the one used to authenticate, so it always has recent
        interactive and non-interactive sign-in activity.

    Each Context issues exactly one (or, for chunking, a small fixed number of)
    live query in its BeforeAll and caches the result in $script: variables so
    every It block in that Context shares the same data, keeping live Graph
    calls to a minimum. Sign-in records are captured with Excel = $true (the
    only path that calls Show-IRTEntraSignInLog) and Xml = $false. The first
    captured object is the metadata header inserted by the function; it is
    filtered out via -not $_.Metadata before assertions.

-- -UserObject, interactive, 30-day query ---------------------------------

    Queries the test user's interactive sign-ins over the default 30-day
    window in a single chunk.

    'returns at least 1 interactive sign-in for the test user'
        The test user authenticates via Connect-IRT, so an interactive sign-in
        always exists in the last 30 days. Zero means the UserId filter or the
        query pipeline broke.

    'every record belongs to the test user'
        Each record's UserId must equal the test user's Id, confirming the
        "UserId eq '<guid>'" filter reached Graph rather than being dropped.

    'all records fall within the 30-day window'
        Verifies the createdDateTime bounds were applied. A record outside the
        window means the date filter was not propagated.

-- -AllUsers, 7-day query (beta) ------------------------------------------

    One tenant-wide query over 7 days. Also captures a representative source
    IP for the -IpAddress context that follows.

    'returns at least 1 sign-in record'
        Any active M365 tenant has continuous sign-in activity.

    'all records fall within the 7-day window'
        Confirms the date bounds constrain tenant-wide results.

-- -IpAddress (derived from a live sign-in) -------------------------------

    Reuses an IP address observed in the -AllUsers result and queries by it.
    Because that exact sign-in falls inside the window, the query must return
    at least the originating record. Skipped if the AllUsers query produced no
    usable IP.

    'returns at least 1 sign-in for the derived IP'
        The originating record guarantees a non-empty result.

    'every record matches the queried IP'
        Each record's IpAddress must equal the queried address, confirming the
        "ipAddress eq '<ip>'" filter reached Graph.

-- -AllUsers, -NonInteractive, 7-day query --------------------------------

    Exercises the non-interactive path, which adds the
    "signInEventTypes/any(t: t eq 'NonInteractiveUser')" clause.

    'returns at least 1 non-interactive sign-in'
        Background token refreshes generate non-interactive sign-ins
        continuously in any active tenant.

    'every record is non-interactive'
        Each record's IsInteractive must be $false, confirming the event-type
        filter reached Graph. A $true here means the clause was dropped.

-- -Beta $false (v1.0 endpoint), AllUsers, 7-day query --------------------

    Forces the v1.0 endpoint (Get-MgAuditLogSignIn) instead of the default
    beta endpoint, exercising the non-beta branch live.

    'returns at least 1 record from the v1.0 endpoint'
        Confirms the v1.0 query path returns data.

    'all records fall within the 7-day window'
        Confirms the date filter works on the v1.0 path too.

-- date chunking: 7-day query split into 1-day chunks ---------------------

    Days = 7 with ChunkDays = 1 splits the range into 7 contiguous 1-day
    sub-queries (ChunkDelaySeconds = 0 keeps it fast). Specifically exercises
    the multi-chunk query / accumulate / merge / sort code path against live
    data.

    'returns at least 1 record merged across chunks'
        A zero count means chunking or the per-chunk date bounds broke the
        query; the single-chunk AllUsers context proves data exists.

    'all records fall within the 7-day window'
        Verifies every chunk used correct bounds; a record outside the window
        means a chunk boundary was miscomputed.

    'merged records are sorted newest first'
        The function sorts the accumulated results descending by
        CreatedDateTime; verifies that final sort survived the merge.

-- date range: -Start / -End absolute -------------------------------------

    An absolute window from 14 days ago to 7 days ago -- fully in the past so
    the boundary is stable for the duration of the run.

    'returns at least 1 record in the absolute range'
        The window is wide enough that an active tenant has activity in it.

    'every record falls within the specified absolute range'
        Records (with a 1-day tolerance for UTC/local conversion) must lie in
        the window, confirming -Start and -End were parsed and forwarded.
#>

InModuleScope M365IncidentResponseTools {

    Describe 'Get-IRTEntraSignInLog (live)' -Tag 'Online' {

        BeforeAll {
            if (-not ($Global:IRT_Session -and $Global:IRT_Session.Graph)) {
                throw ('Get-IRTEntraSignInLog online tests require an active Graph ' +
                    'session. Ensure Connect-IRT ran successfully first.')
            }
            if (-not $env:IRT_TEST_USER_ID) {
                throw 'IRT_TEST_USER_ID not set. Run tests/.env.ps1 first.'
            }

            $script:TestUser = Get-MgUser -UserId $env:IRT_TEST_USER_ID

            # captured across contexts: an IP observed in the AllUsers result,
            # reused by the -IpAddress context to query a known-good address.
            $script:LiveIp = $null
        }

        # -------------------------------------------------------------------
        Context '-UserObject, interactive, 30-day query' {

            BeforeAll {
                Mock Write-IRT { }
                Mock Write-PSFMessage { }

                $script:CapturedUser = $null
                Mock Show-IRTEntraSignInLog { param($Logs) $script:CapturedUser = $Logs }

                $Params = @{
                    UserObject = $script:TestUser
                    Days       = 30
                    Excel      = $true
                    Xml        = $false
                }
                Get-IRTEntraSignInLog @Params
                $script:UserLogs = @(
                    $script:CapturedUser | Where-Object { $_ -and -not $_.Metadata }
                )
            }

            It 'returns at least 1 interactive sign-in for the test user' {
                if ($script:UserLogs.Count -eq 0) {
                    throw ('No interactive sign-ins for the test user in 30 days; ' +
                        'the auth account should always have recent activity')
                }
                $script:UserLogs.Count | Should -BeGreaterThan 0
            }

            It 'every record belongs to the test user' {
                foreach ($Entry in $script:UserLogs) {
                    $Entry.UserId | Should -Be $script:TestUser.Id
                }
            }

            It 'all records fall within the 30-day window' {
                $WindowStart = [datetime]::UtcNow.AddDays(-31)
                $WindowEnd = [datetime]::UtcNow.AddDays(1)
                foreach ($Entry in $script:UserLogs) {
                    $Entry.CreatedDateTime | Should -BeGreaterOrEqual $WindowStart
                    $Entry.CreatedDateTime | Should -BeLessOrEqual $WindowEnd
                }
            }
        }

        # -------------------------------------------------------------------
        Context '-AllUsers, 7-day query (beta)' {

            BeforeAll {
                Mock Write-IRT { }
                Mock Write-PSFMessage { }

                $script:CapturedAll = $null
                Mock Show-IRTEntraSignInLog { param($Logs) $script:CapturedAll = $Logs }

                $Params = @{
                    AllUsers = $true
                    Days     = 7
                    Excel    = $true
                    Xml      = $false
                }
                Get-IRTEntraSignInLog @Params
                $script:AllLogs = @(
                    $script:CapturedAll | Where-Object { $_ -and -not $_.Metadata }
                )

                # capture a usable source IP for the -IpAddress context
                $script:LiveIp = (
                    $script:AllLogs |
                        Where-Object { $_.IpAddress } |
                        Select-Object -First 1
                ).IpAddress
            }

            It 'returns at least 1 sign-in record' {
                if ($script:AllLogs.Count -eq 0) {
                    throw 'No sign-in records found; active M365 tenants always have activity'
                }
                $script:AllLogs.Count | Should -BeGreaterThan 0
            }

            It 'all records fall within the 7-day window' {
                $WindowStart = [datetime]::UtcNow.AddDays(-8)
                $WindowEnd = [datetime]::UtcNow.AddDays(1)
                foreach ($Entry in $script:AllLogs) {
                    $Entry.CreatedDateTime | Should -BeGreaterOrEqual $WindowStart
                    $Entry.CreatedDateTime | Should -BeLessOrEqual $WindowEnd
                }
            }
        }

        # -------------------------------------------------------------------
        Context '-IpAddress (derived from a live sign-in)' {

            BeforeAll {
                Mock Write-IRT { }
                Mock Write-PSFMessage { }

                $script:CapturedIp = $null
                Mock Show-IRTEntraSignInLog { param($Logs) $script:CapturedIp = $Logs }

                if ($script:LiveIp) {
                    $Params = @{
                        IpAddress = $script:LiveIp
                        Days      = 7
                        Excel     = $true
                        Xml       = $false
                    }
                    Get-IRTEntraSignInLog @Params
                }
                $script:IpLogs = @(
                    $script:CapturedIp | Where-Object { $_ -and -not $_.Metadata }
                )
            }

            It 'returns at least 1 sign-in for the derived IP' {
                if (-not $script:LiveIp) {
                    Set-ItResult -Skipped -Because 'no source IP from the AllUsers query'
                    return
                }
                $script:IpLogs.Count | Should -BeGreaterThan 0
            }

            It 'every record matches the queried IP' {
                if (-not $script:LiveIp) {
                    Set-ItResult -Skipped -Because 'no source IP from the AllUsers query'
                    return
                }
                foreach ($Entry in $script:IpLogs) {
                    $Entry.IpAddress | Should -Be $script:LiveIp
                }
            }
        }

        # -------------------------------------------------------------------
        Context '-AllUsers, -NonInteractive, 7-day query' {

            BeforeAll {
                Mock Write-IRT { }
                Mock Write-PSFMessage { }

                $script:CapturedNI = $null
                Mock Show-IRTEntraSignInLog { param($Logs) $script:CapturedNI = $Logs }

                $Params = @{
                    AllUsers       = $true
                    NonInteractive = $true
                    Days           = 7
                    Excel          = $true
                    Xml            = $false
                }
                Get-IRTEntraSignInLog @Params
                $script:NILogs = @(
                    $script:CapturedNI | Where-Object { $_ -and -not $_.Metadata }
                )
            }

            It 'returns at least 1 non-interactive sign-in' {
                if ($script:NILogs.Count -eq 0) {
                    throw ('No non-interactive sign-ins found; background token ' +
                        'refreshes generate these continuously')
                }
                $script:NILogs.Count | Should -BeGreaterThan 0
            }

            It 'every record is non-interactive' {
                foreach ($Entry in $script:NILogs) {
                    $Entry.IsInteractive | Should -Be $false
                }
            }
        }

        # -------------------------------------------------------------------
        Context '-Beta $false (v1.0 endpoint), AllUsers, 7-day query' {

            BeforeAll {
                Mock Write-IRT { }
                Mock Write-PSFMessage { }

                $script:CapturedV1 = $null
                Mock Show-IRTEntraSignInLog { param($Logs) $script:CapturedV1 = $Logs }

                $Params = @{
                    AllUsers = $true
                    Beta     = $false
                    Days     = 7
                    Excel    = $true
                    Xml      = $false
                }
                Get-IRTEntraSignInLog @Params
                $script:V1Logs = @(
                    $script:CapturedV1 | Where-Object { $_ -and -not $_.Metadata }
                )
            }

            It 'returns at least 1 record from the v1.0 endpoint' {
                if ($script:V1Logs.Count -eq 0) {
                    throw 'No sign-in records from the v1.0 endpoint; tenant always has activity'
                }
                $script:V1Logs.Count | Should -BeGreaterThan 0
            }

            It 'all records fall within the 7-day window' {
                $WindowStart = [datetime]::UtcNow.AddDays(-8)
                $WindowEnd = [datetime]::UtcNow.AddDays(1)
                foreach ($Entry in $script:V1Logs) {
                    $Entry.CreatedDateTime | Should -BeGreaterOrEqual $WindowStart
                    $Entry.CreatedDateTime | Should -BeLessOrEqual $WindowEnd
                }
            }
        }

        # -------------------------------------------------------------------
        Context 'date chunking: 7-day query split into 1-day chunks' {

            BeforeAll {
                Mock Write-IRT { }
                Mock Write-PSFMessage { }

                $script:CapturedChunked = $null
                Mock Show-IRTEntraSignInLog { param($Logs) $script:CapturedChunked = $Logs }

                $Params = @{
                    AllUsers          = $true
                    Days              = 7
                    ChunkDays         = 1
                    ChunkDelaySeconds = 0
                    Excel             = $true
                    Xml               = $false
                }
                Get-IRTEntraSignInLog @Params
                $script:ChunkedLogs = @(
                    $script:CapturedChunked | Where-Object { $_ -and -not $_.Metadata }
                )
            }

            It 'returns at least 1 record merged across chunks' {
                if ($script:ChunkedLogs.Count -eq 0) {
                    throw ('No records across the 1-day chunks; likely a chunking ' +
                        'or merge error -- the single-chunk query found data')
                }
                $script:ChunkedLogs.Count | Should -BeGreaterThan 0
            }

            It 'all records fall within the 7-day window' {
                $WindowStart = [datetime]::UtcNow.AddDays(-8)
                $WindowEnd = [datetime]::UtcNow.AddDays(1)
                foreach ($Entry in $script:ChunkedLogs) {
                    $Entry.CreatedDateTime | Should -BeGreaterOrEqual $WindowStart
                    $Entry.CreatedDateTime | Should -BeLessOrEqual $WindowEnd
                }
            }

            It 'merged records are sorted newest first' {
                $Dates = $script:ChunkedLogs.CreatedDateTime
                $SortedDates = $Dates | Sort-Object -Descending
                $Dates | Should -Be $SortedDates
            }
        }

        # -------------------------------------------------------------------
        Context 'date range: -Start and -End absolute' {

            BeforeAll {
                Mock Write-IRT { }
                Mock Write-PSFMessage { }

                $script:CapturedAbs = $null
                Mock Show-IRTEntraSignInLog { param($Logs) $script:CapturedAbs = $Logs }

                # 14 days ago to 7 days ago -- fully in the past, stable boundary
                $script:AbsStart = [datetime]::UtcNow.AddDays(-14).ToString('yyyy-MM-dd')
                $script:AbsEnd = [datetime]::UtcNow.AddDays(-7).ToString('yyyy-MM-dd')

                $Params = @{
                    AllUsers = $true
                    Start    = $script:AbsStart
                    End      = $script:AbsEnd
                    Excel    = $true
                    Xml      = $false
                }
                Get-IRTEntraSignInLog @Params
                $script:AbsLogs = @(
                    $script:CapturedAbs | Where-Object { $_ -and -not $_.Metadata }
                )
            }

            It 'returns at least 1 record in the absolute range' {
                if ($script:AbsLogs.Count -eq 0) {
                    throw 'No records in the absolute 7-day window; likely a script error'
                }
                $script:AbsLogs.Count | Should -BeGreaterThan 0
            }

            It 'every record falls within the specified absolute range' {
                $LowerBound = ([datetime]$script:AbsStart).AddDays(-1)
                $UpperBound = ([datetime]$script:AbsEnd).AddDays(1)
                foreach ($Entry in $script:AbsLogs) {
                    $Entry.CreatedDateTime | Should -BeGreaterOrEqual $LowerBound
                    $Entry.CreatedDateTime | Should -BeLessOrEqual $UpperBound
                }
            }
        }
    }
}
