---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Connect-IRT

## SYNOPSIS
Connects to Microsoft Graph and Exchange Online for incident response.

## SYNTAX

### TenantId (Default)
```
Connect-IRT -TenantId <String> [-Silent] [-Cloud <String>] [-AdditionalScope <String[]>] [-Graph] [-Exchange]
 [-IPPS] [-Browser <String>] [-Private] [-Force] [-ClientId <String>] [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

### Refresh
```
Connect-IRT [-Refresh] [-Silent] [-Cloud <String>] [-AdditionalScope <String[]>] [-Graph] [-Exchange] [-IPPS]
 [-Browser <String>] [-Private] [-Force] [-ClientId <String>] [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

## DESCRIPTION
Orchestrates connections to Graph and Exchange Online.
When no service switches are specified, both services are connected.
Use -Graph
or -Exchange to connect to specific services only.

## EXAMPLES

### EXAMPLE 1
```
Connect-IRT -TenantId $tid
Connects to Graph and Exchange Online.
```

### EXAMPLE 2
```
Connect-IRT -TenantId $tid -Graph -DeviceCode
Connects to Graph only using device code auth.
```

### EXAMPLE 3
```
Connect-IRT -TenantId $tid -Exchange -GCCHigh
Connects to Exchange in a GCC High environment.
```

## PARAMETERS

### -TenantId
The TenantId GUID for the environment you want to connect to.

```yaml
Type: String
Parameter Sets: TenantId
Aliases:

Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Refresh
Re-connects all services that are present in the current session using the
stored TenantId and cloud environment. Reads parameters from
$Global:IRT_Session instead of requiring them on the command line.
Combine with -Silent to suppress interactive auth fallback.

```yaml
Type: SwitchParameter
Parameter Sets: Refresh
Aliases:

Required: True
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -Silent
When set, token acquisition skips the interactive browser/device-code
fallback. If MSAL cannot silently refresh a token, the function throws
instead of prompting. Intended for use in the prompt function and other
non-interactive callers.

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

### -Cloud
Cloud to connect to. Valid values: Commercial, USGov, China.
When omitted the cloud is detected automatically via OIDC discovery. Provide
this parameter to skip the lookup or to override the detected value.

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

### -AdditionalScope
Additional Graph scopes to request beyond the default set.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases: AdditionalScopes

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

### -IPPS
{{ Fill IPPS Description }}

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

### -Browser
Browser to use for device code login and URL opening.
Valid values: msedge, chrome, firefox, brave, default.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: $Global:IRT_Config.Browser
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

### -Force
{{ Fill Force Description }}

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

### -ClientId
Override the MSAL client ID used for all three services (Graph, Exchange,
IPPS). When omitted, each service uses its own first-party Microsoft client
ID. Use this when connecting via a custom app registration that has been
granted the necessary delegated permissions.

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
Version: 1.0.0

## RELATED LINKS
