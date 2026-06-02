function Get-TokenPayload {
    <#
    .SYNOPSIS
    Decodes a JWT access token's payload (claims) and returns it as an object, or $null
    if the token cannot be decoded.

    .DESCRIPTION
    Splits the JWT, base64url-decodes the payload segment, and parses it as JSON. Useful
    for reading claims such as 'aud' (audience) and 'exp' without contacting the issuer.
    Returns $null on any failure rather than throwing.

    .PARAMETER Token
    The JWT access token string to decode.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [string] $Token
    )

    try {
        $parts = $Token.Split('.')
        if ($parts.Count -lt 2) { return $null }

        # Base64url decode the payload segment (second part of the JWT)
        $payload = $parts[1].Replace('-', '+').Replace('_', '/')
        switch ($payload.Length % 4) {
            2 { $payload += '==' }
            3 { $payload += '=' }
        }

        $bytes = [System.Convert]::FromBase64String($payload)
        [System.Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
    }
    catch {
        return $null
    }
}