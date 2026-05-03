---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Get-AdAdminUser

## SYNOPSIS
Displays a list of admin users.

## SYNTAX

```
Get-AdAdminUser [-Csv] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Retrieves all Active Directory users where AdminCount equals 1 (the standard AD
attribute set by SDProp for accounts that have been members of privileged groups).
Results are sorted by Enabled status then LastLogonDate descending, and include each
user's group memberships.

Use -Csv to export the results to a CSV file in C:\Temp.

## EXAMPLES

### EXAMPLE 1
```
Get-AdAdminUser
Displays all AdminCount=1 users in a formatted table.
```

### EXAMPLE 2
```
Get-AdAdminUser -Csv
Exports the list to AdAdminUsers_<domain>_<date>.csv in C:\Temp.
```

## PARAMETERS

### -Csv
Export results to a CSV file instead of displaying them in the console.

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

### None (console table) by default.
### CSV file when -Csv is used.
## NOTES
Version: 1.0.0

## RELATED LINKS
