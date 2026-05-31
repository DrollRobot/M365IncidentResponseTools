function Show-IRTUser {
    <#
    .SYNOPSIS
    Displays user properties.

    .DESCRIPTION
    Retrieves the full Graph user object (all available properties) and displays it as a
    formatted tree in the console. Also updates $Global:IRT_UserObjects with the enriched
    object so downstream playbook steps receive complete data.

    Falls back to $Global:IRT_UserObjects if no -UserObject is passed.

    .PARAMETER UserObject
    One or more Microsoft Graph user objects to display. Falls back to global session
    objects if omitted.

    .EXAMPLE
    Show-IRTUser
    Displays info for the user stored in the global session.

    .EXAMPLE
    Show-IRTUser -UserObject $User
    Displays info for a specific user object.

    .OUTPUTS
    None. Output is written to the console.

    .NOTES
    Version: 1.2.0
    1.2.0 - Switched to Format-Tree, Show-GraphUserTree
    #>
    [Alias(
        'Show-IRTUsers',
        'Show-User', 'Show-Users',
        'ShowIRTUser', 'ShowIRTUsers',
        'ShowUser', 'ShowUsers'
    )]
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [Microsoft.Graph.PowerShell.Models.MicrosoftGraphUser[]] $UserObject
    )

    begin {
        Update-IRTToken -Service 'Graph'
        # if not passed directly, find global user object
        if ( -not $UserObject -or $UserObject.Count -eq 0 ) {

            # get from global variables
            $ScriptUserObjects = Get-GlobalUserObject

            # if none found, exit
            if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                throw "No user objects passed or found in global variables."
            }
        }
        else {
            $ScriptUserObjects = $UserObject
        }
    }

    process {

        # overwrite global $UserObject so we can add the full user objects with all properties
        $Global:IRT_UserObjects = [System.Collections.Generic.List[psobject]]::new()

        foreach ($ScriptUserObject in $ScriptUserObjects) {

            # variables
            $UserEmail = $ScriptUserObject.UserPrincipalName

            # get user object with all possible properties
            Write-IRT "Getting full user object."
            $ScriptUserObject = Get-FullUserObject -UserObject $ScriptUserObject

            # copy full user object to global variables
            $Global:IRT_UserObjects.Add($ScriptUserObject)

            Write-IRT "Showing user properties for: ${UserEmail}"
            $ScriptUserObject | Show-GraphUserTree | Out-Host

            Write-IRT "Showing groups for: ${UserEmail}"
            $UserGroups = Get-MgUserMemberOfAsGroup -UserId $ScriptUserObject.Id
            if ( $UserGroups ) {
                $UserGroups |
                    Sort-Object DisplayName |
                    Format-Table DisplayName, GroupTypes, Mail, Description |
                    Out-Host
            }
            else {
                Write-Host "None" | Out-Host
            }
        }
    }
}