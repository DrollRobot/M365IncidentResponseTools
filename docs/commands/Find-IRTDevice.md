---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Find-IRTDevice

## SYNOPSIS
Finds devices by display name, device ID, operating system, registered owner, serial number, or other
Entra/Intune identifiers.
Creates $IRT_DeviceObjects from combined Entra + Intune device records.

## SYNTAX

```
Find-IRTDevice [-Search] <String[]> [-VarPrefix <String>] [-Script] [-AllMatches]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
{{ Fill in the Description }}

## EXAMPLES

### EXAMPLE 1
```
Find-IRTDevice DESKTOP-ABC123
Find-IRTDevice -Search DESKTOP-ABC123,LAPTOP-XYZ789
Find-IRTDevice flast@domain.com
Find-IRTDevice -Search bf7573a5844f   # partial device id / Entra id / Intune id
Find-IRTDevice -Search SN1234567890   # serial number (Intune)
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

### -AllMatches
{{ Fill AllMatches Description }}

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

### System.Management.Automation.PSObject[]
## NOTES
Version: 1.1.0

## RELATED LINKS
