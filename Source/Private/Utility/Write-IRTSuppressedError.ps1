function Write-IRTSuppressedError {
    <#
    .SYNOPSIS
    Logs an error that is deliberately kept quiet, or reports it during live test runs.

    .DESCRIPTION
    FIXME: temporary workaround. Remove it, and its calls, once each caller can tell its
    normal failures from real ones.

    Some lookups keep their failures quiet because the failure is normal in some tenants,
    such as a user without a mailbox. The same code path also hides failures that are not
    normal, such as a missing permission. The two can't be told apart yet, because the
    unexpected errors haven't been reproduced to learn what they look like.

    On a normal run the error only goes to the debug log, so nothing changes for users.
    When the IRT_TEST_STRICT_ERRORS environment variable is '1', which the live test run
    sets, the error is reported with an Error-level Write-IRT message instead, so the
    tests fail on it. An environment variable is used rather than a parameter because it
    also reaches playbook steps, which run in their own PowerShell sessions.

    .PARAMETER ErrorRecord
    The caught error.

    .PARAMETER Message
    What was being attempted, such as "Get-EXOMailbox failed for jdoe@contoso.com". The
    error's own message is appended.

    .EXAMPLE
    ```powershell
    catch {
        Write-IRTSuppressedError -ErrorRecord $_ -Message "Get-EXOMailbox failed for $Upn"
    }
    ```
    Keeps the failure quiet on a normal run, and reports it during a live test run.

    .OUTPUTS
    None.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord] $ErrorRecord,

        [Parameter(Mandatory)]
        [string] $Message
    )

    Import-IRTModule -Name 'PSFramework'

    # name the function that caught the error, not this helper
    $Caller = (Get-PSCallStack | Select-Object -Skip 1 -First 1).Command
    $Text = "${Message}: $($ErrorRecord.Exception.Message)"

    if ($env:IRT_TEST_STRICT_ERRORS -eq '1') {
        Write-PSFMessage -Level 8 -Message "${Caller}: reporting (IRT_TEST_STRICT_ERRORS): $Text"
        Write-IRT $Text -Level Error -FunctionName $Caller
    }
    else {
        Write-PSFMessage -Level 8 -Message "${Caller}: kept quiet: $Text"
    }
}
