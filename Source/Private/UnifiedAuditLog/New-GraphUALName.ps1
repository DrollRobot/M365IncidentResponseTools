function New-GraphUALName {
    <#
    .SYNOPSIS
    Builds the displayName that identifies one audit search job on the tenant.

    .DESCRIPTION
    Internal helper. The Graph audit log query API stores no metadata of its own: a
    listed query has filters and a status but no created timestamp and nowhere to record
    which investigation it belongs to. Jobs also outlive the PowerShell session that
    created them, by up to thirty days. The displayName is therefore the only place to
    put everything needed to list, age, group and rebuild a search later.

    Format:

        <Prefix>UAL|<ObjectName>|<ProfileTag>|<Days>d|<yyMMdd-HHmm>|g<GroupId>|j<Index>

    for example:

        IRT: UAL|jdoe|Default|30d|260909-1412|g3f9a1c2b|j1

    The prefix matches the one used for email compliance searches
    (IRT_Config.JobNamePrefix) so every IRT-created artifact on a tenant is
    recognisable by the same marker. Fields are pipe separated because a pipe cannot
    appear in any of the values: ObjectName is sanitized here, and the rest are generated.

    .PARAMETER ObjectName
    Short name of the thing being searched, usually the user's mailbox alias or a
    sanitized service principal display name. Non alphanumeric characters are stripped.

    .PARAMETER ProfileTag
    Profile the search belongs to: 'Default', 'RiskyOperations' or 'SignInLogs'.

    .PARAMETER Days
    Number of days the search covers, used for display only.

    .PARAMETER GroupId
    Eight character group id shared by every job in one search.

    .PARAMETER Index
    Position of this job within its group, counting from 1.

    .PARAMETER Stamp
    Creation stamp in yyMMdd-HHmm form. Defaults to now. Every job in a group should
    share one stamp, so the caller normally generates it once and passes it in.

    .PARAMETER Prefix
    Name prefix. Defaults to IRT_Config.JobNamePrefix.

    .EXAMPLE
    ```powershell
    $Params = @{
        ObjectName = 'jdoe'
        ProfileTag = 'Default'
        Days       = 30
        GroupId    = '3f9a1c2b'
        Index      = 1
    }
    New-GraphUALName @Params
    ```
    Returns 'IRT: UAL|jdoe|Default|30d|260909-1412|g3f9a1c2b|j1'.

    .OUTPUTS
    [string] the displayName to submit to Graph.

    .NOTES
    Version: 1.0.0
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds a string; changes no state.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $ObjectName,

        [Parameter(Mandatory)]
        [string] $ProfileTag,

        [Parameter(Mandatory)]
        [int] $Days,

        [Parameter(Mandatory)]
        [string] $GroupId,

        [Parameter(Mandatory)]
        [int] $Index,

        [string] $Stamp,

        [string] $Prefix = (Get-IRTJobNamePrefix)
    )

    if (-not $Stamp) { $Stamp = (Get-Date).ToString('yyMMdd-HHmm') }

    # the pipe is the field separator, so it must not survive in a value. Strip anything
    # that is not alphanumeric, then fall back to a placeholder if nothing is left.
    $SafeName = $ObjectName -replace '[^a-zA-Z0-9]', ''
    if (-not $SafeName) { $SafeName = 'unknown' }

    $Parts = @(
        'UAL'
        $SafeName
        $ProfileTag
        "${Days}d"
        $Stamp
        "g${GroupId}"
        "j${Index}"
    )

    return $Prefix + ($Parts -join '|')
}
