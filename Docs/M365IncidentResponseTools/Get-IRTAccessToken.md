---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 08/03/2026
PlatyPS schema version: 2024-05-01
title: Get-IRTAccessToken
---

# Get-IRTAccessToken

## SYNOPSIS

Acquires an access token for Graph, Exchange Online, or IPPS from the MSAL cache.

## SYNTAX

```
Get-IRTAccessToken [-Service] <string> [[-SearchOnly] <bool>] [[-AdditionalScope] <string[]>]
 [[-ClientId] <string>] [-Silent] [-ForceRefresh] [<CommonParameters>]
```

## ALIASES

None.

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

```powershell
Get-IRTAccessToken -Service Exchange -Silent
```
Returns a fresh Exchange token from the cache without ever prompting.

### EXAMPLE 2

```powershell
(Get-IRTAccessToken -Service Graph).AccessToken
```
Returns just the bearer token string for a manual Graph REST call.

## PARAMETERS

### -AdditionalScope

Graph only.
Additional delegated scopes to request beyond the default
incident-response set.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- AdditionalScopes
ParameterSets:
- Name: (All)
  Position: 2
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ClientId

Override the MSAL client ID.
Defaults to the session override if set,
otherwise the service's first-party app (Graph CLI Tools for Graph, the EXO
app for Exchange and IPPS).

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 3
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ForceRefresh

Bypass the cached access token and force MSAL to redeem the refresh token.
Used after audience-validation failures.

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

### -SearchOnly

IPPS only.
Use the search-only audience (dataservice.o365filtering.com)
instead of the full Exchange audience.
Defaults to $true, matching
Connect-IRTIPPS.

```yaml
Type: System.Boolean
DefaultValue: True
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 1
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Service

Which service to acquire a token for: Graph, Exchange, or IPPS.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Silent

Never prompt.
If no cached account yields a token silently, throw instead
of opening a browser.

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

### Microsoft.Identity.Client.AuthenticationResult. Callers typically use
.AccessToken

### Microsoft.Identity.Client.AuthenticationResult

## NOTES

Version: 1.0.0
Requires ExchangeOnlineManagement >= 3.2.0 module-wide for token-based
connections (the enforced floor is 3.6.0).


## RELATED LINKS

{{ Fill in the related links here }}
