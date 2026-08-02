---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 07/31/2026
PlatyPS schema version: 2024-05-01
title: Reset-IRTAdUserPassword
---

# Reset-IRTAdUserPassword

## SYNOPSIS

Resets an Active Directory user's password.

## SYNTAX

### RandomCharacters

```
Reset-IRTAdUserPassword [[-UserObjects] <psobject[]>] [-RandomCharacters] [-Length <int>] [-WhatIf]
 [-Confirm] [<CommonParameters>]
```

### Custom

```
Reset-IRTAdUserPassword [[-UserObjects] <psobject[]>] [-Custom] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

### ForceChangePasswordNextSignIn

```
Reset-IRTAdUserPassword [[-UserObjects] <psobject[]>] [-ForceChangePasswordNextSignIn] [-WhatIf]
 [-Confirm] [<CommonParameters>]
```

## ALIASES

ResetAdPassword, ResetAdPasswords, Reset-AdPassword

## DESCRIPTION

Resets the on-premises AD password for one or more users.
Exactly one of the three
password mode switches must be specified:

  -RandomCharacters     Generates a random password (default length: 30 characters)
                        and sets it immediately.
The new password is printed to the
                        console via [Console]::WriteLine so it is NOT captured in
                        PowerShell transcripts.

  -Custom               Prompts the operator to enter a password interactively via
                        Read-Host -AsSecureString.
The password is set immediately.

  -ForceChangePasswordNextSignIn
                        Does not set a new password.
Instead, sets
                        ChangePasswordAtLogon = $true on the account, which forces
                        the user to choose a new password on their next login.

If no -UserObjects is supplied, the function falls back to the global session objects
stored via Get-AdGlobalUserObject.
An error is thrown if neither source yields a user.

After the reset, updated account properties are retrieved and displayed as a table.
If running on a domain controller, intra-AD replication is triggered via repadmin.
If the ADSync service is local, an Azure AD delta sync is started.

Supports -WhatIf and -Confirm via SupportsShouldProcess.

## EXAMPLES

### EXAMPLE 1

Reset-IRTAdUserPassword -RandomCharacters
Generates and sets a random password for the user in the global session.

### EXAMPLE 2

Reset-IRTAdUserPassword -UserObjects $User -RandomCharacters
Resets the password for a specific user object using a random password.

### EXAMPLE 3

Reset-IRTAdUserPassword -Custom
Prompts the operator to enter a custom password for the global session user.

### EXAMPLE 4

Reset-IRTAdUserPassword -UserObjects $User -ForceChangePasswordNextSignIn
Forces the user to set a new password on their next sign-in, without changing
the current password.

### EXAMPLE 5

Reset-IRTAdUserPassword -RandomCharacters -Length 48
Resets the password using a random 48-character password.

### EXAMPLE 6

Reset-IRTAdUserPassword -UserObjects $User -RandomCharacters -WhatIf
Shows what would happen without actually resetting the password.

## PARAMETERS

### -Confirm

Prompts you for confirmation before running the cmdlet.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases:
- cf
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

### -Custom

Prompts the operator to enter a custom password via Read-Host -AsSecureString.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Custom
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ForceChangePasswordNextSignIn

Sets ChangePasswordAtLogon = $true on the account without changing the current
password.
The user will be required to set a new password on their next sign-in.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: ForceChangePasswordNextSignIn
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Length

The length of the randomly generated password.
Only valid with -RandomCharacters.
Must be at least 4 characters.
Defaults to 30.

```yaml
Type: System.Int32
DefaultValue: 30
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: RandomCharacters
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -RandomCharacters

Generates a random password of the specified length (default: 30 characters) and
applies it to the account.
The password is written directly to the console (bypassing
transcript logging) so it can be recorded securely by the operator.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases:
- Random
ParameterSets:
- Name: RandomCharacters
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -UserObjects

One or more AD user objects whose passwords will be reset.
Falls back to
global session objects if omitted.

```yaml
Type: System.Management.Automation.PSObject[]
DefaultValue: ''
SupportsWildcards: false
Aliases:
- UserObject
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

### -WhatIf

Runs the command in a mode that only reports what would happen without performing the actions.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ''
SupportsWildcards: false
Aliases:
- wi
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### None. Updated user properties are displayed as a formatted table in the console.

## NOTES

Version: 1.1.0
1.1.0 - Added ForceChangePasswordNextSignIn parameter set.
Removed default parameter
        set; operator must now explicitly choose a password mode.
Added -Length
        parameter.
Renamed to Reset-IRTAdUserPassword.
1.0.0 - Initial version as Reset-AdUserPassword.


## RELATED LINKS

{{ Fill in the related links here }}
