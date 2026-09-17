function Get-GraphUALJob {
    <#
    .SYNOPSIS
    Lists audit search jobs on the tenant, parsed and grouped.

    .DESCRIPTION
    Internal helper. Fetches the audit log query collection and turns each entry into an
    object carrying both what the API reports (id, status, filters) and what the display
    name encodes (object name, profile, group, age).

    The collection is always fetched whole. The endpoint ignores $top, $filter, $select and
    $orderby, so every filter here is applied locally.

    Jobs whose names this module did not write are included only with -All. They are
    listed with a null GroupId, since there is no way to know what they belong to or how
    to rebuild their output.

    Every job the tenant still holds is listed, including ones already downloaded. The API
    has no delete, so a finished search stays visible until Purview expires it after about
    thirty days. Downloaded results are matched to their search by name instead: the
    exported file carries the same stamp and group id as the search that produced it.

    .PARAMETER All
    Include jobs that were not created by this module.

    .PARAMETER Prefix
    Name prefix identifying this module's jobs. Defaults to IRT_Config.JobNamePrefix.

    .EXAMPLE
    ```powershell
    Get-GraphUALJob
    ```
    Lists this module's audit search jobs on the tenant.

    .OUTPUTS
    [pscustomobject[]] one per job, with Id, DisplayName, Status, GroupId, ObjectName,
    ProfileTag, Days, Stamp, Index, Label, Created, StartUtc, EndUtc, FilePrefix and
    SheetTitle.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    [OutputType([psobject[]])]
    param(
        [switch] $All,

        [string] $Prefix = (Get-IRTJobNamePrefix)
    )

    Import-IRTModule -Name 'PSFramework'
    $FunctionName = $MyInvocation.MyCommand.Name

    $Response = Invoke-GraphUALRequest -Path 'queries'
    if (-not $Response.Ok) {
        Write-IRT "Could not list audit searches: $($Response.Status)" -Level Error
        return [psobject[]]@()
    }

    $Jobs = [System.Collections.Generic.List[psobject]]::new()

    # profile metadata is needed to rebuild file names and sheet titles at download time,
    # and the display name only carries the tag
    $ProfileInfo = @{
        Default         = @{
            FilePrefix = 'UnifiedAuditLogs'
            SheetTitle = 'Unified audit logs'
        }
        RiskyOperations = @{
            FilePrefix = 'UALRiskyOperations'
            SheetTitle = 'UAL risky operations'
        }
        SignInLogs      = @{
            FilePrefix = 'UALSignInLogs'
            SheetTitle = 'UAL sign-in logs'
        }
    }

    foreach ($Query in @($Response.Result.value)) {

        $Parsed = Read-GraphUALName -Name $Query.displayName -Prefix $Prefix
        $IsOurs = $null -ne $Parsed
        if (-not $IsOurs -and -not $All) { continue }

        $Info = $ProfileInfo[$Parsed.ProfileTag]
        if (-not $Info) {
            $Info = @{ FilePrefix = 'UnifiedAuditLogs'; SheetTitle = 'Unified audit logs' }
        }

        # a filter summary is what makes one job in a group distinguishable from another
        $Label = Get-GraphUALJobLabel -Query $Query

        $StartUtc = $null
        $EndUtc = $null
        try {
            if ($Query.filterStartDateTime) {
                $StartUtc = ([datetime]$Query.filterStartDateTime).ToUniversalTime()
            }
            if ($Query.filterEndDateTime) {
                $EndUtc = ([datetime]$Query.filterEndDateTime).ToUniversalTime()
            }
        }
        catch {
            Write-PSFMessage -Level 9 -Message (
                "${FunctionName}: unparseable filter dates on '$($Query.displayName)'.")
        }

        $Jobs.Add([pscustomobject]@{
                Id          = [string]$Query.id
                DisplayName = [string]$Query.displayName
                Status      = [string]$Query.status
                IsOurs      = $IsOurs
                GroupId     = $Parsed.GroupId
                ObjectName  = $Parsed ? $Parsed.ObjectName : '(external)'
                ProfileTag  = $Parsed ? $Parsed.ProfileTag : 'Default'
                Days        = $Parsed ? $Parsed.Days : 0
                Index       = $Parsed ? $Parsed.Index : 0
                Created     = $Parsed.Created
                Stamp       = $Parsed.Stamp
                Label       = $Label
                StartUtc    = $StartUtc
                EndUtc      = $EndUtc
                FilePrefix  = $Info.FilePrefix
                SheetTitle  = $Info.SheetTitle
            })
    }

    Write-PSFMessage -Level 8 -Message "${FunctionName}: returning $($Jobs.Count) job(s)."
    return $Jobs.ToArray()
}
