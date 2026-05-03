---
external help file: LocalAdTools-help.xml
Module Name: LocalAdTools
online version:
schema: 2.0.0
---

# Show-AdUserInfo

## SYNOPSIS
Displays AD user properties.

## SYNTAX

```
Show-AdUserInfo [[-UserObjects] <PSObject[]>] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Shows a comprehensive Format-List of an on-premises AD user's attributes, including:
identity fields (Name, DisplayName, SamAccountName, UPN), contact and address info,
password metadata (PasswordLastSet, pwdLastSet raw value, PasswordNeverExpires),
Exchange attributes (msExchHideFromAddressLists, mailNickname, proxyAddresses),
group memberships, and DistinguishedName.
Timestamps are converted to local time.

Falls back to global session objects (via Get-AdGlobalUserObject) if no -UserObjects
is passed.

## EXAMPLES

### EXAMPLE 1
```
Show-AdUserInfo
Displays info for the user(s) in the global session.
```

### EXAMPLE 2
```
Show-AdUserInfo -UserObjects $AdUser
Displays info for a specific AD user object.
```

## PARAMETERS

### -UserObjects
One or more AD user objects to display.
Falls back to global session objects if omitted.

```yaml
Type: PSObject[]
Parameter Sets: (All)
Aliases: UserObject

Required: False
Position: 1
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

### None. Output is written to the console.
## NOTES
Version: 1.1.2
1.1.2 - Added pwdLastSet

## RELATED LINKS
