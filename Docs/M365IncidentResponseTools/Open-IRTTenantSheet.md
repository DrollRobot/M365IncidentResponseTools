---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 09/16/2026
PlatyPS schema version: 2024-05-01
title: Open-IRTTenantSheet
---

# Open-IRTTenantSheet

## SYNOPSIS

Opens the tenants worksheet for editing. Creates it if it doesn't exist.

## SYNTAX

```
Open-IRTTenantSheet [[-TenantFile] <string>] [<CommonParameters>]
```

## ALIASES

Open-IRTTenantWorksheet, OpenIRTTenantWorksheet, OpenIRTTenantSheet, IRTTenantSheet

## DESCRIPTION

Opens the tenants worksheet that Connect-IRTTenant reads.
When the file is not
present it is generated first, with the standard columns and a few sample rows
showing the expected format, then opened in the default handler for .xlsx files.

## EXAMPLES

### EXAMPLE 1

```powershell
Open-IRTTenantSheet
```
Opens the tenants worksheet, generating it first if this is the first run.

### EXAMPLE 2

```powershell
Open-IRTTenantSheet -TenantFile 'C:\Cases\tenants.xlsx'
```
Opens a tenants worksheet stored outside the default configuration directory.

## PARAMETERS

### -TenantFile

Path to the tenants worksheet.
Defaults to $env:APPDATA\M365IncidentResponseTools\tenants.xlsx.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### None. The worksheet is opened in the default application for .xlsx files.

## NOTES

Version: 1.1.0


## RELATED LINKS

{{ Fill in the related links here }}
