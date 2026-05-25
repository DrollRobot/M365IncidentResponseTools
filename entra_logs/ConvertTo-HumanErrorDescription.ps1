function ConvertTo-HumanErrorDescription {
    <#
    .SYNOPSIS
    Helper function for Entra sign in logs. Accepts an error code number and returns a human-readable description string.

    .DESCRIPTION
    Looks up an Entra ID (Azure AD) sign-in error code in the bundled entra_error_codes.csv
    data file and returns a formatted string in the form "CODE:Description". The lookup
    table is cached in $Global:IRT_EntraErrorTable after the first call for performance.

    Used internally by Get-SignInLog and Get-NonInteractiveLog to annotate each log row.

    .PARAMETER ErrorCode
    The integer Entra sign-in error code to look up.

    .EXAMPLE
    ConvertTo-HumanErrorDescription -ErrorCode 50076
    Returns '50076:User was required to use multi-factor authentication.'

    .OUTPUTS
    System.String

    .NOTES
    Version: 1.1.0
    1.1.0 - Converted from doing the whole sheet to just one log at a time
    #>
    [OutputType([string])]
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
