<#
.SYNOPSIS
    Project-specific build steps that run before ModuleBuilder is invoked.

.DESCRIPTION
    Build.ps1 is intentionally generic and reusable across any ModuleBuilder project.
    Put anything specific to this project here: generating files, updating version metadata,
    copying assets into the source tree, etc.

    This script is invoked automatically by Build.ps1 if it exists in the repo root.
    Delete or rename it to skip the pre-build phase entirely.
#>

$ErrorActionPreference = 'Stop'

# Ensure ImportExcel is available
if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
    Write-Host "Installing ImportExcel module..." -ForegroundColor Cyan
    Install-Module -Name ImportExcel -Scope CurrentUser -Force -AllowClobber
}
Import-Module -Name ImportExcel -Force

# Reapply conditional formatting rules to the template to prevent drift
$RepoRoot = Split-Path -Path $PSScriptRoot -Parent
$JoinPathParams = @{
    Path                = $RepoRoot
    ChildPath           = 'Source'
    AdditionalChildPath = @('Data', 'IpAddressConditionalFormattingTemplate.xlsx')
}
$TemplatePath = Join-Path @JoinPathParams

$ScriptParams = @{
    Path          = $TemplatePath
    ColumnName    = 'ipaddress'
    ClearExisting = $true
}

$ScriptPathParams = @{
    Path                = $RepoRoot
    ChildPath           = 'Build'
    AdditionalChildPath = @('Add-IpAddressConditionalFormattingTemplate.ps1')
}
$ScriptPath = Join-Path @ScriptPathParams

& $ScriptPath @ScriptParams

# Ensure the bundled MSAL cache-extension assembly is present in Source\Data.
# Import-MsalExtensionAssembly loads it at runtime for the persistent token cache;
# if it goes missing (fresh clone gone wrong, accidental delete), restore the pinned
# version from the NuGet v3 flat container and verify its hash.
$MsalExtVersion = '4.66.2'
$MsalExtSha256 = 'DE7E52F3DDCFDC106B04766B7CA7181CFA08E8849C1B9B58E28B6E52F648C6D6'
$MsalExtDllParams = @{
    Path                = $RepoRoot
    ChildPath           = 'Source'
    AdditionalChildPath = @('Data', 'Microsoft.Identity.Client.Extensions.Msal.dll')
}
$MsalExtDll = Join-Path @MsalExtDllParams

if (-not (Test-Path -LiteralPath $MsalExtDll)) {
    $RestoreMsg = "Restoring Microsoft.Identity.Client.Extensions.Msal $MsalExtVersion..."
    Write-Host $RestoreMsg -ForegroundColor Cyan
    $LowerId = 'microsoft.identity.client.extensions.msal'
    $NupkgUrl = "https://api.nuget.org/v3-flatcontainer/$LowerId/$MsalExtVersion/" +
    "$LowerId.$MsalExtVersion.nupkg"
    $TempDir = [System.IO.Path]::GetTempPath()
    $TempNupkg = Join-Path -Path $TempDir -ChildPath "$LowerId.$MsalExtVersion.nupkg"
    $ExtractDir = Join-Path -Path $TempDir -ChildPath "$LowerId.$MsalExtVersion"
    try {
        Invoke-WebRequest -Uri $NupkgUrl -OutFile $TempNupkg -UseBasicParsing -ErrorAction Stop
        Expand-Archive -Path $TempNupkg -DestinationPath $ExtractDir -Force
        $MsalExtDllName = 'Microsoft.Identity.Client.Extensions.Msal.dll'
        $SourceDllParams = @{
            Path                = $ExtractDir
            ChildPath           = 'lib'
            AdditionalChildPath = @('netstandard2.0', $MsalExtDllName)
        }
        $SourceDll = Join-Path @SourceDllParams
        $ActualHash = (Get-FileHash -Path $SourceDll -Algorithm SHA256).Hash
        if ($ActualHash -ne $MsalExtSha256) {
            throw ("Downloaded Extensions.Msal DLL hash '$ActualHash' does not match pinned " +
                "'$MsalExtSha256'. Aborting build.")
        }
        Copy-Item -Path $SourceDll -Destination $MsalExtDll -Force
    } finally {
        if (Test-Path $TempNupkg) {
            Remove-Item -Path $TempNupkg -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $ExtractDir) {
            Remove-Item -Path $ExtractDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
