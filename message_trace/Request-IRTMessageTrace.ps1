function Build-TraceContinuation {
    # helper: parse continuation Hints from the cmdlet's Warning text
    param([string]$WarningText)

    $cmdText = [regex]::Match($WarningText, 'Get-MessageTraceV2\s.+').Value
    if (-not $cmdText) { return $null }

    $next = @{}

    $sd = [regex]::Match($cmdText, '-StartDate\s+"([^"]+)"').Groups[1].Value
    $ed = [regex]::Match($cmdText, '-EndDate\s+"([^"]+)"').Groups[1].Value
    if ($sd) { $next['StartDate'] = [datetime]$sd }
    if ($ed) { $next['EndDate']   = [datetime]$ed }

    # capture any -starting* param (eg, -StartingRecipientAddress)
    $startMatch = [regex]::Match($cmdText, '-(Starting\w+)\s+"([^"]+)"')
    if ($startMatch.Success) {
        $paramName  = $startMatch.Groups[1].Value
        $paramValue = $startMatch.Groups[2].Value
        $next[$paramName] = $paramValue
    }

    if ($next.Count -eq 0) { return $null }
    return $next
}

function Request-IRTMessageTrace {
    [CmdletBinding()]
    param(
        [string[]] $SenderAddress,
        [string[]] $RecipientAddress,

        # #FIXME convert to start and end dates
        # [datetime] $StartDateUtc,
        # [datetime] $EndDateUtc,

        [Parameter(Mandatory)]
        [ValidateRange(1,90)]
        [int] $Days,

        [int] $ResultLimit = 50000,
        [switch] $Quiet
    )

    begin {

        #region BEGIN
        $Function = $MyInvocation.MyCommand.Name
        $MaxPageSize = 5000
        $AbsoluteEnd   = Get-Date
        $AbsoluteStart = $AbsoluteEnd.AddDays(-1 * $Days)
        $AllMessages = [System.Collections.Generic.List[psobject]]::new()

        # colors
        $Blue = @{ForegroundColor = 'Blue'}
        # $Green = @{ForegroundColor = 'Green'}
        # $Magenta = @{ForegroundColor = 'Magenta'}
        $Red = @{ForegroundColor = 'Red'}
        $Yellow = @{ForegroundColor = 'Yellow'}

        # # adjust start date if older than 90 days.
        # $90DaysAgo = (Get-Date).AddDays(-90).ToUniversalTime()
        # if ($StartDateUtc -lt $90DaysAgo) {
        #     $DateString = $StartDateUtc.ToLocalTime().ToString('MM/dd/yy hh:mmtt')
        #     Write-Host @Yellow "${Function}: ${DateString} is more than max range of 90 days. Setting to 90 days."
        #     $StartDateUtc = $90DaysAgo
        # }

        # build non-overlapping 10-day chunks, newest to oldest
        $Chunks = [System.Collections.Generic.List[object]]::new()
        $ChunkEnd = $AbsoluteEnd
        while ($ChunkEnd -gt $AbsoluteStart) {
            $ChunkStart = $ChunkEnd.AddDays(-10)
            if ($ChunkStart -lt $AbsoluteStart) {
                $ChunkStart = $AbsoluteStart
            }
            $Chunks.Add(
                [pscustomobject]@{
                    Start = $ChunkStart
                    End = $ChunkEnd
                }
            )
            # prevent overlap: next Chunk ends just before this Chunk starts
            $ChunkEnd = $ChunkStart.AddTicks(-1)
        }
    }

    process {

        foreach ($Chunk in $Chunks) {
            # prepare base params for this Chunk
            $LoopParams = @{
                StartDate      = $Chunk.Start
                EndDate        = $Chunk.End
                ResultSize     = $MaxPageSize
                WarningAction = 'Continue'
                WarningVariable  = '+Warn'
                ErrorAction    = 'Stop'
            }
            if ($SenderAddress) {
                $LoopParams['SenderAddress']    = $SenderAddress
            }
            if ($RecipientAddress) {
                $LoopParams['RecipientAddress'] = $RecipientAddress
            }

            $StartDateString = $LoopParams.StartDate.ToString("MM/dd/yy")
            $EndDateString = $LoopParams.EndDate.ToString("MM/dd/yy")
            if (-not $Quiet) { Write-Host @Blue "Requesting message trace from ${StartDateString} to ${EndDateString}" }

            # request first page in this chunk
            $SleepCount = 0
            while ($true) {
                try {
                    $Warn = @()
                    $Page = [psobject[]]@( Get-MessageTraceV2 @LoopParams 3>$null )
                    break
                }
                catch {
                    # handle exo throttling with backoff; on any other error, return what we have so far
                    $IsRateLimit = $_.Exception.Message -match 'surpassed the permitted limit|try again later'
                    $IsWriteError       = $_.FullyQualifiedErrorId -match 'Write-ErrorMessage'
                    if ($IsRateLimit -and $IsWriteError -and $SleepCount -lt 5) {
                        Write-Host @Red "${Function}: $($_.Exception.Message)" | Out-Host
                        Write-Host @Yellow "${Function}: Pausing for 60 seconds..." | Out-Host
                        $SleepCount++
                        Start-Sleep -Seconds 60
                        continue
                    }
                    else {
                        Write-Host @Yellow "${Function}: Unable to complete operation. Returning."
                        Write-Output $AllMessages
                        return
                    }
                }
            }
            $PageCount = ($Page | Measure-Object).Count
            if (-not $Quiet) { Write-Host "Retrieved ${PageCount} messages." }

            # add page messages to AllMessages
            if ($PageCount) {
                foreach ($i in $Page) {
                    $AllMessages.Add($i)
                }
            }

            # if ResultLimit hit, return
            if ($AllMessages.Count -ge $ResultLimit) {
                Write-Output ($AllMessages | Select-Object -First $ResultLimit)
                return
            }

            # keep following the service-provided continuation only while we hit the page size limit
            while ($PageCount -eq $MaxPageSize) {
                $Hint = $Warn | Where-Object { $_ -like '*Get-MessageTraceV2*' } | Select-Object -Last 1
                if (-not $Hint) { break }
                $NextParams = Build-TraceContinuation -WarningText $Hint
                if (-not $NextParams) { break }

                # reset any existing -starting* keys, then merge the new Hints (clamped to the chunk)
                foreach ($k in @($LoopParams.Keys)) {
                    if ($k -like 'Starting*') {
                        $null = $LoopParams.Remove($k)
                    }
                }
                foreach ($k in $NextParams.Keys) {
                    if ($k -eq 'StartDate') {
                        $LoopParams[$k] = if ($NextParams[$k] -lt $Chunk.Start) {
                            $Chunk.Start
                        }
                        else {
                            $NextParams[$k]
                        }
                    }
                    elseif ($k -eq 'EndDate') {
                        $LoopParams[$k] = if ($NextParams[$k] -gt $Chunk.End) {
                            $Chunk.End
                        }
                        else {
                            $NextParams[$k]
                        }
                    }
                    else {
                        $LoopParams[$k] = $NextParams[$k]
                    }
                }

                # next page for this chunk
                $StartDateString = $LoopParams.StartDate.ToString("MM/dd/yy")
                $EndDateString = $LoopParams.EndDate.ToString("MM/dd/yy")
                if (-not $Quiet) { Write-Host @Blue "Requesting message trace from ${StartDateString} to ${EndDateString}" }

                $SleepCount = 0
                while ($true) {
                    try {
                        $Warn = @()
                        $Page = [psobject[]]@( Get-MessageTraceV2 @LoopParams 3>$null )
                        break
                    }
                    catch {
                        # handle exo throttling with backoff; on any other error, return what we have so far
                        $IsRateLimit = $_.Exception.Message -match 'surpassed the permitted limit|try again later'
                        $IsWriteError       = $_.FullyQualifiedErrorId -match 'Write-ErrorMessage'
                        if ($IsRateLimit -and $IsWriteError -and $SleepCount -lt 5) {
                            Write-Host @Red "${Function}: $($_.Exception.Message)" | Out-Host
                            Write-Host @Yellow "${Function}: Pausing for 60 seconds..." | Out-Host
                            $SleepCount++
                            Start-Sleep -Seconds 60
                            continue
                        }
                        else {
                            Write-Host @Yellow "${Function}: Unable to complete operation. Returning."
                            Write-Output $AllMessages
                            return
                        }
                    }
                }

                $PageCount = ($Page | Measure-Object).Count
                if (-not $Quiet) { Write-Host "Retrieved ${PageCount} messages." }
                foreach ($m in $Page) {$AllMessages.Add($m)}
                if (($AllMessages | Measure-Object).Count -ge $ResultLimit) {
                    Write-Output ($AllMessages | Select-Object -First $ResultLimit)
                    return
                }
            }

            # if we got here, either page count < 5000 (done with this chunk) or no more Hint was provided
        }

        Write-Output $AllMessages
    }
}