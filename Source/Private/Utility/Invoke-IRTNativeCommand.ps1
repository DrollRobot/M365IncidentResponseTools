function Invoke-IRTNativeCommand {
    <#
    .SYNOPSIS
    Runs an external CLI tool and returns its stdout, stderr, and exit code.

    .DESCRIPTION
    Central wrapper for invoking external executables (e.g. ip_info, python, uv).
    Uses System.Diagnostics.Process with both standard streams redirected and
    decoded as UTF-8, so the caller always gets the tool's stdout and stderr as
    data instead of it printing raw to the console disconnected from IRT logging.

    Because both streams are captured (rather than inherited by the console) the
    tool's output is not streamed live -- live streaming would require writing to
    the host from background reader threads. Instead the captured stdout and
    stderr, the resolved path, argument count, command-line length, and exit code
    are written to the debug log via Write-PSFMessage -Level 8.

    Redirecting BOTH streams explicitly also avoids the
    "StandardOutputEncoding is only supported when standard output is redirected"
    error that PowerShell throws when only stderr is redirected (e.g. naive 2>).

    stdout and stderr are drained concurrently (stderr via ReadToEndAsync) to
    avoid the classic pipe-buffer deadlock when a tool fills one stream while the
    caller blocks reading the other.

    If the process cannot be started at all, ExitCode is -1 and StdErr carries the
    exception message, so callers can branch on ExitCode uniformly.

    .PARAMETER FilePath
    The executable to run. A bare command name (e.g. 'ip_info') is resolved to a
    full path via Get-Command, because Process.Start with UseShellExecute = $false
    does not reliably search PATH on all platforms.

    .PARAMETER Arguments
    Arguments passed to the executable. Supplied via ArgumentList, so each element
    is escaped individually and values are never re-parsed as a single string.

    .PARAMETER Environment
    Optional extra environment variables to set for the child process only (does
    not mutate the caller's session). For example, @{ PYTHONUTF8 = '1' } forces a
    Python tool to write UTF-8 to match this wrapper's UTF-8 decoding.

    .EXAMPLE
    $Result = Invoke-IRTNativeCommand -FilePath 'ip_info' -Arguments @(
        '--apis', 'bulk', '--output_format', 'jsontable', '--ip_addresses', '1.1.1.1')
    if ($Result.ExitCode -ne 0) { Write-IRT $Result.StdErr -Level Error }

    .OUTPUTS
    [pscustomobject] with StdOut ([string[]] of lines), StdErr ([string]), and
    ExitCode ([int]).

    .NOTES
    Version: 1.2.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $FilePath,

        [Parameter(Position = 1)]
        [string[]] $Arguments = @(),

        [hashtable] $Environment
    )

    Import-IRTModule -Name 'PSFramework'

    # Resolve a bare command name to its full executable path.
    $ResolvedPath = $FilePath
    if (-not (Test-Path -LiteralPath $FilePath)) {
        $Cmd = Get-Command -Name $FilePath -CommandType Application -ErrorAction Ignore |
            Select-Object -First 1
        if ($Cmd) { $ResolvedPath = $Cmd.Source }
    }

    $CmdLineLength = $ResolvedPath.Length + ($Arguments -join ' ').Length + 1
    Write-PSFMessage -Level 8 -Message (
        "Invoke-IRTNativeCommand: $ResolvedPath -- $($Arguments.Count) arg(s), " +
        "~$CmdLineLength char command line.")

    $StartInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $StartInfo.FileName = $ResolvedPath
    $StartInfo.UseShellExecute = $false
    $StartInfo.CreateNoWindow = $true
    $StartInfo.RedirectStandardOutput = $true
    $StartInfo.RedirectStandardError = $true
    $StartInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $StartInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    foreach ($Arg in $Arguments) { $StartInfo.ArgumentList.Add($Arg) }
    if ($Environment) {
        foreach ($Key in $Environment.Keys) {
            $StartInfo.Environment[$Key] = [string]$Environment[$Key]
        }
    }

    $Process = [System.Diagnostics.Process]::new()
    $Process.StartInfo = $StartInfo

    try {
        $null = $Process.Start()
    } catch {
        $Process.Dispose()
        $Message = $_.Exception.Message
        Write-PSFMessage -Level 8 -Message (
            "Invoke-IRTNativeCommand: failed to start '$ResolvedPath': $Message")
        return [pscustomobject]@{
            StdOut   = @()
            StdErr   = $Message
            ExitCode = -1
        }
    }

    # Drain stderr asynchronously while reading stdout to end, then join.
    $StdErrTask = $Process.StandardError.ReadToEndAsync()
    $StdOutText = $Process.StandardOutput.ReadToEnd()
    $Process.WaitForExit()
    $StdErrText = $StdErrTask.GetAwaiter().GetResult()
    $ExitCode = $Process.ExitCode
    $Process.Dispose()

    # The tool's output is captured rather than streamed, so route it to the debug
    # log where it is available without polluting normal command output.
    Write-PSFMessage -Level 8 -Message (
        "Invoke-IRTNativeCommand: exit $ExitCode -- stdout $($StdOutText.Length) " +
        "char(s), stderr $($StdErrText.Length) char(s).")
    if ($StdOutText.Trim()) {
        Write-PSFMessage -Level 8 -Message (
            "Invoke-IRTNativeCommand stdout: $($StdOutText.TrimEnd())")
    }
    if ($StdErrText.Trim()) {
        Write-PSFMessage -Level 8 -Message (
            "Invoke-IRTNativeCommand stderr: $($StdErrText.TrimEnd())")
    }

    # Normalize stdout to a line array so callers can scan/slice it.
    $StdOutLines = $StdOutText.Replace("`r`n", "`n").Split("`n")

    [pscustomobject]@{
        StdOut   = $StdOutLines
        StdErr   = $StdErrText
        ExitCode = $ExitCode
    }
}
