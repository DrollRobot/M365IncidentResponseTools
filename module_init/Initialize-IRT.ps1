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

        # Display connection status for Graph and Exchange.
        # Read token expiry directly from the session object - no network call needed.
        $graphDomain = 'none'

        if ($Global:IRT_Session) {
            # Refresh any service whose token expires within 30 minutes.
            $irt_needsRefresh = $false
            foreach ($svc in 'Graph', 'Exchange', 'IPPS') {
                $svcObj = $Global:IRT_Session.$svc
                if ($svcObj -and $svcObj.TokenExpiry -and
                    ($svcObj.TokenExpiry - [datetime]::UtcNow).TotalMinutes -lt 30) {
                    $irt_needsRefresh = $true
                }
            }
            if ($irt_needsRefresh) {
                Write-Host ''
                Write-Warning '[IRT] Token expiring soon - refreshing...' -NoNewline
                try { Connect-IRT -Refresh -ErrorAction Stop } catch {
                    Write-Host ''
                    Write-Warning "[IRT] Token refresh failed: $_"
                }
            }

            if ($Global:IRT_Session.Graph -and $Global:IRT_Session.Graph.TokenExpiry -and
                ($Global:IRT_Session.Graph.TokenExpiry - [datetime]::UtcNow).TotalMinutes -gt 0) {
                $graphDomain = ($Global:IRT_Session.Graph.Account -split '@')[-1]
            }
        }

        if ($Global:IRT_Session -and $Global:IRT_Session.Exchange -and
            $Global:IRT_Session.Exchange.TokenExpiry -and
            ($Global:IRT_Session.Exchange.TokenExpiry - [datetime]::UtcNow).TotalMinutes -gt 0) {
            $exoDomain = ($Global:IRT_Session.Exchange.UserPrincipalName -split '@')[-1]
        } else {
            $exoDomain = 'none'
        }
        $ippsConnected = $Global:IRT_Session -and $Global:IRT_Session.IPPS -and
            $Global:IRT_Session.IPPS.TokenExpiry -and
            ($Global:IRT_Session.IPPS.TokenExpiry - [datetime]::UtcNow).TotalMinutes -gt 0

        Write-Host ''
        Write-Host @PromptColor '[IRT] ' -NoNewline
        Write-Host @PromptColor 'Graph:' -NoNewline
        Write-Host $graphDomain -NoNewline
        Write-Host @PromptColor ' Exchange:' -NoNewline
        Write-Host $exoDomain -NoNewline
        Write-Host @PromptColor ' IPPS:' -NoNewline
        Write-Host $ippsConnected -NoNewline

        if ($Global:IRT_UserObjects) {
            $userList = ($Global:IRT_UserObjects.UserPrincipalName) -join ','
            Write-Host @PromptColor ' Users:' -NoNewline
            Write-Host $userList -NoNewline
        }

        Write-Host ''
        & $Global:IRT_OriginalPrompt
    }
}
