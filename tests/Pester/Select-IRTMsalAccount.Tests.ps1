#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Tests for Select-IRTMsalAccount candidate ordering.

.DESCRIPTION
    All tests are offline and use synthetic account objects shaped like
    Microsoft.Identity.Client.IAccount (Username, Environment, HomeAccountId
    with TenantId/Identifier). Select-IRTMsalAccount is a pure ordering
    function, so no mocks are needed.

    The ordering contract (the fix for spurious interactive prompts when the
    shared cache holds one account per customer tenant):

      1. Accounts from other cloud environments are excluded entirely.
      2. The sticky account (last known good for this client ID) goes first.
      3. Accounts homed in the target tenant go next, sorted by Username.
      4. Remaining same-environment accounts (guest/B2B operators) go last,
         sorted by Username.

    Callers try every returned candidate with AcquireTokenSilent before
    falling back to interactive auth, so inclusion (not just ordering)
    matters: a guest account must still be returned even though it is not
    homed in the target tenant.
#>

InModuleScope M365IncidentResponseTools {

    BeforeAll {
        $script:CommercialHost = 'login.microsoftonline.com'
        $script:TargetTenant = 'aaaaaaaa-0000-0000-0000-aaaaaaaaaaaa'
        $script:OtherTenant = 'bbbbbbbb-0000-0000-0000-bbbbbbbbbbbb'

        # New-TestAccount builds a synthetic IAccount-shaped object. Identifier
        # mirrors MSAL's "<oid>.<tid>" HomeAccountId format but any unique
        # string works for the ordering logic.
        function New-TestAccount {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test-only factory helper; ShouldProcess is not applicable.')]
            param(
                [string] $Username,
                [string] $TenantId = $script:TargetTenant,
                [string] $Environment = $script:CommercialHost
            )
            [pscustomobject]@{
                Username      = $Username
                Environment   = $Environment
                HomeAccountId = [pscustomobject]@{
                    TenantId   = $TenantId
                    Identifier = "$Username.$TenantId"
                }
            }
        }
    }

    Describe 'Select-IRTMsalAccount' {

        Context 'environment filtering' {

            It 'excludes accounts from other cloud environments' {
                $Accounts = @(
                    New-TestAccount -Username 'commercial@contoso.com'
                    New-TestAccount -Username 'gov@a.us' -Environment 'login.microsoftonline.us'
                )
                $SelectParams = @{
                    Account           = $Accounts
                    TenantId          = $script:TargetTenant
                    ExpectedLoginHost = $script:CommercialHost
                }
                $Result = @(Select-IRTMsalAccount @SelectParams)
                $Result | Should -HaveCount 1
                $Result[0].Username | Should -Be 'commercial@contoso.com'
            }

            It 'returns an empty result when nothing matches the environment' {
                $Accounts = @(
                    New-TestAccount -Username 'gov@a.us' -Environment 'login.microsoftonline.us'
                )
                $SelectParams = @{
                    Account           = $Accounts
                    TenantId          = $script:TargetTenant
                    ExpectedLoginHost = $script:CommercialHost
                }
                @(Select-IRTMsalAccount @SelectParams) | Should -HaveCount 0
            }

            It 'returns an empty result for empty input' {
                $SelectParams = @{
                    Account           = @()
                    TenantId          = $script:TargetTenant
                    ExpectedLoginHost = $script:CommercialHost
                }
                @(Select-IRTMsalAccount @SelectParams) | Should -HaveCount 0
            }
        }

        Context 'tier ordering' {

            It 'orders home-tenant accounts before accounts homed elsewhere' {
                # 'aaa@elsewhere.com' sorts alphabetically before
                # 'zzz@customer.com', so a plain Username sort would pick the
                # wrong account first; tier ordering must win.
                $Accounts = @(
                    New-TestAccount -Username 'aaa@elsewhere.com' -TenantId $script:OtherTenant
                    New-TestAccount -Username 'zzz@customer.com'
                )
                $SelectParams = @{
                    Account           = $Accounts
                    TenantId          = $script:TargetTenant
                    ExpectedLoginHost = $script:CommercialHost
                }
                $Result = @(Select-IRTMsalAccount @SelectParams)
                $Result[0].Username | Should -Be 'zzz@customer.com'
                $Result[1].Username | Should -Be 'aaa@elsewhere.com'
            }

            It 'still includes guest accounts homed in another tenant' {
                # B2B operators are homed elsewhere but may still get a token
                # for the target tenant; they must be tried before interactive.
                $Accounts = @(
                    New-TestAccount -Username 'guest@operator.com' -TenantId $script:OtherTenant
                )
                $SelectParams = @{
                    Account           = $Accounts
                    TenantId          = $script:TargetTenant
                    ExpectedLoginHost = $script:CommercialHost
                }
                $Result = @(Select-IRTMsalAccount @SelectParams)
                $Result | Should -HaveCount 1
                $Result[0].Username | Should -Be 'guest@operator.com'
            }

            It 'places the sticky account first even when it sorts last' {
                $Accounts = @(
                    New-TestAccount -Username 'aaa@customer.com'
                    New-TestAccount -Username 'zzz@customer.com'
                )
                $SelectParams = @{
                    Account           = $Accounts
                    TenantId          = $script:TargetTenant
                    ExpectedLoginHost = $script:CommercialHost
                    StickyAccountId   = "zzz@customer.com.$($script:TargetTenant)"
                }
                $Result = @(Select-IRTMsalAccount @SelectParams)
                $Result[0].Username | Should -Be 'zzz@customer.com'
                $Result[1].Username | Should -Be 'aaa@customer.com'
            }

            It 'does not duplicate the sticky account in later tiers' {
                $Accounts = @(
                    New-TestAccount -Username 'admin@customer.com'
                )
                $SelectParams = @{
                    Account           = $Accounts
                    TenantId          = $script:TargetTenant
                    ExpectedLoginHost = $script:CommercialHost
                    StickyAccountId   = "admin@customer.com.$($script:TargetTenant)"
                }
                @(Select-IRTMsalAccount @SelectParams) | Should -HaveCount 1
            }

            It 'ignores a sticky ID that matches no cached account' {
                $Accounts = @(
                    New-TestAccount -Username 'admin@customer.com'
                )
                $SelectParams = @{
                    Account           = $Accounts
                    TenantId          = $script:TargetTenant
                    ExpectedLoginHost = $script:CommercialHost
                    StickyAccountId   = 'gone@customer.com.deadbeef'
                }
                $Result = @(Select-IRTMsalAccount @SelectParams)
                $Result | Should -HaveCount 1
                $Result[0].Username | Should -Be 'admin@customer.com'
            }
        }

        Context 'deterministic ordering within tiers' {

            It 'sorts accounts by Username within each tier' {
                $Accounts = @(
                    New-TestAccount -Username 'charlie@customer.com'
                    New-TestAccount -Username 'alice@customer.com'
                    New-TestAccount -Username 'bob@customer.com'
                )
                $SelectParams = @{
                    Account           = $Accounts
                    TenantId          = $script:TargetTenant
                    ExpectedLoginHost = $script:CommercialHost
                }
                $Result = @(Select-IRTMsalAccount @SelectParams)
                $Result.Username | Should -Be @(
                    'alice@customer.com', 'bob@customer.com', 'charlie@customer.com')
            }

            It 'full ordering: sticky, then home tenant, then others' {
                $Accounts = @(
                    New-TestAccount -Username 'guest@operator.com' -TenantId $script:OtherTenant
                    New-TestAccount -Username 'bbb@customer.com'
                    New-TestAccount -Username 'aaa@customer.com'
                    New-TestAccount -Username 'gov@a.us' -Environment 'login.microsoftonline.us'
                )
                $SelectParams = @{
                    Account           = $Accounts
                    TenantId          = $script:TargetTenant
                    ExpectedLoginHost = $script:CommercialHost
                    StickyAccountId   = "bbb@customer.com.$($script:TargetTenant)"
                }
                $Result = @(Select-IRTMsalAccount @SelectParams)
                $Result.Username | Should -Be @(
                    'bbb@customer.com',     # sticky
                    'aaa@customer.com',     # home tenant
                    'guest@operator.com')   # other (gov account excluded)
            }
        }
    }
}
