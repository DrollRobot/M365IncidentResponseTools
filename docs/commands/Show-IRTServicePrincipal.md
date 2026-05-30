---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Show-IRTServicePrincipal

## SYNOPSIS
Displays detailed service principal properties for objects produced by Find-ServicePrincipal.

## SYNTAX

```
Show-IRTServicePrincipal [[-ServicePrincipalObject] <PSObject[]>] [-Cached]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Retrieves the full Graph service principal object using a curated property list and
displays it as a formatted tree in the console via Show-GraphServicePrincipalTree.

Falls back to $Global:IRT_ServicePrincipalObjects if no -ServicePrincipalObject is
passed.
This lets you run Find-ServicePrincipal first to select a target, then run
Show-IRTServicePrincipal with no arguments to display it.

Properties retrieved include credentials (key and password certificates), OAuth2
permission scopes, app roles, reply URLs, SSO settings, publisher verification,
and all standard identity fields.

After the property tree, four additional tables are displayed:
- OAuth2 Permission Grants: delegated permissions the SP has been granted (user or
  admin consent), with the resource display name resolved from the resource ID.
- App Role Assignments: application permissions (admin-consented app roles) assigned
  to the SP, with the role GUID resolved to the human-readable permission value.
- Directory Role Memberships: Entra admin roles (e.g.
Cloud Application Administrator)
  the SP has been assigned to.
Uses the IRT_DirectoryRoles cache if populated.
- App Role Assigned To: users, groups, and SPs that have been granted access to this app.

## EXAMPLES

### EXAMPLE 1
```
Find-ServicePrincipal MyApp
Show-IRTServicePrincipal
Two-step workflow: find then display.
```

### EXAMPLE 2
```
Show-IRTServicePrincipal
Display info for the service principal already stored in the global session.
```

### EXAMPLE 3
```
Show-IRTServicePrincipal -ServicePrincipalObject $SP
Display info for a specific service principal object passed directly.
```

## PARAMETERS

### -ServicePrincipalObject
One or more service principal objects to display.
Falls back to
$Global:IRT_ServicePrincipalObjects if omitted.

```yaml
Type: PSObject[]
Parameter Sets: (All)
Aliases: ServicePrincipalObjects

Required: False
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Cached
Pass -Cached to all Request-* calls so previously fetched Graph data is reused
instead of making new API calls.
Without this switch, each Request-* call fetches
fresh data from Graph.

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

### None. Output is written to the console.
## NOTES
Version: 1.3.0

## RELATED LINKS
