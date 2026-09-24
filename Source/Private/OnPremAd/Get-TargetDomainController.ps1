function Get-TargetDomainController {
    <#
    .SYNOPSIS
    Returns the host name of the writable domain controller to make AD changes on.

    .DESCRIPTION
    Internal helper. Prefers this computer when it is a writable domain controller, so
    changes land on the DC the operator is working on. Otherwise returns a writable DC
    found by DC locator discovery.

    Discovery alone isn't enough: run on a DC, it can still return a peer DC (for example
    from its cache). Read-only DCs are skipped because they can't take changes.

    Requires the ActiveDirectory module. If this computer isn't a writable DC and
    discovery fails, the discovery error is thrown to the caller.

    .EXAMPLE
    ```powershell
    $DomainController = Get-TargetDomainController
    Set-ADUser -Identity $User -ChangePasswordAtLogon $true -Server $DomainController
    ```
    Makes the change on this computer if it is a writable DC, otherwise on a discovered
    writable DC.

    .OUTPUTS
    System.String. The DNS host name of the chosen domain controller.

    .NOTES
    Version: 1.0.0
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param ()

    # prefer this computer when it is a writable DC. not found means it isn't a DC
    try {
        $LocalDc = Get-ADDomainController -Identity $env:COMPUTERNAME -ErrorAction Stop
    }
    catch {
        $LocalDc = $null
    }
    if ($LocalDc -and -not $LocalDc.IsReadOnly -and $LocalDc.HostName) {
        return [string]$LocalDc.HostName
    }

    $DiscoverParams = @{
        Discover    = $true
        Writable    = $true
        ErrorAction = 'Stop'
    }
    return [string](
        Get-ADDomainController @DiscoverParams |
            Select-Object -ExpandProperty HostName -First 1
    )
}
