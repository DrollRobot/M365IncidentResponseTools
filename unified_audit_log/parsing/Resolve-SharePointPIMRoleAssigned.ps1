function Resolve-SharePointPIMRoleAssigned {
    <#
	.SYNOPSIS
    Parses Sharepoint "PIMRoleAssigned" events from UAL.
	
	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [psobject] $Log
    )

    begin {

        # variables
        $SummaryLines = [System.Collections.Generic.List[string]]::new()

        $Users = Request-GraphUsers
    }

    process {

        # User 
        $GuidPattern = "\b[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\b"
        $UserId = $Log.AuditData.EventData | Select-String -Pattern $GuidPattern -AllMatches | ForEach-Object { $_.Matches.Value }
        $UserPrincipalName = ($Users | Where-Object {$_.Id -eq $UserId}).UserPrincipalName
        $SummaryLines.Add("User: ${UserPrincipalName}")

        # Role
        $ModifiedPropertiesDict = $Log.AuditData.ModifiedProperties
        $OldValue = ($ModifiedPropertiesDict | Where-Object {$_.Name -eq 'PIMRoleAssigned'}).OldValue
        $NewValue = ($ModifiedPropertiesDict | Where-Object {$_.Name -eq 'PIMRoleAssigned'}).NewValue
        if ($NewValue -and $OldValue) {
            $Role = "New: ${NewValue}, Old: ${OldValue}"
        }
        else {
            if ($OldValue) {
                $Role = $OldValue
            }
            if ($NewValue) {
                $Role = $NewValue
            }
        }
        $SummaryLines.Add("Role: ${Role}")

        # join strings, create return object
        $Summary = $SummaryLines -join "`n"
        $EventObject = [pscustomobject]@{
            Summary = $Summary
        }

        return $EventObject
    }
}