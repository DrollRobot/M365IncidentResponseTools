---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Find-IRTServicePrincipal

## SYNOPSIS
Finds service principals in the tenant by display name, app ID, or object ID.
Creates $IRT_ServicePrincipalObjects.

## SYNTAX

```
Find-IRTServicePrincipal [-Search] <String[]> [-VarPrefix <String>] [-Cached] [-Script] [-AllMatches]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

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
$Global:IRT_\<VarPrefix\>ServicePrincipalObjects when -VarPrefix is supplied).
Pass
-Script to suppress all console output and return the objects directly instead.

## EXAMPLES

### EXAMPLE 1
```
Find-IRTServicePrincipal MyApp
Find a single service principal by display name.
```

### EXAMPLE 2
```
Find-IRTServicePrincipal -Search MyApp,AnotherApp
Find multiple service principals in one call.
```

### EXAMPLE 3
```
Find-IRTServicePrincipal -Search 00000003-0000-0000-c000-000000000000
Find by full or partial AppId (Microsoft Graph in this example).
```

### EXAMPLE 4
```
Find-IRTServicePrincipal -Search bf7573a5844f
Find by partial object ID.
```

### EXAMPLE 5
```
Find-IRTServicePrincipal MyApp -Script
Return the matched object directly without console output or setting the global variable.
```

## PARAMETERS

### -Search
One or more search strings.
Each is matched against DisplayName, AppDisplayName,
AppId, and Id using -match (regex-capable, case-insensitive).

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -VarPrefix
Optional prefix inserted into the global variable name:
$Global:IRT_\<VarPrefix\>ServicePrincipalObjects.
Useful when working with multiple
service principals simultaneously.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Cached
Use service principal data already cached in $Global:IRT_ServicePrincipals from a
previous call instead of fetching fresh data from Graph.

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

### -Script
Suppresses all console output and returns matched objects directly as an array.
Used by playbook scripts that need the objects without interactive display.

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

### -AllMatches
When specified, adds all objects that match a given search string instead of
rejecting the search when more than one result is found.
Results are deduplicated
by object ID, so overlapping search strings that resolve to the same service
principal produce only one entry in the output.

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

### None by default. Sets $Global:IRT_ServicePrincipalObjects.
### With -Script: [object[]] of matched service principal objects.
## NOTES
Version: 1.1.0
1.1.0 - Added -AllMatches to collect all matching service principals and deduplicate results.

By default, fresh data is fetched from Graph on every call.
Pass -Cached to
skip the network request and reuse data already stored in
$Global:IRT_ServicePrincipals from a previous call.

## RELATED LINKS
