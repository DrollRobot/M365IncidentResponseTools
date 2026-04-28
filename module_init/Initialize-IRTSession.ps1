# ScriptsToProcess - runs in the CALLER's scope (not the module's) on every Import-Module.
# Because this runs outside the module scope, the prompt function defined here is NOT
# tracked by the module and will NOT be removed when the module is reimported with -Force.

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
        Write-Host '[IRT] ' -NoNewline -ForegroundColor Cyan
        Write-Host 'Graph:' -NoNewline -ForegroundColor Cyan
        Write-Host $graphDomain -NoNewline
        Write-Host ' Exchange:' -NoNewline -ForegroundColor Cyan
        Write-Host $exoDomain -NoNewline
        Write-Host ' IPPS:' -NoNewline -ForegroundColor Cyan
        Write-Host $ippsConnected -NoNewline

        if ($Global:IRT_UserObjects) {
            $userList = ($Global:IRT_UserObjects.UserPrincipalName) -join ','
            Write-Host ' Users:' -NoNewline -ForegroundColor Cyan
            Write-Host $userList -NoNewline
        }

        Write-Host ' ' -NoNewline
        & $Global:IRT_OriginalPrompt
    }
}
