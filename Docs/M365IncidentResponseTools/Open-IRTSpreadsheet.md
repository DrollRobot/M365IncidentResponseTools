---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 10/03/2026
PlatyPS schema version: 2024-05-01
title: Open-IRTSpreadsheet
---

# Open-IRTSpreadsheet

## SYNOPSIS

Opens the .xlsx spreadsheets in a folder.

## SYNTAX

```
Open-IRTSpreadsheet [[-Path] <string>] [-Recurse] [<CommonParameters>]
```

## ALIASES

Open-IRTSpreadsheets, OpenIRTSpreadsheet, IRTSpreadsheet

## DESCRIPTION

Opens every .xlsx workbook in a folder (the current directory by default) using the
system default spreadsheet application.
Intended for users who turn off the
OpenSpreadsheets config setting so IRT exports do not open automatically: after running
a batch of commands, run Open-IRTSpreadsheet to open the workbooks that were created.

Excel lock and temporary files (names beginning with '~$') are skipped.

## EXAMPLES

### EXAMPLE 1

```powershell
Open-IRTSpreadsheet
```
Opens every .xlsx file in the current directory.

### EXAMPLE 2

```powershell
Open-IRTSpreadsheet -Path 'C:\Cases\Contoso' -Recurse
```
Opens every .xlsx file under C:\Cases\Contoso and all of its subfolders.

## PARAMETERS

### -Path

Folder to search for .xlsx files.
Defaults to the current directory.

```yaml
Type: System.String
DefaultValue: .
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

### -Recurse

Also open .xlsx files found in subfolders of Path.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### None.

## NOTES

Version: 1.0.1
1.0.1 - Fences the help examples as PowerShell code.


## RELATED LINKS

{{ Fill in the related links here }}
