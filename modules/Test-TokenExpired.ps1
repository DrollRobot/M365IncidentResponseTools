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

    try {
        $parts = $Token.Split('.')
        if ($parts.Count -lt 2) { return $true }

        # Base64url decode the payload segment (second part of the JWT)
        $payload = $parts[1]
        $padded  = $payload.Replace('-', '+').Replace('_', '/')
        switch ($padded.Length % 4) {
            2 { $padded += '==' }
            3 { $padded += '='  }
        }

        $json   = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($padded))
        $claims = $json | ConvertFrom-Json

        if (-not $claims.exp) { return $true }

        $expiry    = [System.DateTimeOffset]::FromUnixTimeSeconds([long]$claims.exp).UtcDateTime
        $threshold = [System.DateTime]::UtcNow.AddSeconds($BufferSeconds)

        return $expiry -le $threshold
    }
    catch {
        # If the token cannot be decoded, treat it as expired to force re-acquisition
        return $true
    }
}
