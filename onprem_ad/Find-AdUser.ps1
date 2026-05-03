function Find-AdUser {
    <#
    .SYNOPSIS
    Finds local AD user by DisplayName, Name, UserPrincipalName, ProxyAddresses, SamAccountName, or ObjectGUID.

    .DESCRIPTION
    Searches Active Directory for users matching one or more search strings. The search is
    applied across DisplayName, Name, UserPrincipalName, ProxyAddresses (email extracted
    by regex), SamAccountName, and ObjectGUID.

    If a single user is found, the full AD object is retrieved and stored in
    $Global:UserObject, $Global:UserObjects, and $Global:UserEmail. For multiple matches
    only $Global:UserObjects is populated. Use -Script to suppress global side effects and
    return objects directly.

    .PARAMETER Search
    One or more search strings. Each string is independently searched across all supported
    fields.

    .PARAMETER VarPrefix
    Optional prefix for the global variable names (e.g. 'Admin' > $Global:AdminUserObject).
    Useful when working with multiple users simultaneously.

    .PARAMETER Script
    Return objects directly and suppress global variable assignment. Use when calling from
    scripts or the playbook.

    .EXAMPLE
    Find-AdUser flast
    Finds users matching 'flast' and sets the global user object if exactly one match.

    .EXAMPLE
    Find-AdUser flast@contoso.com
    Searches by email address.

    .EXAMPLE
    $Users = Find-AdUser -Search 'flast','jsmith' -Script
    Returns matching user objects for two search strings without setting globals.

    .OUTPUTS
    None by default (sets global variables).
    Microsoft.ActiveDirectory.Management.ADUser[] when -Script is used.

    .NOTES
    Version: 1.2.1
    1.2.1 - Fixed bug where script was passing collections of user objects rather than user objects.
    1.2.0 - Major rewrite.
    #>
    [Alias('FindAdUser', 'FindAdUsers', 'Find-AdUsers')]
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, Mandatory)]
        [string[]] $Search,
        [string] $VarPrefix,
        [switch] $Script
    )

    begin {

        if (-not (Test-AdAvailable)) {
            Write-Error 'ActiveDirectory RSAT module not available.'
            return
        }

        # variables
        $ScriptUserObjects = [System.Collections.Generic.List[PsObject]]::new()
        $GetProperties = @(
            'DisplayName'
            'Enabled'
            'Name'
            'ObjectGUID'
            'ProxyAddresses'
            'SamAccountName'
            'UserPrincipalName'
        )
        $DisplayProperties = @(
            'Enabled'
            'DisplayName'
            'Name'
            'SamAccountName'
            'UserPrincipalName'
            'ObjectGUID'
        )
        $EmailPattern = "[A-Za-z0-9._%+-]{1,63}@(?:[A-Za-z0-9.-]+\.)+[A-Za-z]{2,6}"

        # find users whos displayname or email matches search
        $Users = Get-AdUser -Filter * -Property $GetProperties
    }

    process {

        foreach ($SearchString in $Search) {

            $MatchingUsers = [System.Collections.Generic.List[PsObject]]::new()

            # find matching users
            foreach ($User in $Users) {

                # extract emails from proxy addresses
                $ProxyEmails = $User.ProxyAddresses |
                    Select-String -Pattern $EmailPattern -AllMatches |
                    ForEach-Object { $_.Matches.Value }

                # if matching, add to list
                if ( $User.DisplayName -match $SearchString -or
                    $User.Name -match $SearchString -or
                    $User.UserPrincipalName -match $SearchString -or
                    $ProxyEmails -match $SearchString -or
                    $User.SamAccountName -match $SearchString -or
                    $User.ObjectGUID -match $SearchString
                ) {
                    $MatchingUsers.Add( $User )
                }
            }

            if (($MatchingUsers | Measure-Object).Count -eq 1) {

                if (-not $Script) {

                    # show user info
                    Write-IRT "Showing results for search: ${SearchString}"
                    $MatchingUsers | Format-Table $DisplayProperties
                }

                # get full user object
                $FullUserObject = Get-AdUser -Identity $MatchingUsers[0] -Property *

                # add user to array
                $ScriptUserObjects.Add( ( $FullUserObject | Select-Object -First 1 ) )
            }
            elseif (($MatchingUsers | Measure-Object).Count -gt 1) {

                if (-not $Script) {

                    # show user info
                    Write-IRT "Showing results for search: ${SearchString}"
                    $MatchingUsers | Format-Table $DisplayProperties
                    Write-IRT 'Multiple users found. Refine search.' -Level Error
                }
            }
            # if no users found
            else {
                if (-not $Script) {
                    Write-IRT "$SearchString not found. Try a different search." -Level Error
                }
            }
        }

        # if script, just return objects
        if ($Script) {
            return $ScriptUserObjects
        }

        # if one user
        if (($ScriptUserObjects | Measure-Object).Count -eq 1) {

            # set objects
            $VariableParams = @{
                Name  = "${VarPrefix}UserObject"
                Value = $ScriptUserObjects | Select-Object -First 1
                Scope = 'Global'
                Force = $true
            }
            New-Variable @VariableParams
            $VariableParams = @{
                Name  = "${VarPrefix}UserObjects"
                Value = $ScriptUserObjects | Select-Object -First 1
                Scope = 'Global'
                Force = $true
            }
            New-Variable @VariableParams
            $VariableParams = @{
                Name  = "${VarPrefix}UserEmail"
                Value = $ScriptUserObjects.UserPrincipalName
                Scope = 'Global'
                Force = $true
            }
            New-Variable @VariableParams
            Write-IRT "Created `$${VarPrefix}UserObject, `$${VarPrefix}UserObjects, and `$${VarPrefix}UserEmail"
        }
        elseif (($ScriptUserObjects | Measure-Object).Count -gt 1) {

            # set objects
            $VariableParams = @{
                Name  = "${VarPrefix}UserObjects"
                Value = @( $ScriptUserObjects )
                Scope = 'Global'
                Force = $true
            }
            New-Variable @VariableParams
            Write-IRT "Created `$${VarPrefix}UserObjects"
            $ScriptUserObjects | Format-Table $DisplayProperties
        }
    }
}


