function Get-IRTJobNamePrefix {
    <#
    .SYNOPSIS
    Returns the prefix used to name jobs this module creates on a tenant.

    .DESCRIPTION
    Internal helper. Several features leave long-lived jobs behind on a tenant: email
    compliance searches, and Graph audit log queries. Both are prefixed with the same
    configurable marker so an analyst can tell at a glance which entries in a tenant were
    created by this module rather than by the portal or another tool.

    The setting is IRT_Config.JobNamePrefix. It was previously EmailSearchNamePrefix,
    which only described the first feature to use it, so the old key is still honoured for
    anyone whose saved configuration predates the rename.

    Falls back to 'IRT: ' when neither key is set.

    .EXAMPLE
    ```powershell
    $Prefix = Get-IRTJobNamePrefix
    ```
    Returns 'IRT: ' unless the configuration overrides it.

    .OUTPUTS
    [string] the configured prefix.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $Config = $Global:IRT_Config
    if ($Config) {
        if ($Config.JobNamePrefix) { return [string]$Config.JobNamePrefix }
        # honour the pre-rename key so an existing saved config keeps working
        if ($Config.EmailSearchNamePrefix) { return [string]$Config.EmailSearchNamePrefix }
    }
    return 'IRT: '
}
