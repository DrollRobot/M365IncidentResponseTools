#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Live end-to-end test for Start-IRTPlaybook.

.DESCRIPTION
    Runs the real playbook against the test tenant: resolves the test user
    (from $env:IRT_TEST_USER_ID), runs Start-IRTPlaybook into a temporary
    investigation folder, and verifies that the parallel runspace steps
    actually completed by checking the generated spreadsheets and the error
    stream. This is the regression net for the runspace token redesign: a
    worker that cannot import the right module version, silently mint an
    Exchange token, or reach Graph through the shared context shows up here
    as a step error and a missing output file.

    Depends on the session established by 'Connect-IRT session state (live)'
    (tests.ps1 runs that file first; the session persists for the remaining
    online files). Uses cached auth - no interactive prompts.

    'playbook completes without any step errors'
        Every failed runspace step surfaces on the error stream via the
        playbook's EndInvoke handling; zero errors means every step ran to
        completion.

    'playbook generates the expected spreadsheets'
        Counts .xlsx files in the investigation folder. The healthy-run
        count on the test tenant is asserted as a floor so a partially
        broken pool (steps dying early) fails loudly.

    'parent Exchange connection survives the playbook'
        Workers connect and disconnect their own runspace-local connections;
        the parent's ConnectionId must still be Connected afterwards.
#>

Describe 'Start-IRTPlaybook end-to-end (live)' -Tag 'live', 'e2e' {

    BeforeAll {
        if (-not ($Global:IRT_Session -and
                $Global:IRT_Session.Graph -and
                $Global:IRT_Session.Exchange)) {
            throw ('Playbook tests require active Graph and Exchange connections. ' +
                "Run '.\tests.ps1 Online' so the session is established first.")
        }

        # Resolve the test user from the environment or the .env.ps1 file.
        $TestUserId = $env:IRT_TEST_USER_ID
        if (-not $TestUserId) {
            $EnvFile = Join-Path -Path $PSScriptRoot -ChildPath '..\.env.ps1'
            if (Test-Path $EnvFile) { . $EnvFile }
            $TestUserId = $env:IRT_TEST_USER_ID
        }
        if (-not $TestUserId) {
            throw ('Set $env:IRT_TEST_USER_ID or add it to tests/.env.ps1 ' +
                'before running the playbook test.')
        }

        $script:TestUser = Find-IRTUser -Search $TestUserId -Script
        if (-not $script:TestUser) {
            throw "Test user '$TestUserId' was not found in the test tenant."
        }

        $script:ParentConnectionId = $Global:IRT_Session.Exchange.ConnectionId

        # Keep the run headless and self-contained: no new terminal tab, and all
        # output files in a disposable working directory.
        $script:SavedOpenNewTab = $Global:IRT_Config.PlaybookOpenNewTab
        $Global:IRT_Config.PlaybookOpenNewTab = $false

        $TempName = "irt-playbook-test-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        $script:TempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath $TempName
        $null = New-Item -ItemType Directory -Path $script:TempRoot -Force
        Push-Location -Path $script:TempRoot

        # Worker runspaces share the parent host; their module loads must not
        # reset the terminal title Connect-IRT set.
        $script:TitleBefore = $Host.UI.RawUI.WindowTitle

        # Run the real playbook. Step failures surface as non-terminating errors
        # from the EndInvoke loop; collect them instead of failing here so the
        # assertions below can report exactly what broke.
        $script:PlaybookErrors = @()
        $PlaybookParams = @{
            UserObject    = $script:TestUser
            Ticket        = 'IRT-TEST'
            Confirm       = $false
            ErrorAction   = 'SilentlyContinue'
            ErrorVariable = 'PlaybookErrors'
        }
        Start-IRTPlaybook @PlaybookParams
        $script:PlaybookErrors = @($PlaybookErrors)

        $script:Spreadsheets = @(
            Get-ChildItem -Path $script:TempRoot -Filter '*.xlsx' -Recurse -File
        )
    }

    AfterAll {
        Pop-Location
        if ($script:SavedOpenNewTab -is [bool]) {
            $Global:IRT_Config.PlaybookOpenNewTab = $script:SavedOpenNewTab
        }
        if ($script:TempRoot -and (Test-Path $script:TempRoot)) {
            Remove-Item -Path $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'playbook completes without any step errors' {
        # Include exception type and stack trace per error: intermittent races
        # inside runspace steps are unfindable from the message alone.
        $ErrorSummary = ($script:PlaybookErrors | Select-Object -First 5 |
                ForEach-Object {
                    $Type = $_.Exception?.GetType().FullName
                    $Stack = "$($_.ScriptStackTrace)" -replace '\r?\n', ' <- '
                    "$_ [$Type] [$Stack]"
                }) -join ' ;; '
        $script:PlaybookErrors | Should -BeNullOrEmpty -Because (
            "every runspace step must complete (errors: $ErrorSummary)")
    }

    It 'playbook generates the expected spreadsheets' {
        # One pattern per file-producing step, as observed on a healthy full run
        # against the test tenant (the remaining steps are terminal-output-only
        # or data-dependent). A dead worker shows up as that step's missing file.
        $ExpectedPatterns = @(
            'AdminRoles_*.xlsx'             # Get-IRTAdminRole
            'MFAMethods_*.xlsx'             # Show-IRTUserMfa
            'InboxRules_*.xlsx'             # Get-IRTInboxRule
            'EntraAuditLogs_*.xlsx'         # Get-IRTEntraAuditLog
            'SignInLogs_*.xlsx'             # Get-IRTEntraSignInLog
            'NonInteractiveLogs_*.xlsx'     # Get-IRTNonInteractiveSignIn
            'MessageTrace_*_AllUsers_*.xlsx' # Get-IRTMessageTrace -AllUsers
            'MessageTrace_90Days_*.xlsx'    # Get-IRTMessageTrace (user)
            'UnifiedAuditLogs_*.xlsx'       # Get-IRTUnifiedAuditLog
            'UALRiskyOperations_*.xlsx'     # UALRiskyOperations
            'UALSignInLogs_*.xlsx'          # UALSignInLogs
        )
        $FileList = ($script:Spreadsheets.Name | Sort-Object) -join ', '
        foreach ($Pattern in $ExpectedPatterns) {
            $Match = @($script:Spreadsheets | Where-Object { $_.Name -like $Pattern })
            $Match.Count | Should -BeGreaterOrEqual 1 -Because (
                "the step writing '$Pattern' must complete (found: $FileList)")
        }
    }

    It 'parent Exchange connection survives the playbook' {
        $GciParams = @{
            ConnectionId = $script:ParentConnectionId
            ErrorAction  = 'SilentlyContinue'
        }
        (Get-ConnectionInformation @GciParams).State | Should -Be 'Connected'
    }

    It 'parent terminal title survives the playbook' {
        # Each worker imports the module while sharing the parent's host; the
        # module-load title set must be skipped in workers or the parent's
        # domain-suffixed title gets stomped back to plain [IRT].
        $Host.UI.RawUI.WindowTitle | Should -Be $script:TitleBefore
    }
}
