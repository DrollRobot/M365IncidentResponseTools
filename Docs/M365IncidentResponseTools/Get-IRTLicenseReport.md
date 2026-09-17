---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 09/07/2026
PlatyPS schema version: 2024-05-01
title: Get-IRTLicenseReport
---

# Get-IRTLicenseReport

## SYNOPSIS

Shows table of tenant licenses.

## SYNTAX

```
Get-IRTLicenseReport [-Objects] [-Runspace] [<CommonParameters>]
```

## ALIASES

LicenseReport

## DESCRIPTION

Retrieves all subscribed SKUs from Microsoft Graph, resolves each SKU's friendly
product name via Get-LicenseFullName, and displays a formatted table showing
capability status, applies-to scope, license name, total enabled units, consumed
units, and available units.
Use -Objects to return raw enriched objects instead.

## EXAMPLES

### EXAMPLE 1

```powershell
Get-IRTLicenseReport
```
Displays a color-formatted license table in the console.

### EXAMPLE 2

```powershell
$Licenses = Get-IRTLicenseReport -Objects
```
Returns raw license objects for further processing.

## PARAMETERS

### -Objects

Return raw license objects (with the LicenseFullName property added) instead of
displaying the formatted table.
Useful for piping to further processing.

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

### -Runspace

Deprecated.
Output is always a plain Format-Table now; the switch is retained
so existing callers do not break.

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

### None (console table) by default.
Microsoft.Graph.PowerShell.Models.MicrosoftGraphSubscribedSku[] when -Objects is used.

## NOTES

Version: 1.3.0
1.3.0 - Highlight E5 SKUs in yellow via $PSStyle (PS 7.2+) and print an E5
        security-tooling callout after the table.
1.2.0 - Removed the Write-PSObject dependency; output is always plain
        Format-Table.
-Runspace is now a no-op kept for compatibility.
1.1.3 - Added optional output formatting for runspaces.


## RELATED LINKS

{{ Fill in the related links here }}
