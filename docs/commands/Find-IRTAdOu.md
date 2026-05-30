---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Find-IRTAdOu

## SYNOPSIS
Makes finding specific OUs easier.

## SYNTAX

```
Find-IRTAdOu [-Search] <String> [-Script] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Searches all Active Directory Organizational Units for entries matching the -Search
string.
The search is applied against Name (regex), CanonicalName (exact), and
DistinguishedName (exact).
If exactly one match is found it is stored in
$Global:OuObject and displayed; multiple or zero results produce a warning.

## EXAMPLES

### EXAMPLE 1
```
Find-IRTAdOu 'Workstations'
Finds all OUs with 'Workstations' in their name and sets $Global:OuObject if exactly one match.
```

### EXAMPLE 2
```
$Ou = Find-IRTAdOu -Search 'contoso.com/Workstations' -Script
Returns the OU object directly for use in a script.
```

## PARAMETERS

### -Search
String to search for.
Tested as a regex against Name and as an exact match against
CanonicalName and DistinguishedName.

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

### -Script
Return the matching OU object directly instead of printing it and setting the global
variable.
Useful when calling from scripts.

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

### None by default (sets $Global:OuObject and writes to console).
### Microsoft.ActiveDirectory.Management.ADOrganizationalUnit when -Script is used.
## NOTES
Version: 1.0.0

## RELATED LINKS
