function New-IRTEmailSearch {
    <#
    .SYNOPSIS
    Builds, creates, and starts an email search.

    .DESCRIPTION
    Assembles a Keyword Query Language (KeyQL) ContentMatchQuery from recipient, keyword,
    and date criteria.

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

    .PARAMETER NamePrefix
    String prepended to the search name (whether auto-generated or supplied via -Name).
    Defaults to IRT_Config.JobNamePrefix ('IRT: '). The prefix is not re-applied
    if the resolved name already starts with it. Pass '' to omit the prefix.

    .PARAMETER ExchangeLocation
    Mailboxes to search. Default: All.

    .PARAMETER Force
    On a name collision, automatically use the next available 'Name N' instead of
    prompting. Never overwrites an existing search.

    .EXAMPLE
    ```powershell
    New-IRTEmailSearch
    ```
    Launches the interactive query builder.

    .EXAMPLE
    ```powershell
    New-IRTEmailSearch -From 'sus@hacker.com' -Subject 'Payroll' -Start '5/28/26'
    ```
    Builds a search for mail from a sender on or after the start date.

    .EXAMPLE
    ```powershell
    New-IRTEmailSearch -Subject 'invoice' -Start '5/28/26' -End '5/29/26'
    ```
    Builds a search over an absolute date range.

    .OUTPUTS
    [pscustomobject] describing the search (including a Started flag). Also appended to
    $Global:IRT_EmailSearch.

    .NOTES
    Version: 1.2.0
    1.2.0 - Prepend a configurable name prefix (IRT_Config.JobNamePrefix, default 'IRT: ').
    1.1.0 - Create and start when connected to IPPS; when offline, save criteria and warn.
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
        [string] $NamePrefix = (Get-IRTJobNamePrefix),
        [string[]] $ExchangeLocation = 'All',
        [switch] $Force
    )

    # refresh the IPPS token if a session exists, without erroring when there is none.
    # PassThru reports per-service validity; a missing session returns $null.
    $TokenStatus = Update-IRTToken -Service 'IPPS' -PassThru -SkipIfNeverConnected
    $IppsConnected = [bool]($TokenStatus -and $TokenStatus.IPPS)

    # compliance cmdlets live in the Exchange Online module
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

    # prepend the configurable prefix so IRT-created searches are easy to identify.
    # skip when the name already starts with it (e.g. a -Name that includes the prefix).
    if ($NamePrefix -and -not $Name.StartsWith($NamePrefix)) {
        $Name = "$NamePrefix$Name"
    }

    # email search names reject certain characters - notably the * and ? wildcards
    # that a query value like 'microsoft*' introduces. Strip them so creation does not
    # fail; the wildcard still works in the ContentMatchQuery, just not in the name.
    $Name = ($Name -replace '[*?<>\\/|"]', '').Trim()

    $Search = $null
    $Started = $false

    if ($IppsConnected) {

        # handle a name collision. Rather than overwrite, let the user adjust the name
        # (e.g. append a number). -Force keeps the old overwrite behavior for scripts.
        while ($true) {
            $Existing = Get-ComplianceSearch -Identity $Name -ErrorAction SilentlyContinue
            if (-not $Existing) {
                break
            }

            # suggest the first free 'Name N'
            $Suggested = $Name
            $Counter = 2
            while (Get-ComplianceSearch -Identity $Suggested -ErrorAction SilentlyContinue) {
                $Suggested = "$Name $Counter"
                $Counter++
            }

            # -Force resolves the collision non-interactively by taking the free name
            if ($Force) {
                Write-IRT "Name in use; using '$Suggested' instead." -Level Warn
                $Name = $Suggested
                break
            }

            Write-IRT "A search named '$Name' already exists." -Level Warn
            $Reply = (Read-Host (
                    "Enter a new name, press Enter for '$Suggested', or 'q' to cancel")).Trim()
            if ($Reply -match '^[Qq]$') {
                Write-IRT 'Cancelled. No search created.' -Level Warn
                return
            }
            if ($Reply -eq '') {
                $Name = $Suggested
            }
            else {
                $Name = ($Reply -replace '[*?<>\\/|"]', '').Trim()
            }
        }

        if (-not $PSCmdlet.ShouldProcess($Name, 'Create and start email search')) {
            return
        }

        # always create and start together when the connection is good
        Write-IRT "Creating email search: $Name"
        $NewParams = @{
            Name              = $Name
            ExchangeLocation  = $ExchangeLocation
            ContentMatchQuery = $Query
        }
        try {
            $Search = New-ComplianceSearch @NewParams -ErrorAction Stop
        }
        catch {
            $_
            Write-IRT "Failed to create email search: $Name" -Level Error
            return
        }

        Write-IRT "Starting email search: $Name"
        try {
            Start-ComplianceSearch -Identity $Search.Identity -ErrorAction Stop
            $Started = $true
        }
        catch {
            $_
            Write-IRT "Created but failed to start: $Name" -Level Error
        }
    }
    else {
        Write-IRT 'Not connected to IPPS. Search not created or started.' -Level Warn
        Write-IRT 'Criteria saved to $Global:IRT_EmailSearch. Reconnect and re-run.' -Level Warn
    }

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
        Started        = $Started
        Created        = Get-Date
    }

    if ($Global:IRT_EmailSearch -isnot [System.Collections.Generic.List[psobject]]) {
        $Global:IRT_EmailSearch = [System.Collections.Generic.List[psobject]]::new()
    }
    $Global:IRT_EmailSearch.Add($Result)

    if ($Started) {
        Write-IRT "Search created and started. Saved to `$Global:IRT_EmailSearch."
        Write-IRT "  Query: $Query"
    }

    return $Result
}
