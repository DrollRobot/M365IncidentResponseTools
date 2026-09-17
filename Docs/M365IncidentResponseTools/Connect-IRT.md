---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 09/07/2026
PlatyPS schema version: 2024-05-01
title: Connect-IRT
---

# Connect-IRT

## SYNOPSIS

Connects to Microsoft Graph and Exchange Online for incident response.

## SYNTAX

### TenantId (Default)

```
Connect-IRT -TenantId <string> [-Silent] [-Cloud <string>] [-AdditionalScope <string[]>] [-Graph]
 [-Exchange] [-IPPS] [-Browser <string>] [-Private] [-Force] [-ClientId <string>]
 [<CommonParameters>]
```

### Refresh

```
Connect-IRT -Refresh [-Silent] [-Cloud <string>] [-AdditionalScope <string[]>] [-Graph] [-Exchange]
 [-IPPS] [-Browser <string>] [-Private] [-Force] [-ClientId <string>] [<CommonParameters>]
```

## ALIASES

ConnectIRT

## DESCRIPTION

Orchestrates connections to Graph and Exchange Online.
When no service switches are specified, both services are connected.
Use -Graph
or -Exchange to connect to specific services only.

The cloud environment is identified automatically via an unauthenticated OIDC
discovery lookup.
Pass -Cloud to skip the lookup and connect directly
to a known cloud.

## EXAMPLES

### EXAMPLE 1

```powershell
Connect-IRT -TenantId $tid
```
Connects to Graph and Exchange Online.

### EXAMPLE 2

```powershell
Connect-IRT -TenantId $tid -Exchange -Cloud USGov
```
Connects to Exchange in a USGov cloud, skipping OIDC discovery.

### EXAMPLE 3

```powershell
Connect-IRT -Refresh
```
Silently re-acquires tokens for all services in the existing session.

## PARAMETERS

### -AdditionalScope

Additional Graph scopes to request beyond the default set.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- AdditionalScopes
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

### -Browser

Browser to use for URL opening.
Valid values: msedge, chrome, firefox,
brave, default.

```yaml
Type: System.String
DefaultValue: $Global:IRT_Config.Browser ?? 'default'
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

### -ClientId

Override the MSAL client ID used for all three services (Graph, Exchange,
IPPS).
When omitted, each service uses its own first-party Microsoft client
ID.
Use this when connecting via a custom app registration that has been
granted the necessary delegated permissions.

```yaml
Type: System.String
DefaultValue: ''
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

### -Cloud

Cloud to connect to.
Valid values: Commercial, USGov, China.
When omitted the cloud is detected automatically via OIDC discovery.
Provide
this parameter to skip the lookup or to override the detected value.

```yaml
Type: System.String
DefaultValue: ''
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

### -Exchange

Connect to Exchange Online only.

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

### -Force

{{ Fill Force Description }}

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

### -Graph

Connect to Microsoft Graph only.

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

### -IPPS

{{ Fill IPPS Description }}

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

### -Private

Open the browser in private/incognito mode.

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

### -Refresh

Re-connects all services that are present in the current session using the
stored TenantId and cloud environment.
Reads parameters from
$Global:IRT_Session instead of requiring them on the command line.
Combine with -Silent to suppress interactive auth fallback.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Refresh
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Silent

When set, token acquisition skips the interactive browser/device-code
fallback.
If MSAL cannot silently refresh a token, the function throws
instead of prompting.
Intended for use in the prompt function and other
non-interactive callers.

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

### -TenantId

The TenantId GUID for the environment you want to connect to.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: TenantId
  Position: Named
  IsRequired: true
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

## NOTES

Version: 1.1.0


## RELATED LINKS

{{ Fill in the related links here }}
