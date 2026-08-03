function Clear-IRTTokenCache {
    <#
    .SYNOPSIS
    Removes the persistent IRT MSAL token cache and signs out all in-process accounts.

    .DESCRIPTION
    When the persistent token cache is enabled (config: EnableTokenCache),
    MSAL writes refresh tokens to disk so the user is not re-prompted in every
    new PowerShell session. This command:

      1. Removes every account from each PublicClientApplication currently held
         in $Global:IRT_Session.Apps. Removal also strips their tokens from the
         on-disk cache via the registered cache helper.
      2. Clears the sticky per-client account memory so the next acquisition
         starts fresh.
      3. Deletes the on-disk cache file as a belt-and-suspenders measure in
         case no MSAL app is currently registered against it.

    Use this after a credential rotation, when sharing a workstation, or to
    force the next Connect-IRT to prompt interactively.

    .EXAMPLE
    ```powershell
    Clear-IRTTokenCache
    ```
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
        foreach ($App in @($Global:IRT_Session.Apps?.Values)) {
            if (-not $App) { continue }
            try {
                $Accounts = $App.GetAccountsAsync().GetAwaiter().GetResult()
                foreach ($acct in $Accounts) {
                    $null = $App.RemoveAsync($acct).GetAwaiter().GetResult()
                }
            }
            catch {
                $AppId = $App.AppConfig.ClientId
                Write-IRT "Failed to remove MSAL accounts for client ${AppId}: $_" -Level Warn
            }
        }
        if ($null -ne $Global:IRT_Session.StickyAccount) {
            $Global:IRT_Session.StickyAccount.Clear()
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
