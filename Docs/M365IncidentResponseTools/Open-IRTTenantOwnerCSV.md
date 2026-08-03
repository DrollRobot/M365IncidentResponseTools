---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 08/03/2026
PlatyPS schema version: 2024-05-01
title: Open-IRTTenantOwnerCSV
---

# Open-IRTTenantOwnerCSV

## SYNOPSIS

Opens the local tenant info cache CSV in the default application.

## SYNTAX

```
Open-IRTTenantOwnerCSV [<CommonParameters>]
```

## ALIASES

None.

## DESCRIPTION

Opens $env:APPDATA\<ModuleName>\TenantOwnerInfo.csv in the system default
application (typically Excel or Notepad), where <ModuleName> is resolved at
runtime.
If the file does not exist yet, a warning is displayed.

## EXAMPLES

### EXAMPLE 1

```powershell
Open-IRTTenantOwnerCSV
```

## PARAMETERS

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

## NOTES

Version: 1.0.0


## RELATED LINKS

{{ Fill in the related links here }}
