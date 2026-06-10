function Test-TokenExpired {
    <#
    .SYNOPSIS
    Returns $true if a JWT access token has expired or is within the buffer window of expiry.

    .PARAMETER Token
    The JWT access token string to evaluate.

    .PARAMETER BufferSeconds
    Number of seconds before the actual expiry time to treat the token as expired.
    Defaults to 300 (5 minutes) to avoid using a token that expires mid-operation.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter( Mandatory )]
        [string] $Token,

        [int] $BufferSeconds = 300
    )

    Import-IRTModule -Name 'PSFramework'

    $expiry = Get-TokenExpiry -Token $Token
    if ($null -eq $expiry) {
        Write-PSFMessage -Level 8 -Message (
            'Test-TokenExpired: Could not decode expiry - treating as expired.')
        return $true
    }

    $threshold = [System.DateTime]::UtcNow.AddSeconds($BufferSeconds)
    $expired = $expiry -le $threshold
    $minutesLeft = [int](($expiry - [datetime]::UtcNow).TotalMinutes)
    Write-PSFMessage -Level 8 -Message (
        "Test-TokenExpired: Expiry=$expiry UTC, Buffer=${BufferSeconds}s, " +
        "MinutesLeft=$minutesLeft, Expired=$expired")
    return $expired
}
