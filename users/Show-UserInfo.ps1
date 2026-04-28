New-Alias -Name 'ShowUser' -Value 'Show-UserInfo' -Force
New-Alias -Name 'ShowUsers' -Value 'Show-UserInfo' -Force
function Show-UserInfo {
    <#
	.SYNOPSIS
	Displays user properties.

	.NOTES
	Version: 1.2.0
    1.2.0 - Switched to Format-Tree, Show-GraphUserTree
	#>
    [CmdletBinding()]
    param(
        [Parameter( Position = 0 )]
        [Alias('UserObjects')]
        [Microsoft.Graph.PowerShell.Models.MicrosoftGraphUser[]] $UserObject
    )

    begin {

        # if not passed directly, find global user object
        if ( -not $UserObject -or $UserObject.Count -eq 0 ) {

            # get from global variables
            $ScriptUserObjects = Get-IRTUserObject

            # if none found, exit
            if ( -not $ScriptUserObjects -or $ScriptUserObjects.Count -eq 0 ) {
                throw "No user objects passed or found in global variables."
            }
        }
        else {
            $ScriptUserObjects = $UserObject
        }

        # colors
        $Blue = @{ ForegroundColor = 'Blue' }
        # $Cyan = @{ ForegroundColor = 'Cyan' }
        # $Green = @{ ForegroundColor = 'Green' }
        # $Red = @{ ForegroundColor = 'Red' }
        # $Magenta = @{ ForegroundColor = 'Magenta' }
    }

    process {

        # overwrite global $UserObject so we can add the full user objects with all properties
        $Global:IRT_UserObjects = [System.Collections.Generic.List[psobject]]::new()

        foreach ($ScriptUserObject in $ScriptUserObjects) {

            # variables
            $UserEmail = $ScriptUserObject.UserPrincipalName

            # get user object with all possible properties
            Write-Host @Blue "`nGetting full user object."
            $ScriptUserObject = Get-FullUserObject -UserObject $ScriptUserObject

            # copy full user object to global variables
            $Global:IRT_UserObjects.Add($ScriptUserObject)

            Write-Host @Blue "`nShowing user properties for: ${UserEmail}"
            $ScriptUserObject | Show-GraphUserTree | Out-Host

            Write-Host @Blue "`nShowing groups for: ${UserEmail}"
            $UserGroups = Get-MgUserMemberOfAsGroup -UserId $ScriptUserObject.Id
            if ( $UserGroups ) {
                $UserGroups |
                    Sort-Object DisplayName |
                    Format-Table DisplayName,GroupTypes,Mail,Description |
                    Out-Host
            }
            else {
                Write-Host "None" | Out-Host
            }
        }
    }
}


