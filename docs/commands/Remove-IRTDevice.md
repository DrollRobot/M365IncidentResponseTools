---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Remove-IRTDevice

## SYNOPSIS
Permanently delete Entra and Intune device(s).
Requires the user to type each
device's display name as confirmation before deletion proceeds.

## SYNTAX

```
Remove-IRTDevice [[-DeviceObject] <PSObject[]>] [-Force] [-ProgressAction <ActionPreference>] [-WhatIf]
 [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
Removes the Entra directory object (Remove-MgDevice) and, when the device is
Intune-enrolled, the Intune managed device (Remove-MgDeviceManagementManagedDevice)
for each supplied device object.

Before any deletion the user is shown the device's DisplayName, Entra ID,
Intune ID (or '(not enrolled)'), and OS.
The user must then type the
DisplayName exactly to proceed.
Use -Force to bypass this prompt (e.g.
in
automated remediation scripts).
-WhatIf and -Confirm are also supported.

## EXAMPLES

### EXAMPLE 1
```
Remove-IRTDevice
Operates on $IRT_DeviceObjects. Prompts for name confirmation before each deletion.
```

### EXAMPLE 2
```
Find-IRTDevice DESKTOP-ABC123
Remove-IRTDevice
Find a device by name, then delete it (with confirmation prompt).
```

### EXAMPLE 3
```
Remove-IRTDevice -Force -WhatIf
Show what would be deleted without prompting or actually deleting anything.
```

## PARAMETERS

### -DeviceObject
One or more combined Entra+Intune device objects as returned by Find-IRTDevice
or stored in $IRT_DeviceObjects.
If omitted, $IRT_DeviceObjects is used.

```yaml
Type: PSObject[]
Parameter Sets: (All)
Aliases: DeviceObjects

Required: False
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Force
Skip the manual name-confirmation prompt.
The SupportsShouldProcess gate
(-WhatIf / -Confirm) still applies.

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

## NOTES
Version: 1.0.0

## RELATED LINKS
