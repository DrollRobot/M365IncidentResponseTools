---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 10/03/2026
PlatyPS schema version: 2024-05-01
title: Get-IRTServicePrincipal
---

# Get-IRTServicePrincipal

## SYNOPSIS

Displays all service principals in the tenant, or filters by a search term.

## SYNTAX

```
Get-IRTServicePrincipal [[-Search] <string>] [[-TableStyle] <string>] [[-Font] <string>]
 [[-Open] <bool>] [-Cached] [-Excel] [<CommonParameters>]
```

## ALIASES

GetTenantServicePrincipal, GetTenantServicePrincipals, GetTenantSP, GetTenantSPs, GetTenantApp, GetTenantApps, GetTenantApplication, GetTenantApplications, GetTenantEnterpriseApp, GetTenantEnterpriseApps, GetAllServicePrincipals, GetAllSP, GetAllSPs, GetAllApps, GetAllApplications, GetAllEnterpriseApps, Get-Apps, Get-ServicePrincipals, Get-EnterpriseApps, Get-Applications

## DESCRIPTION

Lists the tenant's service principals with created date, type, sign-in audience, reply
URLs and owning tenant.
Owning tenant IDs are resolved to names with
Get-IRTTenantOwner.
Returns objects by default.
Use -Excel to export a workbook
instead.

## EXAMPLES

### EXAMPLE 1

```powershell
Get-IRTServicePrincipal -Search 'Graph'
```
Lists service principals whose display name matches 'Graph'.

### EXAMPLE 2

```powershell
Get-IRTServicePrincipal -Excel
```
Exports all service principals in the tenant to an Excel workbook.

## PARAMETERS

### -Cached

Use pre-cached Graph data where available.

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

Export results to an Excel workbook instead of returning objects.

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

Excel font name.
Used with -Excel.
Defaults to IRT_Config.ExcelFont.

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

### -Open

Open the Excel file immediately after export.
Used with -Excel.
Defaults to
IRT_Config.OpenSpreadsheets.

```yaml
Type: System.Boolean
DefaultValue: '[bool]$Global:IRT_Config.OpenSpreadsheets'
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

### -Search

Regular expression matched against service principal display names.
When omitted, all
service principals are returned.

```yaml
Type: System.String
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

### -TableStyle

Excel table style.
Used with -Excel.
Defaults to IRT_Config.ExcelTableStyle.

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

### IRT.TenantServicePrincipal objects. None when -Excel is used.

### System.Collections.Generic.List`1[[System.Management.Automation.PSObject, System.Management.Automation, Version=7.6.0.500, Culture=neutral, PublicKeyToken=31bf3856ad364e35]]

## NOTES

Version: 1.3.0
1.3.0 - Added -Excel export option.


## RELATED LINKS

{{ Fill in the related links here }}
