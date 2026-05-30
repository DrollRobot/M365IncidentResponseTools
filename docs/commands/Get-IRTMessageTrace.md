---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Get-IRTMessageTrace

## SYNOPSIS
Downloads incoming and outgoing message trace for specified user, or all users.

## SYNTAX

### UserObject (Default)
```
Get-IRTMessageTrace [[-UserObject] <PSObject[]>] [-Days <Int32>] [-Start <String>] [-End <String>]
 [-ResultLimit <Int32>] [-Variable <Boolean>] [-Excel <Boolean>] [-Quiet] [-Xml <Boolean>]
 [-TableStyle <String>] [-Font <String>] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

### UserEmail
```
Get-IRTMessageTrace [-UserEmail <String[]>] [-Days <Int32>] [-Start <String>] [-End <String>]
 [-ResultLimit <Int32>] [-Variable <Boolean>] [-Excel <Boolean>] [-Quiet] [-Xml <Boolean>]
 [-TableStyle <String>] [-Font <String>] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

### AllUsers
```
Get-IRTMessageTrace [-AllUsers] [-Days <Int32>] [-Start <String>] [-End <String>] [-ResultLimit <Int32>]
 [-Variable <Boolean>] [-Excel <Boolean>] [-Quiet] [-Xml <Boolean>] [-TableStyle <String>] [-Font <String>]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Retrieves Exchange Online message trace records for one or more users over a configurable
date range and exports results to Excel.
Accepts user objects, email addresses, or an
-AllUsers switch for tenant-wide queries.

Supports both the modern V2 API (large result sets via background jobs) and the legacy
V1 endpoint.
Date range defaults to the last 10 days when no -Days, -Start, or -End
is specified.

## EXAMPLES

### EXAMPLE 1
```
Get-IRTMessageTrace
Downloads message trace for the user in the global session (last 10 days).
```

### EXAMPLE 2
```
Get-IRTMessageTrace -UserObject $User -Days 30
Downloads 30 days of message trace for a specific user.
```

### EXAMPLE 3
```
Get-IRTMessageTrace -AllUsers -Start '2026-04-01' -End '2026-04-30'
Downloads all tenant message trace for April 2026.
```

## PARAMETERS

### -UserObject
One or more user objects to trace.
Mutually exclusive with -UserEmail and -AllUsers.
Falls back to global session objects if omitted.

```yaml
Type: PSObject[]
Parameter Sets: UserObject
Aliases: UserObjects

Required: False
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -UserEmail
One or more email addresses to trace.
Mutually exclusive with -UserObject and -AllUsers.

```yaml
Type: String[]
Parameter Sets: UserEmail
Aliases: UserEmails

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -AllUsers
Query message trace for all users in the tenant.
Mutually exclusive with -UserObject
and -UserEmail.

```yaml
Type: SwitchParameter
Parameter Sets: AllUsers
Aliases:

Required: False
Position: Named
Default value: False
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

### -ResultLimit
Maximum number of records to return.
Default: 50000.

```yaml
Type: Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: 50000
Accept pipeline input: False
Accept wildcard characters: False
```

### -Variable
Save results to a session variable for downstream use.
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

### -Excel
Export results to an Excel workbook.
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

### -Quiet
Suppress progress output.

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

### -TableStyle
Excel table style.
Defaults to IRT_Config.ExcelTableStyle.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: $Global:IRT_Config.ExcelTableStyle
Accept pipeline input: False
Accept wildcard characters: False
```

### -Font
Excel font name.
Defaults to IRT_Config.ExcelFont.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: $Global:IRT_Config.ExcelFont
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

### None. Results are exported to Excel and stored in a session variable.
## NOTES
Version: 1.5.0
1.5.0 - Integrated V1 and V2 into same function.
1.4.0 - Switched to separate get/show functions.
Updated to passing objects, not files.
Added global variables.

## RELATED LINKS
