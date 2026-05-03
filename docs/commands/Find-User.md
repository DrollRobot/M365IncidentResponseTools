---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Find-User

## SYNOPSIS
Finds graph user by displayname, email address, or user id guid.
Creates $UserObjects variable.

## SYNTAX

```
Find-User [-Search] <String[]> [-VarPrefix <String>] [-Script] [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

## DESCRIPTION
{{ Fill in the Description }}

## EXAMPLES

### EXAMPLE 1
```
Find-User flast
Find-User -Search flast,flast,flast
Find-User flast@domain.com
Find-User -Search bf7573a5844f (partial user id number)
```

## PARAMETERS

### -Search
{{ Fill Search Description }}

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
{{ Fill VarPrefix Description }}

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
{{ Fill Script Description }}

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

## NOTES
Version: 1.1.4
1.1.4 - Fixed bug with $UserObjects not being a collection.
Moved getting full object to Show-User function.
1.1.3 - Removed checks for modules and permissions.
Checking at module level instead.
1.1.2 - Added enabled as a displayed field.
1.1.1 - Bug fix.
Script was passing collections rather than user objects.
1.1.0 - Major rewrite.
Renamed to Find-User.

## RELATED LINKS
