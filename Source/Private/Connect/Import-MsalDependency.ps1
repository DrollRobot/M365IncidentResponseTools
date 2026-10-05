function Import-MsalDependency {
    <#
    .SYNOPSIS
    Loads the highest available Microsoft.IdentityModel.Abstractions assembly.

    .DESCRIPTION
    Internal helper, called by Import-MsalAssembly before it loads MSAL.

    MSAL depends on Microsoft.IdentityModel.Abstractions. .NET only probes for it
    next to MSAL, but Microsoft.Graph.Authentication keeps it one folder up, in
    Dependencies\. Graph 2.41+ isolates its own dependencies, so it no longer makes
    the DLL available to the session, and MSAL fails with "Could not load file or
    assembly 'Microsoft.IdentityModel.Abstractions'".

    Only one version can load per session, and an older loaded version cannot
    satisfy a newer reference. ExchangeOnlineManagement ships its own copy, so
    loading Graph's when Exchange's is newer breaks Connect-ExchangeOnline. This
    function therefore loads the highest version shipped by either module.

    Does nothing if the assembly is already loaded, or if neither module ships it.

    .EXAMPLE
    Import-MsalDependency

    .OUTPUTS
    System.String. The path of the DLL loaded, or $null when nothing was loaded.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Import-IRTModule -Name 'PSFramework'

    $AssemblyName = 'Microsoft.IdentityModel.Abstractions'
    $DllName = "$AssemblyName.dll"

    $Loaded = Get-LoadedAssembly -Name $AssemblyName
    if ($Loaded) {
        Write-PSFMessage -Level 8 -Message "MSAL dependency already loaded: $($Loaded.FullName)"
        return $null
    }

    # Both are required modules. Import them so ModuleBase reflects the versions
    # this session will actually use.
    Import-IRTModule -Name 'Microsoft.Graph.Authentication', 'ExchangeOnlineManagement'

    $Candidates = [System.Collections.Generic.List[string]]::new()
    $GraphModule = Get-Module -Name 'Microsoft.Graph.Authentication'
    if ($GraphModule) {
        $GraphDeps = Join-Path -Path $GraphModule.ModuleBase -ChildPath 'Dependencies'
        $Candidates.Add((Join-Path -Path $GraphDeps -ChildPath $DllName))
        $GraphCoreParams = @{
            Path                = $GraphDeps
            ChildPath           = 'Core'
            AdditionalChildPath = $DllName
        }
        $Candidates.Add((Join-Path @GraphCoreParams))
    }
    $ExoModule = Get-Module -Name 'ExchangeOnlineManagement'
    if ($ExoModule) {
        $ExoDllParams = @{
            Path                = $ExoModule.ModuleBase
            ChildPath           = 'netCore'
            AdditionalChildPath = $DllName
        }
        $Candidates.Add((Join-Path @ExoDllParams))
    }

    $Best = $null
    $BestVersion = $null
    foreach ($Candidate in $Candidates) {
        if (-not (Test-Path -LiteralPath $Candidate)) {
            Write-PSFMessage -Level 9 -Message "No $DllName at: $Candidate"
            continue
        }
        $Version = Get-AssemblyFileVersion -Path $Candidate
        Write-PSFMessage -Level 8 -Message "Found $DllName $Version at: $Candidate"
        if (-not $BestVersion -or $Version -gt $BestVersion) {
            $Best = $Candidate
            $BestVersion = $Version
        }
    }

    if (-not $Best) {
        Write-PSFMessage -Level 8 -Message (
            "$DllName not found in Graph or Exchange modules. Leaving it to .NET to resolve.")
        return $null
    }

    Write-PSFMessage -Level 8 -Message "Loading MSAL dependency $BestVersion from: $Best"
    try {
        Add-Type -Path $Best -ErrorAction Stop
    } catch {
        throw "Failed to load MSAL dependency from '$Best': $_"
    }
    return $Best
}
