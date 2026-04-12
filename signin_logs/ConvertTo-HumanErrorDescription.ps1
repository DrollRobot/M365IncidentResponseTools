function ConvertTo-HumanErrorDescription {
	<#
	.SYNOPSIS
	Helper function for Entra sign in logs. Accepts number, returns "N:DESCRIPTION".
	
	.NOTES
	Version: 1.1.0
    1.1.0 - Converted from doing the whole sheet to just one log at a time
	#>
    [CmdletBinding()]
    param (
        [int] $ErrorCode
    )

    begin {

        # variables
        $ModuleRoot = $MyInvocation.MyCommand.Module.ModuleBase
        $CsvPath = Join-Path $ModuleRoot -ChildPath "data\entra_error_codes.csv"

        # import csv table
        if (($Global:IRT_EntraErrorTable.Keys | Measure-Object).Count -eq 0) {
            $Csv = Import-Csv -Path $CsvPath
            $Global:IRT_EntraErrorTable = @{}
            foreach ($Row in $Csv) {
                $Global:IRT_EntraErrorTable[[int]$Row.Error] = $Row
            }
        }
	}

    process {

        if ($Global:IRT_EntraErrorTable.ContainsKey($ErrorCode)) {
            # get row from table
            $Row = $Global:IRT_EntraErrorTable[$ErrorCode]
            # pick best description, if present
            $Description = if (-not [string]::IsNullOrWhiteSpace($Row.CustomDescription)) {
                $Row.CustomDescription
            }
            elseif (-not [string]::IsNullOrWhiteSpace($Row.ShortDescription)) {
                $Row.ShortDescription
            }
            # if there's a description return code:description string, if not, just the code
            if ($Description) {
                return "${ErrorCode}:${Description}"
            }
            else {
                return "$ErrorCode"
            }
        }
        else {
            return "$ErrorCode"
        }
    }
}