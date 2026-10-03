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
         case no MSAL app is currently registered against it. On macOS and
         Linux the tokens live in the OS keyring rather than the file, so the
         keyring entry is cleared as well.

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
    Version: 1.1.0
    1.1.0 - Also clears the OS keyring entry that holds the cache on macOS and Linux.
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

    # Off Windows the cache file is only a lock; the tokens live in the OS keyring,
    # which a new session's apps are not yet registered against.
    if (-not $IsWindows -and $PSCmdlet.ShouldProcess('OS keyring', 'Clear MSAL token cache')) {
        try {
            (Get-MsalCacheHelper -CachePath $CachePath).Clear()
            Write-IRT 'Cleared the token cache from the OS keyring.'
        }
        catch {
            Write-IRT "Could not clear the token cache from the OS keyring: $_" -Level Warn
        }
    }
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
