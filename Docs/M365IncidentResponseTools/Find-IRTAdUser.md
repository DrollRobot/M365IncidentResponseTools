---
document type: cmdlet
external help file: M365IncidentResponseTools-Help.xml
HelpUri: ''
Locale: en-US
Module Name: M365IncidentResponseTools
ms.date: 08/02/2026
PlatyPS schema version: 2024-05-01
title: Find-IRTAdUser
---

# Find-IRTAdUser

## SYNOPSIS

Finds local AD user by DisplayName, Name, UserPrincipalName, ProxyAddresses,
SamAccountName, or ObjectGUID.

## SYNTAX

### Search (Default)

```
Find-IRTAdUser [-Search] <string[]> [-VarPrefix <string>] [-Script] [<CommonParameters>]
```

### Clipboard

```
Find-IRTAdUser -FromClipboard [-VarPrefix <string>] [-Script] [<CommonParameters>]
```

## ALIASES

Find-IRTAdUsers, Find-AdUser, Find-AdUsers, FindIRTAdUser, FindIRTAdUsers, FindAdUser, FindAdUsers

## DESCRIPTION

Searches Active Directory for users matching one or more search strings.
The search is
applied across DisplayName, Name, UserPrincipalName, ProxyAddresses (email extracted
by regex), SamAccountName, and ObjectGUID.

If a single user is found, the full AD object is retrieved and stored in
$Global:IRT_UserObject.
Use -VarPrefix to change the variable name
(e.g.
'Admin' > $Global:IRT_AdminUserObject).
For multiple matches the results are
displayed but no global is set.
Use -Script to suppress global side effects and
return objects directly.

## EXAMPLES

### EXAMPLE 1

Find-IRTAdUser flast
Finds users matching 'flast' and sets the global user object if exactly one match.

### EXAMPLE 2

Find-IRTAdUser flast@contoso.com
Searches by email address.

### EXAMPLE 3

$Users = Find-IRTAdUser -Search 'flast','jsmith' -Script
Returns matching user objects for two search strings without setting globals.

### EXAMPLE 4

Find-IRTAdUser -FromClipboard
Reads the clipboard and searches for each line as a separate query.

## PARAMETERS

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

Return objects directly and suppress global variable assignment.
Use when calling from
scripts or the playbook.

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
'Admin' > $Global:IRT_AdminUserObject).
Useful when working with multiple users
simultaneously.

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

### None by default (sets global variables).
Microsoft.ActiveDirectory.Management.ADUser[] when -Script is used.

### System.Collections.Generic.List`1[[System.Management.Automation.PSObject, System.Management.Automation, Version=7.6.0.500, Culture=neutral, PublicKeyToken=31bf3856ad364e35]]

## NOTES

Version: 1.3.0
1.3.0 - Added -FromClipboard to read one search query per clipboard line.
1.2.1 - Fixed bug where script was passing collections of user objects rather than user objects.
1.2.0 - Major rewrite.


## RELATED LINKS

{{ Fill in the related links here }}
