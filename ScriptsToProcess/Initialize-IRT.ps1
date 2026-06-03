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
    # Use Get-Variable to avoid strict-mode errors when the variable is not yet set.
    $_irtPromptVar = Get-Variable -Name 'IRT_OriginalPrompt' -Scope Global -ErrorAction SilentlyContinue
    if ($null -eq $_irtPromptVar -or $_irtPromptVar.Value -isnot [scriptblock]) {
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
                if ($c) { $c } else { 'DarkYellow' }
            }
            else { 'DarkYellow' }
        }
        catch { 'DarkYellow' }
        $PromptColor = @{ForegroundColor = $irt_color }

        # Check actual live connections to display real status in the prompt.
        $irt_connected = @()
        $irt_domain = $null

        try {
            $GraphCtx = Get-MgContext -ErrorAction SilentlyContinue
            if ($GraphCtx -and $GraphCtx.Account) {
                try {
                    $null = Invoke-MgGraphRequest -Uri 'v1.0/organization?$select=id&$top=1' -ErrorAction Stop
                    $irt_connected += 'Graph'
                    if (-not $irt_domain) {
                        $irt_domain = ($GraphCtx.Account -split '@')[-1]
                    }
                } catch {
                    # Graph token invalid or expired
                }
            }
        } catch {
            # Ignore errors; Graph not available
        }

        try {
            $IppsPattern = 'compliance\.protection\.(outlook\.com|office365\.us)'
            $AllExoConns = Get-ConnectionInformation -ErrorAction SilentlyContinue |
                Where-Object { $_.State -eq 'Connected' }
            $ExoConn = $AllExoConns |
                Where-Object { $_.ConnectionUri -notmatch $IppsPattern } |
                Select-Object -First 1
            $IppsConn = $AllExoConns |
                Where-Object { $_.ConnectionUri -match $IppsPattern } |
                Select-Object -First 1

            if ($ExoConn) {
                $irt_connected += 'Exchange'
                if (-not $irt_domain -and $ExoConn.UserPrincipalName) {
                    $irt_domain = ($ExoConn.UserPrincipalName -split '@')[-1]
                }
            }
            if ($IppsConn) {
                $irt_connected += 'IPPS'
                if (-not $irt_domain -and $IppsConn.UserPrincipalName) {
                    $irt_domain = ($IppsConn.UserPrincipalName -split '@')[-1]
                }
            }
        } catch {
            # Ignore errors; Exchange/IPPS not available
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
