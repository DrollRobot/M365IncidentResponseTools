---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 09/07/2026
PlatyPS schema version: 2024-05-01
title: Connect-IRTTenant
---

# Connect-IRTTenant

## SYNOPSIS

Connects to a tenant using a friendly alias looked up from a tenant configuration worksheet.

## SYNTAX

```
Connect-IRTTenant [-Alias] <string> [-TenantFile <string>] [-Graph] [-Exchange]
 [-AdditionalScope <string[]>] [-PasswordBrowser <string>] [-Private] [<CommonParameters>]
```

## ALIASES

IRTTenant

## DESCRIPTION

Reads tenant information from a worksheet and matches the provided alias against
each tenant's Aliases regex pattern.
Once matched, it passes the tenant's parameters
to Connect-IRT and opens any configured URLs in the browser.

If multiple tenants match the alias, a numbered menu is presented so the user can
select which tenant to connect to.
This allows the same alias patterns to be shared
across multiple tenants belonging to the same client.

The tenants worksheet should be stored at $env:APPDATA\M365IncidentResponseTools\tenants.xlsx.
A template file (TenantsTemplate.xlsx) is included in the Data folder for reference.

## EXAMPLES

### EXAMPLE 1

```powershell
Connect-IRTTenant contoso
```
Looks up 'contoso' in the tenants worksheet and connects to all services.

### EXAMPLE 2

```powershell
Connect-IRTTenant fab -Graph
```
Looks up 'fab' in the tenants worksheet and connects to Graph only.

### EXAMPLE 3

```powershell
irttenant bestcompany
```
Uses the alias to connect to the matching tenant.

## PARAMETERS

### -AdditionalScope

Additional Graph scopes to request beyond the default set.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- AdditionalScopes
- Scopes
- Scope
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

### -Alias

A string to match against tenant alias patterns.
Matched as a regex against the
Aliases column in the tenants worksheet.

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

### -PasswordBrowser

{{ Fill PasswordBrowser Description }}

```yaml
Type: System.String
DefaultValue: $IRT_Config.PasswordBrowser
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

### -TenantFile

Path to the tenants worksheet.
Defaults to $env:APPDATA\M365IncidentResponseTools\tenants.xlsx.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

## NOTES

Version: 1.2.0
1.2.0 - Multiple-match now prompts user with a selection menu instead of throwing.
1.1.0 - Updated to use xlsx file instead of csv.


## RELATED LINKS

{{ Fill in the related links here }}
