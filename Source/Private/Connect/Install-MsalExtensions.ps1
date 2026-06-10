function Install-MsalExtensions {
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseSingularNouns', '',
        Justification = 'Internal helper; plural name reflects MSAL extensions assembly.')]
    param()

    Import-IRTModule -Name 'PSFramework'

    # Pinned version. Bump when Graph SDK's bundled MSAL outpaces this.
    $Version = '4.66.2'
    $MsalFloor = [version]'4.61.3'  # Extensions.Msal 4.66.x minimum MSAL

    # Already loaded?
    $Loaded = [System.AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq 'Microsoft.Identity.Client.Extensions.Msal' }
    if ($Loaded) {
        Write-PSFMessage -Level 8 -Message (
            "Install-MsalExtensions: Already loaded from $($Loaded.Location)")
        return $Loaded.Location
    }

    # Verify the MSAL DLL Graph loaded meets the Extensions floor.
    $Msal = [System.AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq 'Microsoft.Identity.Client' } |
        Select-Object -First 1
    if (-not $Msal) {
        throw 'Microsoft.Identity.Client is not loaded. ' +
        'Import a connect function (which loads MSAL) before calling Install-MsalExtensions.'
    }
    $MsalVersion = [version]$Msal.GetName().Version
    Write-PSFMessage -Level 8 -Message (
        "Install-MsalExtensions: Loaded MSAL version: $MsalVersion (floor: $MsalFloor)")
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
    $DllDir = Split-Path $DllPath -Parent

    Write-PSFMessage -Level 8 -Message "Install-MsalExtensions: DLL target: $DllPath"
    if (-not (Test-Path $DllPath)) {
        if (-not (Test-Path $DllDir)) {
            $null = New-Item -ItemType Directory -Path $DllDir -Force
        }

        # Download .nupkg from NuGet v3 flat container. The nupkg is just a ZIP.
        $LowerId = 'microsoft.identity.client.extensions.msal'
        $NupkgUrl = "https://api.nuget.org/v3-flatcontainer/$LowerId/$Version/" +
        "$LowerId.$Version.nupkg"
        Write-PSFMessage -Level 8 -Message "Install-MsalExtensions: Downloading from $NupkgUrl"
        $TempDir = [System.IO.Path]::GetTempPath()
        $TempNupkg = Join-Path -Path $TempDir -ChildPath "$LowerId.$Version.nupkg"
        $ExtractDir = Join-Path -Path $TempDir -ChildPath "$LowerId.$Version"

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

    Write-PSFMessage -Level 8 -Message "Install-MsalExtensions: Loading assembly from $DllPath"
    Add-Type -Path $DllPath
    return $DllPath
}
