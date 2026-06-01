function Resolve-DateRange {
    <#
	.SYNOPSIS
    Validates and resolves date range parameters into a standardized object.

    .DESCRIPTION
    Accepts either a relative range (-Days) or an absolute range (-Start and -End).
    Validates inputs, parses date strings, converts to UTC, and returns a structured
    object with all values needed to build API filter strings and display output.

    Pass -DefaultDays to specify the fallback used when the user provides no date
    arguments. This is handled internally so that the raw -Days value reflects only
    what the user explicitly passed, keeping validation correct.

    .OUTPUTS
    [pscustomobject] with properties:
        RangeType   - 'Relative' or 'Absolute'
        Days        - int: user-specified relative value, or ceiling of absolute span
        StartUtc    - [datetime] UTC start
        EndUtc      - [datetime] UTC end
        StartString - string formatted as "yyyy-MM-ddTHH:mm:ssZ" for API filters
        EndString   - string formatted as "yyyy-MM-ddTHH:mm:ssZ" for API filters

	.NOTES
	Version: 1.1.0
	#>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [int]    $Days,
        [string] $Start,
        [string] $End,
        [int]    $DefaultDays
    )

    # validate mutual exclusivity: -Days cannot be combined with -Start or -End
    if ($Days -and ($Start -or $End)) {
        $ErrorParams = @{
            Category    = 'InvalidArgument'
            Message     = 'Choose either relative range with -Days ' +
            'or absolute range with -Start and -End.'
            ErrorAction = 'Stop'
        }
        Write-Error @ErrorParams
    }

    # validate both-or-neither: -Start and -End must be used together
    if (($Start -and -not $End) -or ($End -and -not $Start)) {
        $ErrorParams = @{
            Category    = 'InvalidArgument'
            Message     = "Specify both -Start and -End."
            ErrorAction = 'Stop'
        }
        Write-Error @ErrorParams
    }

    if ($Start -and $End) {

        # absolute range
        $RangeType = 'Absolute'

        # parse start date
        try {
            $StartDate = Get-Date -Date $Start -ErrorAction 'Stop'
            $StartUtc = [DateTime]::SpecifyKind($StartDate, [DateTimeKind]::Local).ToUniversalTime()
        }
        catch {
            $ErrorParams = @{
                Category    = 'InvalidArgument'
                Message     = "-Start invalid. Use format 'MM/dd/yy hh:mm(tt)'"
                ErrorAction = 'Stop'
            }
            Write-Error @ErrorParams
        }

        # parse end date
        try {
            $EndDate = Get-Date -Date $End -ErrorAction 'Stop'
            $EndUtc = [DateTime]::SpecifyKind($EndDate, [DateTimeKind]::Local).ToUniversalTime()
        }
        catch {
            $ErrorParams = @{
                Category    = 'InvalidArgument'
                Message     = "-End invalid. Use format 'MM/dd/yy hh:mm(tt)'"
                ErrorAction = 'Stop'
            }
            Write-Error @ErrorParams
        }

        # ensure start is before end
        if ($StartUtc -gt $EndUtc) {
            $Temp = $StartUtc
            $StartUtc = $EndUtc
            $EndUtc = $Temp
            # also swap local dates so Days calculation is correct
            $Temp = $StartDate
            $StartDate = $EndDate
            $EndDate = $Temp
        }

        # calculate days from absolute range
        $Days = [Int]([Math]::Ceiling(($EndDate - $StartDate).TotalDays))
    }
    else {

        # relative range - apply default if user did not specify -Days
        $RangeType = 'Relative'
        if (-not $Days) {
            $Days = $DefaultDays
        }
        $StartUtc = (Get-Date).AddDays($Days * -1).ToUniversalTime()
        $EndUtc = (Get-Date).ToUniversalTime()
    }

    [pscustomobject]@{
        RangeType   = $RangeType
        Days        = $Days
        StartUtc    = $StartUtc
        EndUtc      = $EndUtc
        StartString = $StartUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
        EndString   = $EndUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
}
