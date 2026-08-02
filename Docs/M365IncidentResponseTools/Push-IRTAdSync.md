---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 07/31/2026
PlatyPS schema version: 2024-05-01
title: Push-IRTAdSync
---

# Push-IRTAdSync

## SYNOPSIS

Forces an Active Directory / Entra ID (Azure AD Connect) sync cycle.

## SYNTAX

```
Push-IRTAdSync [[-SyncServer] <string[]>] [[-ThrottleLimit] <int>] [-ResetCredentials]
 [<CommonParameters>]
```

## ALIASES

Push-IRTAdSyncs, Push-AdSync, Push-AdSyncs, PushIRTAdSync, PushIRTAdSyncs, PushAdSync, PushAdSyncs, AdSync, SyncAd

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

Push-IRTAdSync
Automatically discovers and triggers a delta sync.

### EXAMPLE 2

Push-IRTAdSync -SyncServer 'sync01.contoso.com'
Triggers sync on a known server without discovery.

### EXAMPLE 3

Push-IRTAdSync -ResetCredentials
Re-prompts for domain admin credentials before syncing.

## PARAMETERS

### -ResetCredentials

Clear the cached domain admin credentials and prompt again before connecting.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases:
- Reset
- ResetPassword
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SyncServer

Target one or more specific server names directly, bypassing AD discovery.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- SyncServers
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ThrottleLimit

Maximum number of parallel runspaces used for server discovery.
Default: 20.

```yaml
Type: System.Int32
DefaultValue: 20
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 1
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### None. Progress is written to the console.

## NOTES

Version: 2.0.0
2.0.0 - Parallel server discovery via runspace pool (ping, open session, service check).
        Added -SyncServer parameter to target specific servers directly, bypassing AD query.
        Added -ThrottleLimit parameter.


## RELATED LINKS

{{ Fill in the related links here }}
