---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Get-SignInLog

## SYNOPSIS
Downloads user sign in logs.

## SYNTAX

### UserObject (Default)
```
Get-SignInLog [[-UserObject] <PSObject[]>] [-Days <Int32>] [-Start <String>] [-End <String>] [-NonInteractive]
 [-Beta <Boolean>] [-Excel <Boolean>] [-IpInfo <Boolean>] [-Open <Boolean>] [-Test] [-Xml <Boolean>]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

### AllUsers
```
Get-SignInLog [-AllUsers] [-Days <Int32>] [-Start <String>] [-End <String>] [-NonInteractive] [-Beta <Boolean>]
 [-Excel <Boolean>] [-IpInfo <Boolean>] [-Open <Boolean>] [-Test] [-Xml <Boolean>]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

### IpAddress
```
Get-SignInLog [-IpAddress <String[]>] [-Days <Int32>] [-Start <String>] [-End <String>] [-NonInteractive]
 [-Beta <Boolean>] [-Excel <Boolean>] [-IpInfo <Boolean>] [-Open <Boolean>] [-Test] [-Xml <Boolean>]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Retrieves Entra ID interactive sign-in logs via Microsoft Graph for one or more users,
a set of IP addresses, or all users in the tenant.
Enriches each log entry with
IP geolocation data and human-readable Entra error descriptions, then exports results
to an Excel workbook.

Date range defaults to the last 30 days when no -Days, -Start, or -End is specified.

## EXAMPLES

### EXAMPLE 1
```
Get-SignInLog
Downloads the last 30 days of sign-in logs for the user in the global session.
```

### EXAMPLE 2
```
Get-SignInLog -UserObject $User -Days 90
Downloads 90 days of sign-in logs for a specific user.
```

### EXAMPLE 3
```
Get-SignInLog -IpAddress '203.0.113.5' -Days 14
Finds all sign-ins from a specific IP over the last 14 days.
```

## PARAMETERS

### -UserObject
One or more user objects whose sign-in logs to retrieve.
Mutually exclusive with
-AllUsers and -IpAddress.
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

### -AllUsers
Retrieve sign-in logs for all users in the tenant.
Mutually exclusive with -UserObject
and -IpAddress.

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

### -IpAddress
One or more IP addresses to filter sign-in logs by source IP.
Mutually exclusive with
-UserObject and -AllUsers.

```yaml
Type: String[]
Parameter Sets: IpAddress
Aliases:

Required: False
Position: Named
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

### -NonInteractive
Retrieve non-interactive sign-in logs instead of interactive logs.

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
Use the Microsoft Graph beta endpoint.
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

### -IpInfo
Enrich results with IP geolocation data.
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

### -Test
Enable stopwatch timing output.

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
Version: 1.1.2
1.1.2 - Added graceful exit when no logs are found.
1.1.1 - Added test timers.

## RELATED LINKS
