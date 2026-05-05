---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Show-AdOus

## SYNOPSIS
Shows a list of all OUs with a count of users and devices.

## SYNTAX

```
Show-AdOus [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Lists all Organizational Units in the current AD domain, sorted by CanonicalName.
For each OU, counts users and computers directly inside it (OneLevel scope) and
displays the results in a formatted table.

Output objects use the custom type 'ShowAdOus' with a DefaultDisplayPropertySet
so Format-Table shows CanonicalName, Name, Users, Computers, and DistinguishedName
by default.

## EXAMPLES

### EXAMPLE 1
```
Show-AdOus
Lists all OUs with user and computer counts.
```

### EXAMPLE 2
```
Show-AdOus | Where-Object { $_.Users -gt 0 }
Returns only OUs that contain at least one user.
```

## PARAMETERS

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

### PSCustomObject[] (type: ShowAdOus)
## NOTES
Version: 1.0.1

## RELATED LINKS
