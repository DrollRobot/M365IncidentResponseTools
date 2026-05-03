---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Show-IRTMessageTrace

## SYNOPSIS
Processes message trace data and creates spreadsheet.

## SYNTAX

### Objects (Default)
```
Show-IRTMessageTrace [-Message] <System.Collections.Generic.List`1[System.Management.Automation.PSObject]>
 [-TableStyle <String>] [-Font <String>] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

### Xml
```
Show-IRTMessageTrace [-XmlPath] <String> [-TableStyle <String>] [-Font <String>]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
{{ Fill in the Description }}

## EXAMPLES

### Example 1
```powershell
PS C:\> {{ Add example code here }}
```

{{ Add example description here }}

## PARAMETERS

### -Message
{{ Fill Message Description }}

```yaml
Type: System.Collections.Generic.List`1[System.Management.Automation.PSObject]
Parameter Sets: Objects
Aliases: Messages

Required: True
Position: 1
Default value: None
Accept pipeline input: True (ByValue)
Accept wildcard characters: False
```

### -XmlPath
{{ Fill XmlPath Description }}

```yaml
Type: String
Parameter Sets: Xml
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -TableStyle
{{ Fill TableStyle Description }}

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
{{ Fill Font Description }}

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
