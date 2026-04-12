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
        [Alias('UserObject')]
        [Microsoft.Graph.PowerShell.Models.MicrosoftGraphUser[]] $UserObjects,

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

        $ScriptUserObjects = $UserObjects
        foreach ($ScriptUserObject in $ScriptUserObjects) {
            if ($null -eq $ScriptUserObject) { continue }

            # create a pscustomobject projection so we can safely tweak values
            $Projected = $ScriptUserObject | Select-Object -Property * -ExcludeProperty $Exclude
            Format-SentinelDates $Projected

            # call format-tree with defaults; always omit null/empty
            $Params = @{
                Depth        = $Depth
                OmitNullOrEmpty = $true
            }
            $Projected | Format-Tree @Params
        }
    }
}

function Format-SentinelDates([pscustomobject]$Obj) {
    # helper: normalize sentinel dates (year 1) to $null
    foreach ($Name in 'Birthday','HireDate') {
        $Prop = $Obj.PSObject.Properties[$Name]
        if (-not $Prop) { continue }
        $Value = $Prop.Value
        $IsEmptyDate = $false

        if ($Value -is [datetime]) {
            if ($Value.Year -le 1) { $IsEmptyDate = $true }
        } elseif ($Value) {
            try {
                $dt = [datetime]::Parse($Value)
                if ($dt.Year -le 1) { $IsEmptyDate = $true }
            } catch { }
        }

        if ($IsEmptyDate) { $Obj.$Name = $null }
    }
}