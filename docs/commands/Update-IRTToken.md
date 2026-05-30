---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Update-IRTToken

## SYNOPSIS
Checks whether the token for one or more M365 services is expiring soon and refreshes
if needed.
Writes a friendly error if a required service is not connected.

## SYNTAX

```
Update-IRTToken [[-Service] <String[]>] [-SkipIfNeverConnected] [-PassThru]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Intended to be called at the start of any domain function that requires a live
Graph, Exchange, or IPPS connection.
For each requested service it reads the
token expiry stored in $Global:IRT_Session and:

  - Writes an error message and returns if the service is not connected.
  - Calls Connect-IRT -Refresh when the token expires within 5 minutes.
  - Does nothing when the token is healthy.

The 5-minute window aligns with MSAL's internal silent-refresh threshold so
that AcquireTokenSilent uses the refresh token and returns genuinely new tokens
rather than the same near-expired cached access token.

## EXAMPLES

### EXAMPLE 1
```
Update-IRTToken -Service 'Graph'
Checks and refreshes the Graph token if it is expiring within 5 minutes.
Writes an error if the Graph session does not exist.
```

### EXAMPLE 2
```
Update-IRTToken -Service 'Graph', 'Exchange'
Checks both Graph and Exchange tokens and refreshes if either is expiring soon.
```

### EXAMPLE 3
```
Update-IRTToken
Checks all three services (Graph, Exchange, IPPS).
```

## PARAMETERS

### -Service
One or more service names to check.
Accepts 'Graph', 'Exchange', and 'IPPS'.
Defaults to all three.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: @('Graph', 'Exchange', 'IPPS')
Accept pipeline input: False
Accept wildcard characters: False
```

### -SkipIfNeverConnected
When set, silently skips any service that has no active session rather than
writing an error.
Intended for use in the prompt function, which runs regardless
of whether the user has called Connect-IRT.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -PassThru
When set, returns a hashtable keyed by each requested service name with a boolean
value indicating whether the token is currently valid (not expired).
The status
reflects the state after any refresh that was performed.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

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

### System.Collections.Hashtable
### When -PassThru is specified, returns a hashtable keyed by service name (Graph,
### Exchange, IPPS) with boolean values indicating whether each token is currently valid.
### Returns nothing otherwise.
## NOTES
Version: 1.0.0

## RELATED LINKS
