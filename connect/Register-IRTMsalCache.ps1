#region Install-IRTMsalExtensions
function Install-IRTMsalExtensions {
    <#
    .SYNOPSIS
    Ensures the Microsoft.Identity.Client.Extensions.Msal assembly is loaded.

    .DESCRIPTION
    Internal helper. If the assembly is not already loaded into the AppDomain,
    downloads the pinned .nupkg from nuget.org into the user's local app data
    folder (one-time), extracts the netstandard2.0 DLL, and loads it via
    Add-Type. Throws if the download or extraction fails, or if the loaded
    MSAL version is older than the pinned Extensions.Msal requires.

    .OUTPUTS
    [string] - the path to the loaded Extensions DLL.

    .NOTES
    Version: 1.0.0
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param()

    # Pinned version. Bump when Graph SDK's bundled MSAL outpaces this.
    $Version    = '4.66.2'
    $MsalFloor  = [version]'4.61.3'  # Extensions.Msal 4.66.x minimum MSAL

    # Already loaded?
    $Loaded = [System.AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq 'Microsoft.Identity.Client.Extensions.Msal' }
    if ($Loaded) {
        return $Loaded.Location
    }

    # Verify the MSAL DLL Graph loaded meets the Extensions floor.
    $Msal = [System.AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq 'Microsoft.Identity.Client' } |
        Select-Object -First 1
    if (-not $Msal) {
        throw 'Microsoft.Identity.Client is not loaded. ' +
            'Import a connect function (which loads MSAL) before calling Install-IRTMsalExtensions.'
    }
    $MsalVersion = [version]$Msal.GetName().Version
    if ($MsalVersion -lt $MsalFloor) {
        throw ("Loaded MSAL version $MsalVersion is older than Extensions.Msal $Version requires " +
            "($MsalFloor). Update Microsoft.Graph.Authentication.")
    }

    # Target path.
    $JpParams = @{
        Path                = $env:LOCALAPPDATA
        ChildPath           = 'M365IncidentResponseTools'
        AdditionalChildPath = @('msal-extensions', $Version,
            'Microsoft.Identity.Client.Extensions.Msal.dll')
    }
    $DllPath = Join-Path @JpParams
    $DllDir  = Split-Path $DllPath -Parent

    if (-not (Test-Path $DllPath)) {
        if (-not (Test-Path $DllDir)) {
            New-Item -ItemType Directory -Path $DllDir -Force | Out-Null
        }

        # Download .nupkg from NuGet v3 flat container. The nupkg is just a ZIP.
        $LowerId = 'microsoft.identity.client.extensions.msal'
        $NupkgUrl = "https://api.nuget.org/v3-flatcontainer/$LowerId/$Version/" +
            "$LowerId.$Version.nupkg"
        $TempNupkg = Join-Path ([System.IO.Path]::GetTempPath()) ("$LowerId.$Version.nupkg")
        $ExtractDir = Join-Path ([System.IO.Path]::GetTempPath()) ("$LowerId.$Version")

        Write-IRT "Downloading Microsoft.Identity.Client.Extensions.Msal $Version from nuget.org..."

        try {
            $IwrParams = @{
                Uri             = $NupkgUrl
                OutFile         = $TempNupkg
                UseBasicParsing = $true
                ErrorAction     = 'Stop'
            }
            Invoke-WebRequest @IwrParams

            if (Test-Path $ExtractDir) {
                Remove-Item -Path $ExtractDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            Expand-Archive -Path $TempNupkg -DestinationPath $ExtractDir -Force

            $SourceJp = @{
                Path                = $ExtractDir
                ChildPath           = 'lib'
                AdditionalChildPath = @('netstandard2.0',
                    'Microsoft.Identity.Client.Extensions.Msal.dll')
            }
            $SourceDll = Join-Path @SourceJp
            if (-not (Test-Path $SourceDll)) {
                throw "Expected DLL not found in extracted nupkg: $SourceDll"
            }
            Copy-Item -Path $SourceDll -Destination $DllPath -Force
        }
        finally {
            if (Test-Path $TempNupkg) {
                Remove-Item -Path $TempNupkg -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path $ExtractDir) {
                Remove-Item -Path $ExtractDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Add-Type -Path $DllPath
    return $DllPath
}
#endregion


#region Register-IRTMsalCache
function Register-IRTMsalCache {
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
    Register-IRTMsalCache -App $App

    .EXAMPLE
    Register-IRTMsalCache -App $App -CachePath 'C:\Temp\test-msal.bin'

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

    Install-IRTMsalExtensions | Out-Null

    $CacheDir  = Split-Path $CachePath -Parent
    $CacheFile = Split-Path $CachePath -Leaf

    if (-not (Test-Path $CacheDir)) {
        New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
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
        [System.Collections.Generic.KeyValuePair[string,string]]::new('Version', '1'),
        [System.Collections.Generic.KeyValuePair[string,string]]::new('ProductGroup', 'IRT'))
    $StorageProps = $PropsBuilder.Build()

    $Helper =
        [Microsoft.Identity.Client.Extensions.Msal.MsalCacheHelper]::CreateAsync(
            $StorageProps).GetAwaiter().GetResult()
    $Helper.RegisterCache($App.UserTokenCache)
}
#endregion
