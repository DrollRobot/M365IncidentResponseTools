---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 07/31/2026
PlatyPS schema version: 2024-05-01
title: Find-IRTUser
---

# Find-IRTUser

## SYNOPSIS

Finds graph user by displayname, email address, or user id guid. Creates $UserObjects variable.

## SYNTAX

### Search (Default)

```
Find-IRTUser [-Search] <string[]> [-VarPrefix <string>] [-Cached] [-Script] [-AllMatches]
 [<CommonParameters>]
```

### Clipboard

```
Find-IRTUser -FromClipboard [-VarPrefix <string>] [-Cached] [-Script] [-AllMatches]
 [<CommonParameters>]
```

## ALIASES

Find-IRTUsers, FindIRTUser, FindIRTUsers, Find-User, Find-Users, FindUser, FindUsers

## DESCRIPTION

Searches Graph users for one or more search strings.
Each string is matched against
DisplayName, UserPrincipalName, the user object id, ProxyAddresses, and
OnPremisesSamAccountName.

Matching users are stored in $Global:IRT_UserObjects.
Use -VarPrefix to change the variable
name (e.g.
'Admin' > $Global:IRT_AdminUserObjects).
A search that returns more than one user
is reported but contributes nothing unless -AllMatches is used.
Use -Script to suppress
global side effects and return the objects directly.

## EXAMPLES

### EXAMPLE 1

Find-IRTUser flast
Finds users matching 'flast' and creates $IRT_UserObjects.

### EXAMPLE 2

Find-IRTUser -Search flast,jsmith
Searches for two users, one query per string.

### EXAMPLE 3

Find-IRTUser bf7573a5844f
Searches by partial user id. Email addresses and proxy addresses also match.

### EXAMPLE 4

$Users = Find-IRTUser -Search 'flast' -AllMatches -Script
Returns every matching user object without setting globals or writing to the console.

### EXAMPLE 5

Find-IRTUser -FromClipboard
Reads the clipboard and searches for each line as a separate query.

## PARAMETERS

### -AllMatches

Keep every user returned by a search instead of only searches that match exactly one user.
Results are deduplicated by user object id.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
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

### -Cached

Search the cached user list instead of requesting fresh users from Graph.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
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

### -FromClipboard

Read one search query per line from the clipboard instead of supplying -Search.
Each
non-empty line is treated as a separate search string.
Mutually exclusive with -Search.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Clipboard
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Script

Return objects directly and suppress console output and global variable assignment.
Use when
calling from scripts or the playbook.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
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

### -Search

One or more search strings.
Each string is independently searched across all supported
fields.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Search
  Position: 0
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -VarPrefix

Optional prefix inserted after 'IRT_' in the global variable name
(e.g.
'Admin' > $Global:IRT_AdminUserObjects).
Useful when working with multiple sets of
users simultaneously.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
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

### System.Management.Automation.PSObject[]

## NOTES

Version: 1.3.1
1.3.1 - Added missing help sections so PlatyPS can generate the command page.
1.3.0 - Added -FromClipboard to read one search query per clipboard line.
1.2.0 - Added -AllMatches to collect all matching users and deduplicate results.
1.1.4 - Fixed bug with $UserObjects not being a collection.
        Moved getting full object to Show-User function.
1.1.3 - Removed checks for modules and permissions.
Checking at module level instead.
1.1.2 - Added enabled as a displayed field.
1.1.1 - Bug fix.
Script was passing collections rather than user objects.
1.1.0 - Major rewrite.
Renamed to Find-User.


## RELATED LINKS

{{ Fill in the related links here }}
