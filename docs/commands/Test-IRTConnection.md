---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Test-IRTConnection

## SYNOPSIS
Shows which IRT services are connected and to which tenant.

## SYNTAX

```
Test-IRTConnection [-Quiet] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Checks the current Graph and Exchange Online connections and displays
the connected domain for each.
Useful for confirming which tenant you
are working against before running incident response commands.

## EXAMPLES

### EXAMPLE 1
```
Test-IRTConnection
Displays connection status for Graph and Exchange.
```

### EXAMPLE 2
```
if (-not (Test-IRTConnection -Quiet)) { throw 'Not fully connected.' }
Silently asserts that both services are connected to the same tenant.
```

## PARAMETERS

### -Quiet
Returns $true if both Graph and Exchange are connected to the same
tenant (matched by TenantId), $false otherwise.
Suppresses all output.

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
Version: 1.0.0

## RELATED LINKS
