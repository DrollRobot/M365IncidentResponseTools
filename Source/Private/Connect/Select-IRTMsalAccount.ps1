function Select-IRTMsalAccount {
    <#
    .SYNOPSIS
    Orders cached MSAL accounts by how likely they are to work for a target tenant.

    .DESCRIPTION
    Internal helper. The shared persistent MSAL cache accumulates one account per
    customer tenant (plus any guest/B2B accounts), all in the same cloud
    environment. Picking an arbitrary account makes AcquireTokenSilent fail and
    falls through to a spurious interactive prompt, so callers instead try every
    candidate this function returns, in order, before going interactive.

    Ordering, after filtering to the expected cloud environment:
      1. The sticky account - the one that last succeeded for this client ID in
         this session.
      2. Accounts homed in the target tenant (HomeAccountId.TenantId match) -
         the per-customer-tenant admin account fast path.
      3. Remaining accounts in the same environment (guest/B2B operators homed
         in a different tenant).

    Pure function: no MSAL calls, no global state. Returns an empty array when
    nothing matches the environment.

    .PARAMETER Account
    The cached accounts to order (from IPublicClientApplication.GetAccountsAsync).

    .PARAMETER TenantId
    The target tenant GUID.

    .PARAMETER ExpectedLoginHost
    The bare login host for the target cloud (e.g. login.microsoftonline.com).
    Accounts from other clouds are excluded.

    .PARAMETER StickyAccountId
    Optional HomeAccountId.Identifier of the account that last succeeded for this
    client ID. Ordered first when present.

    .EXAMPLE
    Select-IRTMsalAccount -Account $Cached -TenantId $Tid -ExpectedLoginHost $Host

    .OUTPUTS
    [object[]] - ordered IAccount candidates (possibly empty).

    .NOTES
    Version: 1.0.0
    #>
    [OutputType([object[]])]
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]] $Account,

        [Parameter(Mandatory)]
        [string] $TenantId,

        [Parameter(Mandatory)]
        [string] $ExpectedLoginHost,

        [string] $StickyAccountId
    )

    Import-IRTModule -Name 'PSFramework'

    $EnvMatch = @($Account | Where-Object { $_.Environment -eq $ExpectedLoginHost })
    Write-PSFMessage -Level 8 -Message (
        "Select-IRTMsalAccount: $(@($Account).Count) cached account(s), " +
        "$($EnvMatch.Count) match environment '$ExpectedLoginHost'.")

    $Sticky = @()
    if ($StickyAccountId) {
        $Sticky = @($EnvMatch |
                Where-Object { $_.HomeAccountId.Identifier -eq $StickyAccountId })
    }

    $HomeTenant = @($EnvMatch |
            Where-Object {
                $_.HomeAccountId.TenantId -eq $TenantId -and
                $_.HomeAccountId.Identifier -notin $Sticky.HomeAccountId.Identifier
            } |
            Sort-Object -Property Username)

    $Picked = @($Sticky.HomeAccountId.Identifier) + @($HomeTenant.HomeAccountId.Identifier)
    $Rest = @($EnvMatch |
            Where-Object { $_.HomeAccountId.Identifier -notin $Picked } |
            Sort-Object -Property Username)

    $Ordered = @($Sticky) + @($HomeTenant) + @($Rest)

    $Summary = foreach ($Acct in $Ordered) {
        $Tier = if ($Acct.HomeAccountId.Identifier -in $Sticky.HomeAccountId.Identifier) {
            'sticky'
        } elseif ($Acct.HomeAccountId.TenantId -eq $TenantId) {
            'home-tenant'
        } else {
            'other'
        }
        "$($Acct.Username) [$Tier]"
    }
    Write-PSFMessage -Level 8 -Message (
        "Select-IRTMsalAccount: candidate order: $($Summary -join ', ')")

    return $Ordered
}
