function Get-MsalCacheHelper {
    <#
    .SYNOPSIS
    Returns the MSAL cache helper for the IRT persistent token cache.

    .DESCRIPTION
    Internal helper. Loads the bundled Microsoft.Identity.Client.Extensions.Msal
    assembly and creates an MsalCacheHelper for the cache at -CachePath, creating its
    folder if needed. The helper keeps the cache in the platform's protected store:
    a DPAPI-encrypted file on Windows, the Keychain on macOS, and the Secret Service
    keyring (for example GNOME Keyring) on Linux, where the file is only a lock.

    Register-MsalCache attaches the helper to an MSAL app; Clear-IRTTokenCache uses it
    to empty the store.

    .PARAMETER CachePath
    Full path to the MSAL cache file. Defaults to $Global:IRT_Config.MsalCachePath.

    .EXAMPLE
    ```powershell
    $Helper = Get-MsalCacheHelper
    $Helper.RegisterCache($App.UserTokenCache)
    ```
    Attaches the persistent cache to an MSAL app.

    .OUTPUTS
    [Microsoft.Identity.Client.Extensions.Msal.MsalCacheHelper]

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [string] $CachePath = $Global:IRT_Config.MsalCachePath
    )

    Import-IRTModule -Name 'PSFramework'
    Write-PSFMessage -Level 8 -Message "Get-MsalCacheHelper: CachePath=$CachePath"

    $null = Import-MsalExtensionAssembly

    $CacheDir = Split-Path $CachePath -Parent
    $CacheFile = Split-Path $CachePath -Leaf

    if (-not (Test-Path $CacheDir)) {
        Write-PSFMessage -Level 8 -Message "Get-MsalCacheHelper: Creating $CacheDir"
        $null = New-Item -ItemType Directory -Path $CacheDir -Force
    }

    # macOS/Linux fields are required by the builder even on Windows.
    $PropsBuilder =
    [Microsoft.Identity.Client.Extensions.Msal.StorageCreationPropertiesBuilder]::new(
        $CacheFile, $CacheDir)
    $PropsBuilder = $PropsBuilder.WithMacKeyChain(
        'Microsoft.M365IncidentResponseTools', 'MSALCache')
    $PropsBuilder = $PropsBuilder.WithLinuxKeyring(
        'com.microsoft.m365incidentresponsetools.tokencache',
        'default',
        'IRT MSAL token cache',
        [System.Collections.Generic.KeyValuePair[string, string]]::new('Version', '1'),
        [System.Collections.Generic.KeyValuePair[string, string]]::new('ProductGroup', 'IRT'))
    $StorageProps = $PropsBuilder.Build()

    [Microsoft.Identity.Client.Extensions.Msal.MsalCacheHelper]::CreateAsync(
        $StorageProps).GetAwaiter().GetResult()
}
