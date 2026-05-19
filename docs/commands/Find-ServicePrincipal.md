---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Find-ServicePrincipal

## SYNOPSIS
Finds service principals in the tenant by display name, app ID, or object ID.
Creates $IRT_ServicePrincipalObjects.

## SYNTAX

```
Find-ServicePrincipal [-Search] <String[]> [-VarPrefix <String>] [-Script] [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
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
match.
When no match is found, an error message is displayed.

On success, results are stored in $Global:IRT_ServicePrincipalObjects (or
$Global:IRT_\<VarPrefix\>ServicePrincipalObjects when -VarPrefix is supplied).
Pass
-Script to suppress all console output and return the objects directly instead.

## EXAMPLES

### EXAMPLE 1
```
Find-ServicePrincipal MyApp
Find a single service principal by display name.
```

### EXAMPLE 2
```
Find-ServicePrincipal -Search MyApp,AnotherApp
Find multiple service principals in one call.
```

### EXAMPLE 3
```
Find-ServicePrincipal -Search 00000003-0000-0000-c000-000000000000
Find by full or partial AppId (Microsoft Graph in this example).
```

### EXAMPLE 4
```
Find-ServicePrincipal -Search bf7573a5844f
Find by partial object ID.
```

### EXAMPLE 5
```
Find-ServicePrincipal MyApp -Script
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
Version: 1.0.0

Search data is fetched once from Graph on the first call and cached in
$Global:IRT_ServicePrincipals for the remainder of the session.
Subsequent
calls use the cache automatically.

## RELATED LINKS
