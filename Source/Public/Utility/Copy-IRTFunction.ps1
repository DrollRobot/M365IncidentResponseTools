function Copy-IRTFunction {
    <#
    .SYNOPSIS
    Copies IRT helper functions to the clipboard for use on remote machines.

    .DESCRIPTION
    Retrieves function definitions from the loaded module in memory and
    concatenates them into a single pasteable script, then sends the result
    to the clipboard via Set-Clipboard.

    A bootstrap block that initialises $Global:IRT_Config (using the current
    session's color preferences as defaults) is prepended automatically.

    The default set includes:
      - Write-IRT, Get-RandomPassword, Get-YesNo
      - All On-Prem AD functions

    Use -FunctionName to include additional functions beyond the default set.

    .PARAMETER FunctionName
    One or more additional function names to include beyond the default set.
    Accepts pipeline input.

    .EXAMPLE
    Copy-IRTFunction

    Copies the default set of IRT helper functions to the clipboard.

    .EXAMPLE
    Copy-IRTFunction -FunctionName 'Get-IRTMessageTrace'

    Copies the default set plus Get-IRTMessageTrace.

    .EXAMPLE
    'Get-IRTInboxRule', 'Get-IRTMessageTrace' | Copy-IRTFunction

    Copies the default set plus both named functions via the pipeline.

    .OUTPUTS
    None. Output is sent to the clipboard.

    .NOTES
    Version: 2.0.0

    # FIXME add aliases matching m365 commands? finduser, disableuser, etc.?

    #>
    [Alias(
        'Copy-IRTFunctions', 'CopyIRTFunctions', 'CopyIRTFunction', 'IRTFunction', 'IRTFunctions')]
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string[]] $FunctionName
    )

    begin {
        $DefaultFunctions = @(
            # Core helpers
            'Write-IRT'
            'Get-RandomPassword'
            'Format-Tree'
            'Get-YesNo'
            # On-prem AD functions
            'Disable-IRTAdUser'
            'Enable-IRTAdUser'
            'Find-IRTAdDevice'
            'Find-IRTAdOu'
            'Find-IRTAdUser'
            'Find-IRTDomainController'
            'Get-IRTAdAdminUser'
            'Get-AdGlobalUserObject'
            'Push-IRTAdSync'
            'Reset-IRTAdUserPassword'
            'Set-AdUserEnabled'
            'Show-IRTAdDevice'
            'Show-IRTAdOus'
            'Show-IRTAdUser'
            'Test-AdAvailable'
            'Test-RunningOnDomainController'
        )

        $Queue = [System.Collections.Generic.List[string]]::new()
        foreach ($F in $DefaultFunctions) { $Queue.Add($F) }
    }

    process {
        foreach ($F in $FunctionName) {
            if ($Queue -notcontains $F) { $Queue.Add($F) }
        }
    }

    end {
        # Resolve current color values (or fallbacks) at copy-time so the pasted
        # code carries the user's preferences onto the remote machine.
        $infoColor = if ($Global:IRT_Config?.InfoColor) {
            $Global:IRT_Config.InfoColor
        } else { 'DarkCyan' }
        $warnColor = if ($Global:IRT_Config?.WarnColor) {
            $Global:IRT_Config.WarnColor
        } else { 'Yellow' }
        $errorColor = if ($Global:IRT_Config?.ErrorColor) {
            $Global:IRT_Config.ErrorColor
        } else { 'Red' }

        $Bootstrap = @"
if (-not `$Global:IRT_Config) {
    `$Global:IRT_Config = [PSCustomObject]@{
        InfoColor  = '$infoColor'
        WarnColor  = '$warnColor'
        ErrorColor = '$errorColor'
    }
}
"@

        $Builder = [System.Text.StringBuilder]::new()
        $null = $Builder.AppendLine($Bootstrap)

        $Resolved = 0
        foreach ($Name in $Queue) {
            $GcParams = @{
                Name        = $Name
                CommandType = 'Function'
                ErrorAction = 'SilentlyContinue'
            }
            $Cmd = Get-Command @GcParams
            if (-not $Cmd) {
                Write-IRT "Function not found in session: $Name" -Level Warn
                continue
            }
            $null = $Builder.AppendLine("function $Name {")
            $null = $Builder.AppendLine($Cmd.Definition)
            $null = $Builder.AppendLine('}')
            $null = $Builder.AppendLine()
            $Resolved++
        }

        if ($Resolved -eq 0) {
            Write-IRT 'No functions could be resolved.' -Level Warn
            return
        }

        $FmtParams = @{
            Content    = $Builder.ToString()
            Script     = $true
            Comments   = $true
            EmptyLines = $true
            Whitespace = $true
        }
        $Formatted = Format-Powershell @FmtParams
        Set-Clipboard -Value $Formatted
        Write-IRT "Copied $Resolved function(s) to clipboard."
    }
}
