function New-IRTEmailSearch {
    <#
    .SYNOPSIS
    Builds and creates (but does not start) an Exchange compliance search for email.

    .DESCRIPTION
    Assembles a Keyword Query Language (KeyQL) ContentMatchQuery from recipient, keyword,
    and date criteria, then creates a compliance search with New-ComplianceSearch. The
    search is created in a ready state but is NOT started; run it later with the start
    stage of the workflow.

    Two modes:
      - Parameter mode: supply any of the criteria parameters and the query is built
        non-interactively.
      - Interactive mode: call with no criteria parameters to launch a console builder
        that shows the live query and lets you edit each field before accepting.

    On creation, a result object is appended to $Global:IRT_EmailSearch containing the
    criteria, the generated name, the built query, and the New-ComplianceSearch return
    object.

    .PARAMETER Start
    Absolute start of the Received date range (any Get-Date-parseable value). Required.
    Stored as UTC. In interactive mode a relative duration shortcut is also offered.

    .PARAMETER End
    Absolute end of the Received date range (any Get-Date-parseable value). Optional.
    Stored as UTC.

    .PARAMETER From
    One or more sender addresses (KeyQL From). Multiple values are combined with OR.

    .PARAMETER To
    One or more To recipients (KeyQL To). Multiple values are combined with OR.

    .PARAMETER Participants
    One or more parties in any of From/To/Cc/Bcc (KeyQL Participants).

    .PARAMETER Recipients
    One or more recipients in any of To/Cc/Bcc (KeyQL Recipients).

    .PARAMETER Subject
    One or more subject keywords (KeyQL Subject, partial match).

    .PARAMETER Body
    One or more body keywords (KeyQL Body).

    .PARAMETER AttachmentName
    One or more attachment file names (KeyQL AttachmentNames).

    .PARAMETER Name
    Override the auto-generated search name. By default the name is built from the
    recipient and keyword criteria (dates excluded).

    .PARAMETER ExchangeLocation
    Mailboxes to search. Default: All.

    .PARAMETER Force
    Overwrite an existing search of the same name without prompting.

    .EXAMPLE
    New-IRTEmailSearch
    Launches the interactive query builder.

    .EXAMPLE
    New-IRTEmailSearch -From 'sus@hacker.com' -Subject 'Payroll' -Start '5/28/26'
    Builds a search for mail from a sender on or after the start date.

    .EXAMPLE
    New-IRTEmailSearch -Subject 'invoice' -Start '5/28/26' -End '5/29/26'
    Builds a search over an absolute date range.

    .OUTPUTS
    [pscustomobject] describing the created search. Also appended to $Global:IRT_EmailSearch.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [string] $Start,
        [string] $End,
        [string[]] $From,
        [string[]] $To,
        [string[]] $Participants,
        [string[]] $Recipients,
        [string[]] $Subject,
        [string[]] $Body,
        [string[]] $AttachmentName,
        [string] $Name,
        [string[]] $ExchangeLocation = 'All',
        [switch] $Force
    )

    # check if token update is needed
    Update-IRTToken -Service 'IPPS'

    # import modules
    Import-IRTModule -Name 'ExchangeOnlineManagement'

    # criteria parameters that, when present, trigger non-interactive mode
    $CriteriaParams = @(
        'Start', 'End', 'From', 'To', 'Participants',
        'Recipients', 'Subject', 'Body', 'AttachmentName'
    )
    $Interactive = -not ($CriteriaParams | Where-Object { $PSBoundParameters.ContainsKey($_) })

    # seed criteria from parameters
    $Criteria = [ordered]@{
        Start          = $null
        End            = $null
        From           = $From
        To             = $To
        Participants   = $Participants
        Recipients     = $Recipients
        Subject        = $Subject
        Body           = $Body
        AttachmentName = $AttachmentName
    }

    # parse absolute date parameters to UTC
    if ($Start) {
        try {
            $Parsed = Get-Date -Date $Start -ErrorAction Stop
            $Criteria.Start = [DateTime]::SpecifyKind(
                $Parsed, [DateTimeKind]::Local).ToUniversalTime()
        }
        catch {
            Write-Error -Category InvalidArgument -ErrorAction Stop -Message (
                "-Start invalid. Use a date like '5/28/26 17:00'.")
        }
    }
    if ($End) {
        try {
            $Parsed = Get-Date -Date $End -ErrorAction Stop
            $Criteria.End = [DateTime]::SpecifyKind(
                $Parsed, [DateTimeKind]::Local).ToUniversalTime()
        }
        catch {
            Write-Error -Category InvalidArgument -ErrorAction Stop -Message (
                "-End invalid. Use a date like '5/28/26 17:00'.")
        }
    }

    # interactive builder
    if ($Interactive) {
        $Criteria = Read-EmailSearchCriteria -Criteria $Criteria
        if (-not $Criteria) {
            Write-IRT 'Cancelled. No search created.' -Level Warn
            return
        }
    }

    # a start date is required (interactive mode enforces this on accept; this also
    # covers parameter mode)
    if (-not $Criteria.Start) {
        Write-Error -Category InvalidArgument -ErrorAction Stop -Message (
            'A start date is required. Use -Start.')
    }

    # build the query and name
    $Query = Build-EmailSearchQuery -Criteria $Criteria
    if (-not $Name) {
        $Name = Build-EmailSearchName -Criteria $Criteria
    }

    # handle an existing search of the same name
    $Existing = Get-ComplianceSearch -Identity $Name -ErrorAction SilentlyContinue
    if ($Existing) {
        $Overwrite = $Force -or (Get-YesNo "A search named '$Name' already exists. Overwrite?")
        if (-not $Overwrite) {
            Write-IRT 'Aborted. Existing search left unchanged.' -Level Warn
            return
        }
        Remove-ComplianceSearch -Identity $Name -Confirm:$false
    }

    # create the search (not started)
    if (-not $PSCmdlet.ShouldProcess($Name, 'Create compliance search')) {
        return
    }

    Write-IRT "Creating compliance search: $Name"
    $NewParams = @{
        Name              = $Name
        ExchangeLocation  = $ExchangeLocation
        ContentMatchQuery = $Query
    }
    $Search = New-ComplianceSearch @NewParams

    # build the result object and store it in the global collection
    $Result = [pscustomobject]@{
        Name           = $Name
        Query          = $Query
        Start          = $Criteria.Start
        End            = $Criteria.End
        From           = $Criteria.From
        To             = $Criteria.To
        Participants   = $Criteria.Participants
        Recipients     = $Criteria.Recipients
        Subject        = $Criteria.Subject
        Body           = $Criteria.Body
        AttachmentName = $Criteria.AttachmentName
        Search         = $Search
        Created        = Get-Date
    }

    if ($Global:IRT_EmailSearch -isnot [System.Collections.Generic.List[psobject]]) {
        $Global:IRT_EmailSearch = [System.Collections.Generic.List[psobject]]::new()
    }
    $Global:IRT_EmailSearch.Add($Result)

    Write-IRT "Search created (not started) and saved to `$Global:IRT_EmailSearch."
    Write-IRT "  Query: $Query"

    return $Result
}
