function Build-TraceContinuation {
    # helper: parse continuation Hints from the cmdlet's Warning text
    param([string]$WarningText)

    $cmdText = [regex]::Match($WarningText, 'Get-MessageTraceV2\s.+').Value
    if (-not $cmdText) { return $null }

    $next = @{}

    $sd = [regex]::Match($cmdText, '-StartDate\s+"([^"]+)"').Groups[1].Value
    $ed = [regex]::Match($cmdText, '-EndDate\s+"([^"]+)"').Groups[1].Value
    if ($sd) { $next['StartDate'] = [datetime]$sd }
    if ($ed) { $next['EndDate'] = [datetime]$ed }

    # capture any -starting* param (eg, -StartingRecipientAddress)
    $startMatch = [regex]::Match($cmdText, '-(Starting\w+)\s+"([^"]+)"')
    if ($startMatch.Success) {
        $paramName = $startMatch.Groups[1].Value
        $paramValue = $startMatch.Groups[2].Value
        $next[$paramName] = $paramValue
    }

    if ($next.Count -eq 0) { return $null }
    return $next
}
