#region Clear-IRTTokenCache
function Clear-IRTTokenCache {
    <#
    .SYNOPSIS
    Removes the persistent IRT MSAL token cache and signs out all in-process accounts.

    .DESCRIPTION
    When the persistent token cache is enabled (config: EnableTokenCache),
    MSAL writes refresh tokens to disk so the user is not re-prompted in every
    new PowerShell session. This command:

      1. Removes every account from any PublicClientApplication currently held
         in $Global:IRT_Session (Graph, Exchange, IPPS). Removal also strips
         their tokens from the on-disk cache via the registered cache helper.
      2. Deletes the on-disk cache file as a belt-and-suspenders measure in
         case no MSAL app is currently registered against it.

    Use this after a credential rotation, when sharing a workstation, or to
    force the next Connect-IRT to prompt interactively.

    .EXAMPLE
    Clear-IRTTokenCache
    Wipes the cache. The next Connect-IRT call will require interactive sign-in.

    .OUTPUTS
    None.

    .NOTES
    Version: 1.0.0
    #>
    [Alias('ClearIRTTokenCache')]
    [CmdletBinding(SupportsShouldProcess)]
    param()

    # Sign out in-process accounts first. This invokes the cache helper's
    # write callback and removes the entries from the file cleanly.
    if ($Global:IRT_Session) {
        foreach ($svc in 'Graph', 'Exchange', 'IPPS') {
            $App = $Global:IRT_Session.$svc.PublicClientApplication
            if (-not $App) { continue }
            try {
                $Accounts = $App.GetAccountsAsync().GetAwaiter().GetResult()
                foreach ($acct in $Accounts) {
                    $null = $App.RemoveAsync($acct).GetAwaiter().GetResult()
                }
            }
            catch {
                Write-IRT "Failed to remove $svc MSAL accounts: $_" -Level Warn
            }
        }
    }

    # Belt-and-suspenders: delete the cache file directly if it survived.
    $CachePath = $Global:IRT_Config.MsalCachePath
    if (Test-Path $CachePath) {
        if ($PSCmdlet.ShouldProcess($CachePath, 'Delete MSAL token cache file')) {
            Remove-Item -Path $CachePath -Force -ErrorAction SilentlyContinue
            Write-IRT "Deleted token cache file at $CachePath."
        }
    }
    else {
        Write-IRT 'No token cache file found.'
    }
}
#endregion
