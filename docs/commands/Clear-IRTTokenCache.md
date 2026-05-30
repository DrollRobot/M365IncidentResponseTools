---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Clear-IRTTokenCache

## SYNOPSIS
Removes the persistent IRT MSAL token cache and signs out all in-process accounts.

## SYNTAX

```
Clear-IRTTokenCache [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
When the persistent token cache is enabled (config: EnableTokenCache),
MSAL writes refresh tokens to disk so the user is not re-prompted in every
new PowerShell session.
This command:

  1.
Removes every account from any PublicClientApplication currently held
     in $Global:IRT_Session (Graph, Exchange, IPPS).
Removal also strips
     their tokens from the on-disk cache via the registered cache helper.
  2.
Deletes the on-disk cache file as a belt-and-suspenders measure in
     case no MSAL app is currently registered against it.

Use this after a credential rotation, when sharing a workstation, or to
force the next Connect-IRT to prompt interactively.

## EXAMPLES

### EXAMPLE 1
```
Clear-IRTTokenCache
Wipes the cache. The next Connect-IRT call will require interactive sign-in.
```

## PARAMETERS

### -WhatIf
Shows what would happen if the cmdlet runs.
The cmdlet is not run.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: wi

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Confirm
Prompts you for confirmation before running the cmdlet.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: cf

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

### None.
## NOTES
Version: 1.0.0

## RELATED LINKS
