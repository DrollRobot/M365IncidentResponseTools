function Get-GraphUALRetryDelay {
    <#
    .SYNOPSIS
    Works out how many seconds to wait before retrying a failed Graph request.

    .DESCRIPTION
    Internal helper. Prefers the server's own Retry-After value, first from the response
    header object and then from the message text, because honouring it is both faster and
    politer than guessing. Falls back to exponential backoff from a base delay
    (base, base*2, base*4, ...) when Graph sends no Retry-After, which it often does not.

    The result is capped at one hour so a malformed header cannot park a session
    indefinitely.

    .PARAMETER ErrorRecord
    The error record from the failed request.

    .PARAMETER Attempt
    Which attempt just failed, counting from 1. Drives the exponential fallback.

    .PARAMETER BaseSeconds
    Base delay for the exponential fallback. Default: 30.

    .EXAMPLE
    ```powershell
    $Wait = Get-GraphUALRetryDelay -ErrorRecord $_ -Attempt 2 -BaseSeconds 30
    ```
    Returns the server's Retry-After if present, otherwise 60.

    .OUTPUTS
    [int] seconds to wait.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [System.Management.Automation.ErrorRecord] $ErrorRecord,

        [ValidateRange(1, 100)]
        [int] $Attempt = 1,

        [ValidateRange(1, 3600)]
        [int] $BaseSeconds = 30
    )

    $MaxWait = 3600
    $RetryAfter = $null

    # preferred source: the parsed response header
    try {
        $Delta = $ErrorRecord.Exception.Response.Headers.RetryAfter.Delta
        if ($null -ne $Delta) { $RetryAfter = [int]$Delta.TotalSeconds }
    }
    catch {
        $RetryAfter = $null
    }

    # fallback: some SDK errors only carry the delay in the message text
    if (-not $RetryAfter -and $ErrorRecord) {
        $Message = [string]$ErrorRecord.Exception.Message
        if ($Message -match 'try again (?:in|after)[^0-9]*([0-9]+)\s*second') {
            $RetryAfter = [int]$Matches[1]
        }
    }

    if ($RetryAfter -and $RetryAfter -gt 0) {
        return [Math]::Min($RetryAfter, $MaxWait)
    }

    $Wait = [int]($BaseSeconds * [Math]::Pow(2, $Attempt - 1))
    return [Math]::Min($Wait, $MaxWait)
}
