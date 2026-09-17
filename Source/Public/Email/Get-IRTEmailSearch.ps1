function Get-IRTEmailSearch {
    <#
    .SYNOPSIS
    Interactive manager for existing email searches: start, wait, view
    results, purge matched email, or delete the search.

    .DESCRIPTION
    Lists the tenant's email searches and lets you pick one, then loops an action
    menu against it:

      - Start         Starts a not-yet-started search (Start-ComplianceSearch).
      - Wait          Polls until the search completes, then plays a sound.
      - Results       Shows the per-mailbox hit summary (mailbox, item count, size) from
                      the search's SearchStatistics, with an Excel export. This uses only
                      ordinary Compliance Search permissions - no eDiscovery Preview role -
                      so only aggregate data is available, not per-message detail or folder.
      - Purge email   Soft- or hard-deletes the matched email (New-ComplianceSearchAction
                      -Purge). Exchange purges at most ~10 items per mailbox per action.
      - Delete search Removes the email search definition (Remove-ComplianceSearch).

    Requires a live IPPS (Security & Compliance) connection.

    .PARAMETER Name
    Identity of an email search to act on directly, skipping the picker.

    .EXAMPLE
    ```powershell
    Get-IRTEmailSearch
    ```
    Lists searches and launches the interactive action menu.

    .EXAMPLE
    ```powershell
    Get-IRTEmailSearch -Name 'From:sus@hacker.com'
    ```
    Skips the picker and opens the action menu for the named search.

    .OUTPUTS
    None. Drives an interactive console workflow.

    .NOTES
    Version: 1.0.0
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string] $Name
    )

    # a live IPPS connection is required for every action
    $TokenStatus = Update-IRTToken -Service 'IPPS' -PassThru -SkipIfNeverConnected
    $IppsConnected = [bool]($TokenStatus -and $TokenStatus.IPPS)
    if (-not $IppsConnected) {
        Write-IRT 'Not connected to IPPS. Connect first, then re-run.' -Level Error
        return
    }

    Import-IRTModule -Name 'ExchangeOnlineManagement', 'ImportExcel'

    # session cache of detailed (per-identity) search objects, keyed by name. The list
    # view of Get-ComplianceSearch does not populate Items, so the picker shows the count
    # only for searches already fetched here (i.e. ones the user has viewed this session).
    if ($Global:IRT_EmailSearchDetail -isnot [hashtable]) {
        $Global:IRT_EmailSearchDetail = @{}
    }

    # prefix that identifies IRT-created searches, used by the bulk-delete option
    $Prefix = (Get-IRTJobNamePrefix)

    # outer loop: pick a search (unless one was named), then run the action loop
    :picker while ($true) {

        # resolve the working search
        if ($Name) {
            $Search = Get-ComplianceSearch -Identity $Name -ErrorAction SilentlyContinue
            if (-not $Search) {
                Write-IRT "No email search named '$Name'." -Level Error
                return
            }
        }
        else {
            $Searches = @(Get-ComplianceSearch | Sort-Object LastModifiedTime -Descending)
            if ($Searches.Count -eq 0) {
                Write-IRT 'No email searches found.' -Level Warn
                return
            }

            # draw a numbered, column-aligned list in the same visual style as the
            # New-IRTEmailSearch builder (indent + [N] + PadRight columns). Widths are
            # sized to the data so the columns line up regardless of name length.
            $NameWidth = (@(
                    $Searches.Name | ForEach-Object { "$_".Length }
                ) | Measure-Object -Maximum).Maximum
            $StatusWidth = (@(
                    $Searches.Status | ForEach-Object { "$_".Length }
                ) | Measure-Object -Maximum).Maximum

            Write-Host ''
            Write-Host '  Email searches:'
            Write-Host ''
            for ($i = 0; $i -lt $Searches.Count; $i++) {
                $S = $Searches[$i]
                $NumCol = "[$($i + 1)]".PadRight(5)
                $NameCol = "$($S.Name)".PadRight($NameWidth)
                $StatusCol = "$($S.Status)".PadRight($StatusWidth)

                # show the item count only when we have the detailed object cached
                $Detail = $Global:IRT_EmailSearchDetail[$S.Name]
                $CountText = if ($Detail) { "Items:$($Detail.Items)" } else { '' }
                Write-Host "    $NumCol $NameCol  $StatusCol  $CountText"
            }
            Write-Host ''
            if ($Prefix) {
                Write-Host "    [D] Delete all searches starting with '$Prefix'"
                Write-Host ''
            }

            $Search = $null
            while (-not $Search) {
                $SelectPrompt = if ($Prefix) {
                    'Select a search by number (D to bulk-delete, Q to quit)'
                }
                else {
                    'Select a search by number (Q to quit)'
                }
                $Choice = (Read-Host $SelectPrompt).Trim()
                if ($Choice -match '^[Qq]$') { return }
                if ($Prefix -and $Choice -match '^[Dd]$') {
                    $ToDelete = @($Searches | Where-Object { $_.Name -like "$Prefix*" })
                    if ($ToDelete.Count -eq 0) {
                        Write-IRT "No searches start with '$Prefix'." -Level Warn
                        continue
                    }
                    Write-Host ''
                    Write-Host "  These $($ToDelete.Count) search(es) will be deleted:"
                    foreach ($D in $ToDelete) {
                        Write-Host "    $($D.Name)" -ForegroundColor DarkGray
                    }
                    if (-not (Get-YesNo "Delete these $($ToDelete.Count) search(es)?")) {
                        continue
                    }
                    foreach ($D in $ToDelete) {
                        if ($PSCmdlet.ShouldProcess($D.Name, 'Remove email search')) {
                            Remove-ComplianceSearch -Identity $D.Name -Confirm:$false
                            $Global:IRT_EmailSearchDetail.Remove($D.Name)
                            Write-IRT "Deleted: $($D.Name)"
                        }
                    }
                    continue picker
                }
                if ($Choice -match '^\d+$' -and
                    [int]$Choice -ge 1 -and [int]$Choice -le $Searches.Count) {
                    $Search = $Searches[[int]$Choice - 1]
                }
                else {
                    Write-IRT "Enter a number from 1 to $($Searches.Count), or Q." -Level Warn
                }
            }
        }

        $SearchName = $Search.Name

        # inner loop: act on the selected search
        $BackToList = $false
        while (-not $BackToList) {

            # a Completed search is immutable, so reuse the cached detailed object and
            # skip the round trip. Otherwise fetch (and cache) so status/gating stay
            # current and the picker can show this search's count.
            $Cached = $Global:IRT_EmailSearchDetail[$SearchName]
            if ($Cached -and $Cached.Status -eq 'Completed') {
                $Search = $Cached
            }
            else {
                $Search = Get-ComplianceSearch -Identity $SearchName -ErrorAction Stop
                $Global:IRT_EmailSearchDetail[$SearchName] = $Search
            }
            Write-Host ''
            Write-Host "Search: $SearchName" -ForegroundColor Cyan
            $HeaderText = "  Status: $($Search.Status)   Items: $($Search.Items)"
            Write-Host $HeaderText -ForegroundColor DarkGray

            $ActionMenu = [ordered]@{
                '1' = @{ String = 'Start' }
                '2' = @{ String = 'Wait for completion' }
                '3' = @{ String = 'Results' }
                '4' = @{ String = 'Purge email' }
                '5' = @{ String = 'Wait for purge' }
                '6' = @{ String = 'Delete search' }
                'B' = @{ String = 'Back to list' }
                'Q' = @{ String = 'Quit' }
            }
            $Action = Build-Menu -Option $ActionMenu -Title 'Choose an action:' -List

            switch ($Action) {

                'Start' {
                    if ($Search.Status -ne 'NotStarted') {
                        Write-IRT "Search is '$($Search.Status)', not 'NotStarted'." -Level Warn
                    }
                    elseif ($PSCmdlet.ShouldProcess($SearchName, 'Start email search')) {
                        Start-ComplianceSearch -Identity $SearchName
                        Write-IRT "Started: $SearchName"
                    }
                }

                'Wait for completion' {
                    # check first so an already-completed search returns immediately
                    $Current = Get-ComplianceSearch -Identity $SearchName -ErrorAction Stop
                    if ($Current.Status -ne 'Completed') {
                        Write-IRT "Waiting for '$SearchName' to complete. Ctrl+C to stop."
                        while ($Current.Status -ne 'Completed') {
                            Write-Host "  Status: $($Current.Status)" -ForegroundColor DarkGray
                            Start-Sleep -Seconds 5
                            $Current = Get-ComplianceSearch -Identity $SearchName -ErrorAction Stop
                        }
                    }
                    [System.Media.SystemSounds]::Asterisk.Play()
                    Write-IRT "Completed: $SearchName ($($Current.Items) items)."
                }

                'Results' {
                    if ($Search.Status -ne 'Completed') {
                        Write-IRT "Search is '$($Search.Status)'. Run and wait first." -Level Warn
                        break
                    }

                    # FIXME: add a second results mode (e.g. a -ViaGraph switch or a
                    # 'Results (Graph, with folder)' menu item) that, when the caller has
                    # Mail.Read, drives a per-mailbox Graph /messages query to return
                    # message-level rows (sender/subject/received) plus a Folder column
                    # for trash detection. See Get-EmailSearchResult for the lookup.
                    $Results = Get-EmailSearchResult -Name $SearchName
                    if (-not $Results) {
                        Write-IRT 'No items to display.' -Level Warn
                        break
                    }

                    $Results |
                        Format-Table -AutoSize Mailbox, Items, Size |
                        Out-Host
                    $TotalItems = ($Results | Measure-Object Items -Sum).Sum
                    Write-IRT ("$($Results.Count) mailbox(es) with hits, " +
                        "$TotalItems item(s) total.")

                    # tenant domain from the matched mailboxes; run date from the search
                    $Domain = if ($Results[0].Mailbox -match '@') {
                        ($Results[0].Mailbox -split '@', 2)[-1]
                    }
                    else {
                        ''
                    }
                    $RunDate = if ($Search.JobEndTime) {
                        $Search.JobEndTime
                    }
                    else {
                        $Search.LastModifiedTime
                    }
                    $RunString = if ($RunDate) {
                        ([datetime]$RunDate).ToString('M-d-yy h:mmtt').ToLower()
                    }
                    else {
                        'unknown'
                    }

                    $TitleParts = @("Email search: '$SearchName'")
                    if ($Domain) { $TitleParts += "Tenant: $Domain" }
                    $TitleParts += "Run: $RunString"

                    $Safe = ($SearchName -replace '[\\/:*?"<>|]', '_')
                    $Stamp = (Get-Date).ToString('yy-MM-dd_HH-mm')
                    $Path = "EmailSearchResults_${Safe}_${Stamp}.xlsx"
                    $ExcelParams = @{
                        Path          = $Path
                        WorkSheetname = 'Results'
                        Title         = $TitleParts -join '   '
                        TableStyle    = $Global:IRT_Config.ExcelTableStyle
                        AutoSize      = $true
                        FreezeTopRow  = $true
                        Show          = $true
                    }
                    try {
                        $Results | Export-Excel @ExcelParams
                        Write-IRT "Saved and opened: $Path"
                    }
                    catch {
                        $_
                        Write-IRT 'Error exporting to Excel.' -Level Error
                    }
                }

                'Purge email' {
                    if ($Search.Status -ne 'Completed') {
                        Write-IRT "Search is '$($Search.Status)'. Run and wait first." -Level Warn
                        break
                    }

                    Write-IRT ("Purge removes matched email. Exchange purges at most ~10 " +
                        "items per mailbox per action.") -Level Warn

                    # choose the purge type first, then confirm
                    $PurgeMenu = [ordered]@{
                        '1' = @{ String = 'SoftDelete (easily recovered)' }
                        '2' = @{ String = 'HardDelete (difficult to recover)' }
                    }
                    $PurgeChoice = Build-Menu -Option $PurgeMenu -Title 'Purge type:' -List
                    $PurgeType = if ($PurgeChoice -like 'Hard*') {
                        'HardDelete'
                    }
                    else {
                        'SoftDelete'
                    }

                    $Confirm = Get-YesNo (
                        "$PurgeType $($Search.Items) estimated item(s) from '$SearchName'?")
                    if (-not $Confirm) {
                        Write-IRT 'Purge cancelled.' -Level Warn
                        break
                    }

                    if ($PSCmdlet.ShouldProcess($SearchName, "Purge email ($PurgeType)")) {
                        try {
                            $PurgeParams = @{
                                SearchName  = $SearchName
                                Purge       = $true
                                PurgeType   = $PurgeType
                                Force       = $true
                                Confirm     = $false
                                ErrorAction = 'Stop'
                            }
                            $null = New-ComplianceSearchAction @PurgeParams
                            Write-IRT ("Purge ($PurgeType) submitted for: $SearchName. " +
                                "Use 'Wait for purge' to monitor.")
                        }
                        catch {
                            if ("$_" -match '403|Forbidden') {
                                Write-IRT ('Purge failed (403 Forbidden). Your account ' +
                                    "needs the 'Search And Purge' role (Organization " +
                                    'Management or Data Investigator role group), then ' +
                                    'reconnect IPPS.') -Level Error
                            }
                            else {
                                $_
                                Write-IRT 'Error submitting purge action.' -Level Error
                            }
                        }
                    }
                }

                'Wait for purge' {
                    $PurgeName = "${SearchName}_Purge"
                    $GetParams = @{
                        Identity    = $PurgeName
                        ErrorAction = 'SilentlyContinue'
                    }
                    $Purge = Get-ComplianceSearchAction @GetParams
                    if (-not $Purge) {
                        Write-IRT ("No purge action for '$SearchName'. " +
                            'Run Purge email first.') -Level Warn
                        break
                    }
                    # check first so an already-completed purge returns immediately
                    if ($Purge.Status -ne 'Completed') {
                        $GetParams.ErrorAction = 'Stop'
                        Write-IRT "Waiting for purge of '$SearchName'. Ctrl+C to stop."
                        while ($Purge.Status -ne 'Completed') {
                            Write-Host "  Status: $($Purge.Status)" -ForegroundColor DarkGray
                            Start-Sleep -Seconds 5
                            $Purge = Get-ComplianceSearchAction @GetParams
                        }
                    }
                    [System.Media.SystemSounds]::Asterisk.Play()
                    Write-IRT "Purge completed: $SearchName"
                }

                'Delete search' {
                    $Confirm = Get-YesNo "Delete the search definition '$SearchName'?"
                    if (-not $Confirm) {
                        Write-IRT 'Delete cancelled.' -Level Warn
                        break
                    }
                    if ($PSCmdlet.ShouldProcess($SearchName, 'Remove email search')) {
                        Remove-ComplianceSearch -Identity $SearchName -Confirm:$false
                        $Global:IRT_EmailSearchDetail.Remove($SearchName)
                        Write-IRT "Deleted: $SearchName"
                        # the search is gone; go back to the list
                        if ($Name) { return }
                        $BackToList = $true
                    }
                }

                'Back to list' {
                    if ($Name) { return }
                    $BackToList = $true
                }

                'Quit' {
                    return
                }
            }
        }
    }
}
