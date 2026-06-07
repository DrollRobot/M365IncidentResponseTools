function ConvertTo-TimeSpan {
    <#
    .SYNOPSIS
    Parses a human duration string such as '3 hours' or '5 days' into a TimeSpan.

    .DESCRIPTION
    Converts a relative duration expression into a [timespan]. The input is a number
    followed by a unit, for example '3 hours', '5 days', '90 minutes', or '2 weeks'.
    A trailing 'ago' is tolerated but not required.

    Supported units (singular, plural, and common abbreviations): seconds, minutes,
    hours, days, weeks. Months and years are not supported because they do not map to
    a fixed-length TimeSpan; use days or an absolute date instead.

    This is the relative-duration counterpart to Get-Date, which only understands
    absolute date/time formats.

    .PARAMETER InputString
    The duration text to parse, e.g. '3 hours' or '5 days'.

    .EXAMPLE
    ConvertTo-TimeSpan -InputString '3 hours'
    Returns a TimeSpan of 3 hours.

    .EXAMPLE
    ConvertTo-TimeSpan -InputString '5 days'
    Returns a TimeSpan of 5 days.

    .OUTPUTS
    System.TimeSpan. Throws on unparseable input.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    [OutputType([timespan])]
    param(
        [Parameter(Mandatory)]
        [string] $InputString
    )

    $Text = $InputString.Trim().ToLower()
    if (-not $Text) {
        throw 'ConvertTo-TimeSpan: empty input.'
    }

    # "<number> <unit>" with an optional, ignored trailing 'ago'
    $Match = [regex]::Match($Text, '^(\d+)\s*([a-z]+)\s*(ago)?$')
    if (-not $Match.Success) {
        throw "Could not parse '$InputString'. Use e.g. '3 hours' or '5 days'."
    }

    $Amount = [int] $Match.Groups[1].Value
    $Unit = $Match.Groups[2].Value

    $Span = switch -Regex ($Unit) {
        '^(second|seconds|sec|secs)$' { [timespan]::FromSeconds($Amount) }
        '^(minute|minutes|min|mins)$' { [timespan]::FromMinutes($Amount) }
        '^(hour|hours|hr|hrs|h)$' { [timespan]::FromHours($Amount) }
        '^(day|days|d)$' { [timespan]::FromDays($Amount) }
        '^(week|weeks|wk|wks|w)$' { [timespan]::FromDays(7 * $Amount) }
        default { $null }
    }

    if ($null -eq $Span) {
        throw "Unrecognized unit '$Unit'. Use seconds/minutes/hours/days/weeks."
    }

    return $Span
}
