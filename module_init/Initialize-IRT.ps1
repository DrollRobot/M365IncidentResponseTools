# ScriptsToProcess - runs in the CALLER's scope (not the module's) on every Import-Module.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
param()
# Because this runs outside the module scope, the prompt function defined here is NOT
# tracked by the module and will NOT be removed when the module is reimported with -Force.

# vscode does weird stuff with the prompt function. excluding for now.
if ($env:TERM_PROGRAM -ne 'vscode') {

    # Back up the current prompt only if we haven't done so yet.
    # On a -Force reimport the current prompt is already the IRT prompt, so we must not
    # overwrite $Global:IRT_OriginalPrompt with our own scriptblock.
    if (-not $Global:IRT_OriginalPrompt -or $Global:IRT_OriginalPrompt -isnot [scriptblock]) {
        $Global:IRT_OriginalPrompt = (Get-Command prompt -ErrorAction SilentlyContinue).ScriptBlock
        if (-not $Global:IRT_OriginalPrompt) {
            $Global:IRT_OriginalPrompt = {
                "PS $($executionContext.SessionState.Path.CurrentLocation)" +
                    "$('>' * ($nestedPromptLevel + 1)) "
            }
        }
    }

    function prompt {
        # Best-effort: read PromptColor from the user config if it exists;
        # fall back to hard-coded default.
        $irt_jpParams = @{
            Path                = $env:APPDATA
            ChildPath           = 'M365IncidentResponseTools'
            AdditionalChildPath = 'config.json'
        }
        $irt_configPath = Join-Path @irt_jpParams
        $irt_color = try {
            if (Test-Path $irt_configPath) {
                $c = (Get-Content $irt_configPath -Raw | ConvertFrom-Json).PromptColor
                if ($c) {$c} else {'DarkYellow'}
            }
            else {'DarkYellow'}
        }
        catch {'DarkYellow'}
        $PromptColor = @{ForegroundColor = $irt_color }

        # Display connection status.
        # Update-IRTToken handles expiry checks and refresh; -PassThru returns current status.
        if ($Global:IRT_Session) {
            $irt_status    = Update-IRTToken -SkipIfNeverConnected -PassThru
            $irt_connected = @('Graph', 'Exchange', 'IPPS') | Where-Object { $irt_status[$_] }
            $irt_domain    = $null
            foreach ($irt_svc in $irt_connected) {
                $irt_obj = $Global:IRT_Session.$irt_svc
                $irt_upn = $irt_obj.Account ?? $irt_obj.UserPrincipalName
                if ($irt_upn) { $irt_domain = ($irt_upn -split '@')[-1]; break }
            }
        } else {
            $irt_connected = @()
            $irt_domain    = $null
        }

        Write-Host ''
        Write-Host @PromptColor '[IRT] Connected:' -NoNewline
        if ($irt_connected) {
            Write-Host ($irt_connected -join ',') -NoNewline
            if ($irt_domain) {
                Write-Host @PromptColor ' Domain:' -NoNewline
                Write-Host $irt_domain -NoNewline
            }
        } else {
            Write-Host 'none' -NoNewline
        }
        if ($Global:IRT_UserObjects) {
            $irt_userList = ($Global:IRT_UserObjects.UserPrincipalName) -join ', '
            Write-Host @PromptColor ' User:' -NoNewline
            Write-Host $irt_userList -NoNewline
        }

        Write-Host ''
        & $Global:IRT_OriginalPrompt
    }
}
