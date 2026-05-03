---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Get-EntraAuditLog

## SYNOPSIS
Downloads Entra ID (Azure AD) audit log events for one or more users.

## SYNTAX

```
Get-EntraAuditLog [[-UserObject] <PSObject[]>] [-Days <Int32>] [-Start <String>] [-End <String>] [-AllUsers]
 [-Beta] [-Open <Boolean>] [-Xml <Boolean>] [-Cached] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Queries the Entra ID directory audit log via Microsoft Graph for activity related
to the specified users over a configurable date range.
Results are exported to an
Excel workbook.
Use -AllUsers to pull the full tenant audit log regardless of user.

Date range defaults to the last 30 days when no -Days, -Start, or -End is specified.

## EXAMPLES

### EXAMPLE 1
```
Get-EntraAuditLog
Downloads the last 30 days of Entra audit events for the user in the global session.
```

### EXAMPLE 2
```
Get-EntraAuditLog -UserObject $User -Days 90
Downloads 90 days of audit events for a specific user.
```

### EXAMPLE 3
```
Get-EntraAuditLog -AllUsers -Start '2026-04-01' -End '2026-04-30'
Downloads all tenant audit events for April 2026.
```

## PARAMETERS

### -UserObject
One or more user objects to query.
Falls back to global session objects if omitted.

```yaml
Type: PSObject[]
Parameter Sets: (All)
Aliases: UserObjects

Required: False
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Days
Number of days back to search.
Cannot be used with -Start / -End.

```yaml
Type: Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: 0
Accept pipeline input: False
Accept wildcard characters: False
```

### -Start
Start of date range (parseable date string).
Used with -End for an absolute range.

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

### -End
End of date range (parseable date string).
Used with -Start for an absolute range.

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

### -AllUsers
Pull the full tenant audit log without filtering by user.

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

### -Beta
Use the Microsoft Graph beta endpoint instead of v1.0.

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

### -Open
Open the Excel file immediately after export.
Default: $true.

```yaml
Type: Boolean
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: True
Accept pipeline input: False
Accept wildcard characters: False
```

### -Xml
Export raw XML alongside the Excel file.
Defaults to IRT_Config.ExportXml.

```yaml
Type: Boolean
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: $Global:IRT_Config.ExportXml
Accept pipeline input: False
Accept wildcard characters: False
```

### -Cached
Use pre-cached Graph data instead of making new API calls.

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

### None. Results are exported to an Excel workbook.
## NOTES
Version: 1.1.0

## RELATED LINKS
