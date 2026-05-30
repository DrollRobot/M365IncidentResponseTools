function Find-IRTServicePrincipal {
    <#
    .SYNOPSIS
    Finds service principals in the tenant by display name, app ID, or object ID.
    Creates $IRT_ServicePrincipalObjects.

    .DESCRIPTION
    Searches all service principals cached from the tenant against one or more search
    strings. A match is attempted against DisplayName, AppDisplayName, AppId, and Id
    using regular-expression matching (-match), so partial strings and regex patterns
    are both accepted.

    When exactly one match is found for a search string, the service principal is added
    to the result collection and a summary table is displayed. When multiple matches are
    found, the table is shown but nothing is saved -- refine the search to a single
    match, or use -AllMatches to add all of them. When no match is found, an error
    message is displayed.

    On success, results are stored in $Global:IRT_ServicePrincipalObjects (or
    $Global:IRT_<VarPrefix>ServicePrincipalObjects when -VarPrefix is supplied). Pass
    -Script to suppress all console output and return the objects directly instead.

    .PARAMETER Search
    One or more search strings. Each is matched against DisplayName, AppDisplayName,
    AppId, and Id using -match (regex-capable, case-insensitive).

    .PARAMETER VarPrefix
    Optional prefix inserted into the global variable name:
    $Global:IRT_<VarPrefix>ServicePrincipalObjects. Useful when working with multiple
    service principals simultaneously.

    .PARAMETER Cached
    Use service principal data already cached in $Global:IRT_ServicePrincipals from a
    previous call instead of fetching fresh data from Graph.

    .PARAMETER Script
    Suppresses all console output and returns matched objects directly as an array.
    Used by playbook scripts that need the objects without interactive display.

    .PARAMETER AllMatches
    When specified, adds all objects that match a given search string instead of
    rejecting the search when more than one result is found. Results are deduplicated
    by object ID, so overlapping search strings that resolve to the same service
    principal produce only one entry in the output.

    .EXAMPLE
    Find-IRTServicePrincipal MyApp
    Find a single service principal by display name.

    .EXAMPLE
    Find-IRTServicePrincipal -Search MyApp,AnotherApp
    Find multiple service principals in one call.

    .EXAMPLE
    Find-IRTServicePrincipal -Search 00000003-0000-0000-c000-000000000000
    Find by full or partial AppId (Microsoft Graph in this example).

    .EXAMPLE
    Find-IRTServicePrincipal -Search bf7573a5844f
    Find by partial object ID.

    .EXAMPLE
    Find-IRTServicePrincipal MyApp -Script
    Return the matched object directly without console output or setting the global variable.

    .OUTPUTS
    None by default. Sets $Global:IRT_ServicePrincipalObjects.
    With -Script: [object[]] of matched service principal objects.

    .NOTES
    Version: 1.1.0
    1.1.0 - Added -AllMatches to collect all matching service principals and deduplicate results.

    By default, fresh data is fetched from Graph on every call. Pass -Cached to
    skip the network request and reuse data already stored in
    $Global:IRT_ServicePrincipals from a previous call.
    #>
    [Alias(
        # ServicePrincipal
        'Find-IRTServicePrincipals',
        'Find-ServicePrincipal', 'Find-ServicePrincipals',
        'FindIRTServicePrincipal', 'FindIRTServicePrincipals',
        'FindServicePrincipal', 'FindServicePrincipals',
        # SP
        'Find-IRTSP', 'Find-IRTSPs',
        'Find-SP', 'Find-SPs',
        'FindIRTSP', 'FindIRTSPs',
        'FindSP', 'FindSPs',
        # EnterpriseApplication
        'Find-IRTEnterpriseApplication', 'Find-IRTEnterpriseApplications',
        'Find-EnterpriseApplication', 'Find-EnterpriseApplications',
        'FindIRTEnterpriseApplication', 'FindIRTEnterpriseApplications',
        'FindEnterpriseApplication', 'FindEnterpriseApplications'
    )]
    [OutputType([object[]])]
    [CmdletBinding()]
    param (
        [Parameter( Position = 0, Mandatory )]
        [string[]] $Search,
        [string] $VarPrefix,
        [switch] $Cached,
        [switch] $Script,
        [switch] $AllMatches
    )

    begin {
        Update-IRTToken -Service 'Graph'
        $ScriptServicePrincipalObjects = [System.Collections.Generic.List[PsObject]]::new()
        $SeenIds = [System.Collections.Generic.HashSet[string]]::new()
        $DisplayProperties = @(
            'AccountEnabled'
            'AppDisplayName'
            'ServicePrincipalType'
            'AppId'
            'Id'
        )

        # fetch fresh data by default; use cache only when -Cached is specified
        if ($Cached) {
            $AllServicePrincipals = Request-GraphServicePrincipal -Cached
        } else {
            $AllServicePrincipals = Request-GraphServicePrincipal
        }
    }

    process {

        Write-IRT ''

        foreach ( $SearchString in $Search ) {

            # match against display name, app display name, app ID, or object ID
            $MatchingServicePrincipals = $AllServicePrincipals | Where-Object {
                $_.DisplayName    -match $SearchString -or
                $_.AppDisplayName -match $SearchString -or
                $_.AppId          -match $SearchString -or
                $_.Id             -match $SearchString
            }

            if (($MatchingServicePrincipals | Measure-Object).Count -eq 1) {

                if ( -not $Script ) {

                    Write-IRT "Showing results for search: ${SearchString}"
                    $MatchingServicePrincipals | Format-Table $DisplayProperties
                }

                $SP = $MatchingServicePrincipals | Select-Object -First 1
                if ($SeenIds.Add($SP.Id)) {
                    $ScriptServicePrincipalObjects.Add($SP)
                }
            }
            elseif (($MatchingServicePrincipals | Measure-Object).Count -gt 1) {

                if ( -not $Script ) {

                    Write-IRT "Showing results for search: ${SearchString}"
                    $MatchingServicePrincipals | Format-Table $DisplayProperties
                }

                if ($AllMatches) {
                    foreach ($SP in $MatchingServicePrincipals) {
                        if ($SeenIds.Add($SP.Id)) {
                            $ScriptServicePrincipalObjects.Add($SP)
                        }
                    }
                } elseif (-not $Script) {
                    $Msg = 'Multiple service principals found. Refine search or use -AllMatches.'
                    Write-IRT $Msg -Level Error
                }
            }
            else {
                if ( -not $Script ) {
                    Write-IRT "$SearchString not found. Try a different search." -Level Error
                }
            }
        }

        # if script, just return objects
        if ($Script) {
            return @($ScriptServicePrincipalObjects)
        }

        if ( $ScriptServicePrincipalObjects.Count -gt 0 ) {

            $VariableParams = @{
                Name  = "IRT_${VarPrefix}ServicePrincipalObjects"
                Value = @($ScriptServicePrincipalObjects)
                Scope = 'Global'
                Force = $true
            }
            New-Variable @VariableParams
            Write-IRT "Created `$IRT_${VarPrefix}ServicePrincipalObjects"

            if ( $ScriptServicePrincipalObjects.Count -gt 1 ) {
                $ScriptServicePrincipalObjects | Format-Table $DisplayProperties
            }
        }
    }
}
