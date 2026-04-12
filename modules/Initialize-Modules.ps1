function Initialize-Modules {
    <#
    .SYNOPSIS
    Ensures required modules are imported without Microsoft.Identity.Client
    assembly conflicts.

    .DESCRIPTION
    Microsoft.Graph.Authentication and ExchangeOnlineManagement both ship
    their own version of Microsoft.Identity.Client.dll (MSAL). PowerShell
    only allows one version of an assembly per session — whichever loads
    first wins.

    This function scans all installed copies of both modules, finds the
    highest version of the MSAL assembly across all of them, and loads it
    via Add-Type before importing either module. This guarantees that both
    modules get a version that is >= what they shipped with.

    Call this once at module load time (e.g. from the .psm1 file).

    .NOTES
    Version: 2.0.0
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string[]] $ModuleNames
    )

    process {

        # --- 1. Find the highest MSAL assembly across all relevant modules ---
        $MsalLoaded = [System.AppDomain]::CurrentDomain.GetAssemblies() |
            Where-Object { $_.FullName -like 'Microsoft.Identity.Client,*' }

        if ( -not $MsalLoaded ) {

            # scan all installed versions of each module for their bundled MSAL DLL
            $MsalCandidates = foreach ( $Name in $ModuleNames ) {
                $InstalledModules = Get-Module $Name -ListAvailable -ErrorAction SilentlyContinue
                foreach ( $Mod in $InstalledModules ) {
                    $Dll = Get-ChildItem $Mod.ModuleBase -Recurse -Filter 'Microsoft.Identity.Client.dll' -ErrorAction SilentlyContinue |
                        Select-Object -First 1
                    if ( $Dll ) {
                        [PSCustomObject]@{
                            Module  = $Name
                            Version = [version] $Dll.VersionInfo.FileVersion
                            Path    = $Dll.FullName
                        }
                    }
                }
            }

            if ( -not $MsalCandidates ) {
                throw 'Could not find Microsoft.Identity.Client.dll in any installed module (Microsoft.Graph.Authentication, ExchangeOnlineManagement).'
            }

            $Winner = $MsalCandidates | Sort-Object Version -Descending | Select-Object -First 1

            Write-Verbose "Pre-loading Microsoft.Identity.Client $( $Winner.Version ) from $( $Winner.Module )"
            Write-Verbose "  Path: $( $Winner.Path )"

            Add-Type -Path $Winner.Path

        } else {
            Write-Verbose "Microsoft.Identity.Client already loaded: $( $MsalLoaded.FullName )"
        }

        # --- 2. Import all modules in the order provided ---
        foreach ( $Name in $ModuleNames ) {
            if ( -not ( Get-Module $Name ) ) {
                Import-Module $Name -ErrorAction Stop
            }
        }
    }
}