---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Get-IRTUnifiedAuditLog

## SYNOPSIS
Runs multiple queries to pull all Unified Audit Log records related to a specific user.

## SYNTAX

### UserObject (Default)
```
Get-IRTUnifiedAuditLog [[-UserObject] <PSObject[]>] [-Days <Int32>] [-Start <String>] [-End <String>]
 [-ResultLimit <Int32>] [-Operation <String[]>] [-RiskyOperation] [-SignInLog] [-FreeText <String[]>]
 [-Excel <Boolean>] [-WaitOnMessageTrace <Boolean>] [-Xml <Boolean>] [-Cached]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

### AllUsers
```
Get-IRTUnifiedAuditLog [-AllUsers] [-Days <Int32>] [-Start <String>] [-End <String>] [-ResultLimit <Int32>]
 [-Operation <String[]>] [-RiskyOperation] [-SignInLog] [-FreeText <String[]>] [-Excel <Boolean>]
 [-WaitOnMessageTrace <Boolean>] [-Xml <Boolean>] [-Cached] [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

### ServicePrincipal
```
Get-IRTUnifiedAuditLog [[-ServicePrincipal] <PSObject[]>] [-Days <Int32>] [-Start <String>] [-End <String>]
 [-ResultLimit <Int32>] [-Operation <String[]>] [-RiskyOperation] [-SignInLog] [-FreeText <String[]>]
 [-Excel <Boolean>] [-WaitOnMessageTrace <Boolean>] [-Xml <Boolean>] [-Cached]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Queries the Microsoft 365 Unified Audit Log via Exchange Online for activity related
to one or more users, a service principal, or all users in the tenant.
Runs several
categorised queries in parallel (e.g.
SharePoint, Exchange, Teams, Azure AD) and
exports each category to a separate sheet in an Excel workbook.

Date range defaults to the last 30 days when no -Days, -Start, or -End is specified.
Requires an active Exchange Online connection.

## EXAMPLES

### EXAMPLE 1
```
Get-IRTUnifiedAuditLog
Queries the UAL for the last 30 days for the user in the global session.
```

### EXAMPLE 2
```
Get-IRTUnifiedAuditLog -UserObject $User -Days 90
Queries 90 days of UAL activity for a specific user.
```

### EXAMPLE 3
```
Get-IRTUnifiedAuditLog -AllUsers -Operation 'FileDeleted' -Start '2026-04-01' -End '2026-04-30'
Finds all FileDeleted events for any user during April 2026.
```

## PARAMETERS

### -UserObject
One or more user objects to query.
Mutually exclusive with -AllUsers and
-ServicePrincipal.
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
Query the UAL for all users in the tenant.
Mutually exclusive with -UserObject and
-ServicePrincipal.

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

### -ServicePrincipal
One or more service principal objects to query.
Mutually exclusive with -UserObject
and -AllUsers.

```yaml
Type: PSObject[]
Parameter Sets: ServicePrincipal
Aliases: ServicePrincipals

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

### -ResultLimit
Maximum total records to retrieve across all queries and date chunks. Stops at the
next 5000-record page boundary after the limit is reached. Since queries run from
the most recent chunk backward, the most recent events are retained. Default: 50000.

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

### -Operation
Filter results to specific UAL operation names.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases: Operations

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -RiskyOperation
Filter to a predefined list of high-risk operations.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: RiskyOperations

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -SignInLog
Filter to only UAL sign-in operations.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: SignInLogs

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -FreeText
One or more free-text search strings passed to Search-UnifiedAuditLog.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
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

### -WaitOnMessageTrace
Wait for any pending message trace jobs before querying.
Intended for use when running
playbook.
(running functions in parallel) Default: $false.

```yaml
Type: Boolean
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

### -Cached
Use pre-cached Graph data where available.

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
Version: 1.6.0
1.6.0 - Added profile tags to allow generating specific sheets in Show-IRTUnifiedAuditLog.
1.5.1 - Added function name to all output.
1.5.0 - Added -AllUsers option, added test timers.
1.4.0 - Updating to add metadata object, use shorter file names.
1.3.0 - Updated to output objects.

## RELATED LINKS
