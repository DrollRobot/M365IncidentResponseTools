---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Get-IRTServicePrincipalSignInLog

## SYNOPSIS
Downloads service principal sign-in logs.

## SYNTAX

### ServicePrincipalObject (Default)
```
Get-IRTServicePrincipalSignInLog [[-ServicePrincipalObject] <PSObject[]>] [-Days <Int32>] [-Start <String>]
 [-End <String>] [-Beta <Boolean>] [-Excel <Boolean>] [-IpInfo <Boolean>] [-Open <Boolean>] [-Xml <Boolean>]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

### AllServicePrincipals
```
Get-IRTServicePrincipalSignInLog [-AllServicePrincipals] [-Days <Int32>] [-Start <String>] [-End <String>]
 [-Beta <Boolean>] [-Excel <Boolean>] [-IpInfo <Boolean>] [-Open <Boolean>] [-Xml <Boolean>]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Retrieves Entra ID service principal sign-in logs via Microsoft Graph for one or more
service principals or all service principals in the tenant.
Enriches each log entry
with IP geolocation data and human-readable Entra error descriptions, then exports
results to an Excel workbook.

Date range defaults to the last 30 days when no -Days, -Start, or -End is specified.

Falls back to $Global:IRT_ServicePrincipalObjects if no -ServicePrincipalObject is
passed.
Use Find-ServicePrincipal first to populate that global variable.

## EXAMPLES

### EXAMPLE 1
```
Find-ServicePrincipal MyApp
Get-IRTServicePrincipalSignInLog
Two-step workflow: find the SP then download its sign-in logs.
```

### EXAMPLE 2
```
Get-IRTServicePrincipalSignInLog -ServicePrincipalObject $SP -Days 90
Downloads 90 days of sign-in logs for a specific service principal.
```

### EXAMPLE 3
```
Get-IRTServicePrincipalSignInLog -AllServicePrincipals -Days 7
Downloads 7 days of sign-in logs for all service principals in the tenant.
```

## PARAMETERS

### -ServicePrincipalObject
One or more service principal objects whose sign-in logs to retrieve.
Mutually
exclusive with -AllServicePrincipals.
Falls back to global session objects if omitted.

```yaml
Type: PSObject[]
Parameter Sets: ServicePrincipalObject
Aliases: ServicePrincipalObjects

Required: False
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -AllServicePrincipals
Retrieve sign-in logs for all service principals in the tenant.
Mutually exclusive
with -ServicePrincipalObject.

```yaml
Type: SwitchParameter
Parameter Sets: AllServicePrincipals
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
Version: 1.0.0

## RELATED LINKS
