---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# New-InvestigationFolder

## SYNOPSIS
Makes a new directory based on client and user info.

## SYNTAX

```
New-InvestigationFolder [[-UserObject] <PSObject[]>] [-Ticket <String>] [-ProgressAction <ActionPreference>]
 [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
Creates a timestamped investigation output folder in the current working directory.
The folder name is built from the tenant's default domain, an optional ticket number,
and the display names of the users under investigation.

If the Graph context is not available the function prompts for a client name
interactively.
Falls back to $Global:IRT_UserObjects if no -UserObject is passed.

## EXAMPLES

### EXAMPLE 1
```
New-InvestigationFolder
Creates a folder like: investigation_contoso_jsmith_26-05-03_14-30
```

### EXAMPLE 2
```
New-InvestigationFolder -Ticket 'INC-1234' -UserObject $User
Creates a folder that includes the ticket number and user name.
```

## PARAMETERS

### -UserObject
One or more user objects whose names are included in the folder name.
Falls back to
global session objects if omitted.

```yaml
Type: PSObject[]
Parameter Sets: (All)
Aliases: UserObjects

Required: False
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Ticket
Optional ticket or case number to include in the folder name.

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

### -WhatIf
Shows what would happen if the cmdlet runs.
The cmdlet is not run.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: wi

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Confirm
Prompts you for confirmation before running the cmdlet.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: cf

Required: False
Position: Named
Default value: None
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

### System.IO.DirectoryInfo
## NOTES
Version: 1.0.2

## RELATED LINKS
