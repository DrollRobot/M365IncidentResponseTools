function Build-EmailSearchQuery {
    <#
    .SYNOPSIS
    Builds an Exchange KQL ContentMatchQuery string from a set of email search criteria.

    .DESCRIPTION
    Pure helper for New-IRTEmailSearch. Takes a criteria dictionary and returns a
    Keyword Query Language (KQL) string suitable for the -ContentMatchQuery parameter
    of New-ComplianceSearch.

    The query is always scoped to mail items, so it begins with (kind:email) and any
    criteria are appended from there. Date values are expected in UTC and are rendered
    in the 'yyyy-MM-ddTHH:mm:ss' format used by Exchange Received-date queries. Text
    criteria accept one or more values; multiple values for a property are combined
    with OR inside the clause. Every property clause is wrapped in parentheses and the
    clauses are joined with AND.

    .PARAMETER Criteria
    An ordered dictionary describing the search. Recognized keys:
        Start          [datetime] UTC lower bound for Received (optional)
        End            [datetime] UTC upper bound for Received (optional)
        From           [string[]] sender addresses
        To             [string[]] To recipients
        Participants   [string[]] any From/To/Cc/Bcc party
        Recipients     [string[]] any To/Cc/Bcc recipient
        Subject        [string[]] subject keywords (partial match)
        Body           [string[]] body keywords
        AttachmentName [string[]] attachment file names

    .EXAMPLE
    $Criteria = [ordered]@{ From = 'sus@hacker.com'; Subject = 'Payroll' }
    Build-EmailSearchQuery -Criteria $Criteria
    Returns: (kind:email) AND (From:"sus@hacker.com") AND (Subject:"Payroll")

    .OUTPUTS
    System.String. The ContentMatchQuery KQL string. Always begins with (kind:email);
    returns just '(kind:email)' when no other criteria are set.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Criteria
    )

    $Clauses = [System.Collections.Generic.List[string]]::new()

    # every email search is scoped to mail items; this clause always leads the query
    $Clauses.Add('(kind:email)')

    # date range on the Received property (proven 'yyyy-MM-ddTHH:mm:ss' UTC format)
    $DateFormat = 'yyyy-MM-ddTHH:mm:ss'
    $Start = $Criteria['Start']
    $End = $Criteria['End']
    if ($Start -and $End) {
        $StartString = ([datetime]$Start).ToString($DateFormat)
        $EndString = ([datetime]$End).ToString($DateFormat)
        $Clauses.Add("(Received:${StartString}..${EndString})")
    }
    elseif ($Start) {
        $StartString = ([datetime]$Start).ToString($DateFormat)
        $Clauses.Add("(Received>=${StartString})")
    }
    elseif ($End) {
        $EndString = ([datetime]$End).ToString($DateFormat)
        $Clauses.Add("(Received<=${EndString})")
    }

    # text properties rendered in a fixed order. key = criteria key, value = KQL property
    $TextProperties = [ordered]@{
        From           = 'From'
        To             = 'To'
        Participants   = 'Participants'
        Recipients     = 'Recipients'
        Subject        = 'Subject'
        Body           = 'Body'
        AttachmentName = 'AttachmentNames'
    }

    foreach ($Key in $TextProperties.Keys) {

        # collect non-empty values for this property
        $Values = @($Criteria[$Key] | Where-Object { $null -ne $_ -and "$_".Trim() -ne '' })
        if ($Values.Count -eq 0) {
            continue
        }

        $Property = $TextProperties[$Key]
        $Quoted = @($Values | ForEach-Object { '"' + "$_".Trim() + '"' })

        # single value -> Property:"value", multiple -> Property:("v1" OR "v2")
        if ($Quoted.Count -eq 1) {
            $Clauses.Add("(${Property}:$($Quoted[0]))")
        }
        else {
            $Joined = $Quoted -join ' OR '
            $Clauses.Add("(${Property}:(${Joined}))")
        }
    }

    return ($Clauses -join ' AND ')
}
