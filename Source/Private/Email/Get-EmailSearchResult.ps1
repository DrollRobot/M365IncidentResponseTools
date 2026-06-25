function Get-EmailSearchResult {
    <#
    .SYNOPSIS
    Returns the per-mailbox hit summary of a completed email search.

    .DESCRIPTION
    Helper for Get-IRTEmailSearch. Reads the aggregate results that an email search
    records on itself - the SearchStatistics JSON on Get-ComplianceSearch - and returns
    one [pscustomobject] per mailbox that had hits. SearchStatistics is structured JSON,
    so it is parsed with ConvertFrom-Json (no text parsing).

    This deliberately avoids New-ComplianceSearchAction -Preview, which requires the
    eDiscovery 'Preview' role. SearchStatistics is available to anyone who can run the
    search, so it works with ordinary Compliance Search permissions. The tradeoff is that
    only aggregate data is available (mailbox, item count, size) - there is no per-message
    sender, subject, or folder without Preview/eDiscovery.

    .PARAMETER Name
    Name (Identity) of the email search to summarize. The search must be Completed.

    .OUTPUTS
    [pscustomobject] rows with: Mailbox, Items, Size. Returns nothing when the search
    recorded no hits.

    .NOTES
    Version: 3.0.0
    3.0.0 - Parse the structured SearchStatistics JSON instead of the SuccessResults text.
    2.0.0 - Switched from eDiscovery Preview to compliance-search statistics so no Preview
        role is required. Per-message detail and folder lookup are no longer available.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[pscustomobject]])]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    # compliance cmdlets live in the Exchange Online module
    Import-IRTModule -Name 'ExchangeOnlineManagement'

    $Search = Get-ComplianceSearch -Identity $Name -ErrorAction Stop

    $StatsJson = "$($Search.SearchStatistics)"
    if ([string]::IsNullOrWhiteSpace($StatsJson)) {
        Write-IRT 'The search recorded no statistics. Has it run to completion?' -Level Warn
        return
    }

    try {
        $Stats = $StatsJson | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-IRT 'Could not parse SearchStatistics JSON.' -Level Warn
        return
    }

    # email searches report per-mailbox hits under ExchangeBinding.Sources, each with
    # Name (mailbox), ContentItems, and a human-formatted ContentSize.
    $Sources = $Stats.ExchangeBinding.Sources
    if (-not $Sources) {
        Write-IRT 'No per-mailbox sources found in SearchStatistics.' -Level Warn
        return
    }

    # one row per mailbox that actually had hits
    $Rows = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($Source in $Sources) {
        if ([int] $Source.ContentItems -le 0) {
            continue
        }
        $Rows.Add([pscustomobject]@{
                Mailbox = $Source.Name
                Items   = [int] $Source.ContentItems
                Size    = $Source.ContentSize
            })
    }

    if ($Rows.Count -eq 0) {
        Write-IRT 'The search completed with zero matching items.' -Level Warn
        return
    }

    # FIXME: optional message-level enrichment via Microsoft Graph (needs Mail.Read).
    # SearchStatistics gives only mailbox + counts - no message IDs - so we cannot join to
    # Graph directly. Instead, scope to the mailboxes above and re-run the search's query
    # per mailbox: prefer the structured criteria in $Global:IRT_EmailSearch for our own
    # searches, else translate the search's ContentMatchQuery (KQL) into a Graph
    # $search/$filter over /users/{mbx}/messages. Select parentFolderId and resolve it to
    # a folder name to flag trash. Note this is an approximate re-query, not an exact join,
    # so counts may differ from the compliance result.

    return $Rows
}
