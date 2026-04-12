function Convert-DecimalToExcelColumn {
	<#
	.SYNOPSIS
	Takes a number and returns an Excel column letter value.

    .EXAMPLE
    1 | Convert-DecimalToExcelColumn
    A

    26 | Convert-DecimalToExcelColumn
    Z

    27 | Convert-DecimalToExcelColumn
    AA

    28 | Convert-DecimalToExcelColumn
	AB
	
	.NOTES
	Version: 1.0.1
    1.0.1 - Fixed type casting error preventing script from working correctly for 27+.
	#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [ValidateRange(1, [int]::MaxValue)]
        [int] $Number
    )

    # initialize result variable
    $ColumnLetters = [System.Collections.Generic.List[char]]::new()

    while ( $Number -gt 0 ) {

        # divide by 26
        [int]$Remainder = ($Number - 1) % 26

        # determine the corresponding letter (a=0 maps to A)
        $Letter = [char]([int][char]'A' + $Remainder)

        # prepend the letter to the result string
        $ColumnLetters.Insert(0,$Letter)

        # update the number for next iteration
        $Number = [int][math]::Floor(($Number - 1) / 26)
    }

    return ($ColumnLetters -join '')
}

<#

# testing:
$Output = [System.Collections.Generic.List[String]]::new()
$Output.Add((20 | Convert-DecimalToExcelColumn))
$Output.Add((5 | Convert-DecimalToExcelColumn))
$Output.Add((514 | Convert-DecimalToExcelColumn))
$Output.Add(' ')
$Output.Add((417 | Convert-DecimalToExcelColumn))
$Output.Add((19 | Convert-DecimalToExcelColumn))
$Output.Add((12978 | Convert-DecimalToExcelColumn))
$Output -join ''

#>