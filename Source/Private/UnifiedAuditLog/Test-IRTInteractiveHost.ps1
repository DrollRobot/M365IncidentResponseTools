function Test-IRTInteractiveHost {
    <#
    .SYNOPSIS
    Reports whether the current host can prompt the user.

    .DESCRIPTION
    Internal helper. A menu shown in a host that cannot read input does not fail visibly;
    it blocks, with nothing on screen to explain why. This checks before prompting so
    callers can fall back to a sensible default instead.

    Two conditions make a host non-interactive here: PowerShell started with
    -NonInteractive, and a runspace worker, where a prompt would be invisible to whoever
    started the parent command.

    .EXAMPLE
    ```powershell
    if (Test-IRTInteractiveHost) { $Choice = Build-Menu @MenuParams }
    ```
    Prompts only when there is someone to answer.

    .OUTPUTS
    [bool] whether the host can prompt.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if ($Global:IRT_IsRunspaceWorker) { return $false }

    # -NonInteractive is surfaced on the command line rather than as a host property
    $CommandLine = [Environment]::GetCommandLineArgs() -join ' '
    if ($CommandLine -match '-NonInteractive') { return $false }

    return $true
}
