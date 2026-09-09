function Read-GraphUALName {
    <#
    .SYNOPSIS
    Parses an audit search displayName back into its parts.

    .DESCRIPTION
    Internal helper. Inverse of New-GraphUALName. Used when listing jobs on a tenant,
    where the displayName is the only record of which investigation a job belongs to,
    how old it is, and which group it shares with its siblings.

    Returns $null for anything that does not match the expected shape, including jobs
    created by another tool, by the Purview portal, or by an older version of this
    module. Callers should treat $null as "show it but do not try to act on it".

    Age is derived from the stamp rather than from the API, because a listed query object
    carries no created or modified timestamp.

    .PARAMETER Name
    The displayName to parse.

    .PARAMETER Prefix
    Expected name prefix. Defaults to IRT_Config.JobNamePrefix. A name that does
    not start with this prefix is not ours and returns $null.

    .EXAMPLE
    ```powershell
    Read-GraphUALName -Name 'IRT: UAL|jdoe|Default|30d|260909-1412|g3f9a1c2b|j1'
    ```
    Returns an object with ObjectName 'jdoe', ProfileTag 'Default', Days 30, GroupId
    '3f9a1c2b' and Index 1.

    .EXAMPLE
    ```powershell
    Read-GraphUALName -Name 'Some analyst search'
    ```
    Returns $null.

    .OUTPUTS
    [pscustomobject] with properties ObjectName, ProfileTag, Days, Stamp, Created,
    GroupId, Index; or $null when the name does not match.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $Name,

        [string] $Prefix = (Get-IRTJobNamePrefix)
    )

    if (-not $Name) { return $null }
    if ($Prefix -and -not $Name.StartsWith($Prefix)) { return $null }

    $Body = $Prefix ? $Name.Substring($Prefix.Length) : $Name
    $Parts = $Body -split '\|'

    # UAL | ObjectName | ProfileTag | <n>d | stamp | g<id> | j<n>
    if ($Parts.Count -ne 7) { return $null }
    if ($Parts[0] -ne 'UAL') { return $null }
    if ($Parts[3] -notmatch '^(\d+)d$') { return $null }
    $Days = [int]$Matches[1]
    if ($Parts[5] -notmatch '^g(.+)$') { return $null }
    $GroupId = $Matches[1]
    if ($Parts[6] -notmatch '^j(\d+)$') { return $null }
    $Index = [int]$Matches[1]

    # the stamp is local time at creation; a job from a differently configured machine
    # could fail to parse, so treat Created as best effort rather than required
    $Stamp = $Parts[4]
    $Created = $null
    try {
        $Culture = [System.Globalization.CultureInfo]::InvariantCulture
        $Created = [datetime]::ParseExact($Stamp, 'yyMMdd-HHmm', $Culture)
    }
    catch {
        $Created = $null
    }

    return [pscustomobject]@{
        ObjectName = $Parts[1]
        ProfileTag = $Parts[2]
        Days       = $Days
        Stamp      = $Stamp
        Created    = $Created
        GroupId    = $GroupId
        Index      = $Index
    }
}
