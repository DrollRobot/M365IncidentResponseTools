---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Open-IRTTenantOwnerCSV

## SYNOPSIS
Opens the local tenant info cache CSV in the default application.

## SYNTAX

```
Open-IRTTenantOwnerCSV [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Opens $env:APPDATA\\\<ModuleName\>\TenantOwnerInfo.csv in the system default
application (typically Excel or Notepad), where \<ModuleName\> is resolved at
runtime.
If the file does not exist yet, a warning is displayed.

## EXAMPLES

### EXAMPLE 1
```
Open-IRTTenantOwnerCSV
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

## NOTES
Version: 1.0.0

## RELATED LINKS
