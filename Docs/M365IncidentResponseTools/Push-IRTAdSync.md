---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 10/03/2026
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
If Active Directory is available from this device, pushes intra-AD replication
   from a writable DC via repadmin (this computer if it is one, otherwise a
   discovered DC).
Skipped with a warning otherwise.
2.
If the ADSync service is running locally, invokes Start-ADSyncSyncCycle directly
   and exits.
3.
Otherwise, checks candidate servers in parallel using a runspace pool (opening a
   PSSession and looking for the service) and invokes the sync cycle remotely on the
   first server to report the service.
Each check is handled as soon as it finishes,
   so slow or unreachable servers don't delay the push, and checks still running
   afterward are stopped.
Candidates are the -SyncServer names if given, or else
   discovered from AD (DCs first, then other enabled servers by last logon).

The ActiveDirectory module is only required for AD discovery.
It is not needed when
the ADSync service is on this device or when -SyncServer is given; without it, only
the replication push is skipped.

Domain admin credentials are cached in $Global:Storage for the session.
Use -ResetCredentials to force a re-prompt.

## EXAMPLES

### EXAMPLE 1

```powershell
Push-IRTAdSync
```
Automatically discovers and triggers a delta sync.

### EXAMPLE 2

```powershell
Push-IRTAdSync -SyncServer 'sync01.contoso.com'
```
Triggers sync on a known server without discovery.

### EXAMPLE 3

```powershell
Push-IRTAdSync -ResetCredentials
```
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
The
ActiveDirectory module is not required when this is used.

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

Version: 2.1.0
2.1.0 - ActiveDirectory module only required for AD discovery.
        Removed ping check; session and service check errors are reported per server.
        Server checks are handled as they finish instead of in query order.
        AD replication is pushed from this computer if it is a writable DC, otherwise
        from a discovered DC, so it no longer requires running on a DC.
        Fixed single-DC domains merging all discovered server names into one hostname.
2.0.0 - Parallel server discovery via runspace pool (ping, open session, service check).
        Added -SyncServer parameter to target specific servers directly, bypassing AD query.
        Added -ThrottleLimit parameter.


## RELATED LINKS

{{ Fill in the related links here }}
