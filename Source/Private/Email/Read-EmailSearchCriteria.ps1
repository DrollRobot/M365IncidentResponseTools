function Read-EmailSearchCriteria {
    <#
    .SYNOPSIS
    Interactive console builder for email compliance search criteria.

    .DESCRIPTION
    Helper for New-IRTEmailSearch. Presents a redrawing panel that always shows the
    auto-generated search name, the live ContentMatchQuery, and every criterion's
    current value. The user edits fields by number until they accept or quit.

    Each date bound (Start/End) is stored as a single absolute UTC value but can be set
    two ways:
      - Absolute fields accept any Get-Date-parseable value.
      - Relative fields accept a duration like '3 hours' or '5 days'; the value is
        immediately resolved to an absolute time (now - duration) and stored on the
        bound. The relative rows are input shortcuts only and never carry a value.

    Text fields accept comma-separated values (combined with OR in the query).
    Entering a blank value clears a field. A start date is required before the criteria
    can be accepted. Returns the completed criteria dictionary on accept, or $null if
    the user quits. This is a Write-Host console UI, mirroring the module's Build-Menu
    helper.

    .PARAMETER Criteria
    An ordered dictionary to seed and edit. When omitted, a fresh empty set is used.
    Keys: Start, End, From, To, Participants, Recipients, Subject, Body, AttachmentName.

    .OUTPUTS
    System.Collections.Specialized.OrderedDictionary on accept, or $null on quit.

    .NOTES
    Version: 1.2.0
    1.2.0 - Relative dates are interactive shortcuts that set the absolute bound. Start
        date is now required.
    1.1.0 - Split each date bound into absolute and relative input fields.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseSingularNouns', '',
        Justification = 'Builds a set of search criteria; the plural noun is intentional.')]
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [System.Collections.IDictionary] $Criteria
    )

    # start from a fresh set, then copy in any seeded values
    $State = [ordered]@{
        Start          = $null
        End            = $null
        From           = @()
        To             = @()
        Participants   = @()
        Recipients     = @()
        Subject        = @()
        Body           = @()
        AttachmentName = @()
    }
    if ($Criteria) {
        foreach ($Key in @($State.Keys)) {
            if ($Criteria.Contains($Key)) {
                $State[$Key] = $Criteria[$Key]
            }
        }
    }

    # menu definition. number -> field metadata. date rows carry a Bound (Start/End);
    # text rows carry a Key
    $Menu = [ordered]@{
        '1'  = @{ Bound = 'Start'; Label = 'Start date (absolute)'; Type = 'Absolute' }
        '2'  = @{ Bound = 'Start'; Label = 'Start date (relative)'; Type = 'Relative' }
        '3'  = @{ Bound = 'End'; Label = 'End date (absolute)'; Type = 'Absolute' }
        '4'  = @{ Bound = 'End'; Label = 'End date (relative)'; Type = 'Relative' }
        '5'  = @{ Key = 'From'; Label = 'From'; Type = 'Text' }
        '6'  = @{ Key = 'To'; Label = 'To'; Type = 'Text' }
        '7'  = @{ Key = 'Participants'; Label = 'Participants (from/to/cc/bcc)'; Type = 'Text' }
        '8'  = @{ Key = 'Recipients'; Label = 'Recipients (to/cc/bcc)'; Type = 'Text' }
        '9'  = @{ Key = 'Subject'; Label = 'Subject'; Type = 'Text' }
        '10' = @{ Key = 'Body'; Label = 'Body'; Type = 'Text' }
        '11' = @{ Key = 'AttachmentName'; Label = 'Attachment name'; Type = 'Text' }
    }

    while ($true) {

        # build the live name and query from current state
        $Query = Build-EmailSearchQuery -Criteria $State
        $Name = Build-EmailSearchName -Criteria $State

        # draw the panel
        Write-Host ''
        Write-Host '  Search name:'
        Write-Host "    $Name" -ForegroundColor Green
        Write-Host ''
        Write-Host '  ContentMatchQuery:'
        Write-Host "    $Query" -ForegroundColor Green
        if (-not $State.Start) {
            Write-Host '    (a start date is required before accepting)' -ForegroundColor DarkGray
        }
        Write-Host ''

        foreach ($Number in $Menu.Keys) {
            $Item = $Menu[$Number]

            # format the current value for display
            $Display = switch ($Item.Type) {
                'Absolute' {
                    $Value = $State[$Item.Bound]
                    if ($Value) {
                        $Local = ([datetime]$Value).ToLocalTime().ToString('yyyy-MM-dd HH:mm')
                        $Utc = ([datetime]$Value).ToString('yyyy-MM-ddTHH:mm:ssZ')
                        "$Local  (UTC $Utc)"
                    }
                    else { '(not set)' }
                }
                'Relative' {
                    # input shortcut only; sets the absolute bound, carries no value
                    ''
                }
                'Text' {
                    $Items = @($State[$Item.Key] | Where-Object { "$_".Trim() -ne '' })
                    if ($Items.Count) { $Items -join ', ' } else { '(not set)' }
                }
            }

            $NumCol = "[$Number]".PadRight(5)
            $Label = $Item.Label.PadRight(30)
            Write-Host "    $NumCol $Label $Display"
        }

        Write-Host ''
        Write-Host '    [A] Accept and create search    [C] Clear all    [Q] Quit'

        $Choice = (Read-Host 'Select').Trim()

        if ($Menu.Contains($Choice)) {
            $Item = $Menu[$Choice]

            switch ($Item.Type) {

                'Absolute' {
                    $Prompt = "Enter $($Item.Label) (e.g. '5/28/26 17:00'; blank clears)"
                    $Raw = (Read-Host $Prompt).Trim()
                    if ($Raw -eq '') {
                        $State[$Item.Bound] = $null
                    }
                    else {
                        try {
                            $Parsed = Get-Date -Date $Raw -ErrorAction Stop
                            $State[$Item.Bound] = [DateTime]::SpecifyKind(
                                $Parsed, [DateTimeKind]::Local).ToUniversalTime()
                        }
                        catch {
                            Write-Host "  Could not parse date: $Raw" -ForegroundColor Red
                        }
                    }
                }

                'Relative' {
                    $Prompt = "Enter $($Item.Label) (e.g. '3 hours' or '5 days')"
                    $Raw = (Read-Host $Prompt).Trim()
                    if ($Raw -ne '') {
                        try {
                            $Span = ConvertTo-TimeSpan -InputString $Raw
                            $State[$Item.Bound] = (Get-Date).ToUniversalTime() - $Span
                        }
                        catch {
                            Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
                        }
                    }
                }

                'Text' {
                    $Prompt = "Enter $($Item.Label) (comma-separated, blank to clear)"
                    $Raw = (Read-Host $Prompt).Trim()
                    if ($Raw -eq '') {
                        $State[$Item.Key] = @()
                    }
                    else {
                        $State[$Item.Key] = @(
                            $Raw -split ',' |
                                ForEach-Object { $_.Trim() } |
                                Where-Object { $_ -ne '' }
                        )
                    }
                }
            }
        }
        elseif ($Choice -match '^[Aa]$') {
            if (-not $State.Start) {
                Write-Host '  Cannot accept: a start date is required.' -ForegroundColor Yellow
            }
            else {
                return $State
            }
        }
        elseif ($Choice -match '^[Cc]$') {
            foreach ($Key in @($State.Keys)) {
                $State[$Key] = if ($Key -in 'Start', 'End') { $null } else { @() }
            }
        }
        elseif ($Choice -match '^[Qq]$') {
            return $null
        }
        else {
            Write-Host "  Unrecognized choice: $Choice" -ForegroundColor Yellow
        }
    }
}
