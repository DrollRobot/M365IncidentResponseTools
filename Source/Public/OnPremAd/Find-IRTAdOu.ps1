function Find-IRTAdOu {
    <#
    .SYNOPSIS
    Makes finding specific OUs easier.

    .DESCRIPTION
    Searches all Active Directory Organizational Units for entries matching the -Search
    string. The search is applied against Name (regex), CanonicalName (exact), and
    DistinguishedName (exact). If exactly one match is found it is stored in
    $Global:OuObject and displayed; multiple or zero results produce a warning.

    .PARAMETER Search
    String to search for. Tested as a regex against Name and as an exact match against
    CanonicalName and DistinguishedName.

    .PARAMETER Script
    Return the matching OU object directly instead of printing it and setting the global
    variable. Useful when calling from scripts.

    .EXAMPLE
    Find-IRTAdOu 'Workstations'
    Finds all OUs with 'Workstations' in their name and sets $Global:OuObject if exactly one match.

    .EXAMPLE
    $Ou = Find-IRTAdOu -Search 'contoso.com/Workstations' -Script
    Returns the OU object directly for use in a script.

    .OUTPUTS
    None by default (sets $Global:OuObject and writes to console).
    Microsoft.ActiveDirectory.Management.ADOrganizationalUnit when -Script is used.

    .NOTES
    Version: 1.0.0
    #>
    [Alias(
        'Find-IRTAdOus',
        'Find-AdOu', 'Find-AdOus',
        'FindIRTAdOu', 'FindIRTAdOus',
        'FindAdOu', 'FindAdOus'
    )]
    [CmdletBinding()]
    param (
        [Parameter( Position = 0, Mandatory )]
        [string] $Search,
        [switch] $Script
    )

    begin {
        $Properties = @(
            'Name'
            'CanonicalName'
            'DistinguishedName'
        )
    }

    process {

        if ( -not ( Test-AdAvailable ) ) {
            Write-Error 'ActiveDirectory RSAT module not available.'
            return
        }

        # find users whos displayname or email matches search
        $Ous = Get-ADOrganizationalUnit -Filter * -Properties $Properties

        # find matching ous
        $MatchingOus = $Ous | Where-Object {
            $_.Name -match $Search -or
            $_.CanonicalName -eq $Search -or
            $_.DistinguishedName -eq $Search
        }

        # if one ou found
        if (@($MatchingOus).Count -eq 1) {
            if ($Script) {
                # return object
                return $MatchingOus
            }
            else {

                # show ou info
                $MatchingOus | Format-Table $Properties

                # set variable
                New-Variable -Name "OuObject" -Value $MatchingOus -Scope 'Global'
                Write-IRT "Created `$Global:OuObject."
            }
        }
        # if multiple ous found
        elseif (@($MatchingOus).Count -gt 1) {
            if ($Script) {

                # show ou info
                $MatchingOus | Format-Table $Properties | Out-Default

                # tell user to try again
                Write-IRT 'Multiple Ous found. Search again.' -Level Error
            }
            else {

                # show ou info
                $MatchingOus | Format-Table $Properties

                # tell user to try again
                Write-IRT 'Multiple Ous found. Search again.' -Level Error
            }
        }
        # if no users found, tell user to search again
        else {
            if ($Script) {
                # tell user to try again
                Write-IRT "$Search not found. Try a different search." -Level Error
            }
            else {
                # tell user to try again
                Write-IRT "$Search not found. Try a different search." -Level Error
            }
        }
    }
}
