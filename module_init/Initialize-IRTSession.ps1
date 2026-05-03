# ScriptsToProcess - runs in the CALLER's scope (not the module's) on every Import-Module.
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
            $Global:IRT_OriginalPrompt = { "PS $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) " }
        }
    }

    function prompt {
        # Best-effort: read PromptColor from the user config if it exists; fall back to hard-coded default.
        $irt_configPath = Join-Path $env:APPDATA 'M365IncidentResponseTools' 'config.json'
        $irt_color = try {
            if (Test-Path $irt_configPath) {
                $c = (Get-Content $irt_configPath -Raw | ConvertFrom-Json).PromptColor
                if ($c) {$c} else {'DarkYellow'}
            }
            else {'DarkYellow'}
        }
        catch {'DarkYellow'}
        $PromptColor = @{ForegroundColor = $irt_color }

        # Display connection status for Graph and Exchange
        # This is a bit hacky but avoids the need to maintain global state about connection status

        $GraphCtx = Get-MgContext -ErrorAction SilentlyContinue
        $graphDomain = if ($GraphCtx -and $GraphCtx.Account) { ($GraphCtx.Account -split '@')[-1] } else { 'none' }

        $AllExoConns = Get-ConnectionInformation -ErrorAction SilentlyContinue |
        Where-Object { $_.State -eq 'Connected' }
        $ExoConn = $AllExoConns |
        Where-Object { $_.ConnectionUri -notmatch 'compliance\.protection\.(outlook\.com|office365\.us)' } |
        Select-Object -First 1
        $exoDomain = if ($ExoConn -and $ExoConn.UserPrincipalName) { ($ExoConn.UserPrincipalName -split '@')[-1] } else { 'none' }
        $ippsConnected = [bool]($AllExoConns |
            Where-Object { $_.ConnectionUri -match 'compliance\.protection\.(outlook\.com|office365\.us)' })

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
