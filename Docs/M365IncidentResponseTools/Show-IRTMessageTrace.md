---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 07/31/2026
PlatyPS schema version: 2024-05-01
title: Show-IRTMessageTrace
---

# Show-IRTMessageTrace

## SYNOPSIS

{{ Fill in the Synopsis }}

## SYNTAX

### Objects (Default)

```
Show-IRTMessageTrace [[-Message] <List`1[psobject]>] [-TableStyle <string>] [-Font <string>]
 [-IpInfo <bool>] [<CommonParameters>]
```

### Xml

```
Show-IRTMessageTrace [-XmlPath] <string> [-TableStyle <string>] [-Font <string>] [-IpInfo <bool>]
 [<CommonParameters>]
```

## ALIASES

None.

## DESCRIPTION

{{ Fill in the Description }}

## EXAMPLES

### Example 1

{{ Add example description here }}

## PARAMETERS

### -Font

{{ Fill Font Description }}

```yaml
Type: System.String
DefaultValue: $Global:IRT_Config.ExcelFont
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

### -IpInfo

{{ Fill IpInfo Description }}

```yaml
Type: System.Boolean
DefaultValue: '[bool]$Global:IRT_Config.IpInfoAvailable'
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

### -Message

{{ Fill Message Description }}

```yaml
Type: System.Collections.Generic.List`1[System.Management.Automation.PSObject]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- Messages
ParameterSets:
- Name: Objects
  Position: 0
  IsRequired: false
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -TableStyle

{{ Fill TableStyle Description }}

```yaml
Type: System.String
DefaultValue: $Global:IRT_Config.ExcelTableStyle
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

### -XmlPath

{{ Fill XmlPath Description }}

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Xml
  Position: 0
  IsRequired: true
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

### System.Collections.Generic.List`1[[System.Management.Automation.PSObject, System.Management.Automation, Version=7.6.0.500, Culture=neutral, PublicKeyToken=31bf3856ad364e35]]

{{ Fill in the Description }}

## OUTPUTS

## NOTES

{{ Fill in the Notes }}

## RELATED LINKS

{{ Fill in the related links here }}
