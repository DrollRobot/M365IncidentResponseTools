function Resolve-DateInput {
    <#
    .SYNOPSIS
    Parses an absolute or relative date/time string into a UTC DateTime.

    .DESCRIPTION
    Accepts the same absolute formats as Get-Date, plus relative expressions such as
    '6 hours ago', '3 days ago', '90 minutes ago', and '2 weeks ago', as well as the
    keywords 'now', 'today', and 'yesterday'. Relative and keyword inputs are computed
    from the current local time; absolute inputs are interpreted as local wall-clock
    time. The result is always returned in UTC.

    PowerShell's Get-Date does not understand relative phrases like '3 days ago', so
    this helper layers a small parser on top of it. The 'ago' suffix is optional, so
    '3 days' is treated the same as '3 days ago'.

    Supported units (singular, plural, and common abbreviations): seconds, minutes,
    hours, days, weeks, months, years.

    .PARAMETER InputString
    The date/time text to parse.

    .EXAMPLE
    Resolve-DateInput -InputString '6 hours ago'
    Returns the UTC DateTime six hours before now.

    .EXAMPLE
    Resolve-DateInput -InputString '5/28/26 17:00'
    Returns the UTC equivalent of the local date/time.

    .OUTPUTS
    System.DateTime in UTC. Throws on unparseable input.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [Parameter(Mandatory)]
        [string] $InputString
    )

    $Text = $InputString.Trim()
    if (-not $Text) {
        throw 'Resolve-DateInput: empty input.'
    }

    $Lower = $Text.ToLower()

    # keyword shortcuts
    switch ($Lower) {
        'now' { return (Get-Date).ToUniversalTime() }
        'today' { return (Get-Date).Date.ToUniversalTime() }
        'yesterday' { return (Get-Date).Date.AddDays(-1).ToUniversalTime() }
    }

    # relative expression: "<number> <unit> [ago]"
    $Match = [regex]::Match($Lower, '^(\d+)\s*([a-z]+)\s*(ago)?$')
    if ($Match.Success) {
        $Amount = [int] $Match.Groups[1].Value
        $Unit = $Match.Groups[2].Value
        $Now = Get-Date

        $Local = switch -Regex ($Unit) {
            '^(second|seconds|sec|secs)$' { $Now.AddSeconds(-$Amount) }
            '^(minute|minutes|min|mins)$' { $Now.AddMinutes(-$Amount) }
            '^(hour|hours|hr|hrs|h)$' { $Now.AddHours(-$Amount) }
            '^(day|days|d)$' { $Now.AddDays(-$Amount) }
            '^(week|weeks|wk|wks|w)$' { $Now.AddDays(-7 * $Amount) }
            '^(month|months|mo|mos)$' { $Now.AddMonths(-$Amount) }
            '^(year|years|yr|yrs|y)$' { $Now.AddYears(-$Amount) }
            default { $null }
        }

        if ($null -ne $Local) {
            return $Local.ToUniversalTime()
        }
        throw "Resolve-DateInput: unrecognized time unit '$Unit'."
    }

    # fall back to absolute parsing via Get-Date (local wall-clock -> UTC)
    try {
        $Parsed = Get-Date -Date $Text -ErrorAction Stop
        return [DateTime]::SpecifyKind($Parsed, [DateTimeKind]::Local).ToUniversalTime()
    }
    catch {
        throw "Resolve-DateInput: could not parse '$InputString' as a date."
    }
}
