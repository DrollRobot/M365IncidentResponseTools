---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Connect-IRTTenant

## SYNOPSIS
Connects to a tenant using a friendly alias looked up from a tenant configuration worksheet.

## SYNTAX

```
Connect-IRTTenant [-Alias] <String> [-TenantFile <String>] [-Graph] [-Exchange] [-AdditionalScope <String[]>]
 [-DeviceCode <Boolean>] [-PasswordBrowser <String>] [-Private] [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

## DESCRIPTION
Reads tenant information from a worksheet and matches the provided alias against
each tenant's Aliases regex pattern.
Once matched, it passes the tenant's parameters
to Connect-IRT and opens any configured URLs in the browser.

The tenants worksheet should be stored at $env:APPDATA\M365IncidentResponseTools\tenants.xlsx.
A template file (tenants_TEMPLATE.xlsx) is included in the module_init folder for reference.

## EXAMPLES

### EXAMPLE 1
```
Connect-IRTTenant contoso
Looks up 'contoso' in the tenants worksheet and connects to all services.
```

### EXAMPLE 2
```
Connect-IRTTenant fab -Graph
Looks up 'fab' in the tenants worksheet and connects to Graph only.
```

### EXAMPLE 3
```
irttenant bestcompany
Uses the alias to connect to the matching tenant.
```

## PARAMETERS

### -Alias
A string to match against tenant alias patterns.
Matched as a regex against the
Aliases column in the tenants worksheet.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -TenantFile
Path to the tenants worksheet.
Defaults to $env:APPDATA\M365IncidentResponseTools\tenants.xlsx.

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

### -Graph
Connect to Microsoft Graph only.

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

### -Exchange
Connect to Exchange Online only.

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

### -AdditionalScope
Additional Graph scopes to request beyond the default set.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases: AdditionalScopes, Scopes, Scope

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -DeviceCode
Use device code authentication.
Requires the tenant's DeviceAuthAllowed column to be set to 'yes'.
Interactive authentication is used by default.
An error is thrown if device code is requested
but the tenant does not allow it.

```yaml
Type: Boolean
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -PasswordBrowser
{{ Fill PasswordBrowser Description }}

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: $IRT_Config.PasswordBrowser
Accept pipeline input: False
Accept wildcard characters: False
```

### -Private
Open the browser in private/incognito mode.

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
Version: 1.1.0
1.1.0 - Updated to use xlsx file instead of csv.

## RELATED LINKS
