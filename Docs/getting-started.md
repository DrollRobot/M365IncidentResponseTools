# Getting Started

## Prerequisites

- PowerShell 7.5 or later, on Windows, Linux, or macOS
- A Microsoft 365 tenant and a Global Admin account to sign in with.
- Recommended: ip_info installed as a uv tool - https://github.com/DrollRobot/ip_info

A few features depend on the platform:

- On-premises Active Directory commands need Windows with the ActiveDirectory
  (RSAT) module.
- `Open-IRTTab` opens a tab in Windows Terminal, or a window in tmux on Linux and
  macOS.
- The persistent token cache (`EnableTokenCache`) uses the Keychain on macOS and a
  Secret Service keyring (such as GNOME Keyring, with libsecret) on Linux.

## Module Install

### Clone from Github

```powershell
# install the module to your user module folder: the first entry in $env:PSModulePath.
# Documents\PowerShell\Modules on Windows, ~/.local/share/powershell/Modules elsewhere.
$ModulesDir = ($env:PSModulePath -split [System.IO.Path]::PathSeparator)[0]
$null = New-Item -ItemType Directory -Path $ModulesDir -Force
Set-Location $ModulesDir

# clone module from github
git clone https://github.com/DrollRobot/M365IncidentResponseTools.git
```

### Install Dependencies

On the first import of the module, (`Import-Module M365IncidentResponseTools`)
Confirm-Dependency.ps1 will verify you have the required modules installed. If not,
it will provide a command to run the Install-Dependency.ps1 script. Something like:
```powershell
& "<modules folder>/M365IncidentResponseTools/ScriptsToProcess/Install-Dependency.ps1"
```

### Configuration

Settings live in `config.json`, created on first import in the module's per-user
folder: `%APPDATA%\M365IncidentResponseTools` on Windows and
`~/.config/M365IncidentResponseTools` on Linux and macOS. The tenants worksheet and
tenant caches are kept there too. Change settings with `Set-IRTConfig`, or edit the
file with `Open-IRTConfig`.

**Connecting to an M365 tenant:**
[Connect to M365](connect.md)
