---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Get-IRTAllEntraDevice

## SYNOPSIS
Exports every Entra ID (Azure AD) device to a spreadsheet, newest registration first.

## SYNTAX

```
Get-IRTAllEntraDevice [[-Open] <Boolean>] [[-Xml] <Boolean>] [[-TableStyle] <String>] [[-Font] <String>]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Queries Microsoft Graph for all registered/joined Entra devices and writes them to an
Excel workbook sorted by registration date (newest first).
Threat actors sometimes
register their own device against a compromised identity to persist and to satisfy
device-based Conditional Access, so surfacing the most recently registered devices at
the top of the sheet makes new, unexpected registrations easy to spot.

As much device detail as Graph exposes is included: join/trust type, registered owner,
operating system, compliance and management state, ownership, enrollment type, and the
registration and last sign-in timestamps.

## EXAMPLES

### EXAMPLE 1
```
Get-IRTAllEntraDevice
Exports all Entra devices to a spreadsheet and opens it.
```

### EXAMPLE 2
```
Get-IRTAllEntraDevice -Open $false -Xml $true
Writes the spreadsheet and a raw XML dump without opening the workbook.
```

## PARAMETERS

### -Open
Open the Excel file immediately after export.
Default: $true.

```yaml
Type: Boolean
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: True
Accept pipeline input: False
Accept wildcard characters: False
```

### -Xml
Export the raw device objects to a .xml file alongside the workbook.
Defaults to IRT_Config.ExportXml.

```yaml
Type: Boolean
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: $Global:IRT_Config.ExportXml
Accept pipeline input: False
Accept wildcard characters: False
```

### -TableStyle
Excel table style.
Defaults to IRT_Config.ExcelTableStyle.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: $Global:IRT_Config.ExcelTableStyle
Accept pipeline input: False
Accept wildcard characters: False
```

### -Font
Worksheet font.
Defaults to IRT_Config.ExcelFont.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 4
Default value: $Global:IRT_Config.ExcelFont
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

### None. Results are exported to an Excel workbook.
## NOTES
Version: 1.0.0

## RELATED LINKS
