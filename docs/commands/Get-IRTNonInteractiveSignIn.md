---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Get-IRTNonInteractiveSignIn

## SYNOPSIS
Downloads non-interactive Entra ID sign-in logs for one or more users.

## SYNTAX

```
Get-IRTNonInteractiveSignIn [[-UserObject] <PSObject[]>] [-Days <Int32>] [-Beta <Boolean>] [-Xml <Boolean>]
 [-Script <Boolean>] [-Open <Boolean>] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
A convenience wrapper around Get-IRTEntraSignInLog that sets -NonInteractive automatically.
Non-interactive sign-ins include token refresh events, legacy protocol logins, and
service-to-service calls - often missed during investigations that focus only on
interactive sign-ins.

Date range and output behavior are identical to Get-IRTEntraSignInLog.
Falls back to $Global:IRT_UserObjects if no -UserObject is passed.

## EXAMPLES

### EXAMPLE 1
```
Get-IRTNonInteractiveSignIn
Downloads non-interactive sign-in logs for the user in the global session.
```

### EXAMPLE 2
```
Get-IRTNonInteractiveSignIn -UserObject $User -Days 30
Downloads 30 days of non-interactive sign-ins for a specific user.
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

### -Script
Return raw objects instead of exporting to Excel.
Default: $false.

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

### None by default. PSCustomObject[] when -Script is $true.
## NOTES
Version: 1.0.0

## RELATED LINKS
