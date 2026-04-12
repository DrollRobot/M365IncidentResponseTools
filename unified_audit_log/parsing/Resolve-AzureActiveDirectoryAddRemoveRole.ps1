function Resolve-AzureActiveDirectoryAddRemoveRole {
    <#
	.SYNOPSIS
    Parses AzureActiveDirectory "Remove member from role." and "Add member to role." events from UAL.
	
	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
        [Parameter( Mandatory )]
        [psobject] $Log
    )

    begin {

        # variables
        $SummaryLines = [System.Collections.Generic.List[string]]::new()
    }

    process {

        # Target
        $TargetDictionary = $Log.AuditData.Target
        $Target = ($TargetDictionary | Where-Object {$_.Type -eq 5}).ID
        $SummaryLines.Add("Target: ${Target}")

        # Role
        $ModifiedPropertiesDict = $Log.AuditData.ModifiedProperties
        if ($ModifiedPropertiesDict.Name -contains 'Role.DisplayName') {
            $OldValue = ($ModifiedPropertiesDict | Where-Object {$_.Name -eq 'Role.DisplayName'}).OldValue
            $NewValue = ($ModifiedPropertiesDict | Where-Object {$_.Name -eq 'Role.DisplayName'}).NewValue
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
            $SummaryLines.Add("Role.DisplayName: ${Role}")
        }
        else {
            $Role = ($ModifiedPropertiesDict | Where-Object {$_.Name -eq 'Role.TemplateId'}).OldValue
            $SummaryLines.Add("Role.TemplateId: ${Role}")
        }

        # join strings, create return object
        $Summary = $SummaryLines -join "`n"
        $EventObject = [pscustomobject]@{
            Summary = $Summary
        }

        return $EventObject
    }
}