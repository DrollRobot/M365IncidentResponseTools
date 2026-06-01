---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Open-IRTTab

## SYNOPSIS
Opens a new Windows Terminal tab and loads the module.

## SYNTAX

```
Open-IRTTab [[-Title] <String>] [-Quiet] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Opens a new tab in the current Windows Terminal window and imports
M365IncidentResponseTools.
If an active IRT session exists, also calls
Connect-IRT to connect to the same tenant.

Must be run from within Windows Terminal; detected via the WT_SESSION
environment variable set by Windows Terminal in every hosted session.

## EXAMPLES

### EXAMPLE 1
```
Open-IRTTab
Opens a new tab. Connects to the current tenant if a session is active.
```

### EXAMPLE 2
```
Open-IRTTab -Quiet
Opens a new tab if in Windows Terminal; silently does nothing otherwise.
```

### EXAMPLE 3
```
Open-IRTTab -Title '[IRT] Secondary'
Opens a new tab with a custom title.
```

## PARAMETERS

### -Title
Title for the new terminal tab.
Defaults to '\[IRT\]'.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: [IRT]
Accept pipeline input: False
Accept wildcard characters: False
```

### -Quiet
When set, silently returns without error if the current console is not
Windows Terminal.
Useful when calling from a profile or script that may
run in multiple console hosts.

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

### None
## NOTES
Version: 1.1.0
1.1.0 - Requires Windows Terminal host.
Opens without connecting when no
        active session exists.

## RELATED LINKS
