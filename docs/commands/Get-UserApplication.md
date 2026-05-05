---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Get-UserApplication

## SYNOPSIS
Displays user's Oauth2 permission grants.
(Applications they have granted consent to)

## SYNTAX

```
Get-UserApplication [[-UserObject] <PSObject[]>] [-TableStyle <String>] [-Font <String>] [-Xml <Boolean>]
 [-Open <Boolean>] [-Cached] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Retrieves all OAuth2 permission grants for one or more Entra ID users and displays the
applications they have personally consented to.
Each row shows the app name, granted
scopes, and the consent date if available.

Falls back to $Global:IRT_UserObjects if no -UserObject is passed.

## EXAMPLES

### EXAMPLE 1
```
Get-UserApplication
Shows OAuth app consents for the user in the global session.
```

### EXAMPLE 2
```
Get-UserApplication -UserObject $User
Shows OAuth app consents for a specific user.
```

## PARAMETERS

### -UserObject
One or more Entra ID user objects to query.
Falls back to global session objects if
omitted.
Accepts pipeline input.

```yaml
Type: PSObject[]
Parameter Sets: (All)
Aliases: UserObjects

Required: False
Position: 1
Default value: None
Accept pipeline input: True (ByPropertyName, ByValue)
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

### -Cached
Use pre-cached Graph service principal data instead of making new API calls.

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

### None. Results are displayed in the console and optionally exported to Excel.

## NOTES

## RELATED LINKS
