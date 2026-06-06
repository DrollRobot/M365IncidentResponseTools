function Read-EmailSearchCriteria {
    <#
    .SYNOPSIS
    Interactive console builder for email compliance search criteria.

    .DESCRIPTION
    Helper for New-IRTEmailSearch. Presents a redrawing panel that always shows the
    auto-generated search name, the live ContentMatchQuery, and every criterion's
    current value. The user edits fields by number until they accept or quit.

    Text fields accept comma-separated values (combined with OR in the query). Date
    fields accept any parseable local date/time or a relative expression such as
    '3 days ago', and are stored in UTC. Entering a blank value clears a field.

    Returns the completed criteria dictionary on accept, or $null if the user quits.
    This is a Write-Host console UI, mirroring the module's Build-Menu helper.

    .PARAMETER Criteria
    An ordered dictionary to seed and edit. When omitted, a fresh empty set is used.
    Keys: Start, End, From, To, Participants, Recipients, Subject, Body, AttachmentName.

    .OUTPUTS
    System.Collections.Specialized.OrderedDictionary on accept, or $null on quit.

    .NOTES
    Version: 1.0.0
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
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

    # menu definition. number -> criteria key, display label, and field type
    $Menu = [ordered]@{
        '1' = @{ Key = 'Start';          Label = 'Start date';                    Type = 'Date' }
        '2' = @{ Key = 'End';            Label = 'End date';                      Type = 'Date' }
        '3' = @{ Key = 'From';           Label = 'From';                          Type = 'Text' }
        '4' = @{ Key = 'To';             Label = 'To';                            Type = 'Text' }
        '5' = @{ Key = 'Participants';   Label = 'Participants (from/to/cc/bcc)';  Type = 'Text' }
        '6' = @{ Key = 'Recipients';     Label = 'Recipients (to/cc/bcc)';        Type = 'Text' }
        '7' = @{ Key = 'Subject';        Label = 'Subject';                       Type = 'Text' }
        '8' = @{ Key = 'Body';           Label = 'Body';                          Type = 'Text' }
        '9' = @{ Key = 'AttachmentName'; Label = 'Attachment name';               Type = 'Text' }
    }

    # the query is always scoped to (kind:email); a query equal to this base means the
    # user has not added any real criteria yet
    $BaseQuery = '(kind:email)'

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
        if ($Query -eq $BaseQuery) {
            Write-Host '    (add at least one criterion before accepting)' -ForegroundColor DarkGray
        }
        Write-Host ''

        foreach ($Number in $Menu.Keys) {
            $Item = $Menu[$Number]
            $Value = $State[$Item.Key]

            # format the current value for display
            if ($Item.Type -eq 'Date') {
                if ($Value) {
                    $Local = ([datetime]$Value).ToLocalTime().ToString('yyyy-MM-dd HH:mm')
                    $Utc = ([datetime]$Value).ToString('yyyy-MM-ddTHH:mm:ssZ')
                    $Display = "$Local  (UTC $Utc)"
                }
                else {
                    $Display = '(not set)'
                }
            }
            else {
                $Items = @($Value | Where-Object { "$_".Trim() -ne '' })
                $Display = if ($Items.Count) { $Items -join ', ' } else { '(not set)' }
            }

            $Label = $Item.Label.PadRight(30)
            Write-Host "    [$Number] $Label $Display"
        }

        Write-Host ''
        Write-Host '    [A] Accept and create search    [C] Clear all    [Q] Quit'

        $Choice = (Read-Host 'Select').Trim()

        switch -Regex ($Choice) {

            '^[1-9]$' {
                $Item = $Menu[$Choice]
                if ($Item.Type -eq 'Date') {
                    $Prompt = "Enter $($Item.Label) (date or '3 days ago'; blank clears)"
                    $Raw = (Read-Host $Prompt).Trim()
                    if ($Raw -eq '') {
                        $State[$Item.Key] = $null
                    }
                    else {
                        try {
                            $State[$Item.Key] = Resolve-DateInput -InputString $Raw
                        }
                        catch {
                            Write-Host "  Could not parse date: $Raw" -ForegroundColor Red
                        }
                    }
                }
                else {
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

            '^[Aa]$' {
                if ((Build-EmailSearchQuery -Criteria $State) -eq $BaseQuery) {
                    Write-Host (
                        '  Cannot accept: add at least one criterion beyond kind:email.'
                    ) -ForegroundColor Yellow
                }
                else {
                    return $State
                }
            }

            '^[Cc]$' {
                foreach ($Key in @($State.Keys)) {
                    $State[$Key] = if ($Key -in 'Start', 'End') { $null } else { @() }
                }
            }

            '^[Qq]$' {
                return $null
            }

            default {
                Write-Host "  Unrecognized choice: $Choice" -ForegroundColor Yellow
            }
        }
    }
}
