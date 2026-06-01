function Show-GraphUserTree {
    <#
	.SYNOPSIS
	Shows a graph user object in a compact tree view.

	.NOTES
	Version: 1.0.5
	#>
    [CmdletBinding()]
    param(
        # accept object(s) from pipeline or parameter
        [Parameter(ValueFromPipeline)]
        [Alias('UserObjects')]
        [Microsoft.Graph.PowerShell.Models.MicrosoftGraphUser[]] $UserObject,

        [int]$Depth = 10
    )

    begin {
        # list of user properties to exclude
        $Exclude = @(
            'AllProperties'
            'AssignedPlans',
            'Drive',
            'ProvisionedPlans',
            'AdditionalProperties',
            'LicenseAssignmentStates'
        )
    }

    process {

        $ScriptUserObjects = $UserObject
        foreach ($ScriptUserObject in $ScriptUserObjects) {
            if ($null -eq $ScriptUserObject) { continue }

            # create a pscustomobject projection so we can safely tweak values
            $Projected = $ScriptUserObject | Select-Object -Property * -ExcludeProperty $Exclude
            Format-SentinelDate $Projected

            # call format-tree with defaults; always omit null/empty
            $Params = @{
                Depth        = $Depth
                OmitNullOrEmpty = $true
            }
            $Projected | Format-Tree @Params
        }
    }
}
