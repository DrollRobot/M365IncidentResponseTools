# Getting Started

## Prerequisites

- PowerShell 7.5 or later
- Windows (on-premises AD commands require Windows RSAT)
- A Microsoft 365 tenant with appropriate read permissions
- Python 3 and `pip` (only needed to build documentation locally)

## Installation

### From the PowerShell Gallery

```powershell
Install-Module M365IncidentResponseTools -Scope CurrentUser
```

### From Source

```powershell
git clone https://github.com/DrollRobot/M365IncidentResponseTools.git
Import-Module .\M365IncidentResponseTools\M365IncidentResponseTools.psd1
```

## Configuration

IRT uses a `config.json` file to store tenant aliases, investigation folder paths, and other
settings. On first run, a default config is created automatically.

To set up or update your config interactively:

```powershell
Set-IRTConfig
```

To view the raw config file:

```powershell
Open-IRTConfig
```

The config stores settings such as:

- A tenant worksheet path (used by `Connect-IRTTenant` to look up tenants by alias)
- Default investigation output folder
- Preferred Excel template paths

## Connecting to a Tenant

### Option 1 -- Direct connection

```powershell
Connect-IRT
```

This connects to Microsoft Graph and Exchange Online using your current credentials. You will
be prompted for a tenant ID or domain if not already configured.

### Option 2 -- Tenant alias (recommended for multi-tenant work)

If you have a tenant worksheet configured, you can connect by alias:

```powershell
Connect-IRTTenant -Tenant contoso
```

### Verify connection status

```powershell
Test-IRTConnection
```

## Resolving a User

Before running the playbook or most investigation commands, load the target user into the
session:

```powershell
Get-IRTUserObject -UserPrincipalName user@contoso.com
```

This populates `$Global:IRT_UserObjects`, which the playbook and most commands read from
automatically when no `-UserObject` parameter is provided.

## Running the Playbook

```powershell
Start-IncidentResponsePlaybook
```

Or with explicit parameters:

```powershell
Start-IncidentResponsePlaybook -UserObject $User -Ticket 'INC-1234'
```

See [Playbook](playbook.md) for a full description of every step.

## Running Commands Individually

Every playbook step can also be run standalone. For example:

```powershell
# Sign-in logs for the last 30 days
Get-SignInLog -Days 30

# Inbox rules
Get-IRTInboxRule

# Admin role report, highlighting the investigated user
Get-AdminRole -Excel -Highlight user@contoso.com
```

## On-Premises AD

On-prem commands require the `ActiveDirectory` RSAT module and must be run on a machine
joined to the domain (or with a reachable domain controller). They do not require a Graph
or Exchange Online connection.

```powershell
# Find a user in AD
Find-AdUser -Identity 'John Smith'

# Force an Entra ID Connect sync
Push-AdSync
```
