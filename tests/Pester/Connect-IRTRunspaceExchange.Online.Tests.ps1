#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Live runspace tests for Connect-IRTRunspaceExchange.

.DESCRIPTION
    Proves the parallel-Exchange design against a real tenant: a worker
    runspace - bootstrapped exactly like Start-IRTPlaybook bootstraps its
    workers (same InitialSessionState variable injection, same module
    imports) - must mint an Exchange token SILENTLY from the shared MSAL
    app injected via $Global:IRT_Session, establish its own runspace-local
    REST connection, and successfully run a live Exchange cmdlet, all
    without prompting and without disturbing the parent session's
    connection.

    Depends on the session established by 'Connect-IRT session state (live)'
    (tests.ps1 runs that file first and the session persists in global scope
    for the remaining online files).

    'worker connects and runs a live Exchange cmdlet'
        The core assertion: Connect-IRTRunspaceExchange succeeded inside the
        runspace and Get-OrganizationConfig returned real data.

    'worker runs in silent worker mode'
        $Global:IRT_IsRunspaceWorker was injected and visible, so token
        acquisition could never have opened a hidden browser prompt.

    'worker holds its own connection, not the parent''s'
        The runspace-local ConnectionId must differ from the parent's -
        workers must never ride (or replace) the parent connection.

    'a second call in the same runspace is a fast-path no-op'
        Calling Connect-IRTRunspaceExchange twice must yield the same
        ConnectionId - the healthy-connection fast path, live.

    'worker token expiry is in the future'
        The runspace-local tracking global records a usable bound-token
        expiry for mid-step refresh decisions.

    'parent connection is undisturbed after the worker ran'
        The parent's ConnectionId still reports Connected and a live call
        from the parent still works - scoped connections in practice.
#>

Describe 'Connect-IRTRunspaceExchange in a live runspace' -Tag 'Online' {

    BeforeAll {
        if (-not ($Global:IRT_Session -and $Global:IRT_Session.Exchange)) {
            throw ('Runspace tests require an active Exchange connection. ' +
                "Run '.\tests.ps1 Online' so the session is established first.")
        }

        $script:ParentConnectionId = $Global:IRT_Session.Exchange.ConnectionId

        # Bootstrap a worker runspace the same way Start-IRTPlaybook does:
        # inject the shared session (with its thread-safe MSAL apps) and the
        # worker flag as globals BEFORE the modules import.
        $IssType = [System.Management.Automation.Runspaces.InitialSessionState]
        $InitialSessionState = $IssType::CreateDefault()
        $SsveType = [System.Management.Automation.Runspaces.SessionStateVariableEntry]
        $SharedRefs = @{
            IRT_Session               = $Global:IRT_Session
            IRT_IsRunspaceWorker      = $true
            ModuleDependenciesChecked = $Global:ModuleDependenciesChecked
        }
        foreach ($Key in $SharedRefs.Keys) {
            $InitialSessionState.Variables.Add($SsveType::new($Key, $SharedRefs[$Key], ''))
        }

        # Import the SAME module instance the test run loaded (source or built),
        # not whatever is installed under PSModulePath.
        $ModulePath = (Get-Module -Name 'M365IncidentResponseTools').Path
        $InitialSessionState.ImportPSModule(
            'ExchangeOnlineManagement',
            $ModulePath,
            'Microsoft.Graph.Authentication'
        )

        $script:Pool = [RunspaceFactory]::CreateRunspacePool(1, 1, $InitialSessionState, $Host)
        $script:Pool.Open()

        $WorkerScript = {
            try {
                # First call: silent mint + connect. Second call must be a
                # fast-path no-op returning the same connection.
                Connect-IRTRunspaceExchange
                $FirstId = $Global:IRT_RunspaceExo.ConnectionId
                Connect-IRTRunspaceExchange
                $SecondId = $Global:IRT_RunspaceExo.ConnectionId

                $Org = Get-OrganizationConfig -ErrorAction Stop

                $Result = [pscustomobject]@{
                    Success          = $true
                    Error            = $null
                    OrgName          = "$($Org.Name)"
                    FirstId          = "$FirstId"
                    SecondId         = "$SecondId"
                    BoundTokenExpiry = $Global:IRT_RunspaceExo.BoundTokenExpiry
                    IsWorker         = [bool]$Global:IRT_IsRunspaceWorker
                }

                # Tidy up this runspace's own connection; never anything else.
                $DcParams = @{
                    ConnectionId = $Global:IRT_RunspaceExo.ConnectionId
                    Confirm      = $false
                    ErrorAction  = 'SilentlyContinue'
                }
                Disconnect-ExchangeOnline @DcParams

                $Result
            } catch {
                [pscustomobject]@{
                    Success = $false
                    Error   = "$_"
                }
            }
        }

        $script:PowerShell = [PowerShell]::Create()
        $script:PowerShell.RunspacePool = $script:Pool
        $null = $script:PowerShell.AddScript($WorkerScript)
        $script:WorkerResult = $script:PowerShell.Invoke() | Select-Object -Last 1
    }

    AfterAll {
        if ($script:PowerShell) { try { $script:PowerShell.Dispose() } catch { } }
        if ($script:Pool) {
            try { $script:Pool.Close() } catch { }
            try { $script:Pool.Dispose() } catch { }
        }
    }

    It 'worker connects and runs a live Exchange cmdlet' {
        $script:WorkerResult.Success | Should -BeTrue -Because (
            "the worker must connect and query silently (error: $($script:WorkerResult.Error))")
        $script:WorkerResult.OrgName | Should -Not -BeNullOrEmpty
    }

    It 'worker runs in silent worker mode' {
        $script:WorkerResult.IsWorker | Should -BeTrue
    }

    It 'worker holds its own connection, not the parent''s' {
        $script:WorkerResult.FirstId | Should -Not -BeNullOrEmpty
        $script:WorkerResult.FirstId | Should -Not -Be "$($script:ParentConnectionId)"
    }

    It 'a second call in the same runspace is a fast-path no-op' {
        $script:WorkerResult.SecondId | Should -Be $script:WorkerResult.FirstId
    }

    It 'worker token expiry is in the future' {
        $script:WorkerResult.BoundTokenExpiry | Should -BeOfType [System.DateTime]
        $script:WorkerResult.BoundTokenExpiry |
            Should -BeGreaterThan ([System.DateTime]::UtcNow)
    }

    It 'parent connection is undisturbed after the worker ran' {
        $GciParams = @{
            ConnectionId = $script:ParentConnectionId
            ErrorAction  = 'SilentlyContinue'
        }
        $ParentConn = Get-ConnectionInformation @GciParams
        $ParentConn.State | Should -Be 'Connected'
        { Get-OrganizationConfig -ErrorAction Stop } | Should -Not -Throw
    }
}
