#Requires -Version 7.4
#Requires -Modules Microsoft.Graph.Authentication
<#
.SYNOPSIS
    Probes the Microsoft Graph Audit Search API (security/auditLog/queries) against a
    live tenant and records what it actually does.

.DESCRIPTION
    Developer tool, non-domain. The Graph audit log query API is documented loosely and
    behaves differently per tenant (v1.0 availability, concurrency rules, OData support,
    record shape). This script submits a set of probe jobs, waits for them, and writes a
    findings report so the behaviour can be re-checked whenever Microsoft changes
    something.

    Default run (no switches): creates the standard probe jobs, waits (about 35 minutes;
    the service batches jobs), then analyzes:

      - v1.0 vs beta availability.
      - Listed query object properties.
      - Record shape: property names, auditData type and key casing, RecordType casing.
      - Record ordering, $top limits, nextLink shape.
      - recordTypeFilters: PascalCase vs camelCase vs invalid value.
      - userPrincipalNameFilters with a UPN vs an object id.
      - keywordFilter vs userPrincipalNameFilters (target-side hits).
      - List endpoint $top / $filter / $select / $orderby handling.
      - DELETE support.
      - Time to complete per job.

    Optional probes:

      -TestUnfilteredCap   Create-only. Submits unfiltered, service-only, and filtered
                           jobs back to back and records which ones the service refuses
                           with TooManyRequests (the one-open-unfiltered-job rule).
      -TestPaging          Creates one unfiltered job over -PagingDays so a multi-page
                           result exists, then probes $top above 999, pages the job twice
                           and diffs the id sets, counts in-pass duplicates, checks
                           ordering, and compares Graph id with auditData.Id.
      -CompareExchange     Runs Search-UnifiedAuditLog over the same window as the
                           paging job (or the shape job) and compares the two record
                           sets by AuditData.Id: overlap, one-sided records, and
                           duplicate counts inside the Exchange result itself. Needs an
                           Exchange Online session.
      -ReuseJobs           Skips creation and analyzes the newest existing jobs carrying
                           -Prefix (or the run named by -JobStamp). No wait when they
                           are already finished.
      -ListOnly            Prints the jobs carrying -Prefix and exits.

    All jobs are named '<Prefix><test>|<stamp>'. Jobs cannot be deleted; they expire
    server-side after about 30 days. Results go to <OutputDirectory>\
    GraphUALEndpoint_<stamp>.md and .json. Ctrl+C saves what has been gathered so far.

.PARAMETER TestUserUpn
    User principal name for the single-user probes. Defaults to the signed-in account.

.PARAMETER Prefix
    displayName prefix that marks this script's jobs. Default: 'IRT: SPIKE|'.

.PARAMETER JobStamp
    With -ReuseJobs, pick the run with this stamp (yyMMdd-HHmm) instead of the newest.

.PARAMETER ReuseJobs
    Analyze existing prefixed jobs instead of creating the standard set.

.PARAMETER ListOnly
    List prefixed jobs and exit.

.PARAMETER TestUnfilteredCap
    Run the create-only concurrency probe. Adds up to six throwaway jobs.

.PARAMETER TestPaging
    Create (or reuse) a wide unfiltered job and run the paging probes on it.

.PARAMETER PagingDays
    Window for the -TestPaging job, in days back from now. Default: 90.

.PARAMETER CompareExchange
    Compare the paging (or shape) job against Search-UnifiedAuditLog.

.PARAMETER TimeoutMinutes
    Stop waiting for jobs after this long; analyses still run on whatever finished.
    Default: 90.

.PARAMETER PollSeconds
    Seconds between status polls. Default: 30.

.PARAMETER MaxCompareRecords
    Cap for full enumerations (paging stability, Exchange compare). Default: 30000.

.PARAMETER OutputDirectory
    Where the results files go. Default: the repo's .local folder if present, else the
    current directory.

.PARAMETER SkipDelete
    Do not attempt the DELETE probe. Implied by -ReuseJobs and -ListOnly.

.PARAMETER Trace
    Emit trace output.

.EXAMPLE
    .\Scripts\Test-GraphUALEndpoint.ps1

    Standard probe run. Expect about 35 minutes.

.EXAMPLE
    .\Scripts\Test-GraphUALEndpoint.ps1 -ReuseJobs -TestUnfilteredCap

    Re-analyze the newest finished jobs and run the concurrency probe. No wait.

.EXAMPLE
    .\Scripts\Test-GraphUALEndpoint.ps1 -ReuseJobs -TestPaging -PagingDays 180 -CompareExchange

    Add a 180-day unfiltered job, wait for it, run the paging probes, and compare the
    result with Search-UnifiedAuditLog over the same window.

.EXAMPLE
    .\Scripts\Test-GraphUALEndpoint.ps1 -ListOnly

    Show the prefixed jobs currently on the tenant.

.OUTPUTS
    None. Writes a markdown and a JSON results file and prints findings as it goes.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')]
[CmdletBinding()]
param(
    [string] $TestUserUpn,
    [string] $Prefix = 'IRT: SPIKE|',
    [string] $JobStamp,
    [switch] $ReuseJobs,
    [switch] $ListOnly,
    [switch] $TestUnfilteredCap,
    [switch] $TestPaging,
    [ValidateRange(1, 3650)]
    [int] $PagingDays = 90,
    [switch] $CompareExchange,
    [int] $TimeoutMinutes = 90,
    [int] $PollSeconds = 30,
    [int] $MaxCompareRecords = 30000,
    [string] $OutputDirectory,
    [switch] $SkipDelete,
    [switch] $Trace
)

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', 'ScriptVersion')]
$ScriptVersion = '1.0.0'

if ($Trace) { $InformationPreference = 'Continue' }
function Write-Trace {
    param([Parameter(Mandatory)][string] $Message)
    Write-Information $Message -Tags 'Trace'
}

$ErrorActionPreference = 'Stop'
$Stamp = (Get-Date).ToString('yyMMdd-HHmm')
$BetaBase = 'https://graph.microsoft.com/beta/security/auditLog'
$V1Base = 'https://graph.microsoft.com/v1.0/security/auditLog'
$Terminal = @('succeeded', 'failed', 'cancelled')
$Findings = [ordered]@{}
$Raw = [ordered]@{}
$Jobs = [ordered]@{}
$Script:Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

if (-not $OutputDirectory) {
    $LocalDir = Join-Path -Path $PSScriptRoot -ChildPath '..\.local'
    if (Test-Path -LiteralPath $LocalDir) { $OutputDirectory = (Resolve-Path -Path $LocalDir).Path }
    else { $OutputDirectory = (Get-Location).Path }
}

#region helpers

function Add-Finding {
    param(
        [Parameter(Mandatory)][string] $Key,
        $Value,
        [string] $Note = ''
    )
    $Findings[$Key] = [ordered]@{ Value = $Value; Note = $Note }
    $Shown = if ($Value -is [string]) { $Value } else { $Value | ConvertTo-Json -Compress -Depth 4 }
    $Shown = [string]$Shown
    if ($Shown.Length -gt 160) { $Shown = $Shown.Substring(0, 160) + '...' }
    Write-Host "  [$Key] $Shown" -ForegroundColor DarkCyan
    if ($Note) {
        $ShownNote = ($Note.Length -gt 300) ? ($Note.Substring(0, 300) + '...') : $Note
        Write-Host "      $ShownNote" -ForegroundColor DarkGray
    }
}

function Get-ShortError {
    param([string] $Text)
    if (-not $Text) { return '' }
    # the SDK folds its 429 retries into one huge message; keep the status code only
    if ($Text -match 'status code: ([A-Za-z]+)') { return "HTTP $($Matches[1])" }
    if ($Text -match 'does not indicate success: ([^()]+)') { return "HTTP $($Matches[1].Trim())" }
    return ($Text.Length -gt 200) ? ($Text.Substring(0, 200) + '...') : $Text
}

function Invoke-GraphCall {
    param(
        [string] $Method = 'GET',
        [Parameter(Mandatory)][string] $Uri,
        [hashtable] $Body,
        [string] $OutputType = 'HashTable'
    )
    $Params = @{
        Method      = $Method
        Uri         = $Uri
        OutputType  = $OutputType
        ErrorAction = 'Stop'
    }
    if ($Body) {
        $Params['Body'] = $Body
        $Params['ContentType'] = 'application/json'
    }
    Write-Trace "$Method $Uri"
    $Sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $Result = Invoke-MgGraphRequest @Params
        return [pscustomobject]@{
            Ok = $true; Result = $Result; Error = $null; Seconds = [int]$Sw.Elapsed.TotalSeconds
        }
    }
    catch {
        Write-Trace "  failed: $($_.Exception.Message)"
        return [pscustomobject]@{
            Ok      = $false
            Result  = $null
            Error   = $_.Exception.Message
            Seconds = [int]$Sw.Elapsed.TotalSeconds
        }
    }
}

function Get-UtcString {
    param([datetime] $Date)
    return $Date.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}

function Initialize-JobRecord {
    param([string] $Name, [hashtable] $Body)
    return [ordered]@{
        Name        = $Name
        Body        = $Body
        Id          = $null
        CreateOk    = $false
        CreateError = $null
        CreateSecs  = $null
        CreatedUtc  = [datetime]::UtcNow
        Status      = $null
        Transitions = [System.Collections.Generic.List[string]]::new()
        DoneUtc     = $null
        Seconds     = $null
        NoWait      = $false
        Reused      = $false
    }
}

function Submit-AuditJob {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][hashtable] $Body,
        [string] $Base = $BetaBase,
        [switch] $NoWait
    )
    $Body['displayName'] = "$Prefix$Name|$Stamp"
    $Response = Invoke-GraphCall -Method 'POST' -Uri "$Base/queries" -Body $Body
    $Job = Initialize-JobRecord -Name $Name -Body $Body
    $Job.CreateOk = $Response.Ok
    $Job.CreateError = $Response.Error
    $Job.CreateSecs = $Response.Seconds
    $Job.NoWait = [bool]$NoWait
    if ($Response.Ok) {
        $Job.Id = $Response.Result.id
        $Job.Status = $Response.Result.status
        $Job.Transitions.Add("$(Get-UtcString ([datetime]::UtcNow)) $($Job.Status)")
        Write-Host ("  created $Name -> $($Job.Id) ($($Job.Status), " +
            "$($Response.Seconds)s)") -ForegroundColor Green
    }
    else {
        Write-Host ("  create FAILED $Name ($(Get-ShortError $Response.Error), " +
            "$($Response.Seconds)s)") -ForegroundColor Yellow
    }
    return $Job
}

function Wait-AuditJob {
    param(
        [Parameter(Mandatory)] $JobTable,
        [int] $TimeoutMinutes,
        [int] $PollSeconds
    )
    $Deadline = [datetime]::UtcNow.AddMinutes($TimeoutMinutes)
    while ($true) {
        $Pending = @($JobTable.Values | Where-Object {
                $_.Id -and -not $_.NoWait -and $_.Status -notin $Terminal
            })
        if ($Pending.Count -eq 0) { return $true }
        if ([datetime]::UtcNow -gt $Deadline) {
            Write-Host "  timeout: $($Pending.Count) job(s) still pending" -ForegroundColor Yellow
            return $false
        }
        foreach ($Job in $Pending) {
            $Response = Invoke-GraphCall -Uri "$BetaBase/queries/$($Job.Id)"
            $Now = Get-UtcString ([datetime]::UtcNow)
            if (-not $Response.Ok) {
                $Job.Transitions.Add("$Now GET failed: $(Get-ShortError $Response.Error)")
                continue
            }
            $New = $Response.Result.status
            if ($New -ne $Job.Status) {
                $Job.Status = $New
                $Job.Transitions.Add("$Now $New")
                if ($New -in $Terminal) {
                    $Job.DoneUtc = [datetime]::UtcNow
                    $Job.Seconds = [int]($Job.DoneUtc - $Job.CreatedUtc).TotalSeconds
                }
            }
        }
        $Line = ($JobTable.Values | Where-Object { $_.Id -and -not $_.NoWait } | ForEach-Object {
                "$($_.Name)=$($_.Status)"
            }) -join '  '
        $Elapsed = $Script:Stopwatch.Elapsed.ToString('hh\:mm\:ss')
        Write-Host "  [$Elapsed] $Line" -ForegroundColor DarkGray
        Start-Sleep -Seconds $PollSeconds
    }
}

function Get-AuditRecordSet {
    param(
        [Parameter(Mandatory)][string] $Id,
        [int] $Top = 999,
        [int] $Max = 0
    )
    $Uri = "$BetaBase/queries/$Id/records?`$top=$Top"
    $All = [System.Collections.Generic.List[object]]::new()
    $Pages = 0
    $FirstNextLink = $null
    $Sw = [System.Diagnostics.Stopwatch]::StartNew()
    $PageError = $null
    while ($Uri) {
        $Response = Invoke-GraphCall -Uri $Uri
        if (-not $Response.Ok) { $PageError = $Response.Error; break }
        $Pages++
        if ($Response.Result.value) { $All.AddRange([object[]]$Response.Result.value) }
        $Uri = $Response.Result.'@odata.nextLink'
        if ($Pages -eq 1 -and $Uri) { $FirstNextLink = $Uri }
        if ($Max -gt 0 -and $All.Count -ge $Max) { break }
    }
    return [pscustomobject]@{
        Records       = $All
        Count         = $All.Count
        Pages         = $Pages
        Seconds       = [int]$Sw.Elapsed.TotalSeconds
        Truncated     = [bool]$Uri
        FirstNextLink = $FirstNextLink
        Error         = $PageError
    }
}

function Get-ExchangeRecordSet {
    # legacy-style pull: ReturnLargeSet paging on one SessionId, Formatted output
    param(
        [Parameter(Mandatory)][datetime] $StartUtc,
        [Parameter(Mandatory)][datetime] $EndUtc,
        [int] $Max = 0
    )
    $All = [System.Collections.Generic.List[object]]::new()
    $Pages = 0
    $Sw = [System.Diagnostics.Stopwatch]::StartNew()
    $PageError = $null
    $Params = @{
        StartDate      = $StartUtc
        EndDate        = $EndUtc
        ResultSize     = 5000
        SessionCommand = 'ReturnLargeSet'
        SessionId      = "GraphUALEndpoint-$Stamp"
        Formatted      = $true
        ErrorAction    = 'Stop'
    }
    while ($true) {
        try {
            $Page = @(Search-UnifiedAuditLog @Params)
        }
        catch {
            $PageError = $_.Exception.Message
            break
        }
        $Pages++
        if ($Page.Count -gt 0) { $All.AddRange([object[]]$Page) }
        if ($Page.Count -lt 5000) { break }
        if ($Max -gt 0 -and $All.Count -ge $Max) { break }
    }
    return [pscustomobject]@{
        Records   = $All
        Count     = $All.Count
        Pages     = $Pages
        Seconds   = [int]$Sw.Elapsed.TotalSeconds
        Truncated = ($Max -gt 0 -and $All.Count -ge $Max)
        Error     = $PageError
    }
}

function Get-IdSet {
    param($Records, [string] $Property = 'id')
    $Set = [System.Collections.Generic.HashSet[string]]::new()
    $Dupes = 0
    foreach ($R in $Records) {
        $Value = [string]$R.$Property
        if (-not $Value) { continue }
        if (-not $Set.Add($Value)) { $Dupes++ }
    }
    return [pscustomobject]@{ Set = $Set; Dupes = $Dupes }
}

function Get-AuditDataIdSet {
    # ids from inside auditData (Graph: hashtable, Exchange: JSON string)
    param($Records)
    $Set = [System.Collections.Generic.HashSet[string]]::new()
    $Dupes = 0
    $Missing = 0
    foreach ($R in $Records) {
        $Data = $R.auditData ?? $R.AuditData
        if ($Data -is [string]) {
            try { $Data = $Data | ConvertFrom-Json -Depth 10 } catch { $Data = $null }
        }
        $Value = [string]($Data.Id ?? $Data['Id'])
        if (-not $Value) { $Missing++; continue }
        if (-not $Set.Add($Value)) { $Dupes++ }
    }
    return [pscustomobject]@{ Set = $Set; Dupes = $Dupes; Missing = $Missing }
}

function Get-Ordering {
    param($Records, [string] $Property = 'createdDateTime')
    $Asc = 0; $Desc = 0; $Prev = $null
    foreach ($R in $Records) {
        $D = [datetime]$R.$Property
        if ($null -ne $Prev) {
            if ($D -gt $Prev) { $Asc++ } elseif ($D -lt $Prev) { $Desc++ }
        }
        $Prev = $D
    }
    if ($Asc -gt 0 -and $Desc -eq 0) { return 'ascending' }
    if ($Desc -gt 0 -and $Asc -eq 0) { return 'descending' }
    if ($Asc -eq 0 -and $Desc -eq 0) { return 'flat/unknown' }
    return "mixed (asc=$Asc desc=$Desc)"
}

function Get-RecordSummary {
    # trimmed view of one Graph record for the raw results file
    param($Record)
    $AuditKeys = @()
    if ($Record.auditData -is [System.Collections.IDictionary]) {
        $AuditKeys = @($Record.auditData.Keys | Sort-Object)
    }
    $AuditRecordType = ''
    if ($AuditKeys -contains 'RecordType') {
        $AuditRecordType = [string]$Record.auditData['RecordType']
    }
    $AuditType = ($null -eq $Record.auditData) ? 'null' : $Record.auditData.GetType().Name
    return [ordered]@{
        properties          = @($Record.Keys | Sort-Object)
        auditLogRecordType  = $Record.auditLogRecordType
        operation           = $Record.operation
        service             = $Record.service
        userType            = $Record.userType
        userPrincipalName   = $Record.userPrincipalName
        auditDataType       = $AuditType
        auditDataKeys       = $AuditKeys
        auditDataRecordType = $AuditRecordType
    }
}

function Get-RecordTypeDistribution {
    param($Records, [int] $Top = 10)
    $Counts = @{}
    foreach ($R in $Records) {
        $K = [string]$R.auditLogRecordType
        $Counts[$K] = ($Counts[$K] ?? 0) + 1
    }
    return @($Counts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First $Top |
            ForEach-Object { "$($_.Key)=$($_.Value)" })
}

function Add-ListProperty {
    param($ListResult, [string] $Key)
    $Items = @($ListResult.value)
    if ($Items.Count -eq 0) { return }
    Add-Finding -Key $Key -Value (@($Items[0].Keys | Sort-Object) -join ', ') -Note (
        'Look for any created/modified timestamp; the docs list none.')
    $Raw[$Key + '.sample'] = $Items[0]
}

function Get-PrefixedJob {
    # newest job per test name among the prefixed ones; -JobStamp pins one run
    param($Queries)
    $ByName = @{}
    foreach ($Q in @($Queries | Where-Object { $_.displayName -like "$Prefix*" })) {
        $Parts = ($Q.displayName.Substring($Prefix.Length) -split '\|')
        if ($Parts.Count -lt 2) { continue }
        $Name = $Parts[0]
        $QStamp = $Parts[1]
        if ($JobStamp -and $QStamp -ne $JobStamp) { continue }
        if (-not $ByName[$Name] -or $QStamp -gt $ByName[$Name].stamp) {
            $ByName[$Name] = @{ query = $Q; stamp = $QStamp }
        }
    }
    return $ByName
}

function Show-JobTable {
    param($Queries)
    $Mine = @($Queries | Where-Object { $_.displayName -like "$Prefix*" } |
            Sort-Object displayName)
    if ($Mine.Count -eq 0) {
        Write-Host "  no jobs with prefix '$Prefix'" -ForegroundColor Yellow
        return
    }
    $NameWidth = (@($Mine | ForEach-Object { "$($_.displayName)".Length }) |
            Measure-Object -Maximum).Maximum
    foreach ($Q in $Mine) {
        $Name = "$($Q.displayName)".PadRight($NameWidth)
        $Window = "$($Q.filterStartDateTime) .. $($Q.filterEndDateTime)"
        Write-Host "  $Name  $("$($Q.status)".PadRight(10))  $Window  $($Q.id)"
    }
}

function Save-Result {
    $JsonPath = Join-Path -Path $OutputDirectory -ChildPath "GraphUALEndpoint_$Stamp.json"
    $MdPath = Join-Path -Path $OutputDirectory -ChildPath "GraphUALEndpoint_$Stamp.md"
    $Ctx = Get-MgContext
    $Mode = @(
        ($ReuseJobs ? 'reuse' : 'create')
        ($ListOnly ? 'list' : $null)
        ($TestUnfilteredCap ? 'cap' : $null)
        ($TestPaging ? 'paging' : $null)
        ($CompareExchange ? 'exchange' : $null)
    ) | Where-Object { $_ }
    $JobSummary = foreach ($J in $Jobs.Values) {
        [ordered]@{
            Name        = $J.Name
            Id          = $J.Id
            Reused      = $J.Reused
            CreateOk    = $J.CreateOk
            CreateError = $J.CreateError
            CreateSecs  = $J.CreateSecs
            Status      = $J.Status
            Seconds     = $J.Seconds
            Transitions = @($J.Transitions)
            Body        = $J.Body
        }
    }
    [ordered]@{
        Stamp         = $Stamp
        ScriptVersion = $ScriptVersion
        Mode          = ($Mode -join '+')
        Tenant        = $Ctx.TenantId
        Account       = $Ctx.Account
        Findings      = $Findings
        Jobs          = @($JobSummary)
        Raw           = $Raw
    } | ConvertTo-Json -Depth 8 | Set-Content -Path $JsonPath -Encoding utf8

    $Lines = [System.Collections.Generic.List[string]]::new()
    $Lines.Add("# Graph UAL endpoint probe ($Stamp)")
    $Lines.Add('')
    $Lines.Add("Tenant: $($Ctx.TenantId)  Account: $($Ctx.Account)  Mode: $($Mode -join '+')")
    $Lines.Add('')
    $Lines.Add('## Findings')
    $Lines.Add('')
    $Lines.Add('| Key | Value | Note |')
    $Lines.Add('| --- | --- | --- |')
    foreach ($K in $Findings.Keys) {
        $V = $Findings[$K].Value
        $VText = ($V -is [string]) ? $V : ($V | ConvertTo-Json -Compress -Depth 4)
        $VText = ([string]$VText) -replace '\|', '\|'
        $N = [string]$Findings[$K].Note
        if ($N.Length -gt 400) { $N = $N.Substring(0, 400) + '...' }
        $N = $N -replace '\|', '\|' -replace '[\r\n]+', ' '
        $Lines.Add("| $K | $VText | $N |")
    }
    $Lines.Add('')
    $Lines.Add('## Jobs')
    $Lines.Add('')
    $Lines.Add('| Name | Id | Created | Status | Seconds | Transitions |')
    $Lines.Add('| --- | --- | --- | --- | --- | --- |')
    foreach ($J in $Jobs.Values) {
        $T = (@($J.Transitions) -join '; ') -replace '\|', '\|'
        $C = if ($J.Reused) { 'reused' }
        elseif ($J.CreateOk) { "ok ($($J.CreateSecs)s)" }
        else { 'FAILED: ' + ((Get-ShortError $J.CreateError) -replace '\|', '\|') }
        $Lines.Add("| $($J.Name) | $($J.Id) | $C | $($J.Status) | $($J.Seconds) | $T |")
    }
    $Lines.Add('')
    $Lines.Add("Raw details: $(Split-Path -Path $JsonPath -Leaf)")
    $Lines | Set-Content -Path $MdPath -Encoding utf8
    Write-Host ''
    Write-Host "Results: $MdPath" -ForegroundColor Cyan
    Write-Host "         $JsonPath" -ForegroundColor Cyan
}

#endregion helpers

try {
    #region preflight
    Write-Host ''
    Write-Host "== Preflight (Test-GraphUALEndpoint v$ScriptVersion) ==" -ForegroundColor Cyan
    $Ctx = Get-MgContext
    $NeededScope = 'AuditLogsQuery.Read.All'
    if (-not $Ctx -or ($Ctx.Scopes -notcontains $NeededScope)) {
        Write-Host "  connecting to Graph with $NeededScope" -ForegroundColor Yellow
        Connect-MgGraph -Scopes $NeededScope -NoWelcome
        $Ctx = Get-MgContext
    }
    Add-Finding -Key 'context' -Value "$($Ctx.Account) / $($Ctx.TenantId)"

    if (-not $TestUserUpn) { $TestUserUpn = $Ctx.Account }
    $UserUri = "https://graph.microsoft.com/v1.0/users/$TestUserUpn" +
    '?$select=id,userPrincipalName'
    $UserResponse = Invoke-GraphCall -Uri $UserUri
    if (-not $UserResponse.Ok) {
        throw "Cannot resolve test user '$TestUserUpn': $($UserResponse.Error)"
    }
    $TestUserId = $UserResponse.Result.id
    Add-Finding -Key 'testUser' -Value "$TestUserUpn ($TestUserId)"

    $ListBefore = Invoke-GraphCall -Uri "$BetaBase/queries"
    $Existing = @()
    if ($ListBefore.Ok) {
        $Existing = @($ListBefore.Result.value)
        $Running = @($Existing | Where-Object { $_.status -in @('notStarted', 'running') })
        Add-Finding -Key 'list.existingCount' -Value $Existing.Count
        Add-Finding -Key 'list.runningCount' -Value $Running.Count -Note (
            'Docs claim a cap of 10 per admin; the standard run adds up to 8.')
        Add-ListProperty -ListResult $ListBefore.Result -Key 'list.queryProperties'
        if ($Running.Count -ge 4 -and -not $ReuseJobs) {
            Write-Host ("  WARNING: $($Running.Count) jobs already running; " +
                'creates may be refused.') -ForegroundColor Yellow
        }
    }
    else {
        Add-Finding -Key 'list.beta' -Value 'FAILED' -Note (Get-ShortError $ListBefore.Error)
    }
    $ListV1 = Invoke-GraphCall -Uri "$V1Base/queries"
    Add-Finding -Key 'list.v1' -Value ($ListV1.Ok ? 'ok' : 'FAILED') -Note (
        Get-ShortError $ListV1.Error)

    if ($ListOnly) {
        Write-Host ''
        Write-Host "== Jobs with prefix '$Prefix' ==" -ForegroundColor Cyan
        Show-JobTable -Queries $Existing
        $Raw['list.names'] = @($Existing | ForEach-Object { "$($_.displayName) [$($_.status)]" })
        return
    }
    #endregion preflight

    $Now = [datetime]::UtcNow
    $Window1h = @{
        filterStartDateTime = Get-UtcString $Now.AddHours(-25)
        filterEndDateTime   = Get-UtcString $Now.AddHours(-24)
    }
    $Window7d = @{
        filterStartDateTime = Get-UtcString $Now.AddDays(-7)
        filterEndDateTime   = Get-UtcString $Now
    }
    $Window30d = @{
        filterStartDateTime = Get-UtcString $Now.AddDays(-30)
        filterEndDateTime   = Get-UtcString $Now
    }
    $OpenUnfiltered = @($Existing | Where-Object {
            $_.status -in @('notStarted', 'running') -and
            -not $_.keywordFilter -and -not $_.serviceFilters -and
            -not $_.userPrincipalNameFilters -and -not $_.recordTypeFilters -and
            -not $_.operationFilters -and -not $_.ipAddressFilters -and -not $_.objectIdFilters
        })

    if ($ReuseJobs) {
        #region reuse existing jobs
        Write-Host ''
        Write-Host '== Reuse existing jobs ==' -ForegroundColor Cyan
        $ByName = Get-PrefixedJob -Queries $Existing
        foreach ($Name in ($ByName.Keys | Sort-Object)) {
            if ($Name -like 'cap*') { continue }
            $Q = $ByName[$Name].query
            $Body = @{
                displayName         = $Q.displayName
                filterStartDateTime = $Q.filterStartDateTime
                filterEndDateTime   = $Q.filterEndDateTime
            }
            $Job = Initialize-JobRecord -Name $Name -Body $Body
            $Job.Id = $Q.id
            $Job.CreateOk = $true
            $Job.Reused = $true
            $Job.Status = $Q.status
            $Job.Transitions.Add("reused from $($ByName[$Name].stamp), status $($Q.status)")
            $Jobs[$Name] = $Job
            Write-Host "  reusing $Name -> $($Q.id) ($($Q.status))" -ForegroundColor Green
        }
        Add-Finding -Key 'reuse.jobs' -Value (@($Jobs.Keys) -join ', ')
        if ($Jobs.Count -eq 0) { Write-Host '  no jobs found to reuse' -ForegroundColor Yellow }
        #endregion reuse existing jobs
    }
    else {
        #region create standard jobs
        Write-Host ''
        Write-Host '== Create standard jobs ==' -ForegroundColor Cyan

        # v1.0 create attempt (documented GA; some tenants report 'Resource not found')
        $Jobs['v1Unfiltered1h'] = Submit-AuditJob -Name 'v1Unfiltered1h' -Base $V1Base -Body (
            $Window1h.Clone())
        $V1Job = $Jobs['v1Unfiltered1h']
        Add-Finding -Key 'create.v1' -Value ($V1Job.CreateOk ? 'ok' : 'FAILED') -Note (
            Get-ShortError $V1Job.CreateError)

        # filtered jobs; only one unfiltered job may be open at a time
        $Jobs['upn30d'] = Submit-AuditJob -Name 'upn30d' -Body (
            $Window30d.Clone() + @{ userPrincipalNameFilters = @($TestUserUpn) })
        $Jobs['keyword30d'] = Submit-AuditJob -Name 'keyword30d' -Body (
            $Window30d.Clone() + @{ keywordFilter = $TestUserUpn })
        $Jobs['guid30d'] = Submit-AuditJob -Name 'guid30d' -Body (
            $Window30d.Clone() + @{ userPrincipalNameFilters = @($TestUserId) })
        $Jobs['rtPascal7d'] = Submit-AuditJob -Name 'rtPascal7d' -Body (
            $Window7d.Clone() + @{ recordTypeFilters = @('AzureActiveDirectoryStsLogon') })
        $Jobs['rtCamel7d'] = Submit-AuditJob -Name 'rtCamel7d' -Body (
            $Window7d.Clone() + @{ recordTypeFilters = @('azureActiveDirectoryStsLogon') })
        $Jobs['rtInvalid7d'] = Submit-AuditJob -Name 'rtInvalid7d' -Body (
            $Window7d.Clone() + @{ recordTypeFilters = @('NotARecordType') })
        # documented in the beta enum and the management API schema (id 261), absent from
        # the v1.0 enum page. Accepted = the v1.0 list is doc lag, not a real accept-list.
        $Jobs['rtBetaOnly7d'] = Submit-AuditJob -Name 'rtBetaOnly7d' -Body (
            $Window7d.Clone() + @{ recordTypeFilters = @('CopilotInteraction') })
        if (-not $Jobs['v1Unfiltered1h'].CreateOk) {
            $Jobs['unfiltered1h'] = Submit-AuditJob -Name 'unfiltered1h' -Body ($Window1h.Clone())
        }

        foreach ($Pair in @(
                @('create.rtPascal', 'rtPascal7d', ''),
                @('create.rtCamel', 'rtCamel7d', ''),
                @('create.rtInvalid', 'rtInvalid7d', ' (rejected = validation visible at create)'),
                @('create.rtBetaOnly', 'rtBetaOnly7d',
                    ' (CopilotInteraction: beta enum only. accepted = v1.0 list is doc lag)'),
                @('create.guidAsUpn', 'guid30d', ''))) {
            $J = $Jobs[$Pair[1]]
            Add-Finding -Key $Pair[0] -Value ($J.CreateOk ? 'accepted' : 'rejected') -Note (
                (Get-ShortError $J.CreateError) + $Pair[2])
        }
        #endregion create standard jobs
    }

    if ($TestUnfilteredCap) {
        #region concurrency / unfiltered cap (create only, never waited on)
        Write-Host ''
        Write-Host '== Unfiltered cap probe (create only) ==' -ForegroundColor Cyan
        Add-Finding -Key 'cap.openUnfilteredBefore' -Value $OpenUnfiltered.Count -Note (
            'Unfiltered jobs already notStarted/running before this probe.')
        $CapBodies = [ordered]@{
            capUnfilteredA    = $Window1h.Clone()
            capUnfilteredB    = $Window1h.Clone()
            capServiceOnlyC   = ($Window1h.Clone() + @{ serviceFilter = 'AzureActiveDirectory' })
            capFilteredD      = ($Window1h.Clone() +
                @{ userPrincipalNameFilters = @($TestUserUpn) })
            capUnfilteredE    = $Window1h.Clone()
            capServicePluralF = ($Window1h.Clone() +
                @{ serviceFilters = @('AzureActiveDirectory') })
        }
        foreach ($Name in $CapBodies.Keys) {
            $CapJob = Submit-AuditJob -Name $Name -Body $CapBodies[$Name] -NoWait
            $Jobs[$Name] = $CapJob
            Add-Finding -Key "cap.$Name" -Value ($CapJob.CreateOk ? 'accepted' : 'rejected') -Note (
                "$(Get-ShortError $CapJob.CreateError) after $($CapJob.CreateSecs)s")
        }
        Add-Finding -Key 'cap.interpretation' -Value 'see cap.* rows' -Note (
            'A accepted + B rejected = one open unfiltered job at a time. C rejected = the ' +
            'singular serviceFilter key is ignored. D accepted = filtered jobs unaffected. ' +
            'F accepted while A is open = the plural serviceFilters key is a real filter.')
        #endregion concurrency / unfiltered cap
    }

    if ($TestPaging) {
        #region paging job (wide unfiltered window)
        Write-Host ''
        Write-Host "== Paging job (unfiltered, $PagingDays days) ==" -ForegroundColor Cyan
        $PagingName = "paging${PagingDays}d"
        if ($Jobs[$PagingName]) {
            Write-Host "  reusing $PagingName ($($Jobs[$PagingName].Status))" -ForegroundColor Green
        }
        elseif ($OpenUnfiltered.Count -gt 0) {
            Add-Finding -Key 'paging.job' -Value 'skipped' -Note (
                "an unfiltered job is already open: $($OpenUnfiltered[0].displayName)")
        }
        else {
            $PagingWindow = @{
                filterStartDateTime = Get-UtcString $Now.AddDays(-$PagingDays)
                filterEndDateTime   = Get-UtcString $Now
            }
            $PagingJob = Submit-AuditJob -Name $PagingName -Body $PagingWindow
            $Jobs[$PagingName] = $PagingJob
            $PagingValue = $PagingJob.CreateOk ? 'created' : 'FAILED'
            Add-Finding -Key 'paging.job' -Value $PagingValue -Note (
                Get-ShortError $PagingJob.CreateError)
        }
        #endregion paging job
    }

    #region wait
    Write-Host ''
    $WaitHeader = "== Wait (timeout $TimeoutMinutes min, poll ${PollSeconds}s) =="
    Write-Host $WaitHeader -ForegroundColor Cyan
    $WaitParams = @{
        JobTable       = $Jobs
        TimeoutMinutes = $TimeoutMinutes
        PollSeconds    = $PollSeconds
    }
    $AllDone = Wait-AuditJob @WaitParams
    Add-Finding -Key 'wait.allTerminal' -Value $AllDone
    foreach ($J in $Jobs.Values) {
        if ($J.Id -and -not $J.NoWait -and -not $J.Reused) {
            Add-Finding -Key "time.$($J.Name)" -Value "$($J.Status) in $($J.Seconds)s" -Note (
                @($J.Transitions) -join '; ')
        }
    }
    #endregion wait

    #region record shape
    Write-Host ''
    Write-Host '== Records: shape, ordering, $top ==' -ForegroundColor Cyan
    # first succeeded candidate that actually has records (a quiet 1h window can be empty)
    $ShapeJob = $null
    $Page1 = $null
    $Candidates = @(($TestPaging ? "paging${PagingDays}d" : $null), 'unfiltered1h',
        'v1Unfiltered1h', 'keyword30d', 'upn30d') | Where-Object { $_ }
    foreach ($Candidate in $Candidates) {
        if (-not $Jobs[$Candidate] -or $Jobs[$Candidate].Status -ne 'succeeded') { continue }
        $Probe = Invoke-GraphCall -Uri "$BetaBase/queries/$($Jobs[$Candidate].Id)/records?`$top=999"
        if ($Probe.Ok -and $Probe.Result.value.Count -gt 0) {
            $ShapeJob = $Jobs[$Candidate]
            $Page1 = $Probe
            break
        }
        Add-Finding -Key "record.shapeCandidate.$Candidate" -Value 'skipped' -Note (
            $Probe.Ok ? 'no records' : (Get-ShortError $Probe.Error))
    }
    if ($ShapeJob) {
        Add-Finding -Key 'record.shapeJob' -Value $ShapeJob.Name
        $First = $Page1.Result.value[0]
        $Summary = Get-RecordSummary -Record $First
        Add-Finding -Key 'record.properties' -Value ($Summary.properties -join ', ')
        Add-Finding -Key 'record.auditDataType' -Value $Summary.auditDataType -Note (
            'Hashtable = object in JSON; String = JSON string like Search-UnifiedAuditLog')
        Add-Finding -Key 'record.auditDataKeys' -Value ($Summary.auditDataKeys -join ', ') -Note (
            'Compare casing with classic AuditData: Workload, Operation, ClientIP, Actor, ...')
        Add-Finding -Key 'record.auditData.RecordType' -Value $Summary.auditDataRecordType -Note (
            'Classic AuditData carries RecordType as an integer.')
        $Values = $Page1.Result.value
        $TypeValues = @($Values | ForEach-Object { $_.auditLogRecordType } | Sort-Object -Unique)
        Add-Finding -Key 'record.recordTypeValues' -Value ($TypeValues -join ', ') -Note (
            'Note the casing.')
        Add-Finding -Key 'record.userTypeValues' -Value (
            @($Values | ForEach-Object { $_.userType } | Sort-Object -Unique) -join ', ')
        Add-Finding -Key 'record.serviceValues' -Value (
            @($Values | ForEach-Object { $_.service } | Sort-Object -Unique) -join ', ')
        Add-Finding -Key 'record.ordering.page1' -Value (Get-Ordering -Records $Values)
        Add-Finding -Key 'record.page1Count' -Value $Values.Count
        Add-Finding -Key 'record.nextLink' -Value ([string]$Page1.Result.'@odata.nextLink') -Note (
            'Empty means the whole job fit in one page of 999.')
        $Raw['record.sample'] = $First
        $Raw['record.sampleAuditDataJson'] = $First.auditData | ConvertTo-Json -Depth 10 -Compress

        # raw JSON view, to be sure about auditData being an object vs a string
        $RawUri = "$BetaBase/queries/$($ShapeJob.Id)/records?`$top=2"
        $RawPage = Invoke-GraphCall -Uri $RawUri -OutputType 'Json'
        if ($RawPage.Ok) {
            $IsObject = $RawPage.Result -match '"auditData"\s*:\s*\{'
            $IsString = $RawPage.Result -match '"auditData"\s*:\s*"'
            Add-Finding -Key 'record.auditDataJsonForm' -Value (
                $IsObject ? 'object' : ($IsString ? 'string' : 'unknown'))
            $Raw['record.rawJsonHead'] = $RawPage.Result.Substring(
                0, [Math]::Min(4000, $RawPage.Result.Length))
        }

        # $top probes; only meaningful when the job has more than 999 records
        Add-Finding -Key 'record.topProbeMeaningful' -Value ($Values.Count -ge 999) -Note (
            'False = the job is smaller than one page, so $top above 999 cannot be judged.')
        foreach ($Top in @(1000, 2000, 5000)) {
            $TopUri = "$BetaBase/queries/$($ShapeJob.Id)/records?`$top=$Top"
            $TopResponse = Invoke-GraphCall -Uri $TopUri
            $Val = $TopResponse.Ok ? "ok, returned $($TopResponse.Result.value.Count)" : 'FAILED'
            Add-Finding -Key "record.top$Top" -Value $Val -Note (Get-ShortError $TopResponse.Error)
        }
        $TopSmall = Invoke-GraphCall -Uri "$BetaBase/queries/$($ShapeJob.Id)/records?`$top=3"
        if ($TopSmall.Ok) {
            $SmallCount = $TopSmall.Result.value.Count
            Add-Finding -Key 'record.top3Honored' -Value ($SmallCount -le 3) -Note (
                "returned $($TopSmall.Result.value.Count); " +
                "nextLink present: $([bool]$TopSmall.Result.'@odata.nextLink')")
        }
    }
    else {
        Add-Finding -Key 'record.shape' -Value 'skipped' -Note 'no succeeded job with records'
    }
    #endregion record shape

    #region paging stability (shape job, twice)
    Write-Host ''
    Write-Host '== Paging stability ==' -ForegroundColor Cyan
    $GraphSet = $null
    if ($ShapeJob) {
        $Pass1 = Get-AuditRecordSet -Id $ShapeJob.Id -Max $MaxCompareRecords
        $GraphSet = $Pass1
        Add-Finding -Key "paging.$($ShapeJob.Name).pass1" -Value (
            "count=$($Pass1.Count) pages=$($Pass1.Pages) seconds=$($Pass1.Seconds) " +
            "truncated=$($Pass1.Truncated)") -Note (Get-ShortError $Pass1.Error)
        Add-Finding -Key 'paging.nextLinkShape' -Value ([string]$Pass1.FirstNextLink)
        Add-Finding -Key 'paging.multiPage' -Value ($Pass1.Pages -gt 1) -Note (
            'False = every stability number below comes from a single page; rerun with ' +
            '-TestPaging on a busier tenant or a wider -PagingDays.')
        if (-not $Pass1.Truncated -and -not $Pass1.Error -and $Pass1.Count -gt 0) {
            $Set1 = Get-IdSet -Records $Pass1.Records
            Add-Finding -Key "paging.$($ShapeJob.Name).dupesWithinPass1" -Value $Set1.Dupes -Note (
                'Same id returned more than once inside one full enumeration.')
            $Pass2 = Get-AuditRecordSet -Id $ShapeJob.Id -Max $MaxCompareRecords
            $Set2 = Get-IdSet -Records $Pass2.Records
            $OnlyIn1 = [System.Collections.Generic.HashSet[string]]::new($Set1.Set)
            $OnlyIn1.ExceptWith($Set2.Set)
            $OnlyIn2 = [System.Collections.Generic.HashSet[string]]::new($Set2.Set)
            $OnlyIn2.ExceptWith($Set1.Set)
            Add-Finding -Key "paging.$($ShapeJob.Name).stability" -Value (
                "pass1=$($Set1.Set.Count) pass2=$($Set2.Set.Count) " +
                "onlyIn1=$($OnlyIn1.Count) onlyIn2=$($OnlyIn2.Count)") -Note (
                'Non-zero onlyIn* reproduces the Q&A inconsistency report.')
            Add-Finding -Key 'record.ordering.full' -Value (Get-Ordering -Records $Pass1.Records)

            # Graph id vs the id inside auditData (needed to dedupe across sources)
            $AuditIds = Get-AuditDataIdSet -Records $Pass1.Records
            $SameId = 0
            foreach ($R in $Pass1.Records) {
                $IsDict = $R.auditData -is [System.Collections.IDictionary]
                $Inner = $IsDict ? $R.auditData['Id'] : $null
                if ([string]$Inner -eq [string]$R.id) { $SameId++ }
            }
            Add-Finding -Key 'record.idEqualsAuditDataId' -Value (
                "$SameId of $($Pass1.Count); auditData.Id dupes=$($AuditIds.Dupes) " +
                "missing=$($AuditIds.Missing)")
            $Raw['paging.recordTypeDistribution'] = Get-RecordTypeDistribution -Records (
                $Pass1.Records)
        }
        else {
            Add-Finding -Key "paging.$($ShapeJob.Name).stability" -Value 'skipped' -Note (
                "truncated=$($Pass1.Truncated) error=$(Get-ShortError $Pass1.Error) " +
                "count=$($Pass1.Count)")
        }
    }
    else {
        Add-Finding -Key 'paging' -Value 'skipped' -Note 'no shape job'
    }
    #endregion paging stability

    #region compare with Search-UnifiedAuditLog
    if ($CompareExchange) {
        Write-Host ''
        Write-Host '== Compare with Search-UnifiedAuditLog ==' -ForegroundColor Cyan
        $Exo = Get-Command -Name 'Search-UnifiedAuditLog' -ErrorAction SilentlyContinue
        if (-not $Exo) {
            Add-Finding -Key 'compare.exchange' -Value 'skipped' -Note (
                'Search-UnifiedAuditLog not available; connect to Exchange Online first.')
        }
        elseif (-not $ShapeJob -or -not $GraphSet -or $GraphSet.Truncated -or $GraphSet.Error) {
            Add-Finding -Key 'compare.exchange' -Value 'skipped' -Note (
                'needs a complete Graph enumeration of the shape job')
        }
        else {
            $StartUtc = [datetime]::Parse($ShapeJob.Body.filterStartDateTime).ToUniversalTime()
            $EndUtc = [datetime]::Parse($ShapeJob.Body.filterEndDateTime).ToUniversalTime()
            Add-Finding -Key 'compare.window' -Value (
                "$(Get-UtcString $StartUtc) .. $(Get-UtcString $EndUtc)")
            $ExoParams = @{
                StartUtc = $StartUtc
                EndUtc   = $EndUtc
                Max      = $MaxCompareRecords
            }
            $ExoSet = Get-ExchangeRecordSet @ExoParams
            Add-Finding -Key 'compare.exchange.pull' -Value (
                "count=$($ExoSet.Count) pages=$($ExoSet.Pages) seconds=$($ExoSet.Seconds) " +
                "truncated=$($ExoSet.Truncated)") -Note (Get-ShortError $ExoSet.Error)
            if ($ExoSet.Count -gt 0 -and -not $ExoSet.Error) {
                $ExoIdentity = Get-IdSet -Records $ExoSet.Records -Property 'Identity'
                $ExoAudit = Get-AuditDataIdSet -Records $ExoSet.Records
                Add-Finding -Key 'compare.exchange.dupes' -Value (
                    "identityDupes=$($ExoIdentity.Dupes) auditDataIdDupes=$($ExoAudit.Dupes) " +
                    "distinctIdentity=$($ExoIdentity.Set.Count) " +
                    "distinctAuditDataId=$($ExoAudit.Set.Count)") -Note (
                    'auditDataIdDupes > identityDupes = the same event came back under ' +
                    'different Identity values (the legacy dedupe misses those).')
                $GraphAudit = Get-AuditDataIdSet -Records $GraphSet.Records
                $Both = [System.Collections.Generic.HashSet[string]]::new($GraphAudit.Set)
                $Both.IntersectWith($ExoAudit.Set)
                $GraphOnly = [System.Collections.Generic.HashSet[string]]::new($GraphAudit.Set)
                $GraphOnly.ExceptWith($ExoAudit.Set)
                $ExoOnly = [System.Collections.Generic.HashSet[string]]::new($ExoAudit.Set)
                $ExoOnly.ExceptWith($GraphAudit.Set)
                Add-Finding -Key 'compare.byAuditDataId' -Value (
                    "graph=$($GraphAudit.Set.Count) exchange=$($ExoAudit.Set.Count) " +
                    "both=$($Both.Count) graphOnly=$($GraphOnly.Count) " +
                    "exchangeOnly=$($ExoOnly.Count)") -Note (
                    'exchangeOnly can include records ingested after the Graph job ran.')
                $Samples = [System.Collections.Generic.List[object]]::new()
                foreach ($R in $ExoSet.Records) {
                    if ($Samples.Count -ge 8) { break }
                    $Data = $R.AuditData
                    if ($Data -is [string]) {
                        try { $Data = $Data | ConvertFrom-Json -Depth 10 } catch { $Data = $null }
                    }
                    if ($Data -and $ExoOnly.Contains([string]$Data.Id)) {
                        $Samples.Add([ordered]@{
                                Identity     = $R.Identity
                                RecordType   = $R.RecordType
                                Operations   = $R.Operations
                                CreationDate = $R.CreationDate
                            })
                    }
                }
                $Raw['compare.exchangeOnlySamples'] = @($Samples)
                $Samples = [System.Collections.Generic.List[object]]::new()
                foreach ($R in $GraphSet.Records) {
                    if ($Samples.Count -ge 8) { break }
                    $IsDict = $R.auditData -is [System.Collections.IDictionary]
                    $Inner = $IsDict ? $R.auditData['Id'] : $null
                    if ($Inner -and $GraphOnly.Contains([string]$Inner)) {
                        $Samples.Add([ordered]@{
                                id              = $R.id
                                recordType      = $R.auditLogRecordType
                                operation       = $R.operation
                                createdDateTime = $R.createdDateTime
                            })
                    }
                }
                $Raw['compare.graphOnlySamples'] = @($Samples)
            }
        }
    }
    #endregion compare with Search-UnifiedAuditLog

    #region filter semantics
    Write-Host ''
    Write-Host '== Filter semantics ==' -ForegroundColor Cyan
    $Sets = @{}
    foreach ($Name in @('upn30d', 'keyword30d', 'guid30d', 'rtPascal7d', 'rtCamel7d')) {
        $J = $Jobs[$Name]
        if (-not $J -or $J.Status -ne 'succeeded') {
            Add-Finding -Key "filter.$Name" -Value 'skipped' -Note "status: $($J.Status)"
            continue
        }
        $R = Get-AuditRecordSet -Id $J.Id -Max $MaxCompareRecords
        $Sets[$Name] = $R
        Add-Finding -Key "filter.$Name.count" -Value (
            "count=$($R.Count) pages=$($R.Pages) seconds=$($R.Seconds) " +
            "truncated=$($R.Truncated)") -Note (Get-ShortError $R.Error)
        if ($R.Count -gt 0) {
            $Raw["record.sample.$Name"] = Get-RecordSummary -Record $R.Records[0]
            Add-Finding -Key "filter.$Name.ordering" -Value (Get-Ordering -Records $R.Records)
        }
    }

    if ($Sets['upn30d'] -and $Sets['keyword30d']) {
        $UpnIds = (Get-IdSet -Records $Sets['upn30d'].Records).Set
        $KwIds = (Get-IdSet -Records $Sets['keyword30d'].Records).Set
        $Both = [System.Collections.Generic.HashSet[string]]::new($UpnIds)
        $Both.IntersectWith($KwIds)
        $KwOnly = [System.Collections.Generic.HashSet[string]]::new($KwIds)
        $KwOnly.ExceptWith($UpnIds)
        $UpnOnly = [System.Collections.Generic.HashSet[string]]::new($UpnIds)
        $UpnOnly.ExceptWith($KwIds)
        Add-Finding -Key 'filter.keywordVsUpn' -Value (
            "upn=$($UpnIds.Count) keyword=$($KwIds.Count) both=$($Both.Count) " +
            "keywordOnly=$($KwOnly.Count) upnOnly=$($UpnOnly.Count)") -Note (
            'keywordOnly > 0 = keywordFilter finds target-side hits like legacy FreeText. ' +
            'upnOnly = 0 = keywordFilter is a superset of the UPN filter.')

        # characterize keyword-only hits: UPN inside auditData while the actor is someone else
        $Samples = [System.Collections.Generic.List[object]]::new()
        $TargetSide = 0
        foreach ($Rec in $Sets['keyword30d'].Records) {
            if (-not $KwOnly.Contains([string]$Rec.id)) { continue }
            $Json = $Rec.auditData | ConvertTo-Json -Depth 10 -Compress
            $InAuditData = $Json -match [regex]::Escape($TestUserUpn)
            $ActorIsUser = [string]$Rec.userPrincipalName -eq $TestUserUpn
            if ($InAuditData -and -not $ActorIsUser) { $TargetSide++ }
            if ($Samples.Count -lt 8) {
                $Samples.Add([ordered]@{
                        id                = $Rec.id
                        userPrincipalName = $Rec.userPrincipalName
                        recordType        = $Rec.auditLogRecordType
                        operation         = $Rec.operation
                        upnInAuditData    = $InAuditData
                    })
            }
        }
        Add-Finding -Key 'filter.keywordOnly.targetSideHits' -Value $TargetSide -Note (
            'keyword-only records where the UPN is in auditData but the actor is someone else.')
        $Raw['filter.keywordOnlySamples'] = @($Samples)
    }

    if ($Sets['upn30d'] -and $Sets['guid30d']) {
        $UpnIds = (Get-IdSet -Records $Sets['upn30d'].Records).Set
        $GuidIds = (Get-IdSet -Records $Sets['guid30d'].Records).Set
        $GuidOnly = [System.Collections.Generic.HashSet[string]]::new($GuidIds)
        $GuidOnly.ExceptWith($UpnIds)
        Add-Finding -Key 'filter.guidVsUpn' -Value (
            "upn=$($UpnIds.Count) guid=$($GuidIds.Count) guidOnly=$($GuidOnly.Count)") -Note (
            'guid=0 = userPrincipalNameFilters ignores object ids.')
    }

    if ($Sets['rtPascal7d'] -and $Sets['rtCamel7d']) {
        $P = (Get-IdSet -Records $Sets['rtPascal7d'].Records).Set
        $C = (Get-IdSet -Records $Sets['rtCamel7d'].Records).Set
        Add-Finding -Key 'filter.recordTypeCase' -Value (
            "pascal=$($P.Count) camel=$($C.Count) identicalSets=$($P.SetEquals($C))") -Note (
            'Both accepted and identical = enum is case-insensitive; no mapping needed.')
        Add-Finding -Key 'filter.recordType.returnedValues' -Value (
            @($Sets['rtPascal7d'].Records | ForEach-Object { $_.auditLogRecordType } |
                    Sort-Object -Unique) -join ', ')
    }
    elseif ($Sets['rtPascal7d'] -or $Sets['rtCamel7d']) {
        $Which = $Sets['rtPascal7d'] ? 'PascalCase only' : 'camelCase only'
        Add-Finding -Key 'filter.recordTypeCase' -Value $Which -Note (
            'Only one casing produced a job.')
    }
    #endregion filter semantics

    #region list endpoint capabilities
    Write-Host ''
    Write-Host '== List endpoint ==' -ForegroundColor Cyan
    $ListAfter = Invoke-GraphCall -Uri "$BetaBase/queries"
    if ($ListAfter.Ok) {
        $TotalAfter = @($ListAfter.Result.value).Count
        Add-Finding -Key 'list.totalAfter' -Value $TotalAfter
        if (-not $Findings.Contains('list.queryProperties')) {
            Add-ListProperty -ListResult $ListAfter.Result -Key 'list.queryProperties'
        }
        $Mine = @($ListAfter.Result.value | Where-Object { $_.displayName -like "$Prefix*" })
        Add-Finding -Key 'list.prefixedJobsVisible' -Value $Mine.Count
        $Raw['list.after.names'] = @($ListAfter.Result.value | ForEach-Object {
                "$($_.displayName) [$($_.status)]"
            })
        $Succeeded = @($ListAfter.Result.value | Where-Object { $_.status -eq 'succeeded' }).Count
        $Escaped = [uri]::EscapeDataString("$Prefix")
        $Tests = [ordered]@{
            'list.top1'              = @{ Uri = "$BetaBase/queries?`$top=1"; Expect = 1 }
            'list.filter.startswith' = @{
                Uri    = "$BetaBase/queries?`$filter=startswith(displayName,'$Escaped')"
                Expect = $Mine.Count
            }
            'list.filter.status'     = @{
                Uri    = "$BetaBase/queries?`$filter=status eq 'succeeded'"
                Expect = $Succeeded
            }
            'list.select'            = @{
                Uri    = "$BetaBase/queries?`$select=id,displayName,status"
                Expect = -1
            }
            'list.orderby'           = @{
                Uri    = "$BetaBase/queries?`$orderby=displayName"
                Expect = -1
            }
        }
        foreach ($K in $Tests.Keys) {
            $R = Invoke-GraphCall -Uri $Tests[$K].Uri
            if (-not $R.Ok) {
                Add-Finding -Key $K -Value 'FAILED' -Note (Get-ShortError $R.Error)
                continue
            }
            $Count = @($R.Result.value).Count
            $Expect = $Tests[$K].Expect
            $Honored = switch ($K) {
                'list.select' { (@($R.Result.value)[0].Keys.Count -le 4) }
                'list.orderby' { 'n/a' }
                default {
                    ($Count -eq $Expect) -and
                    ($Count -ne $TotalAfter -or $Expect -eq $TotalAfter)
                }
            }
            Add-Finding -Key $K -Value "ok, $Count item(s), honored=$Honored" -Note (
                "expected $Expect if honored; total=$TotalAfter")
        }
    }
    else {
        Add-Finding -Key 'list.after' -Value 'FAILED' -Note (Get-ShortError $ListAfter.Error)
    }
    #endregion list endpoint capabilities

    #region delete
    Write-Host ''
    Write-Host '== Delete ==' -ForegroundColor Cyan
    if ($SkipDelete -or $ReuseJobs) {
        Add-Finding -Key 'delete' -Value 'skipped' -Note ($ReuseJobs ? 'reuse mode' : '-SkipDelete')
    }
    else {
        $Victim = @($Jobs.Values | Where-Object { $_.Id -and $_.Name -ne 'v1Unfiltered1h' } |
                Select-Object -Last 1)[0]
        if ($Victim) {
            $Del = Invoke-GraphCall -Method 'DELETE' -Uri "$BetaBase/queries/$($Victim.Id)"
            $Check = Invoke-GraphCall -Uri "$BetaBase/queries/$($Victim.Id)"
            $DelValue = $Del.Ok ? 'DELETE returned success' : 'DELETE failed'
            Add-Finding -Key 'delete' -Value $DelValue -Note (
                "target=$($Victim.Name); GET afterwards: $($Check.Ok ? 'still exists' : 'gone'); " +
                "error: $(Get-ShortError $Del.Error)")
        }
        else {
            Add-Finding -Key 'delete' -Value 'skipped' -Note 'no job to delete'
        }
    }
    #endregion delete
}
finally {
    Write-Host ''
    $Elapsed = $Script:Stopwatch.Elapsed.ToString('hh\:mm\:ss')
    Write-Host "== Saving results (elapsed $Elapsed) ==" -ForegroundColor Cyan
    Save-Result
}
