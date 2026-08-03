---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 08/02/2026
PlatyPS schema version: 2024-05-01
title: Remove-IRTDevice
---

# Remove-IRTDevice

## SYNOPSIS

Permanently delete Entra and Intune device(s). Requires the user to type each
device's display name as confirmation before deletion proceeds.

## SYNTAX

```
Remove-IRTDevice [[-DeviceObject] <psobject[]>] [-Force] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## ALIASES

DeleteDevice, DeleteDevices, RemoveDevice, RemoveDevices

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

Remove-IRTDevice
Operates on $IRT_DeviceObjects. Prompts for name confirmation before each deletion.

### EXAMPLE 2

Find-IRTDevice DESKTOP-ABC123
Remove-IRTDevice
Find a device by name, then delete it (with confirmation prompt).

### EXAMPLE 3

Remove-IRTDevice -Force -WhatIf
Show what would be deleted without prompting or actually deleting anything.

## PARAMETERS

### -Confirm

Prompts you for confirmation before running the cmdlet.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases:
- cf
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -DeviceObject

One or more combined Entra+Intune device objects as returned by Find-IRTDevice
or stored in $IRT_DeviceObjects.
If omitted, $IRT_DeviceObjects is used.

```yaml
Type: System.Management.Automation.PSObject[]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- DeviceObjects
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Force

Skip the manual name-confirmation prompt.
The SupportsShouldProcess gate
(-WhatIf / -Confirm) still applies.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -WhatIf

Runs the command in a mode that only reports what would happen without performing the actions.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases:
- wi
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

## NOTES

Version: 1.0.0


## RELATED LINKS

{{ Fill in the related links here }}
