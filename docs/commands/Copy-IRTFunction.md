---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Copy-IRTFunction

## SYNOPSIS
Copies the contents of the IRT helper functions to the clipboard.

## SYNTAX

```
Copy-IRTFunction [[-Path] <String[]>] [-Recurse] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Reads files from a hardcoded list of internal module paths and any
additional paths supplied via -Path, then concatenates their contents into
a single string with a header line showing each file's full path.
The
combined text is sent to the clipboard via Set-Clipboard.

Hardcoded paths:
  - onprem_ad\*  (all files in the onprem_ad folder)

When -Path is supplied, each entry is resolved as either a .ps1 file or a
directory whose .ps1 files are collected.
Use -Recurse to walk
subdirectories for the extra paths.

## EXAMPLES

### EXAMPLE 1
```
Copy-IRTFunction
```

Copies the hardcoded IRT helper files to the clipboard.

### EXAMPLE 2
```
Copy-IRTFunction -Path .\signin_logs
```

Copies hardcoded files plus all .ps1 files in the signin_logs folder.

## PARAMETERS

### -Path
One or more additional file or directory paths to include.
Accepts pipeline
input.
Directories are scanned for .ps1 files.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases: FullName, PSPath

Required: False
Position: 1
Default value: None
Accept pipeline input: True (ByPropertyName, ByValue)
Accept wildcard characters: False
```

### -Recurse
Recurse into subdirectories when expanding directory paths supplied via
-Path.

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
Version: 1.0.3

## RELATED LINKS
