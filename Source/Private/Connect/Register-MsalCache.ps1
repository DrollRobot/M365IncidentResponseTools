function Register-MsalCache {
    <#
    .SYNOPSIS
    Attaches the IRT persistent token cache to an MSAL PublicClientApplication.

    .DESCRIPTION
    Internal helper. Registers the persistent cache from Get-MsalCacheHelper against
    the supplied app's UserTokenCache. After registration, MSAL automatically persists
    refresh tokens between PowerShell sessions, so subsequent AcquireTokenSilent calls
    succeed without an interactive prompt for the life of the refresh token (up to
    ~90 days).

    The cache lives in the platform's protected store: a DPAPI-encrypted file on
    Windows, the Keychain on macOS, and the Secret Service keyring on Linux. Off
    Windows the store is checked first, and the function throws when it is not
    usable (on Linux it needs libsecret and a running keyring such as GNOME
    Keyring). There is deliberately no unencrypted fallback.

    .PARAMETER App
    The Microsoft.Identity.Client.IPublicClientApplication instance to attach
    the cache to.

    .PARAMETER CachePath
    Full path to the MSAL cache file. Defaults to $Global:IRT_Config.MsalCachePath.
    The default value is set in M365IncidentResponseTools.psm1.
    Override to use an alternate location (e.g. an isolated path for testing).

    .EXAMPLE
    Register-MsalCache -App $App

    .EXAMPLE
    Register-MsalCache -App $App -CachePath 'C:\Temp\test-msal.bin'

    .OUTPUTS
    None.

    .NOTES
    Version: 3.0.0
    3.0.0 - Supports macOS and Linux through the OS keyring.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $App,

        [string] $CachePath = $Global:IRT_Config.MsalCachePath
    )

    Import-IRTModule -Name 'PSFramework'

    Write-PSFMessage -Level 8 -Message "Register-MsalCache: CachePath=$CachePath"

    $Helper = Get-MsalCacheHelper -CachePath $CachePath

    if (-not $IsWindows) {
        try {
            $Helper.VerifyPersistence()
        }
        catch {
            throw ('The OS keyring that would hold the token cache is not usable. ' +
                'On Linux the cache needs libsecret and a running keyring such as ' +
                "GNOME Keyring. $($_.Exception.Message)")
        }
    }

    Write-PSFMessage -Level 8 -Message "Register-MsalCache: Registering cache at: $CachePath"
    $Helper.RegisterCache($App.UserTokenCache)
}
