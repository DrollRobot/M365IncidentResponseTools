function Get-GraphUALErrorStatus {
    <#
    .SYNOPSIS
    Extracts a short HTTP status name from a Graph SDK exception message.

    .DESCRIPTION
    Internal helper. The Graph PowerShell SDK reports failures in two shapes, and folds
    its own internal retries into one very long message. A throttled request can arrive
    as several hundred characters containing four copies of the same JSON error body.
    This reduces either shape to a single status token so callers can branch on it and
    log something readable.

    Recognised shapes:
        "... status code: TooManyRequests.{"error":{...}}"
        "Response status code does not indicate success: InternalServerError (...)"

    Returns 'Unknown' when neither shape matches.

    .PARAMETER Message
    The exception message to parse.

    .EXAMPLE
    ```powershell
    Get-GraphUALErrorStatus -Message $_.Exception.Message
    ```
    Returns a token such as 'TooManyRequests' or 'InternalServerError'.

    .OUTPUTS
    [string] a status name such as 'TooManyRequests', or 'Unknown'.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $Message
    )

    if (-not $Message) { return 'Unknown' }
    if ($Message -match 'status code:\s*([A-Za-z]+)') { return $Matches[1] }
    if ($Message -match 'does not indicate success:\s*([A-Za-z]+)') { return $Matches[1] }
    return 'Unknown'
}
