---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Show-UALog

## SYNOPSIS
Parse and show unified audit logs.

## SYNTAX

### Objects (Default)
```
Show-UALog [-Log] <System.Collections.Generic.List`1[System.Management.Automation.PSObject]>
 [-TableStyle <String>] [-Font <String>] [-IpInfo <Boolean>] [-Open <Boolean>] [-WaitOnMessageTrace <Boolean>]
 [-MaxWaitMinutes <Int32>] [-Test] [-Cached] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

### Xml
```
Show-UALog [-XmlPath] <String> [-TableStyle <String>] [-Font <String>] [-IpInfo <Boolean>] [-Open <Boolean>]
 [-WaitOnMessageTrace <Boolean>] [-MaxWaitMinutes <Int32>] [-Test] [-Cached]
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

### -Log
{{ Fill Log Description }}

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

### -IpInfo
{{ Fill IpInfo Description }}

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
{{ Fill Open Description }}

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

### -WaitOnMessageTrace
{{ Fill WaitOnMessageTrace Description }}

```yaml
Type: Boolean
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -MaxWaitMinutes
{{ Fill MaxWaitMinutes Description }}

```yaml
Type: Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: 15
Accept pipeline input: False
Accept wildcard characters: False
```

### -Test
{{ Fill Test Description }}

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

### -Cached
{{ Fill Cached Description }}

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

## NOTES
Version: 1.0.1
   1.0.1 - Added option pass raw log objects, not just import from file.

## RELATED LINKS
