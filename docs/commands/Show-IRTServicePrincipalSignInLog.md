---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Show-IRTServicePrincipalSignInLog

## SYNOPSIS
Processes service principal sign-in log objects into an Excel spreadsheet.

## SYNTAX

### Objects (Default)
```
Show-IRTServicePrincipalSignInLog
 [-Log] <System.Collections.Generic.List`1[System.Management.Automation.PSObject]> [-TableStyle <String>]
 [-Font <String>] [-IpInfo <Boolean>] [-Open <Boolean>] [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

### Xml
```
Show-IRTServicePrincipalSignInLog -XmlPath <String> [-TableStyle <String>] [-Font <String>] [-IpInfo <Boolean>]
 [-Open <Boolean>] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Takes service principal sign-in log objects produced by Get-IRTServicePrincipalSignInLog
(or imported from a raw XML export) and renders them into a formatted Excel workbook.
Enriches IP addresses with geolocation data when -IpInfo is enabled.

## EXAMPLES

### Example 1
```powershell
PS C:\> {{ Add example code here }}
```

{{ Add example description here }}

## PARAMETERS

### -Log
A list of service principal sign-in log objects with a metadata entry at index 0.
Produced by Get-IRTServicePrincipalSignInLog.
Mutually exclusive with -XmlPath.

```yaml
Type: System.Collections.Generic.List`1[System.Management.Automation.PSObject]
Parameter Sets: Objects
Aliases: Logs

Required: True
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -XmlPath
Path to a raw XML file exported by Get-IRTServicePrincipalSignInLog.
Mutually
exclusive with -Log.

```yaml
Type: String
Parameter Sets: Xml
Aliases:

Required: True
Position: Named
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

### -IpInfo
Enrich IP addresses with geolocation data.
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

### None. Results are written to an Excel workbook.
## NOTES
Version: 1.0.0

## RELATED LINKS
