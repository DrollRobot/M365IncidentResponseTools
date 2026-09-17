# Getting Started

## Prerequisites

- PowerShell 7.5 or later
- A Microsoft 365 tenant and a Global Admin account to sign in with.
- Recommended: ip_info installed as a uv tool - https://github.com/DrollRobot/ip_info

## Module Install

### Clone from Github

```powershell
# install the module to a folder in $env:PsModulePath
# if not sure, use C:\Users\USER\(OneDrive??)\Documents\Powershell\Modules\
$Documents = [environment]::getfolderpath('MyDocuments')
Set-Location "$Documents\Powershell\Modules\"

# clone module from github
git clone https://github.com/DrollRobot/M365IncidentResponseTools.git
```

### Install Dependencies

On the first import of the module, (`Import-Module M365IncidentResponseTools`)
Confirm-Dependency.ps1 will verify you have the required modules installed. If not,
it will provide a command to run the Install-Dependency.ps1 script. Something like:
```powershell
& "C:\*\M365IncidentResponseTools\ScriptsToProcess\Install-Dependency.ps1"
```

**Connecting to an M365 tenant:**
[Connect to M365](connect.md)
