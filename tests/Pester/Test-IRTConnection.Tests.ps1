#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Offline tests for Test-IRTConnection's connected-state logic.

.DESCRIPTION
    All tests are offline. Get-MgContext, Invoke-MgGraphRequest, and
    Get-ConnectionInformation are mocked, so no Graph/EXO/network activity
    occurs. Assertions use -Quiet (the boolean return); the verbose path only
    writes a Format-Table and returns nothing.

-- graph connected detection ----------------------------------------------

    A token bound via Connect-MgGraph -AccessToken leaves Get-MgContext.Account
    null while TenantId and a live Graph call both succeed. "Connected" must key
    off the live call plus the context TenantId, NOT a populated Account, or
    every token-based Graph session would read as disconnected.
#>

InModuleScope M365IncidentResponseTools {

    BeforeAll {
        $script:TestTenant = 'aaaaaaaa-0000-0000-0000-aaaaaaaaaaaa'
        $script:OtherTenant = 'bbbbbbbb-0000-0000-0000-bbbbbbbbbbbb'

        # MgContext stub. Account defaults to $null to mimic -AccessToken mode,
        # where Connect-MgGraph never populates the account.
        function New-MgCtx {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test-only factory helper; ShouldProcess is not applicable.')]
            param(
                [string] $TenantId = $script:TestTenant,
                [object] $Account = $null
            )
            [pscustomobject]@{ TenantId = $TenantId; Account = $Account }
        }

        # Get-ConnectionInformation-shaped EXO connection (non-IPPS URI).
        function New-ExoConn {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test-only factory helper; ShouldProcess is not applicable.')]
            param(
                [string] $TenantId = $script:TestTenant,
                [string] $Upn = 'admin@customer.com'
            )
            [pscustomobject]@{
                State             = 'Connected'
                TenantID          = $TenantId
                UserPrincipalName = $Upn
                ConnectionUri     = 'https://outlook.office365.com/powershell-liveid/'
            }
        }
    }

    Describe 'Test-IRTConnection' -Tag 'unit' {

        BeforeEach {
            $script:SavedSession = (
                Get-Variable -Name IRT_Session -Scope Global -ErrorAction SilentlyContinue
            )?.Value
            $Global:IRT_Session = [pscustomobject]@{
                TenantId = $script:TestTenant
                Graph    = [pscustomobject]@{ Account = 'admin@customer.com' }
            }

            # Healthy defaults: token-mode Graph (null Account), live call OK,
            # one connected EXO session in the same tenant.
            Mock Get-MgContext { New-MgCtx -Account $null }
            Mock Invoke-MgGraphRequest { [pscustomobject]@{ value = @() } }
            Mock Get-ConnectionInformation { @(New-ExoConn) }
        }
        AfterEach {
            $Global:IRT_Session = $script:SavedSession
        }

        It 'reports connected when the Graph context Account is null but the live call works' {
            Test-IRTConnection -Quiet | Should -BeTrue
        }

        It 'reports not connected when the live Graph call fails' {
            Mock Invoke-MgGraphRequest { throw '401 InvalidAuthenticationToken' }
            Test-IRTConnection -Quiet | Should -BeFalse
        }

        It 'reports not connected when there is no Graph context at all' {
            Mock Get-MgContext { $null }
            Test-IRTConnection -Quiet | Should -BeFalse
        }

        It 'reports not connected when Graph and Exchange are different tenants' {
            Mock Get-ConnectionInformation { @(New-ExoConn -TenantId $script:OtherTenant) }
            Test-IRTConnection -Quiet | Should -BeFalse
        }
    }
}
