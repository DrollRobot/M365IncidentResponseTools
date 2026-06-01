function Test-AdAvailable {
    <#
    .SYNOPSIS
    Returns true if the ActiveDirectory module is available and a domain controller can be reached.

    .DESCRIPTION
    Internal helper. Returns $true only when the ActiveDirectory RSAT module is installed
    AND Get-ADDomain succeeds (i.e., a domain controller is reachable). Returns $false on
    any error. Used as a guard condition at the top of every onprem_ad function.

    .NOTES
    Version: 2.0.0
    #>
    [OutputType([bool])]
    [CmdletBinding()]
    param ()

    if (-not (Get-Module -Name ActiveDirectory -ListAvailable)) {
        return $false
    }

    try {
        $null = Get-ADDomain -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}
