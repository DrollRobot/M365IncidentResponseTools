---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Resolve-IRTDateRange

## SYNOPSIS
Validates and resolves date range parameters into a standardized object.

## SYNTAX

```
Resolve-IRTDateRange [[-Days] <Int32>] [[-Start] <String>] [[-End] <String>] [[-DefaultDays] <Int32>]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Accepts either a relative range (-Days) or an absolute range (-Start and -End).
Validates inputs, parses date strings, converts to UTC, and returns a structured
object with all values needed to build API filter strings and display output.

Pass -DefaultDays to specify the fallback used when the user provides no date
arguments.
This is handled internally so that the raw -Days value reflects only
what the user explicitly passed, keeping validation correct.

## EXAMPLES

### Example 1
```powershell
PS C:\> {{ Add example code here }}
```

{{ Add example description here }}

## PARAMETERS

### -Days
{{ Fill Days Description }}

```yaml
Type: Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: 0
Accept pipeline input: False
Accept wildcard characters: False
```

### -Start
{{ Fill Start Description }}

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -End
{{ Fill End Description }}

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -DefaultDays
{{ Fill DefaultDays Description }}

```yaml
Type: Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: 4
Default value: 0
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

### [pscustomobject] with properties:
###     RangeType   - 'Relative' or 'Absolute'
###     Days        - int: user-specified relative value, or ceiling of absolute span
###     StartUtc    - [datetime] UTC start
###     EndUtc      - [datetime] UTC end
###     StartString - string formatted as "yyyy-MM-ddTHH:mm:ssZ" for API filters
###     EndString   - string formatted as "yyyy-MM-ddTHH:mm:ssZ" for API filters
## NOTES
Version: 1.1.0

## RELATED LINKS
