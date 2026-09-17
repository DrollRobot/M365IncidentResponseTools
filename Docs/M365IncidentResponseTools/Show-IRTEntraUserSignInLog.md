---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 09/16/2026
PlatyPS schema version: 2024-05-01
title: Show-IRTEntraUserSignInLog
---

# Show-IRTEntraUserSignInLog

## SYNOPSIS

Processes user sign-in log objects into an Excel spreadsheet.

## SYNTAX

### Objects (Default)

```
Show-IRTEntraUserSignInLog [[-Log] <List`1[psobject]>] [-TableStyle <string>] [-Font <string>]
 [-IpInfo <bool>] [-Open <bool>] [<CommonParameters>]
```

### Xml

```
Show-IRTEntraUserSignInLog -XmlPath <string> [-TableStyle <string>] [-Font <string>]
 [-IpInfo <bool>] [-Open <bool>] [<CommonParameters>]
```

## ALIASES

None.

## DESCRIPTION

Takes user sign-in log objects produced by Get-IRTEntraUserSignInLog (or imported
from a raw XML export) and renders them into a formatted Excel workbook.
Curated
columns are shown by default and all other sign-in fields are present but hidden.
Device code values in AuthenticationProtocol and OriginalTransferMethod are
highlighted.
Enriches IP addresses with geolocation data when -IpInfo is enabled.

## EXAMPLES

### EXAMPLE 1

```powershell
Show-IRTEntraUserSignInLog -XmlPath '.\EntraSignInLog_jsmith_26-09-16_14-30.xml'
```
Rebuilds the sign-in log workbook from a raw XML export.

## PARAMETERS

### -Font

Excel font name.
Defaults to IRT_Config.ExcelFont.

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

Enrich IP addresses with geolocation data.
Default: $true.

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

### -Log

A list of user sign-in log objects with a metadata entry at index 0.
Produced by
Get-IRTEntraUserSignInLog.
Mutually exclusive with -XmlPath.

```yaml
Type: System.Collections.Generic.List`1[System.Management.Automation.PSObject]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- Logs
ParameterSets:
- Name: Objects
  Position: 0
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Open

Open the Excel file immediately after export.
Default: $true.

```yaml
Type: System.Boolean
DefaultValue: True
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

### -TableStyle

Excel table style.
Defaults to IRT_Config.ExcelTableStyle.

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

Path to a raw XML file exported by Get-IRTEntraUserSignInLog.
Mutually exclusive
with -Log.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Xml
  Position: Named
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

## OUTPUTS

### None. Results are written to an Excel workbook.

## NOTES

Version: 1.4.0
1.4.0 - SignInEventTypes is now shown by default (right after UserPrincipalName)
        so interactive and non-interactive sign-ins can be told apart in a mixed
        pull.
1.3.0 - OriginalTransferMethod is now shown by default immediately after
        AuthenticationProtocol, and both columns are highlighted when a cell
        contains a device code value.
AutonomousSystemNumber now sits right after
        IpAddress (still hidden by default).
1.2.0 - Surfaced many more sign-in fields as columns (incl.
AuthenticationProtocol);
        all non-curated columns are present but hidden by default.
1.1.3 - Added timers/progress for testing.


## RELATED LINKS

{{ Fill in the related links here }}
