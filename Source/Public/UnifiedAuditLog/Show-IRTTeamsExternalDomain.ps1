function Show-IRTTeamsExternalDomain {
    <#
    .SYNOPSIS
    Summarises the outside domains in Get-IRTTeamsExternalDomain output as a spreadsheet,
    with a record count and last-seen date for each.

    .DESCRIPTION
    Reads every .xml file in -Path, which is expected to hold the weekly files written by
    Get-IRTTeamsExternalDomain, and writes one worksheet listing each outside
    organisation that tenant users had Teams contact with:

        Domain           - the organisation's domain, or its tenant ID when no domain
                           could be found for it
        Count            - how many audit records name it
        LastDate         - the most recent of those records, in local time
        allow_TRUE_FALSE - FALSE on every row. A reviewer sets it to TRUE for each
                           organisation that should be allowed. The cells are native
                           Excel booleans.

    Each record is handed to a dedicated parser for its operation (for example
    Get-MessageSentParty for MessageSent), which returns every domain and tenant ID the
    record names. Records from operations with no parser are skipped with a warning, so
    other exports in the same folder do no harm. A progress line is shown as each file
    is read.

    The investigated tenant's own parties are removed. Its tenant ID is each record's
    OrganizationId, and its domains are learned from the records themselves: any domain
    paired with that tenant ID (a user's UPN next to their OrganizationId, or a SIP
    domain entry) belongs to it.

    Many records name a tenant ID with no domain, such as reactions and accepted or
    blocked external users. Those tenant IDs are resolved to the tenant's default domain
    with Get-IRTTenantOwner, which needs a Graph connection. When there is no connection,
    or a lookup fails, a warning is shown and the tenant ID is listed in place of the
    domain. A tenant ID that the same record already pairs with a domain is not looked
    up.

    Lookups run in chunks of -TenantIdChunkSize tenant IDs, with a progress line after
    each chunk. A chunk that fails leaves only its own tenant IDs unresolved.

    Counting:
        - A record adds one to each organisation it names, however often it names it.
        - A record found in more than one file is counted once.
        - DATA MISSING markers from Get-IRTUnifiedAuditLog are reported, since they mean
          the counts and dates are incomplete.

    Guest accounts are counted under their home domain, decoded from the #EXT# guest UPN.

    The workbook is written into -Path as TeamsExternalDomainSummary_<date>.xlsx.

    .PARAMETER Path
    Folder containing the .xml files to read. Subfolders are not searched.
    Default: current directory.

    .PARAMETER TenantIdChunkSize
    Number of tenant IDs sent to Get-IRTTenantOwner per call. A failed call leaves only
    its own chunk unresolved, so lower this if lookups fail in bulk. Default: 100.

    .PARAMETER Open
    Open the workbook after export. Default: $true.

    .PARAMETER TableStyle
    Excel table style. Defaults to IRT_Config.ExcelTableStyle.

    .PARAMETER Font
    Worksheet font. Defaults to IRT_Config.ExcelFont.

    .EXAMPLE
    ```powershell
    Show-IRTTeamsExternalDomain
    ```
    Summarises the .xml files in the current directory and opens the workbook.

    .EXAMPLE
    ```powershell
    Get-IRTTeamsExternalDomain -Days 90 -Path 'C:\Cases\Contoso'
    Show-IRTTeamsExternalDomain -Path 'C:\Cases\Contoso'
    ```
    Pulls 90 days of Teams external contact records, then summarises them.

    .EXAMPLE
    ```powershell
    Show-IRTTeamsExternalDomain -Path 'C:\Cases\Contoso' -TenantIdChunkSize 25
    ```
    Looks up tenant IDs 25 at a time, for when larger lookups fail.

    .EXAMPLE
    ```powershell
    Show-IRTTeamsExternalDomain -Path 'C:\Cases\Contoso' -Open $false
    ```
    Writes the workbook without opening it.

    .OUTPUTS
    None. Writes an Excel workbook into -Path.

    .NOTES
    Version: 1.1.0
    1.1.0 - Tenant IDs are looked up in chunks of -TenantIdChunkSize, so one failed
    lookup no longer loses every tenant ID. Progress is shown per file and per chunk.
    #>
    [Alias('ShowTeamsExtDomain', 'ShowTeamsExtDomains')]
    [CmdletBinding()]
    param (
        [string] $Path = (Get-Location).Path,

        # tenant IDs per Get-IRTTenantOwner call; lower it if lookups fail in bulk
        [ValidateRange(1, 1000)]
        [int] $TenantIdChunkSize = 100,

        [boolean] $Open = $true,

        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont
    )

    begin {
        Import-IRTModule -Name 'ImportExcel', 'PSFramework'
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # file and sheet names
        $FileNamePrefix = 'TeamsExternalDomainSummary'
        $WorksheetName = 'TeamsExternalDomains'
        $FileNameDate = (Get-Date).ToString('yy-MM-dd_HH-mm')
        $TitleDateFormat = 'M/d/yy h:mmtt'

        # columns
        $DomainHeader = 'Domain'
        $CountHeader = 'Count'
        $DateHeader = 'LastDate'
        $AllowHeader = 'allow_TRUE_FALSE'
        $DateNumberFormat = 'm/d/yyyy h:mm:ss AM/PM'

        # one dedicated parser per operation queried by Get-IRTTeamsExternalDomain
        $ParserRegistry = @{
            'MessageSent'              = 'Get-MessageSentParty'
            'MessageCreatedHasLink'    = 'Get-MessageCreatedHasLinkParty'
            'MessageUpdated'           = 'Get-MessageUpdatedParty'
            'MessageEditedHasLink'     = 'Get-MessageEditedHasLinkParty'
            'ChatCreated'              = 'Get-ChatCreatedParty'
            'MemberAdded'              = 'Get-MemberAddedParty'
            'MeetingParticipantDetail' = 'Get-MeetingParticipantDetailParty'
            'CallParticipantDetail'    = 'Get-CallParticipantDetailParty'
            'ReactedToMessage'         = 'Get-ReactedToMessageParty'
            'UserAccepted'             = 'Get-UserAcceptedParty'
            'UserBlocked'              = 'Get-UserBlockedParty'
        }

        # validate input directory
        if (-not (Test-Path -Path $Path -PathType 'Container')) {
            $ErrorParams = @{
                Category    = 'ObjectNotFound'
                Message     = "-Path '${Path}' is not an existing directory."
                ErrorAction = 'Stop'
            }
            Write-Error @ErrorParams
        }
        $Path = (Resolve-Path -Path $Path).Path
        $ExcelOutputPath = Join-Path -Path $Path -ChildPath "${FileNamePrefix}_${FileNameDate}.xlsx"
    }

    process {

        #region READ FILES
        $ChildParams = @{
            Path   = $Path
            Filter = '*.xml'
            File   = $true
        }
        $Files = @(Get-ChildItem @ChildParams)
        if ($Files.Count -eq 0) {
            Write-IRT "No .xml files found in ${Path}." -Level Warn
            return
        }
        $FileCount = $Files.Count
        Write-IRT "Reading ${FileCount} .xml file(s) from ${Path}."

        $ParsedRecords = [System.Collections.Generic.List[pscustomobject]]::new()
        $SeenIdentities = [System.Collections.Generic.HashSet[string]]::new()
        $SkippedOperations = @{}
        $GapCount = 0
        $DuplicateCount = 0
        $UnreadableCount = 0

        $FileIndex = 0
        foreach ($File in $Files) {
            $FileIndex++
            Write-IRT "Reading file ${FileIndex} of ${FileCount}: $($File.Name)"
            $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
            Write-PSFMessage -Level 8 -Message (
                "${FunctionName}: Import-Clixml $($File.Name) [$Elapsed]")
            try {
                $Records = Import-Clixml -Path $File.FullName
            }
            catch {
                Write-IRT "Could not read $($File.Name): $($_.Exception.Message)" -Level Warn
                continue
            }

            foreach ($Record in $Records) {
                if ($null -eq $Record -or $Record.Metadata) { continue }
                if ($Record.IRTDataGap) {
                    $GapCount++
                    continue
                }
                # not a unified audit log record
                if (-not $Record.AuditData) { continue }

                $Operation = [string]$Record.Operations
                if (-not $ParserRegistry.ContainsKey($Operation)) {
                    $SkippedOperations[$Operation] = 1 + [int]$SkippedOperations[$Operation]
                    continue
                }

                # the same record can land in more than one file
                $Identity = [string]$Record.Identity
                if ($Identity -and -not $SeenIdentities.Add($Identity)) {
                    $DuplicateCount++
                    continue
                }

                $AuditData = $Record.AuditData
                if ($AuditData -is [string]) {
                    try {
                        $AuditData = $AuditData | ConvertFrom-Json -Depth 10
                    }
                    catch {
                        Write-PSFMessage -Level 8 -Message (
                            "${FunctionName}: Unreadable AuditData on '${Identity}' in " +
                            "$($File.Name): $($_.Exception.Message)")
                        $UnreadableCount++
                        continue
                    }
                }

                $Created = $Record.CreationDate
                if (-not $Created) { $Created = $AuditData.CreationTime }
                if (-not $Created) {
                    Write-PSFMessage -Level 8 -Message (
                        "${FunctionName}: No date on '${Identity}' in $($File.Name)")
                    $UnreadableCount++
                    continue
                }

                $Parser = $ParserRegistry[$Operation]
                $ParsedRecords.Add([pscustomobject]@{
                        Date         = [datetime]$Created
                        HomeTenantId = ([string]$AuditData.OrganizationId).ToLowerInvariant()
                        Parties      = @(& $Parser -AuditData $AuditData)
                    })
            }
        }

        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: Parsed $($ParsedRecords.Count) records, " +
            "${DuplicateCount} duplicates, ${GapCount} gap markers, " +
            "${UnreadableCount} unreadable [$Elapsed]")

        if ($GapCount -gt 0) {
            Write-IRT ("${GapCount} DATA MISSING marker(s) found. Some records were never " +
                "retrieved, so counts and dates are incomplete.") -Level Warn
        }
        if ($UnreadableCount -gt 0) {
            Write-IRT "Skipped ${UnreadableCount} record(s) that could not be read." -Level Warn
        }
        if ($SkippedOperations.Count -gt 0) {
            $SkippedTotal = ($SkippedOperations.Values | Measure-Object -Sum).Sum
            $SkippedList = (
                $SkippedOperations.GetEnumerator() | Sort-Object -Property 'Name' |
                    ForEach-Object { "$($_.Name) ($($_.Value))" }
            ) -join ', '
            Write-IRT ("Skipped ${SkippedTotal} record(s) from operations with no parser: " +
                "${SkippedList}") -Level Warn
        }
        if ($ParsedRecords.Count -eq 0) {
            Write-IRT "No Teams external contact records found in ${Path}." -Level Warn
            return
        }

        #region HOME TENANT
        # The investigated tenant's domains appear paired with its own tenant ID, on its
        # users' UPNs and its SIP domain entry. Learning them from every record first
        # means a home domain that turns up alone elsewhere is still recognised.
        $HomeDomains = @{}
        foreach ($Parsed in $ParsedRecords) {
            $HomeTenantId = $Parsed.HomeTenantId
            if (-not $HomeDomains.ContainsKey($HomeTenantId)) {
                $HomeDomains[$HomeTenantId] = [System.Collections.Generic.HashSet[string]]::new()
            }
            foreach ($Party in $Parsed.Parties) {
                if ($Party.Domain -and $Party.TenantId -eq $HomeTenantId) {
                    [void]$HomeDomains[$HomeTenantId].Add($Party.Domain)
                }
            }
        }
        foreach ($HomeTenantId in $HomeDomains.Keys) {
            Write-PSFMessage -Level 8 -Message (
                "${FunctionName}: Home tenant '${HomeTenantId}' domains: " +
                "$($HomeDomains[$HomeTenantId] -join ', ')")
        }

        #region OUTSIDE PARTIES
        $Contacts = [System.Collections.Generic.List[pscustomobject]]::new()
        $LookupIds = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($Parsed in $ParsedRecords) {
            $HomeTenantId = $Parsed.HomeTenantId
            $OwnDomains = $HomeDomains[$HomeTenantId]
            $Domains = [System.Collections.Generic.HashSet[string]]::new()
            $TenantIds = [System.Collections.Generic.HashSet[string]]::new()
            $PairedTenantIds = [System.Collections.Generic.HashSet[string]]::new()

            foreach ($Party in $Parsed.Parties) {
                if ($Party.TenantId -and $Party.TenantId -eq $HomeTenantId) { continue }
                if ($Party.Domain) {
                    if ($OwnDomains.Contains($Party.Domain)) { continue }
                    [void]$Domains.Add($Party.Domain)
                    if ($Party.TenantId) { [void]$PairedTenantIds.Add($Party.TenantId) }
                }
                else {
                    [void]$TenantIds.Add($Party.TenantId)
                }
            }

            # a tenant this record already names by domain needs no lookup
            $TenantIds.ExceptWith($PairedTenantIds)
            if ($Domains.Count -eq 0 -and $TenantIds.Count -eq 0) { continue }

            $LookupIds.UnionWith($TenantIds)
            $Contacts.Add([pscustomobject]@{
                    Date      = $Parsed.Date
                    Domains   = $Domains
                    TenantIds = $TenantIds
                })
        }

        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-PSFMessage -Level 8 -Message (
            "${FunctionName}: $($Contacts.Count) records name an outside party, " +
            "$($LookupIds.Count) tenant IDs to look up [$Elapsed]")

        #region TENANT LOOKUP
        $TenantDomains = @{}
        if ($LookupIds.Count -gt 0) {
            $LookupCount = $LookupIds.Count
            $TokenParams = @{
                Service              = 'Graph'
                SkipIfNeverConnected = $true
                PassThru             = $true
            }
            $TokenStatus = Update-IRTToken @TokenParams
            if (-not ($TokenStatus -and $TokenStatus['Graph'])) {
                Write-IRT ("Not connected to Graph, so ${LookupCount} tenant ID(s) can't be " +
                    "looked up and are listed in place of their domains. Run Connect-IRT " +
                    "to resolve them.") -Level Warn
            }
            else {
                $LookupList = [string[]]@($LookupIds)
                $ChunkCount = [int][math]::Ceiling($LookupCount / $TenantIdChunkSize)
                Write-IRT ("Looking up domains for ${LookupCount} tenant ID(s) in " +
                    "${ChunkCount} chunk(s) of up to ${TenantIdChunkSize}.")

                # One Get-IRTTenantOwner call per chunk, so a call that throws leaves only
                # its own tenant IDs unresolved and progress shows between chunks.
                $LookedUp = 0
                for ($ChunkIndex = 0; $ChunkIndex -lt $ChunkCount; $ChunkIndex++) {
                    $ChunkStart = $ChunkIndex * $TenantIdChunkSize
                    $ChunkEnd = [math]::Min($ChunkStart + $TenantIdChunkSize, $LookupCount) - 1
                    $Chunk = [string[]]@($LookupList[$ChunkStart..$ChunkEnd])
                    $ChunkLabel = "Chunk $($ChunkIndex + 1) of ${ChunkCount}"

                    $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
                    Write-PSFMessage -Level 8 -Message (
                        "${FunctionName}: Get-IRTTenantOwner ${ChunkLabel}, " +
                        "$($Chunk.Count) tenant IDs [$Elapsed]")
                    $OwnerParams = @{
                        TenantId = $Chunk
                        Cached   = $true
                        Quiet    = $true
                    }
                    try {
                        $Owners = @(Get-IRTTenantOwner @OwnerParams)
                    }
                    catch {
                        Write-IRT ("${ChunkLabel}: tenant lookup failed, so its " +
                            "$($Chunk.Count) tenant ID(s) stay unresolved: " +
                            "$($_.Exception.Message)") -Level Warn
                        $Owners = @()
                    }
                    foreach ($Owner in $Owners) {
                        if ($Owner.Exists -and $Owner.DefaultDomain) {
                            $OwnerDomain = ([string]$Owner.DefaultDomain).ToLowerInvariant()
                            $TenantDomains[[string]$Owner.TenantId] = $OwnerDomain
                        }
                    }

                    $LookedUp += $Chunk.Count
                    Write-IRT "Looked up ${LookedUp} of ${LookupCount} tenant ID(s)."
                }

                $Unresolved = @($LookupIds | Where-Object { -not $TenantDomains.ContainsKey($_) })
                if ($Unresolved.Count -gt 0) {
                    Write-IRT ("Could not find a domain for $($Unresolved.Count) of " +
                        "${LookupCount} tenant ID(s); they are listed in place of their " +
                        "domains.") -Level Warn
                    Write-PSFMessage -Level 8 -Message (
                        "${FunctionName}: Unresolved tenant IDs: $($Unresolved -join ', ')")
                }
            }
        }

        #region ROWS
        $Summary = @{}
        foreach ($Contact in $Contacts) {
            $Keys = [System.Collections.Generic.HashSet[string]]::new()
            $Keys.UnionWith($Contact.Domains)
            foreach ($TenantId in $Contact.TenantIds) {
                if ($TenantDomains.ContainsKey($TenantId)) {
                    [void]$Keys.Add($TenantDomains[$TenantId])
                }
                else {
                    [void]$Keys.Add($TenantId)
                }
            }

            foreach ($Key in $Keys) {
                $Entry = $Summary[$Key]
                if (-not $Entry) {
                    $Entry = [pscustomobject]@{
                        Domain   = $Key
                        Hits     = 0
                        LastDate = $Contact.Date
                    }
                    $Summary[$Key] = $Entry
                }
                $Entry.Hits++
                if ($Contact.Date -gt $Entry.LastDate) { $Entry.LastDate = $Contact.Date }
            }
        }

        if ($Summary.Count -eq 0) {
            Write-IRT ("No outside domains found in $($ParsedRecords.Count) Teams " +
                "record(s).") -Level Warn
            return
        }

        # most contact first. Every organisation starts denied, as a native Excel
        # boolean, until a reviewer allows it.
        $SortProperty = @(
            @{ Expression = 'Hits'; Descending = $true }
            @{ Expression = 'Domain'; Descending = $false }
        )
        $Rows = [System.Collections.Generic.List[pscustomobject]]::new()
        foreach ($Entry in ($Summary.Values | Sort-Object -Property $SortProperty)) {
            $Rows.Add([pscustomobject]@{
                    $DomainHeader = $Entry.Domain
                    $CountHeader  = $Entry.Hits
                    $DateHeader   = $Entry.LastDate.ToLocalTime()
                    $AllowHeader  = $false
                })
        }
        Write-IRT ("Found $($Rows.Count) outside domain(s) in $($Contacts.Count) " +
            "record(s).")

        #region EXPORT EXCEL
        $SortedDates = @($ParsedRecords | ForEach-Object { $_.Date } | Sort-Object)
        $FirstString = $SortedDates[0].ToLocalTime().ToString($TitleDateFormat).ToLower()
        $LastString = $SortedDates[-1].ToLocalTime().ToString($TitleDateFormat).ToLower()
        $WorksheetTitle = "Teams external communication from ${FirstString} to ${LastString}"

        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-PSFMessage -Level 8 -Message "${FunctionName}: Export-Excel [$Elapsed]"
        $ExcelParams = @{
            Path          = $ExcelOutputPath
            WorkSheetname = $WorksheetName
            Title         = $WorksheetTitle
            TableStyle    = $TableStyle
            FreezeTopRow  = $true
            Passthru      = $true
        }
        try {
            $Workbook = $Rows | Export-Excel @ExcelParams
        }
        catch {
            Write-IRT "Error exporting to Excel: $($_.Exception.Message)" -Level Error
            if ( Get-YesNo "The file may be open in Excel. Close it and try again?" ) {
                try {
                    $Workbook = $Rows | Export-Excel @ExcelParams
                }
                catch {
                    Write-IRT "Error exporting to Excel: $($_.Exception.Message)" -Level Error
                    return
                }
            }
            else {
                return
            }
        }

        # post-export formatting only runs when a workbook came back from Export-Excel
        if ($Workbook) {
            $Worksheet = $Workbook.Workbook.Worksheets[$WorksheetName]

            # table ranges
            $SheetStartColumn =
            $Worksheet.Dimension.Start.Column | Convert-DecimalToExcelColumn
            $SheetStartRow = $Worksheet.Dimension.Start.Row
            $TableStartColumn = (
                $Worksheet.Tables.Address | Select-Object -First 1
            ).Start.Column | Convert-DecimalToExcelColumn
            $TableStartRow = (
                $Worksheet.Tables | Select-Object -First 1
            ).Address.Start.Row + 1
            $EndColumn = $Worksheet.Dimension.End.Column | Convert-DecimalToExcelColumn
            $EndRow = $Worksheet.Dimension.End.Row
            $TableRange = "${TableStartColumn}${TableStartRow}:${EndColumn}${EndRow}"

            # column widths
            $ColumnWidths = @{
                $DomainHeader = 45
                $CountHeader  = 10
                $DateHeader   = 26
                $AllowHeader  = 18
            }
            foreach ($ColName in $ColumnWidths.Keys) {
                $Col = (
                    $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq $ColName }
                ).Id
                if ($Col) { $Worksheet.Column($Col).Width = $ColumnWidths[$ColName] }
            }

            # date number format
            $DateColumn = (
                $Worksheet.Tables[0].Columns | Where-Object { $_.Name -eq $DateHeader }
            ).Id | Convert-DecimalToExcelColumn
            $FmtParams = @{
                Worksheet    = $Worksheet
                Range        = "${DateColumn}:${DateColumn}"
                NumberFormat = $DateNumberFormat
            }
            Set-ExcelRange @FmtParams

            # font
            $SetParams = @{
                Worksheet = $Worksheet
                Range     = "${SheetStartColumn}${SheetStartRow}:${EndColumn}${EndRow}"
                FontName  = $Font
            }
            Set-ExcelRange @SetParams

            # left border
            $BorderParams = @{
                Worksheet   = $Worksheet
                Range       = $TableRange
                BorderLeft  = 'Thin'
                BorderColor = 'Black'
            }
            Set-ExcelRange @BorderParams

            # save and open
            Write-IRT "Exporting to: ${ExcelOutputPath}"
            if ($Open) {
                Write-IRT "Opening Excel."
                $Workbook | Close-ExcelPackage -Show
            }
            else {
                $Workbook | Close-ExcelPackage
            }
        }

        $Elapsed = $Stopwatch.Elapsed.ToString('mm\:ss\.fff')
        Write-PSFMessage -Level 8 -Message "${FunctionName}: Complete [$Elapsed]"
    }
}
