---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Get-LicenseReport

## SYNOPSIS
Shows table of tenant licenses.

## SYNTAX

```
Get-LicenseReport [-Objects] [-Runspace] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Retrieves all subscribed SKUs from Microsoft Graph, resolves each SKU's friendly
product name via Get-LicenseFullName, and displays a formatted table showing
capability status, applies-to scope, license name, total enabled units, consumed
units, and available units.
Use -Objects to return raw enriched objects instead.

## EXAMPLES

### EXAMPLE 1
```
Get-LicenseReport
Displays a color-formatted license table in the console.
```

### EXAMPLE 2
```
$Licenses = Get-LicenseReport -Objects
Returns raw license objects for further processing.
```

## PARAMETERS

### -Objects
Return raw license objects (with the LicenseFullName property added) instead of
displaying the formatted table.
Useful for piping to further processing.

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

### -Runspace
Switch to Format-Table -AutoSize output instead of Write-PSObject color formatting.
Set automatically when called from a runspace (e.g., the incident response playbook).

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

### None (console table) by default.
### Microsoft.Graph.PowerShell.Models.MicrosoftGraphSubscribedSku[] when -Objects is used.
## NOTES
Version: 1.1.3
1.1.3 - Added optional output formatting for runspaces.

## RELATED LINKS
