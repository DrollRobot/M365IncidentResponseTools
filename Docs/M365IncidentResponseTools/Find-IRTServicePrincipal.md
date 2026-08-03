---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 08/03/2026
PlatyPS schema version: 2024-05-01
title: Find-IRTServicePrincipal
---

# Find-IRTServicePrincipal

## SYNOPSIS

Finds service principals in the tenant by display name, app ID, or object ID.
Creates $IRT_ServicePrincipalObjects.

## SYNTAX

### Search (Default)

```
Find-IRTServicePrincipal [-Search] <string[]> [-VarPrefix <string>] [-Cached] [-Script]
 [-AllMatches] [<CommonParameters>]
```

### Clipboard

```
Find-IRTServicePrincipal -FromClipboard [-VarPrefix <string>] [-Cached] [-Script] [-AllMatches]
 [<CommonParameters>]
```

## ALIASES

Find-IRTServicePrincipals, Find-ServicePrincipal, Find-ServicePrincipals, FindIRTServicePrincipal, FindIRTServicePrincipals, FindServicePrincipal, FindServicePrincipals, Find-IRTSP, Find-IRTSPs, Find-SP, Find-SPs, FindIRTSP, FindIRTSPs, FindSP, FindSPs, Find-IRTEnterpriseApplication, Find-IRTEnterpriseApplications, Find-EnterpriseApplication, Find-EnterpriseApplications, FindIRTEnterpriseApplication, FindIRTEnterpriseApplications, FindEnterpriseApplication, FindEnterpriseApplications

## DESCRIPTION

Searches all service principals cached from the tenant against one or more search
strings.
A match is attempted against DisplayName, AppDisplayName, AppId, and Id
using regular-expression matching (-match), so partial strings and regex patterns
are both accepted.

When exactly one match is found for a search string, the service principal is added
to the result collection and a summary table is displayed.
When multiple matches are
found, the table is shown but nothing is saved -- refine the search to a single
match, or use -AllMatches to add all of them.
When no match is found, an error
message is displayed.

On success, results are stored in $Global:IRT_ServicePrincipalObjects (or
$Global:IRT_<VarPrefix>ServicePrincipalObjects when -VarPrefix is supplied).
Pass
-Script to suppress all console output and return the objects directly instead.

## EXAMPLES

### EXAMPLE 1

```powershell
Find-IRTServicePrincipal MyApp
```
Find a single service principal by display name.

### EXAMPLE 2

```powershell
Find-IRTServicePrincipal -Search MyApp,AnotherApp
```
Find multiple service principals in one call.

### EXAMPLE 3

```powershell
Find-IRTServicePrincipal -Search 00000003-0000-0000-c000-000000000000
```
Find by full or partial AppId (Microsoft Graph in this example).

### EXAMPLE 4

```powershell
Find-IRTServicePrincipal -Search bf7573a5844f
```
Find by partial object ID.

### EXAMPLE 5

```powershell
Find-IRTServicePrincipal MyApp -Script
```
Return the matched object directly without console output or setting the global variable.

### EXAMPLE 6

```powershell
Find-IRTServicePrincipal -FromClipboard
```
Reads the clipboard and searches for each line as a separate query.

## PARAMETERS

### -AllMatches

When specified, adds all objects that match a given search string instead of
rejecting the search when more than one result is found.
Results are deduplicated
by object ID, so overlapping search strings that resolve to the same service
principal produce only one entry in the output.

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

### -Cached

Use service principal data already cached in $Global:IRT_ServicePrincipals from a
previous call instead of fetching fresh data from Graph.

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

### -FromClipboard

Read one search query per line from the clipboard instead of supplying -Search.
Each
non-empty line is treated as a separate search string.
Mutually exclusive with -Search.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Clipboard
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Script

Suppresses all console output and returns matched objects directly as an array.
Used by playbook scripts that need the objects without interactive display.

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

### -Search

One or more search strings.
Each is matched against DisplayName, AppDisplayName,
AppId, and Id using -match (regex-capable, case-insensitive).

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Search
  Position: 0
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -VarPrefix

Optional prefix inserted into the global variable name:
$Global:IRT_<VarPrefix>ServicePrincipalObjects.
Useful when working with multiple
service principals simultaneously.

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

### None by default. Sets $Global:IRT_ServicePrincipalObjects.
With -Script: [object[]] of matched service principal objects.

### System.Object[]

## NOTES

Version: 1.2.0
1.2.0 - Added -FromClipboard to read one search query per clipboard line.
1.1.0 - Added -AllMatches to collect all matching service principals and deduplicate results.

By default, fresh data is fetched from Graph on every call.
Pass -Cached to
skip the network request and reuse data already stored in
$Global:IRT_ServicePrincipals from a previous call.


## RELATED LINKS

{{ Fill in the related links here }}
