function Get-RandomPassword {
    <#
    .SYNOPSIS
    Generates passwords of random characters. Guarantees at least one character of each type so password will meet complexity requirements.

    Usage:
    Get-RandomPassword 10
    Get-RandomPassword -Length 14

    .NOTES
    Version 0.02
    #>
    param (
        [Parameter(Mandatory)]
        [ValidateRange(4,[int]::MaxValue)]
        [int] $Length
    )

    $upperChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ'.ToCharArray()
    $lowerChars = 'abcdefghjkmnpqrstuvwxyz'.ToCharArray()
    $numberChars = '23456789'.ToCharArray()
    $symbolChars = '!#$%&*/?@[]^~+<=>'.ToCharArray()

    # Ensure at least one character from each category
    $upper = $upperChars | Get-Random
    $lower = $lowerChars | Get-Random
    $number = $numberChars | Get-Random
    $symbol = $symbolChars | Get-Random
    $result = @($upper, $lower, $number, $symbol)

    # Calculate the remaining length for random characters
    $length = $length - 4

    # Define the character set for the remaining random characters
    $charSet = $upperChars + $lowerChars + $numberChars + $symbolChars

    # Create an instance of the random number generator
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider

    # generate more characters to fill array
    $bytes = New-Object byte[]($length)
    $rng.GetBytes($bytes)
    for ( $i = 0; $i -lt $length; $i++ ) {
        $result += $charSet[$bytes[$i] % $charSet.Length]
    }

    $result = $result | Get-Random -Count $result.Count

    return ( -join $result )
}