---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 08/02/2026
PlatyPS schema version: 2024-05-01
title: Get-IRTAdminRole
---

# Get-IRTAdminRole

## SYNOPSIS

Reports all Entra ID directory role members for the tenant.

## SYNTAX

```
Get-IRTAdminRole [[-Highlight] <string[]>] [[-TableStyle] <string>] [[-Font] <string>]
 [[-Open] <bool>] [-Cached] [-Script] [-Excel] [<CommonParameters>]
```

## ALIASES

GetAdmins

## DESCRIPTION

Retrieves every Entra ID (Azure AD) directory role and its members, including users,
service principals, and groups.
When a group holds a role, its members are expanded
inline so the report is always a flat list of effective principals.

Output defaults to formatted console tables grouped by object type (Users, Service
Principals, Groups).
Use -Excel to export a formatted .xlsx workbook instead.

## EXAMPLES

### EXAMPLE 1

Get-IRTAdminRole
Displays all role members grouped by type in the console.

### EXAMPLE 2

Get-IRTAdminRole -Excel -Highlight 'jsmith@contoso.com'
Exports an Excel report and flags any row matching 'jsmith@contoso.com'.

### EXAMPLE 3

$RoleMembers = Get-IRTAdminRole -Script
Returns raw objects for further processing.

## PARAMETERS

### -Cached

Use pre-cached Graph data instead of making new API calls.
Speeds up repeated runs
during the same session.

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

### -Excel

Export results to a formatted Excel workbook (.xlsx) in the current directory.

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

### -Font

Font name for the Excel workbook.
Defaults to the value in IRT_Config.ExcelFont.

```yaml
Type: System.String
DefaultValue: $Global:IRT_Config.ExcelFont
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 2
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Highlight

One or more strings to search across Id, DisplayName, UserPrincipalName, and
Description.
Matching rows are flagged with '>>>' in a Match column.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
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

### -Open

When exporting to Excel, open the file immediately after writing.
Default: $true.

```yaml
Type: System.Boolean
DefaultValue: True
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 3
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Script

Return raw PSCustomObject results instead of printing to the console.
Useful when
calling this function from scripts or the playbook.

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

### -TableStyle

Excel table style name.
Defaults to the value in IRT_Config.ExcelTableStyle.

```yaml
Type: System.String
DefaultValue: $Global:IRT_Config.ExcelTableStyle
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 1
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

### None (console output) by default.
System.Collections.Generic.List[PSCustomObject] when -Script is used.

## NOTES

## RELATED LINKS

{{ Fill in the related links here }}
