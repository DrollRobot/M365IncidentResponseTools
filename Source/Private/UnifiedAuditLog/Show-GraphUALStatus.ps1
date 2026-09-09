function Show-GraphUALStatus {
    <#
    .SYNOPSIS
    Prints one status line per audit search group.

    .DESCRIPTION
    Internal helper for the Wait-IRTGraphUAL poll loop. Groups the jobs, counts their
    statuses, and prints a line per group with the elapsed wait time.

    Groups being waited on are printed in normal colour and other outstanding groups are
    dimmed, so a 35 minute wait does not hide the fact that other searches are also in
    flight, or make it look as though they are being waited on too.

    Age comes from the group's creation stamp rather than from the API, which reports no
    created timestamp for a query.

    .PARAMETER Jobs
    Job objects from Get-GraphUALJob.

    .PARAMETER Focus
    Group ids currently being waited on.

    .PARAMETER Elapsed
    How long the caller has been waiting.

    .EXAMPLE
    ```powershell
    Show-GraphUALStatus -Jobs $Jobs -Focus $Focus -Elapsed $Stopwatch.Elapsed
    ```
    Prints the status table for one poll tick.

    .OUTPUTS
    None. Writes to the host.

    .NOTES
    Version: 1.0.0
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost', '',
        Justification = 'Interactive status table, consistent with Get-IRTEmailSearch.')]
    [CmdletBinding()]
    param(
        [psobject[]] $Jobs,

        [string[]] $Focus,

        [timespan] $Elapsed
    )

    if (($Jobs | Measure-Object).Count -eq 0) { return }

    $Waited = $Elapsed.ToString('hh\:mm\:ss')
    Write-Host ''
    Write-Host "  Audit searches (waiting ${Waited}):" -ForegroundColor Cyan

    # searches from the portal or another tool have no group id; they are listed one per
    # row at the end rather than collapsed into a single nameless group
    $Foreign = @($Jobs | Where-Object { -not $_.GroupId })
    $Groups = $Jobs | Where-Object { $_.GroupId } | Group-Object GroupId | Sort-Object Name
    $NameWidth = (@($Groups | ForEach-Object {
                "$($_.Group[0].ObjectName) $($_.Group[0].ProfileTag)".Length
            }) | Measure-Object -Maximum).Maximum
    if (-not $NameWidth -or $NameWidth -lt 12) { $NameWidth = 12 }

    foreach ($Entry in $Groups) {
        $First = $Entry.Group[0]
        $IsFocused = $First.GroupId -in $Focus

        $Counts = $Entry.Group | Group-Object Status | Sort-Object Name |
            ForEach-Object { "$($_.Count) $($_.Name)" }

        $Age = ''
        if ($First.Created) {
            $Span = (Get-Date) - $First.Created
            $Age = $Span.TotalHours -ge 1 ?
            "$([int]$Span.TotalHours)h$($Span.Minutes)m" : "$([int]$Span.TotalMinutes)m"
        }

        $Name = "$($First.ObjectName) $($First.ProfileTag)".PadRight($NameWidth)
        $Marker = $IsFocused ? '*' : ' '
        $Line = "  $Marker $Name  $($First.Days)d  $($Age.PadLeft(6))  " +
        "[$($First.GroupId)]  $($Counts -join ', ')"

        $Color = $IsFocused ? 'Gray' : 'DarkGray'
        Write-Host $Line -ForegroundColor $Color
    }

    if ($Foreign.Count -gt 0) {
        $Header = "    other searches on this tenant ($($Foreign.Count)):"
        Write-Host $Header -ForegroundColor DarkGray
        foreach ($Job in $Foreign) {
            $Name = $Job.DisplayName
            if ($Name.Length -gt 48) { $Name = $Name.Substring(0, 45) + '...' }
            Write-Host "      $Name  [$($Job.Status)]" -ForegroundColor DarkGray
        }
    }
}
