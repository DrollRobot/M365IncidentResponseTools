---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 08/02/2026
PlatyPS schema version: 2024-05-01
title: Find-IRTRiskyServicePrincipal
---

# Find-IRTRiskyServicePrincipal

## SYNOPSIS

Identifies potentially malicious OAuth applications registered in the tenant.

## SYNTAX

```
Find-IRTRiskyServicePrincipal [-Cached]
```

## ALIASES

RiskyApps, RiskySPs, FindRiskySP, FindRiskySPs, FindRiskyApp, FindRiskyApps, FindRiskyApplication, FindRiskyApplications, FindRiskyServicePrincipal, FindRiskyServicePrincipals, FindRiskyEnterpriseApp, FindRiskyEnterpriseApps, Find-RiskyApplication

## DESCRIPTION

Checks all service principals in the tenant against a configurable list of threat
intelligence feeds to find known malicious OAuth app IDs.
For each match, displays
app details, the source feed, and the users who have granted consent to the app.

Also reports on tenant-level app registration and user consent policies.

New feeds can be added to the $ThreatFeeds array in the begin block.
Each feed requires: Name, Url, Parser (scriptblock), AppIdField, and DisplayProperties.

Requires the PSToml module for feeds that use TOML format.

## EXAMPLES

### EXAMPLE 1

Find-IRTRiskyServicePrincipal
Queries all threat intelligence feeds and reports any matches in the tenant.

### EXAMPLE 2

Find-IRTRiskyServicePrincipal -Cached
Same as above but uses cached Graph data from the current session.

## PARAMETERS

### -Cached

Use pre-cached Graph service principal and OAuth grant data instead of making new
API calls.
Speeds up repeated runs during the same session.

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

## INPUTS

## OUTPUTS

### None. Results are written to the console.

## NOTES

Requires an active Graph connection with appropriate permissions.
Threat intelligence feeds are fetched live from GitHub at runtime.


## RELATED LINKS

{{ Fill in the related links here }}
