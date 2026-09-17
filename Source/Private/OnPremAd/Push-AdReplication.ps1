function Push-AdReplication {
    <#
    .SYNOPSIS
    Pushes AD replication from one domain controller to all of its partners.

    .DESCRIPTION
    Internal helper. Runs 'repadmin /syncall <Server> /APed' (all partitions, push, across
    sites, DNs in output) so changes made on Server reach every other DC. Works from any
    device with repadmin, which is installed with the AD DS RSAT tools and on every DC; it
    does not need to run on the DC itself. Warns and returns if repadmin isn't installed,
    or if it exits with a non-zero code.

    .PARAMETER Server
    The domain controller to push replication from. Pass the DC where the change was made.

    .EXAMPLE
    ```powershell
    Push-AdReplication -Server 'dc01.contoso.com'
    ```
    Pushes changes made on dc01 out to every other domain controller.

    .OUTPUTS
    None. Status is written to the console.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Server
    )

    if (-not (Get-Command -Name 'repadmin' -ErrorAction SilentlyContinue)) {
        Write-IRT 'repadmin not found on this device. Skipping AD replication push.' -Level Warn
        return
    }

    Write-IRT "Pushing AD replication from ${Server}."
    $null = & repadmin /syncall $Server /APed *>&1
    if ($LASTEXITCODE -ne 0) {
        $Msg = "AD replication push from ${Server} failed " +
        "(repadmin exit code $LASTEXITCODE)."
        Write-IRT $Msg -Level Warn
    }
}
