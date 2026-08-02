# Devices

Attackers frequently register their own devices in Entra ID to satisfy MFA or conditional
access policies and maintain persistence. These commands find and display device
information, then disable or remove devices the attacker registered.

For on-premises AD computer accounts in hybrid environments, see
[On-Premises AD Remediation](remediation-ad.md).

## Finding Devices

Select target devices with `Find-IRTDevice`, which searches combined Entra + Intune
device records by display name, device id, serial number, operating system, registered
owner, and other identifiers.

```powershell
# find a device by name fragment
Find-IRTDevice DESKTOP-ABC123

# search by Intune serial number; partial device, Entra, and Intune ids also match
Find-Device SN1234567890

# select multiple devices with multiple search strings
FindDevice DESKTOP-ABC123, LAPTOP-XYZ789

# rather than erroring if a search matches more that one device, select all matching
# devices
finddevice "LT-" -AllMatches

# read one search query per line from the clipboard
finddevice -FromClipboard
```

Matching devices are stored in `$Global:IRT_DeviceObjects` and subsequent device
commands use them automatically when no `-DeviceObject` parameter is provided. A search
that matches more than one device is reported but selects nothing unless `-AllMatches`
is used.

## Showing Device Information

```powershell
# display Entra and Intune properties for the selected devices
Show-IRTDevice

# display a specific device object
showdevice -DeviceObject $Device
```

## All Tenant Devices

```powershell
# export every Entra device to a spreadsheet, newest registration first
Get-IRTAllEntraDevice

# write the spreadsheet and a raw XML dump without opening the workbook
Get-IRTAllEntraDevice -Open $false -Xml $true
```

Sort by registration date to spot devices the attacker joined to the tenant around the
time of compromise.

## Remediation

```powershell
# disable the selected device, preventing it from authenticating
Disable-IRTDevice

# re-enable a previously disabled device
Enable-IRTDevice

# permanently delete the Entra and Intune device records
Remove-IRTDevice

# preview a deletion without prompting or deleting
Remove-IRTDevice -Force -WhatIf
```

`Remove-IRTDevice` shows each device's DisplayName, Entra ID, Intune ID, and OS, then
requires typing the display name exactly before deleting. Use `-Force` to skip the
prompt in automated scripts.

## Commands

| Command | Description |
|---------|-------------|
| [Find-IRTDevice](M365IncidentResponseTools/Find-IRTDevice.md) | Searches combined Entra + Intune device records by name, id, serial number, or owner. |
| [Show-IRTDevice](M365IncidentResponseTools/Show-IRTDevice.md) | Displays Entra ID and Intune device properties for devices found via Find-IRTDevice. |
| [Get-IRTAllEntraDevice](M365IncidentResponseTools/Get-IRTAllEntraDevice.md) | Exports every Entra ID device to a spreadsheet, newest registration first. |
| [Disable-IRTDevice](M365IncidentResponseTools/Disable-IRTDevice.md) | Disables an Entra ID / Intune device, preventing it from authenticating. |
| [Enable-IRTDevice](M365IncidentResponseTools/Enable-IRTDevice.md) | Re-enables a previously disabled Entra ID / Intune device. |
| [Remove-IRTDevice](M365IncidentResponseTools/Remove-IRTDevice.md) | Deletes a device record from Entra ID / Intune. |

**Investigating users:**
[User Investigation](investigation-user.md)

**Remediation:**
[Remediation](remediation-user.md)
