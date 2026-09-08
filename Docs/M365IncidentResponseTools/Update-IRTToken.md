---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 09/07/2026
PlatyPS schema version: 2024-05-01
title: Update-IRTToken
---

# Update-IRTToken

## SYNOPSIS

Checks whether the token for one or more M365 services is expiring soon and refreshes
if needed. Writes a friendly error if a required service is not connected.

## SYNTAX

```
Update-IRTToken [[-Service] <string[]>] [-SkipIfNeverConnected] [-PassThru] [<CommonParameters>]
```

## ALIASES

None.

## DESCRIPTION

Intended to be called at the start of any domain function that requires a live
Graph, Exchange, or IPPS connection (and inside long-running loops).
For each
requested service it reads the bound-token expiry stored in $Global:IRT_Session
and:

  - Writes an error message and returns if the service is not connected.
  - Re-binds ONLY that service (via its private connector) when the token bound
    into the SDK context expires within 5 minutes.
Exchange/IPPS re-binds are
    scoped by ConnectionId, so refreshing one service never tears down another.
  - Does nothing when the bound token is healthy.

Inside playbook runspace workers ($Global:IRT_IsRunspaceWorker) behavior differs:
Graph is a no-op (the parent keeps the process-wide Graph binding fresh), and
Exchange delegates to Connect-IRTRunspaceExchange, which maintains a
runspace-local connection minted silently from the shared MSAL cache.

The 5-minute window aligns with MSAL's internal silent-refresh threshold so
that AcquireTokenSilent uses the refresh token and returns genuinely new tokens
rather than the same near-expired cached access token.

## EXAMPLES

### EXAMPLE 1

```powershell
Update-IRTToken -Service 'Graph'
```
Checks and re-binds the Graph token if it is expiring within 5 minutes.
Writes an error if the Graph session does not exist.

### EXAMPLE 2

```powershell
Update-IRTToken -Service 'Graph', 'Exchange'
```
Checks both Graph and Exchange tokens and refreshes whichever is expiring soon.

### EXAMPLE 3

```powershell
Update-IRTToken
```
Checks all three services (Graph, Exchange, IPPS).

## PARAMETERS

### -PassThru

When set, returns a hashtable keyed by each requested service name with a boolean
value indicating whether the bound token is currently valid (not expired).
The
status reflects the state after any refresh that was performed.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Service

One or more service names to check.
Accepts 'Graph', 'Exchange', and 'IPPS'.
Defaults to all three.

```yaml
Type: System.String[]
DefaultValue: "@('Graph', 'Exchange', 'IPPS')"
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SkipIfNeverConnected

When set, silently skips any service that has no active session rather than
writing an error.
Intended for callers that run regardless of whether the user
has called Connect-IRT.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### System.Collections.Hashtable
When -PassThru is specified

### System.Collections.Hashtable

## NOTES

Version: 2.0.0


## RELATED LINKS

{{ Fill in the related links here }}
