function Find-IRTUser {
    <#
    .SYNOPSIS
    Finds graph user by displayname, email address, or user id guid. Creates $UserObjects variable.

    .DESCRIPTION
    Searches Graph users for one or more search strings. Each string is matched against
    DisplayName, UserPrincipalName, the user object id, ProxyAddresses, and
    OnPremisesSamAccountName.

    Matching users are stored in $Global:IRT_UserObjects. Use -VarPrefix to change the variable
    name (e.g. 'Admin' > $Global:IRT_AdminUserObjects). A search that returns more than one user
    is reported but contributes nothing unless -AllMatches is used. Use -Script to suppress
    global side effects and return the objects directly.

    .PARAMETER Search
    One or more search strings. Each string is independently searched across all supported
    fields.

    .PARAMETER FromClipboard
    Read one search query per line from the clipboard instead of supplying -Search. Each
    non-empty line is treated as a separate search string. Mutually exclusive with -Search.

    .PARAMETER VarPrefix
    Optional prefix inserted after 'IRT_' in the global variable name
    (e.g. 'Admin' > $Global:IRT_AdminUserObjects). Useful when working with multiple sets of
    users simultaneously.

    .PARAMETER Cached
    Search the cached user list instead of requesting fresh users from Graph.

    .PARAMETER Script
    Return objects directly and suppress console output and global variable assignment. Use when
    calling from scripts or the playbook.

    .PARAMETER AllMatches
    Keep every user returned by a search instead of only searches that match exactly one user.
    Results are deduplicated by user object id.

    .EXAMPLE
    Find-IRTUser flast
    Finds users matching 'flast' and creates $IRT_UserObjects.

    .EXAMPLE
    Find-IRTUser -Search flast,jsmith
    Searches for two users, one query per string.

    .EXAMPLE
    Find-IRTUser bf7573a5844f
    Searches by partial user id. Email addresses and proxy addresses also match.

    .EXAMPLE
    $Users = Find-IRTUser -Search 'flast' -AllMatches -Script
    Returns every matching user object without setting globals or writing to the console.

    .EXAMPLE
    Find-IRTUser -FromClipboard
    Reads the clipboard and searches for each line as a separate query.

    .OUTPUTS
    System.Management.Automation.PSObject[]

    .NOTES
    Version: 1.3.1
    1.3.1 - Added missing help sections so PlatyPS can generate the command page.
    1.3.0 - Added -FromClipboard to read one search query per clipboard line.
    1.2.0 - Added -AllMatches to collect all matching users and deduplicate results.
    1.1.4 - Fixed bug with $UserObjects not being a collection.
            Moved getting full object to Show-User function.
    1.1.3 - Removed checks for modules and permissions. Checking at module level instead.
    1.1.2 - Added enabled as a displayed field.
    1.1.1 - Bug fix. Script was passing collections rather than user objects.
    1.1.0 - Major rewrite. Renamed to Find-User.
    #>
    [Alias(
        'Find-IRTUsers', 'FindIRTUser', 'FindIRTUsers',
        'Find-User', 'Find-Users', 'FindUser', 'FindUsers'
    )]
    [OutputType([psobject[]])]
    [CmdletBinding( DefaultParameterSetName = 'Search' )]
    param (
        [Parameter( ParameterSetName = 'Search', Position = 0, Mandatory )]
        [string[]] $Search,
        [Parameter( ParameterSetName = 'Clipboard', Mandatory )]
        [switch] $FromClipboard,
        [string] $VarPrefix,
        [switch] $Cached,
        [switch] $Script,
        [switch] $AllMatches
    )

    begin {
        if ( $FromClipboard ) {
            $Search = Get-IRTClipboardSearch
        }
        Update-IRTToken -Service 'Graph'
        $ScriptUserObjects = [System.Collections.Generic.List[PsObject]]::new()
        $SeenIds = [System.Collections.Generic.HashSet[string]]::new()
        $DisplayProperties = @(
            'AccountEnabled'
            'DisplayName'
            'UserPrincipalName'
            'OnPremisesSamAccountName'
            'Id'
        )

        # fetch fresh data by default; use cache only when -Cached is specified
        $GraphUsers = Request-GraphUser -Cached:$Cached
    }

    process {

        foreach ( $SearchString in $Search ) {

            # find matching users
            $MatchingUsers = $GraphUsers | Where-Object {
                $_.DisplayName -match $SearchString -or
                $_.UserPrincipalName -match $SearchString -or
                $_.Id -match $SearchString -or
                $_.ProxyAddresses -match $SearchString -or
                $_.OnPremisesSamAccountName -match $SearchString
            }

            if (($MatchingUsers | Measure-Object).Count -eq 1) {

                if ( -not $Script ) {

                    # show user info
                    Write-IRT "Showing results for search: ${SearchString}"
                    $MatchingUsers | Format-Table $DisplayProperties
                }

                $User = $MatchingUsers | Select-Object -First 1
                if ($SeenIds.Add($User.Id)) {
                    $ScriptUserObjects.Add($User)
                }
            }
            elseif (($MatchingUsers | Measure-Object).Count -gt 1) {

                if ( -not $Script ) {

                    # show user info
                    Write-IRT "Showing results for search: ${SearchString}"
                    $MatchingUsers | Format-Table $DisplayProperties
                }

                if ($AllMatches) {
                    foreach ($User in $MatchingUsers) {
                        if ($SeenIds.Add($User.Id)) {
                            $ScriptUserObjects.Add($User)
                        }
                    }
                } elseif (-not $Script) {
                    Write-IRT 'Multiple users found. Refine search or use -AllMatches.' -Level Error
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
            return [psobject[]]$ScriptUserObjects
        }

        if ( $ScriptUserObjects.Count -gt 0 ) {

            $VariableParams = @{
                Name  = "IRT_${VarPrefix}UserObjects"
                Value = @($ScriptUserObjects)
                Scope = 'Global'
                Force = $true
            }
            New-Variable @VariableParams
            Write-IRT "Created `$IRT_${VarPrefix}UserObjects"

            if ( $ScriptUserObjects.Count -gt 1 ) {
                $ScriptUserObjects | Format-Table $DisplayProperties
            }
        }
    }
}
