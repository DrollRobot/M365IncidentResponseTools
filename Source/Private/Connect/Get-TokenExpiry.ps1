function Get-TokenExpiry {
    <#
    .SYNOPSIS
    Returns the UTC expiry time from a JWT access token's exp claim, or $null if unreadable.

    .PARAMETER Token
    The JWT access token string to decode.
    #>
    [CmdletBinding()]
    [OutputType([datetime])]
    param (
        [Parameter(Mandatory)]
        [string] $Token
    )

    try {
        $parts = $Token.Split('.')
        if ($parts.Count -lt 2) { return $null }

        # Base64url decode the payload segment (second part of the JWT)
        $payload = $parts[1]
        $padded = $payload.Replace('-', '+').Replace('_', '/')
        switch ($padded.Length % 4) {
            2 { $padded += '==' }
            3 { $padded += '=' }
        }

        $bytes = [System.Convert]::FromBase64String($padded)
        $json = [System.Text.Encoding]::UTF8.GetString($bytes)
        $claims = $json | ConvertFrom-Json

        if (-not $claims.exp) { return $null }

        return [System.DateTimeOffset]::FromUnixTimeSeconds([long]$claims.exp).UtcDateTime
    }
    catch {
        return $null
    }
}
