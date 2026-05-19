---
external help file: M365IncidentResponseTools-help.xml
Module Name: M365IncidentResponseTools
online version:
schema: 2.0.0
---

# Push-AdSync

## SYNOPSIS
Forces an Active Directory / Entra ID (Azure AD Connect) sync cycle.

## SYNTAX

```
Push-AdSync [-ResetCredentials] [[-SyncServer] <String[]>] [[-ThrottleLimit] <Int32>]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Triggers an AD-to-Entra delta sync as quickly as possible.
The execution path is:

1.
If running on a domain controller, fires 'repadmin /syncall /AdeP' to force
   intra-AD replication first.
2.
If the ADSync service is running locally, invokes Start-ADSyncSyncCycle directly
   and exits.
3.
Otherwise, discovers candidate servers (DCs first, then other enabled AD computers
   by last logon) in parallel using a runspace pool and invokes the sync cycle
   remotely on the first server found to have the service.

Domain admin credentials are cached in $Global:Storage for the session.
Use -ResetCredentials to force a re-prompt.

## EXAMPLES

### EXAMPLE 1
```
Push-AdSync
Automatically discovers and triggers a delta sync.
```

### EXAMPLE 2
```
Push-AdSync -SyncServer 'sync01.contoso.com'
Triggers sync on a known server without discovery.
```

### EXAMPLE 3
```
Push-AdSync -ResetCredentials
Re-prompts for domain admin credentials before syncing.
```

## PARAMETERS

### -ResetCredentials
Clear the cached domain admin credentials and prompt again before connecting.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: Reset, ResetPassword

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -SyncServer
Target one or more specific server names directly, bypassing AD discovery.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases: SyncServers

Required: False
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ThrottleLimit
Maximum number of parallel runspaces used for server discovery.
Default: 20.

```yaml
Type: Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: 20
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

### None. Progress is written to the console.
## NOTES
Version: 2.0.0
2.0.0 - Parallel server discovery via runspace pool (ping, open session, service check).
        Added -SyncServer parameter to target specific servers directly, bypassing AD query.
        Added -ThrottleLimit parameter.

## RELATED LINKS
