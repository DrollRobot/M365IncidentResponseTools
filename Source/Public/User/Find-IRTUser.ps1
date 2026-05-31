function Find-IRTUser {
    <#
    .SYNOPSIS
    Finds graph user by displayname, email address, or user id guid. Creates $UserObjects variable.

    .EXAMPLE
    Find-IRTUser flast
    Find-IRTUser -Search flast,flast,flast
    Find-IRTUser flast@domain.com
    Find-IRTUser -Search bf7573a5844f (partial user id number)

    .NOTES
    Version: 1.2.0
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