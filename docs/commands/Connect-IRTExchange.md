---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Connect-IRTExchange

## SYNOPSIS
Connects to Exchange Online.

## SYNTAX

```
Connect-IRTExchange [-TenantId] <String> [[-UserPrincipalName] <String>] [[-Cloud] <String>]
 [[-AccessToken] <String>] [[-Browser] <String>] [-Private] [-Force] [-Silent] [[-ClientId] <String>]
 [[-MsalCachePath] <String>] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
{{ Fill in the Description }}

## EXAMPLES

### Example 1
```powershell
PS C:\> {{ Add example code here }}
```

{{ Add example description here }}

## PARAMETERS

### -TenantId
The TenantId GUID for the environment you want to connect to.

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

### -UserPrincipalName
Optional.
The UserPrincipalName (Email) for the user account.
When provided
with -AccessToken (e.g.
in runspace re-connections), this value is passed to
Connect-ExchangeOnline.
For interactive flows the UPN is derived from the
MSAL token result automatically.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Cloud
Cloud to connect to. Valid values: Commercial, USGov, China.
When omitted the cloud defaults to Commercial.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: Commercial
Accept pipeline input: False
Accept wildcard characters: False
```

### -AccessToken
A pre-existing access token to use for connection.
Intended for use within
runspaces where interactive authentication is not possible.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 4
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Browser
Browser to use for device code login.
Valid values: msedge, chrome, firefox, brave, default.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 5
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

### -Silent
{{ Fill Silent Description }}

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
Override the MSAL client ID. Defaults to the EXO first-party app
(fb78d390-0c51-40cd-8e17-fdbfab77341b).

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 6
Default value: Fb78d390-0c51-40cd-8e17-fdbfab77341b
Accept pipeline input: False
Accept wildcard characters: False
```

### -MsalCachePath
Override the path for the persistent MSAL token cache file. Defaults to
$Global:IRT_Config.MsalCachePath. Useful for testing with an isolated cache.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 7
Default value: $Global:IRT_Config.MsalCachePath
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
Version: 3.0.0

## RELATED LINKS
