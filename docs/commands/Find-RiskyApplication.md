---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Find-RiskyApplication

## SYNOPSIS
Identifies potentially malicious OAuth applications registered in the tenant.

## SYNTAX

```
Find-RiskyApplication [-Cached]
```

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
```
Find-RiskyApplication
Queries all threat intelligence feeds and reports any matches in the tenant.
```

### EXAMPLE 2
```
Find-RiskyApplication -Cached
Same as above but uses cached Graph data from the current session.
```

## PARAMETERS

### -Cached
Use pre-cached Graph service principal and OAuth grant data instead of making new
API calls.
Speeds up repeated runs during the same session.

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

## INPUTS

## OUTPUTS

### None. Results are written to the console.
## NOTES
Requires an active Graph connection with appropriate permissions.
Threat intelligence feeds are fetched live from GitHub at runtime.

## RELATED LINKS
