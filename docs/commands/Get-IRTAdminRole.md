---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Get-IRTAdminRole

## SYNOPSIS
Reports all Entra ID directory role members for the tenant.

## SYNTAX

```
Get-IRTAdminRole [-Cached] [-Script] [-Excel] [[-Highlight] <String[]>] [[-TableStyle] <String>]
 [[-Font] <String>] [[-Open] <Boolean>] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Retrieves every Entra ID (Azure AD) directory role and its members, including users,
service principals, and groups.
When a group holds a role, its members are expanded
inline so the report is always a flat list of effective principals.

Output defaults to formatted console tables grouped by object type (Users, Service
Principals, Groups).
Use -Excel to export a formatted .xlsx workbook instead.

## EXAMPLES

### EXAMPLE 1
```
Get-IRTAdminRole
Displays all role members grouped by type in the console.
```

### EXAMPLE 2
```
Get-IRTAdminRole -Excel -Highlight 'jsmith@contoso.com'
Exports an Excel report and flags any row matching 'jsmith@contoso.com'.
```

### EXAMPLE 3
```
$RoleMembers = Get-IRTAdminRole -Script
Returns raw objects for further processing.
```

## PARAMETERS

### -Cached
Use pre-cached Graph data instead of making new API calls.
Speeds up repeated runs
during the same session.

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

### -Script
Return raw PSCustomObject results instead of printing to the console.
Useful when
calling this function from scripts or the playbook.

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

### -Excel
Export results to a formatted Excel workbook (.xlsx) in the current directory.

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

### -Highlight
One or more strings to search across Id, DisplayName, UserPrincipalName, and
Description.
Matching rows are flagged with '\>\>\>' in a Match column.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -TableStyle
Excel table style name.
Defaults to the value in IRT_Config.ExcelTableStyle.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: $Global:IRT_Config.ExcelTableStyle
Accept pipeline input: False
Accept wildcard characters: False
```

### -Font
Font name for the Excel workbook.
Defaults to the value in IRT_Config.ExcelFont.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: $Global:IRT_Config.ExcelFont
Accept pipeline input: False
Accept wildcard characters: False
```

### -Open
When exporting to Excel, open the file immediately after writing.
Default: $true.

```yaml
Type: Boolean
Parameter Sets: (All)
Aliases:

Required: False
Position: 4
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

### None (console output) by default.
### System.Collections.Generic.List[PSCustomObject] when -Script is used.
## NOTES

## RELATED LINKS
