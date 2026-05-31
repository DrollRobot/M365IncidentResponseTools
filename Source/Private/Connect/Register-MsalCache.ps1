function Register-MsalCache {
    <#
    .SYNOPSIS
    Attaches the IRT persistent token cache to an MSAL PublicClientApplication.

    .DESCRIPTION
    Internal helper. Loads Microsoft.Identity.Client.Extensions.Msal (downloading
    it on first use), then registers a DPAPI-encrypted on-disk cache against the
    supplied app's UserTokenCache. After registration, MSAL automatically
    persists refresh tokens between PowerShell sessions, so subsequent
    AcquireTokenSilent calls succeed without an interactive prompt for the life
    of the refresh token (up to ~90 days).

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

    .NOTES
    Version: 1.1.0
    Windows-only. On non-Windows platforms the function returns silently.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $App,

        [string] $CachePath = $Global:IRT_Config.MsalCachePath
    )

    if (-not $IsWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
        Write-IRT 'Persistent MSAL cache is currently Windows-only.' -Level Warn
        return
    }

    $null = Install-MsalExtensions

    $CacheDir = Split-Path $CachePath -Parent
    $CacheFile = Split-Path $CachePath -Leaf

    if (-not (Test-Path $CacheDir)) {
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

    $Helper =
    [Microsoft.Identity.Client.Extensions.Msal.MsalCacheHelper]::CreateAsync(
        $StorageProps).GetAwaiter().GetResult()
    $Helper.RegisterCache($App.UserTokenCache)
}