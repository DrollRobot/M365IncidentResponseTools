#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Set-AdUserEnabled's domain controller targeting.

.DESCRIPTION
    All tests are offline. The ActiveDirectory and ADSync cmdlets (Enable-ADAccount,
    Disable-ADAccount, Get-ADUser, Start-ADSyncSyncCycle) only exist on hosts with those
    modules, so thin global stubs are created in BeforeAll and mocked. The IRT helpers
    (Test-AdAvailable, Get-TargetDomainController, Push-AdReplication, Write-IRT) are
    mocked, as is Format-Table (to keep the results table out of test output). Which DC
    gets picked is covered by the Get-TargetDomainController tests.

    The function used to target $env:ComputerName, so it only worked on a DC. Every AD
    call must now go to the single target DC, so the readback sees the change and
    replication is pushed from where it was made.

    'disables the account on the target DC and reads it back from it'
        Disable-ADAccount and Get-ADUser both target the DC, picked once.

    'enables the account on the target DC'
        Enable-ADAccount targets the DC.

    'pushes AD replication from the target DC'
        Push-AdReplication gets the same DC the change was made on.
#>

BeforeAll {
    # params exist only so Mock can bind/inspect them; reference them to satisfy
    # PSReviewUnusedParameter
    function global:Enable-ADAccount {
        param($Identity, $Server)
        $null = $Identity, $Server
    }
    function global:Disable-ADAccount {
        param($Identity, $Server)
        $null = $Identity, $Server
    }
    function global:Get-ADUser {
        param($Identity, $Properties, $Server)
        $null = $Identity, $Properties, $Server
    }
    function global:Start-ADSyncSyncCycle {
        param($PolicyType)
        $null = $PolicyType
    }
}

AfterAll {
    @('Enable-ADAccount', 'Disable-ADAccount', 'Get-ADUser', 'Start-ADSyncSyncCycle') |
        ForEach-Object { Remove-Item -Path "Function:\$_" -ErrorAction SilentlyContinue }
}

InModuleScope M365IncidentResponseTools {

    Describe 'Set-AdUserEnabled' -Tag 'unit' {

        BeforeEach {
            $script:User = [pscustomobject]@{ SamAccountName = 'jdoe' }

            Mock Test-AdAvailable { $true }
            Mock Get-TargetDomainController { 'dc1.contoso.com' }
            Mock Push-AdReplication { }
            Mock Write-IRT { }
            Mock Format-Table { }
            Mock Enable-ADAccount { }
            Mock Disable-ADAccount { }
            Mock Get-ADUser { [pscustomobject]@{ SamAccountName = 'jdoe' } }
            Mock Start-ADSyncSyncCycle { }

            # adsync service is not on this device
            Mock Get-Service { } -ParameterFilter { $Name -eq 'adsync' }
        }

        It 'disables the account on the target DC and reads it back from it' {
            Set-AdUserEnabled -UserObject $script:User -Enabled $false

            Should -Invoke Get-TargetDomainController -Times 1 -Exactly
            $F = { $Server -eq 'dc1.contoso.com' }
            Should -Invoke Disable-ADAccount -Times 1 -Exactly -ParameterFilter $F
            Should -Invoke Get-ADUser -Times 1 -Exactly -ParameterFilter $F
            Should -Invoke Enable-ADAccount -Times 0 -Exactly
        }

        It 'enables the account on the target DC' {
            Set-AdUserEnabled -UserObject $script:User -Enabled $true

            $F = { $Server -eq 'dc1.contoso.com' }
            Should -Invoke Enable-ADAccount -Times 1 -Exactly -ParameterFilter $F
        }

        It 'pushes AD replication from the target DC' {
            Set-AdUserEnabled -UserObject $script:User -Enabled $false

            $F = { $Server -eq 'dc1.contoso.com' }
            Should -Invoke Push-AdReplication -Times 1 -Exactly -ParameterFilter $F
        }
    }
}
