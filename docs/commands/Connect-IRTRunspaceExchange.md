---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Connect-IRTRunspaceExchange

## SYNOPSIS
Establishes (or refreshes) a runspace-local Exchange Online connection.

## SYNTAX

```
Connect-IRTRunspaceExchange [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Intended for playbook runspace workers.
Mints a fresh Exchange token
silently from the shared MSAL cache (the parent session's
PublicClientApplication is injected via $Global:IRT_Session and is
thread-safe) and binds it with Connect-ExchangeOnline.
The resulting
ConnectionId and token expiry are tracked in the runspace-local
$Global:IRT_RunspaceExo, so repeated calls are cheap no-ops until the
bound token nears expiry.

This function never prompts: token acquisition is always silent.
If the
refresh token has been revoked mid-playbook, it throws with instructions
to re-run Connect-IRT rather than popping a hidden browser window inside
a worker.

Safe to call in the parent session too, but the parent normally uses
Connect-IRT / Update-IRTToken instead.

## EXAMPLES

### EXAMPLE 1
```
Connect-IRTRunspaceExchange
Inside a playbook step: ensures this runspace has a live Exchange
connection with a fresh token.
```

## PARAMETERS

### -ProgressAction
{{ Fill ProgressAction Description }}

```yaml
Type: ActionPreference
Parameter Sets: (All)
Aliases: proga

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### None.
## NOTES
Version: 1.0.0

## RELATED LINKS
