New-Alias -Name 'FindAdUser'  -Value 'Find-AdUser' 
New-Alias -Name 'FindAdUsers' -Value 'Find-AdUser' 
New-Alias -Name 'Find-AdUsers' -Value 'Find-AdUser' 

function Find-AdUser {
    <#
    .SYNOPSIS
    Finds local ad user by DisplayName, Name, UserPrincipalName, ProxyAddresses, SamAccountName. Creates $UserObject variable

    .EXAMPLE
    Find-AdUser flast
    Find-AdUser flast,flast,flast
    Find-AdUser -Search flast@domain.com
    Find-AdUser bf7573a5844f (partial user id number)

    .NOTES
    Version: 1.2.1
    1.2.1 - Fixed bug where script was passing collections of user objects rather than user objects.
    1.2.0 - Major rewrite.
    #>
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
        $Cyan = @{ForegroundColor = 'Cyan'}
        $Red = @{ForegroundColor = 'Red'}
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
                    Write-Host @Cyan "Showing results for search: ${SearchString}"
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
                    Write-Host @Cyan "Showing results for search: ${SearchString}"
                    $MatchingUsers | Format-Table $DisplayProperties
                    Write-Host @Red 'Multiple users found. Refine search.'
                }
            }
            # if no users found
            else {
                if (-not $Script) {
                    Write-Host @Red "$SearchString not found. Try a different search."
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
            Write-Host @Cyan "Created `$${VarPrefix}UserObject, `$${VarPrefix}UserObjects, and `$${VarPrefix}UserEmail"
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
            Write-Host @Cyan "Created `$${VarPrefix}UserObjects"
            $ScriptUserObjects | Format-Table $DisplayProperties
        }        
    }
}


