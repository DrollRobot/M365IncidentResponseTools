function Format-PhoneNumber {
    <#
    .SYNOPSIS
    Formats a phone number for Excel compatibility by removing the leading '+'.

    .DESCRIPTION
    Converts Graph API phone number format (+1 1234567890) to an Excel-safe format.
    US/CA numbers (+1): 123-456-7890
    Other country codes: 44 123-456-7890

    .EXAMPLE
    Format-PhoneNumber '+1 1234567890'
    123-456-7890

    .EXAMPLE
    Format-PhoneNumber '+44 1234567890'
    44 123-456-7890

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter( Mandatory, Position = 0, ValueFromPipeline )]
        [string] $PhoneNumber
    )

    process {
        if ( $PhoneNumber -match '^\+(\d+)\s+(\d{3})(\d{3})(\d{4})$' ) {
            if ( $Matches[1] -eq '1' ) {
                # US/CA: 123-456-7890
                return "$($Matches[2])-$($Matches[3])-$($Matches[4])"
            }
            else {
                # other country codes: 44 123-456-7890
                return "$($Matches[1]) $($Matches[2])-$($Matches[3])-$($Matches[4])"
            }
        }

        return $PhoneNumber
    }
}
