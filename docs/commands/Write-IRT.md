---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Write-IRT

## SYNOPSIS
Writes a colored, prefixed status message to the host.

## SYNTAX

```
Write-IRT [[-Message] <String>] [-Level <String>] [-FunctionName <String>] [-NoNewline] [-NoColor]
 [-NoFunctionName] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Central output helper for IRT.
Reads foreground colors from $Global:IRT_Config
(InfoColor, WarnColor, ErrorColor) with hardcoded fallbacks so it works even
before the config is loaded (e.g.
in onprem_ad functions pasted to a remote
machine).

The calling function's name is detected automatically from the call stack and
prepended to the message.
Override it with -FunctionName when a parent function
wants its name to appear on output from a child helper it calls.

## EXAMPLES

### EXAMPLE 1
```
Write-IRT "Retrieving sign-in logs for $($User.DisplayName)."
Writes an Info-level message with the calling function's name prepended.
```

### EXAMPLE 2
```
Write-IRT "No records found." -Level Warn
Writes a yellow warning message.
```

## PARAMETERS

### -Message
The message text to display.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Level
Output level: Info (default), Warn, or Error.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: Info
Accept pipeline input: False
Accept wildcard characters: False
```

### -FunctionName
Override the auto-detected caller name.
Useful when a parent passes its own
name down to a child helper: Request-GraphUser -FunctionName $MyInvocation.MyCommand.Name

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -NoNewline
Passes -NoNewline through to Write-Host.

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

### -NoColor
Suppresses color output.
Useful when writing to a transcript or redirected
stream that does not support ANSI color codes.

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

### -NoFunctionName
Suppresses the calling function name prefix. Useful for plain status messages
that do not need attribution.

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

### None. Output is written directly to the console.
## NOTES
Version: 1.0.0

## RELATED LINKS
