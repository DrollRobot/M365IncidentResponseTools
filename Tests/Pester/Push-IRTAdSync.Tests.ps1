#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Tests for Push-IRTAdSync: when the ActiveDirectory module is required, the AD
    replication push, and how candidate servers are checked.

.DESCRIPTION
    The ActiveDirectory and ADSync cmdlets (Get-ADComputer, Get-ADDomainController,
    Start-ADSyncSyncCycle) only exist on hosts with those modules, so thin global stubs
    are created in BeforeAll and mocked. The IRT helpers (Get-TargetDomainController,
    Push-AdReplication, Get-YesNo, Test-AdAvailable, Import-IRTModule, Write-IRT) are
    mocked. $Global:Storage is preloaded with a dummy credential so no prompt appears, and
    restored in AfterAll. Which DC gets picked is covered by the
    Get-TargetDomainController tests.

-- ActiveDirectory module requirement (unit) --------------------------------------

    'pushes locally without the ActiveDirectory module when adsync is on this device'
        With AD unavailable, the local ADSync service still gets the sync, and the
        module is never imported.

    'stops with an error when AD is unavailable and no -SyncServer is given'
        Discovery needs AD; without it the function reports and returns before
        querying AD.

    'imports the ActiveDirectory module when AD is available'
        The module is loaded only once AD is known to be reachable.

-- AD replication (unit) -----------------------------------------------------------

    'pushes replication from the target DC when AD is available'
        No need to run on a DC: replication is pushed from Get-TargetDomainController.

    'skips replication with a warning when AD is unavailable'
        Replication is optional; the sync is still pushed.

    'still pushes the sync when finding a DC fails'
        A DC discovery error is a warning, not a stop.

-- server checks (integration) -----------------------------------------------------

    These run the real runspace pool and New-PSSession against host names that cannot
    resolve (and localhost with a dummy credential), so each session fails in seconds
    with no network target.

    'does not need the ActiveDirectory module when -SyncServer is given'
        No module import, and the session error for the server is reported.

    'checks each discovered server separately in a single-DC domain'
        Regression: with one DC, (Get-ADDomainController).Name is a string, and
        string + array merged every server name into one hostname, which failed
        instantly as a single bogus target.

    'reports a fast check without waiting for a slower one queued ahead of it'
        Checks are handled as they finish, not in query order, so a slow or dead
        server first in line can't hold up the rest (or the push).
#>

BeforeAll {
    $script:Mod = 'M365IncidentResponseTools'

    # params exist only so Mock can bind/inspect them; reference them to satisfy
    # PSReviewUnusedParameter
    function global:Get-ADComputer {
        param($Filter, $Properties)
        $null = $Filter, $Properties
    }
    function global:Get-ADDomainController {
        param($Filter)
        $null = $Filter
    }
    function global:Start-ADSyncSyncCycle {
        param($PolicyType)
        $null = $PolicyType
    }

    $script:OriginalStorage = Get-Variable -Name 'Storage' -Scope Global -ErrorAction Ignore
    $Global:Storage = [pscredential]::new('irt-pester', [securestring]::new())
}

AfterAll {
    @('Get-ADComputer', 'Get-ADDomainController', 'Start-ADSyncSyncCycle') |
        ForEach-Object { Remove-Item -Path "Function:\$_" -ErrorAction SilentlyContinue }
    if ($script:OriginalStorage) {
        $Global:Storage = $script:OriginalStorage.Value
    }
    else {
        Remove-Variable -Name 'Storage' -Scope Global -ErrorAction Ignore
    }
}

Describe 'Push-IRTAdSync' {

    BeforeEach {
        $Mod = 'M365IncidentResponseTools'

        $script:Messages = [System.Collections.Generic.List[string]]::new()
        Mock Write-IRT { $script:Messages.Add($Message) } -ModuleName $Mod
        Mock Write-Progress { } -ModuleName $Mod
        Mock Import-IRTModule { } -ModuleName $Mod
        Mock Push-AdReplication { } -ModuleName $Mod
        Mock Get-YesNo { $true } -ModuleName $Mod
        Mock Test-AdAvailable { $false } -ModuleName $Mod
        Mock Read-Host { } -ModuleName $Mod
        Mock Start-ADSyncSyncCycle { } -ModuleName $Mod
        Mock Get-ADComputer { } -ModuleName $Mod
        Mock Get-ADDomainController { } -ModuleName $Mod
        Mock Get-TargetDomainController { 'dc1.contoso.com' } -ModuleName $Mod

        # default: adsync service is not on this device
        $SvcFilter = { $Name -eq 'adsync' }
        Mock Get-Service { } -ModuleName $Mod -ParameterFilter $SvcFilter

        # helper: put the adsync service on this device
        function Set-LocalAdsync {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test-only mock helper; ShouldProcess is not applicable.')]
            param()
            $SvcParams = @{
                ModuleName      = $script:Mod
                ParameterFilter = { $Name -eq 'adsync' }
            }
            Mock Get-Service { [pscustomobject]@{ Name = 'adsync' } } @SvcParams
        }
    }

    # -------------------------------------------------------------------
    Context 'ActiveDirectory module requirement' -Tag 'unit' {

        It 'pushes locally without the ActiveDirectory module when adsync is on this device' {
            Set-LocalAdsync

            Push-IRTAdSync

            $IA = @{ ModuleName = $script:Mod; ParameterFilter = { $PolicyType -eq 'Delta' } }
            Should -Invoke Start-ADSyncSyncCycle -Times 1 -Exactly @IA
            Should -Invoke Import-IRTModule -ModuleName $script:Mod -Times 0 -Exactly
        }

        It 'stops with an error when AD is unavailable and no -SyncServer is given' {
            Push-IRTAdSync

            $IA = @{ ModuleName = $script:Mod; ParameterFilter = { $Level -eq 'Error' } }
            Should -Invoke Write-IRT -Times 1 -Exactly @IA
            Should -Invoke Get-ADComputer -ModuleName $script:Mod -Times 0 -Exactly
        }

        It 'imports the ActiveDirectory module when AD is available' {
            Mock Test-AdAvailable { $true } -ModuleName $script:Mod

            Push-IRTAdSync

            $F = { $Name -contains 'ActiveDirectory' }
            $IA = @{ ModuleName = $script:Mod; ParameterFilter = $F }
            Should -Invoke Import-IRTModule -Times 1 -Exactly @IA
            Should -Invoke Get-ADComputer -ModuleName $script:Mod -Times 1 -Exactly
        }
    }

    # -------------------------------------------------------------------
    Context 'AD replication' -Tag 'unit' {

        It 'pushes replication from the target DC when AD is available' {
            Mock Test-AdAvailable { $true } -ModuleName $script:Mod
            Set-LocalAdsync

            Push-IRTAdSync

            $F = { $Server -eq 'dc1.contoso.com' }
            $IA = @{ ModuleName = $script:Mod; ParameterFilter = $F }
            Should -Invoke Push-AdReplication -Times 1 -Exactly @IA
        }

        It 'skips replication with a warning when AD is unavailable' {
            Set-LocalAdsync

            Push-IRTAdSync

            Should -Invoke Push-AdReplication -ModuleName $script:Mod -Times 0 -Exactly
            $script:Messages |
                Where-Object { $_ -like '*Skipping AD replication push*' } |
                Should -HaveCount 1
            Should -Invoke Start-ADSyncSyncCycle -ModuleName $script:Mod -Times 1 -Exactly
        }

        It 'still pushes the sync when finding a DC fails' {
            Mock Test-AdAvailable { $true } -ModuleName $script:Mod
            Mock Get-TargetDomainController { throw 'no DC found' } -ModuleName $script:Mod
            Set-LocalAdsync

            Push-IRTAdSync

            Should -Invoke Push-AdReplication -ModuleName $script:Mod -Times 0 -Exactly
            $script:Messages |
                Where-Object { $_ -like 'Finding a domain controller failed*no DC found*' } |
                Should -HaveCount 1
            Should -Invoke Start-ADSyncSyncCycle -ModuleName $script:Mod -Times 1 -Exactly
        }
    }

    # -------------------------------------------------------------------
    Context 'server checks' -Tag 'integration' {

        It 'does not need the ActiveDirectory module when -SyncServer is given' {
            Push-IRTAdSync -SyncServer 'irt-pester-nohost-sync'

            Should -Invoke Import-IRTModule -ModuleName $script:Mod -Times 0 -Exactly
            $script:Messages |
                Where-Object { $_ -like 'Opening session on irt-pester-nohost-sync failed: ?*' } |
                Should -HaveCount 1
        }

        It 'checks each discovered server separately in a single-DC domain' -Tag 'regression' {
            Mock Test-AdAvailable { $true } -ModuleName $script:Mod
            Mock Get-ADDomainController {
                [pscustomobject]@{ Name = 'irt-pester-nohost-dc1' }
            } -ModuleName $script:Mod
            # srv1 logged on more recently than srv2, so it is checked first
            Mock Get-ADComputer {
                $Logons = [ordered]@{
                    'irt-pester-nohost-srv2' = '2026-01-01'
                    'irt-pester-nohost-dc1'  = '2026-01-03'
                    'irt-pester-nohost-srv1' = '2026-01-02'
                }
                foreach ($Key in $Logons.Keys) {
                    [pscustomobject]@{ Name = $Key; LastLogOnDate = [datetime]$Logons[$Key] }
                }
            } -ModuleName $script:Mod

            Push-IRTAdSync

            # checks are reported as they finish, so compare without order
            $Checked = $script:Messages |
                Where-Object { $_ -like 'Opening session on * failed:*' } |
                ForEach-Object { ($_ -split ' ')[3] } |
                Sort-Object
            $Checked | Should -Be @(
                'irt-pester-nohost-dc1'
                'irt-pester-nohost-srv1'
                'irt-pester-nohost-srv2'
            )
        }

        It 'reports a fast check without waiting for a slower one queued ahead of it' {
            # unique name so a cached negative DNS lookup can't make it fail fast;
            # localhost rejects the dummy credential almost immediately
            $SlowName = "irt-pester-$([guid]::NewGuid().ToString('N').Substring(0, 8))"

            Push-IRTAdSync -SyncServer $SlowName, 'localhost'

            $Reported = $script:Messages |
                Where-Object { $_ -like 'Opening session on * failed:*' } |
                ForEach-Object { ($_ -split ' ')[3] }
            $Reported | Should -Be @('localhost', $SlowName)
        }
    }
}
