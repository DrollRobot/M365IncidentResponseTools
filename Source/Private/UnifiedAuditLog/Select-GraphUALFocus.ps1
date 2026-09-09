function Select-GraphUALFocus {
    <#
    .SYNOPSIS
    Works out which audit search groups a wait should follow.

    .DESCRIPTION
    Internal helper for Wait-IRTGraphUAL. Resolves the focus in the least surprising way
    for each situation:

      - An explicit -Group wins outright, with no prompt.
      - A single outstanding group is selected without asking, since there is nothing to
        choose between.
      - Several outstanding groups produce a numbered menu, with an option to follow all
        of them at once.

    The menu is skipped when the host cannot prompt, such as inside a script or a
    scheduled run, and every outstanding group is followed instead. That keeps automation
    working without a hidden prompt stalling it.

    Only groups this module created can be followed. Searches made by the portal or
    another tool are listed for context by Wait-IRTGraphUAL's -All switch, but there is no
    way to know how to rebuild their output, so they are never focus candidates.

    .PARAMETER Jobs
    Job objects from Get-GraphUALJob.

    .PARAMETER Group
    Explicitly requested group ids. When supplied, returned as-is.

    .EXAMPLE
    ```powershell
    $Focus = Select-GraphUALFocus -Jobs $Jobs
    ```
    Picks the group to follow, prompting only when there is a real choice.

    .OUTPUTS
    [string[]] group ids to follow. Empty when the user quit the menu.

    .NOTES
    Version: 1.0.0
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost', '',
        Justification = 'Interactive menu, consistent with Get-IRTEmailSearch.')]
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [psobject[]] $Jobs,

        [string[]] $Group
    )

    Import-IRTModule -Name 'PSFramework'
    $FunctionName = $MyInvocation.MyCommand.Name

    if ($Group) { return [string[]]$Group }

    # only our own searches can be rebuilt into a workbook, so only they can be followed
    $Ours = @($Jobs | Where-Object { $_.IsOurs -and $_.GroupId })
    $GroupIds = @($Ours.GroupId | Sort-Object -Unique)

    if ($GroupIds.Count -eq 0) { return [string[]]@() }
    if ($GroupIds.Count -eq 1) { return [string[]]$GroupIds }

    # a prompt in a non-interactive host would hang a script with no visible cause
    if (-not (Test-IRTInteractiveHost)) {
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: host is not interactive; following all $($GroupIds.Count) group(s).")
        return [string[]]$GroupIds
    }

    $Options = [ordered]@{}
    $Index = 0
    $Lookup = @{}
    foreach ($Id in $GroupIds) {
        $Index++
        $Entry = @($Ours | Where-Object { $_.GroupId -eq $Id })
        $First = $Entry[0]
        $Done = @($Entry | Where-Object {
                $_.Status -in @('succeeded', 'failed', 'cancelled')
            }).Count
        $Text = "$($First.ObjectName) $($First.ProfileTag), $($First.Days)d " +
        "($Done/$($Entry.Count) finished)"
        $Options["$Index"] = @{ String = $Text }
        $Lookup[$Text] = $Id
    }
    $AllText = "All $($GroupIds.Count) searches"
    $Options['A'] = @{ String = $AllText }
    $Options['Q'] = @{ String = 'Quit' }

    $MenuParams = @{
        Options = $Options
        Title   = 'Which audit searches should be watched?'
        List    = $true
    }
    $Choice = Build-Menu @MenuParams

    if ($Choice -eq 'Quit') { return [string[]]@() }
    if ($Choice -eq $AllText) { return [string[]]$GroupIds }
    if ($Lookup.ContainsKey($Choice)) { return [string[]]@($Lookup[$Choice]) }

    return [string[]]$GroupIds
}
