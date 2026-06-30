---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Get-IRTAccessToken

## SYNOPSIS
Acquires an access token for Graph, Exchange Online, or IPPS from the MSAL cache.

## SYNTAX

```
Get-IRTAccessToken [-Service] <String> [[-SearchOnly] <Boolean>] [[-AdditionalScope] <String[]>] [-Silent]
 [-ForceRefresh] [[-ClientId] <String>] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
The single token authority for the module.
Mints tokens on demand from the
session's MSAL public client apps: cached access tokens are returned in
microseconds, expired ones are silently renewed via the refresh token, and
only when no cached account works does it fall back to interactive browser
sign-in (unless -Silent).

Cached accounts are tried in smart order (Select-IRTMsalAccount): the
account that last worked for this client ID, then accounts homed in the
target tenant, then any other account in the same cloud.
Every candidate is
tried before prompting, so a cache full of other customers' accounts never
causes a spurious sign-in prompt.

Tokens are never stored by this function - callers use the result
immediately (e.g.
to bind an SDK connection or call a REST API).
Inside
playbook runspace workers ($Global:IRT_IsRunspaceWorker) the function is
always silent, so a worker can never pop a hidden browser prompt.

## EXAMPLES

### EXAMPLE 1
```
Get-IRTAccessToken -Service Exchange -Silent
Returns a fresh Exchange token from the cache without ever prompting.
```

### EXAMPLE 2
```
(Get-IRTAccessToken -Service Graph).AccessToken
Returns just the bearer token string for a manual Graph REST call.
```

## PARAMETERS

### -Service
Which service to acquire a token for: Graph, Exchange, or IPPS.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -SearchOnly
IPPS only.
Use the search-only audience (dataservice.o365filtering.com)
instead of the full Exchange audience.
Defaults to $true, matching
Connect-IRTIPPS.

```yaml
Type: Boolean
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: True
Accept pipeline input: False
Accept wildcard characters: False
```

### -AdditionalScope
Graph only.
Additional delegated scopes to request beyond the default
incident-response set.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases: AdditionalScopes

Required: False
Position: 3
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Silent
Never prompt.
If no cached account yields a token silently, throw instead
of opening a browser.

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

### -ForceRefresh
Bypass the cached access token and force MSAL to redeem the refresh token.
Used after audience-validation failures.

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

### -ClientId
Override the MSAL client ID.
Defaults to the session override if set,
otherwise the service's first-party app (Graph CLI Tools for Graph, the EXO
app for Exchange and IPPS).

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 4
Default value: None
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

### Microsoft.Identity.Client.AuthenticationResult. Callers typically use
### .AccessToken, .ExpiresOn, and .Account.Username.
## NOTES
Version: 1.0.0
Requires ExchangeOnlineManagement \>= 3.2.0 module-wide for token-based
connections (the enforced floor is 3.6.0).

## RELATED LINKS
