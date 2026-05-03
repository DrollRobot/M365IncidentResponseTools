---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Get-IRTInboxRule

## SYNOPSIS
Retrieves and displays Exchange Online inbox rules for one or more users.

## SYNTAX

```
Get-IRTInboxRule [[-UserObject] <PSObject[]>] [-TableStyle <String>] [-Font <String>] [-Open <Boolean>]
 [-Xml <Boolean>] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Fetches all inbox rules for each provided user via Exchange Online and exports them
to a formatted Excel workbook.
Each rule row includes its enabled state, name,
description, and a pre-built deletion command for quick remediation.

Disabled rules are highlighted in the Excel output.
Falls back to
$Global:IRT_UserObjects if no -UserObject is passed.
Requires an active Exchange
Online connection.

## EXAMPLES

### EXAMPLE 1
```
Get-IRTInboxRule
Retrieves and exports inbox rules for the user in the global session.
```

### EXAMPLE 2
```
Get-IRTInboxRule -UserObject $User
Retrieves inbox rules for a specific user.
```

## PARAMETERS

### -UserObject
One or more user objects to query.
Falls back to global session objects if omitted.

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

### -TableStyle
Excel table style.
Defaults to IRT_Config.ExcelTableStyle.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: $Global:IRT_Config.ExcelTableStyle
Accept pipeline input: False
Accept wildcard characters: False
```

### -Font
Excel font name.
Defaults to IRT_Config.ExcelFont.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: $Global:IRT_Config.ExcelFont
Accept pipeline input: False
Accept wildcard characters: False
```

### -Open
Open the Excel file immediately after export.
Default: $true.

```yaml
Type: Boolean
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: True
Accept pipeline input: False
Accept wildcard characters: False
```

### -Xml
Export raw XML alongside the Excel file.
Defaults to IRT_Config.ExportXml.

```yaml
Type: Boolean
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: $Global:IRT_Config.ExportXml
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

### None. Results are exported to an Excel file and optionally displayed in the console.
## NOTES
Version: 1.1.6
1.1.6 - Added column borders, raw json.
Fixed bugs.
1.1.5 - Added rule to highlight disabled rules.

## RELATED LINKS
