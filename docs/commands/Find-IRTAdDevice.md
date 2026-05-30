---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Find-IRTAdDevice

## SYNOPSIS
Finds a local AD computer by Name, DNSHostName, SamAccountName, Description,
or ObjectGUID.

## SYNTAX

```
Find-IRTAdDevice [-Search] <String[]> [-VarPrefix <String>] [-Script] [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

## DESCRIPTION
Searches Active Directory for computers matching one or more search strings.
The search
is applied across Name, DNSHostName, SamAccountName, Description, and ObjectGUID.

If a single computer is found, the full AD object is retrieved and stored in
$Global:IRT_DeviceObject.
Use -VarPrefix to change the variable name
(e.g.
'Target' \> $Global:IRT_TargetDeviceObject).
For multiple matches the results are
displayed but no global is set.
Use -Script to suppress global side effects and
return objects directly.

## EXAMPLES

### EXAMPLE 1
```
Find-IRTAdDevice DESKTOP-ABC123
Finds computers matching 'DESKTOP-ABC123' and sets the global device object if exactly
one match.
```

### EXAMPLE 2
```
Find-IRTAdDevice desktop-abc123.contoso.com
Searches by DNS host name.
```

### EXAMPLE 3
```
$Devices = Find-IRTAdDevice -Search 'DESKTOP-ABC123','LAPTOP-XYZ789' -Script
Returns matching computer objects for two search strings without setting globals.
```

## PARAMETERS

### -Search
One or more search strings.
Each string is independently searched across all supported
fields.

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
Optional prefix inserted after 'IRT_' in the global variable name
(e.g.
'Target' \> $Global:IRT_TargetDeviceObject).
Useful when working with multiple
devices simultaneously.

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
Return objects directly and suppress global variable assignment.
Use when calling from
scripts or the playbook.

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

### None by default (sets global variables).
### Microsoft.ActiveDirectory.Management.ADComputer[] when -Script is used.
## NOTES
Version: 1.0.0

## RELATED LINKS
