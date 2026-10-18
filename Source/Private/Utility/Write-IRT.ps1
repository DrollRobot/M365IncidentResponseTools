function Write-IRT {
    <#
    .SYNOPSIS
    Writes a colored, prefixed status message to the host.

    .DESCRIPTION
    Central output helper for IRT. Reads foreground colors from $Global:IRT_Config
    (InfoColor, WarnColor, ErrorColor) with hardcoded fallbacks so it works even
    before the config is loaded (e.g. in onprem_ad functions pasted to a remote
    machine).

    The calling function's name is detected automatically from the call stack and
    prepended to the message. Override it with -FunctionName when a parent function
    wants its name to appear on output from a child helper it calls.

    .PARAMETER Message
    The message text to display.

    .PARAMETER Level
    Output level: Info (default), Warn, or Error.

    .PARAMETER FunctionName
    Override the auto-detected caller name. Useful when a parent passes its own
    name down to a child helper: Request-GraphUser -FunctionName $MyInvocation.MyCommand.Name

    .PARAMETER NoNewline
    Passes -NoNewline through to Write-Host.

    .PARAMETER NoColor
    Suppresses color output. Useful when writing to a transcript or redirected
    stream that does not support ANSI color codes.

    .PARAMETER NoFunctionName
    Suppresses the calling function name prefix. Useful for plain status messages
    that do not need attribution.

    .EXAMPLE
    Write-IRT "Retrieving sign-in logs for $($User.DisplayName)."
    Writes an Info-level message with the calling function's name prepended.

    .EXAMPLE
    Write-IRT "No records found." -Level Warn
    Writes a yellow warning message.

    .OUTPUTS
    None. Output is written directly to the console. During a live test run
    (IRT_TEST_STRICT_ERRORS = '1'), an Error-level message is also written to the
    error stream.

    .NOTES
    Version: 1.1.0
    1.1.0 - FIXME temporary workaround: during live test runs, Error-level messages are
    also written to the error stream. See Write-IRTSuppressedError.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string] $Message = '',

        [ValidateSet('Info', 'Warn', 'Error')]
        [string] $Level = 'Info',

        [string] $FunctionName = '',
        [switch] $NoNewline,
        [switch] $NoColor,
        [switch] $NoFunctionName
    )

    if (-not $FunctionName) {
        $FunctionName = (
            Get-PSCallStack |
                Select-Object -Skip 1 |
                Where-Object { $_.Command -notlike '<*>' } |
                Select-Object -First 1
        ).Command
        if (-not $FunctionName) { $FunctionName = '<unknown>' }
    }

    $color = switch ($Level) {
        'Info' {
            if ($Global:IRT_Config?.InfoColor) {
                $Global:IRT_Config.InfoColor
            } else {
                'DarkCyan'
            }
        }
        'Warn' {
            if ($Global:IRT_Config?.WarnColor) {
                $Global:IRT_Config.WarnColor
            } else {
                'Yellow'
            }
        }
        'Error' {
            if ($Global:IRT_Config?.ErrorColor) {
                $Global:IRT_Config.ErrorColor
            } else {
                'Red'
            }
        }
    }

    $text = if ($Message -eq '') {
        ''
    } elseif ($NoFunctionName) {
        $Message
    } else {
        "${FunctionName}: ${Message}"
    }
    if ($NoColor) {
        Write-Host $text -NoNewline:$NoNewline
    } else {
        Write-Host $text -ForegroundColor $color -NoNewline:$NoNewline
    }

    # FIXME: temporary workaround, removed along with Write-IRTSuppressedError. Playbook
    # steps run in their own PowerShell sessions, where the live tests' Write-IRT mock
    # doesn't reach. Writing the message to the error stream during a live test run lets
    # the playbook pass it back like any other step error, so its test fails on it.
    if ($Level -eq 'Error' -and $env:IRT_TEST_STRICT_ERRORS -eq '1') {
        Write-Error -Message $text
    }
}
