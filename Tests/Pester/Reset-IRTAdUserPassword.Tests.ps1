#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Reset-IRTAdUserPassword's domain controller targeting.

.DESCRIPTION
    All tests are offline. The ActiveDirectory and ADSync cmdlets (Set-ADAccountPassword,
    Set-ADUser, Get-ADUser, Start-ADSyncSyncCycle) only exist on hosts with those modules,
    so thin global stubs are created in BeforeAll and mocked. The IRT helpers
    (Test-AdAvailable, Get-TargetDomainController, Push-AdReplication, Write-IRT) are
    mocked, as are Read-Host (for -Custom) and Format-Table (to keep the results table out
    of test output). Which DC gets picked is covered by the Get-TargetDomainController
    tests.

    The function used to target $env:ComputerName, so it only worked on a DC. Every AD
    call must now go to the single target DC, so the readback sees the change and
    replication is pushed from where it was made.

    'resets the password and reads the user back on the target DC'
        Set-ADAccountPassword and Get-ADUser both target the DC, picked once.

    'sets change-at-next-sign-in on the target DC'
        Set-ADUser targets the DC.

    'pushes AD replication from the target DC'
        Push-AdReplication gets the same DC the change was made on.
#>

BeforeAll {
    $script:Mod = 'M365IncidentResponseTools'

    # params exist only so Mock can bind/inspect them; reference them to satisfy
    # PSReviewUnusedParameter
    function global:Set-ADAccountPassword {
        param($Identity, [switch] $Reset, [SecureString] $NewPassword, $Server)
        $null = $Identity, $Reset, $NewPassword, $Server
    }
    function global:Set-ADUser {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSAvoidUsingPlainTextForPassword', 'ChangePasswordAtLogon',
            Justification = 'A bool flag, not a password; mirrors the real Set-ADUser.')]
        param($Identity, [bool] $ChangePasswordAtLogon, $Server)
        $null = $Identity, $ChangePasswordAtLogon, $Server
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
    @('Set-ADAccountPassword', 'Set-ADUser', 'Get-ADUser', 'Start-ADSyncSyncCycle') |
        ForEach-Object { Remove-Item -Path "Function:\$_" -ErrorAction SilentlyContinue }
}

Describe 'Reset-IRTAdUserPassword' -Tag 'unit' {

    BeforeEach {
        $Mod = 'M365IncidentResponseTools'
        $script:User = [pscustomobject]@{ SamAccountName = 'jdoe' }

        Mock Test-AdAvailable { $true } -ModuleName $Mod
        Mock Get-TargetDomainController { 'dc1.contoso.com' } -ModuleName $Mod
        Mock Push-AdReplication { } -ModuleName $Mod
        Mock Write-IRT { } -ModuleName $Mod
        Mock Format-Table { } -ModuleName $Mod
        Mock Read-Host { [securestring]::new() } -ModuleName $Mod
        Mock Set-ADAccountPassword { } -ModuleName $Mod
        Mock Set-ADUser { } -ModuleName $Mod
        Mock Get-ADUser { [pscustomobject]@{ SamAccountName = 'jdoe' } } -ModuleName $Mod
        Mock Start-ADSyncSyncCycle { } -ModuleName $Mod

        # adsync service is not on this device
        Mock Get-Service { } -ModuleName $Mod -ParameterFilter { $Name -eq 'adsync' }
    }

    It 'resets the password and reads the user back on the target DC' {
        Reset-IRTAdUserPassword -UserObjects $script:User -Custom

        Should -Invoke Get-TargetDomainController -ModuleName $script:Mod -Times 1 -Exactly
        $F = { $Server -eq 'dc1.contoso.com' }
        $IA = @{ ModuleName = $script:Mod; ParameterFilter = $F }
        Should -Invoke Set-ADAccountPassword -Times 1 -Exactly @IA
        Should -Invoke Get-ADUser -Times 1 -Exactly @IA
    }

    It 'sets change-at-next-sign-in on the target DC' {
        Reset-IRTAdUserPassword -UserObjects $script:User -ForceChangePasswordNextSignIn

        $F = { $Server -eq 'dc1.contoso.com' -and $ChangePasswordAtLogon }
        $IA = @{ ModuleName = $script:Mod; ParameterFilter = $F }
        Should -Invoke Set-ADUser -Times 1 -Exactly @IA
    }

    It 'pushes AD replication from the target DC' {
        Reset-IRTAdUserPassword -UserObjects $script:User -Custom

        $IA = @{ ModuleName = $script:Mod; ParameterFilter = { $Server -eq 'dc1.contoso.com' } }
        Should -Invoke Push-AdReplication -Times 1 -Exactly @IA
    }
}
