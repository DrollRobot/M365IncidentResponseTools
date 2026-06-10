function Get-UnknownObject {
    <#
	.SYNOPSIS
	Looks up an object by Id using cached ById hashtables.
	Falls back to Get-MgDirectoryObject if not found in cache.

	.NOTES
	Version: 2.0.0
    2.0.0 - Rewrote to use Request-* cached ById hashtables instead of direct Graph calls.
	#>
    [CmdletBinding()]
    param(
        [string] $Id
    )

    begin {
        Import-IRTModule -Name 'Microsoft.Graph.DirectoryObjects'
    }

    process {

        # try cached lookups first
        if ( $Global:IRT_UsersById -and $Global:IRT_UsersById.ContainsKey($Id) ) {
            $Obj = $Global:IRT_UsersById[$Id]
            $Obj | Add-Member -NotePropertyName 'ObjectType' -NotePropertyValue 'User' -Force
            return $Obj
        }
        if ( $Global:IRT_GroupsById -and $Global:IRT_GroupsById.ContainsKey($Id) ) {
            $Obj = $Global:IRT_GroupsById[$Id]
            $Obj | Add-Member -NotePropertyName 'ObjectType' -NotePropertyValue 'Group' -Force
            return $Obj
        }
        if ($Global:IRT_ServicePrincipalsById -and
            $Global:IRT_ServicePrincipalsById.ContainsKey($Id)
        ) {
            $Obj = $Global:IRT_ServicePrincipalsById[$Id]
            $AmSpParams = @{
                NotePropertyName  = 'ObjectType'
                NotePropertyValue = 'ServicePrincipal'
                Force             = $true
            }
            $Obj | Add-Member @AmSpParams
            return $Obj
        }

        # fallback to direct Graph lookup
        try {
            $DirectoryObject = Get-MgDirectoryObject -DirectoryObjectId $Id -ErrorAction Stop
            $AmUnkParams = @{
                NotePropertyName  = 'ObjectType'
                NotePropertyValue = 'Unknown'
                Force             = $true
            }
            $DirectoryObject | Add-Member @AmUnkParams
            return $DirectoryObject
        }
        catch {
            Write-Error "Unable to find object with Id: ${Id}"
        }
    }
}
