---
external help file: LocalAdTools-help.xml
Module Name: LocalAdTools
online version:
schema: 2.0.0
---

# Find-AdUser

## SYNOPSIS
Finds local AD user by DisplayName, Name, UserPrincipalName, ProxyAddresses, SamAccountName, or ObjectGUID.

## SYNTAX

```
Find-AdUser [-Search] <String[]> [-VarPrefix <String>] [-Script] [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

## DESCRIPTION
Searches Active Directory for users matching one or more search strings.
The search is
applied across DisplayName, Name, UserPrincipalName, ProxyAddresses (email extracted
by regex), SamAccountName, and ObjectGUID.

If a single user is found, the full AD object is retrieved and stored in
$Global:UserObject, $Global:UserObjects, and $Global:UserEmail.
For multiple matches
only $Global:UserObjects is populated.
Use -Script to suppress global side effects and
return objects directly.

## EXAMPLES

### EXAMPLE 1
```
Find-AdUser flast
Finds users matching 'flast' and sets the global user object if exactly one match.
```

### EXAMPLE 2
```
Find-AdUser flast@contoso.com
Searches by email address.
```

### EXAMPLE 3
```
$Users = Find-AdUser -Search 'flast','jsmith' -Script
Returns matching user objects for two search strings without setting globals.
```

## PARAMETERS

### -Search
One or more search strings.
Each string is independently searched across all supported
fields.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -VarPrefix
Optional prefix for the global variable names (e.g.
'Admin' \> $Global:AdminUserObject).
Useful when working with multiple users simultaneously.

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

### -Script
Return objects directly and suppress global variable assignment.
Use when calling from
scripts or the playbook.

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

### None by default (sets global variables).
### Microsoft.ActiveDirectory.Management.ADUser[] when -Script is used.
## NOTES
Version: 1.2.1
1.2.1 - Fixed bug where script was passing collections of user objects rather than user objects.
1.2.0 - Major rewrite.

## RELATED LINKS
