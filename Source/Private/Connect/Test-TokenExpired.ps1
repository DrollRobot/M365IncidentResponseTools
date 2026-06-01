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

    $expiry = Get-TokenExpiry -Token $Token
    if ($null -eq $expiry) { return $true }

    $threshold = [System.DateTime]::UtcNow.AddSeconds($BufferSeconds)
    return $expiry -le $threshold
}
