# Service Principal Investigation

Malicious OAuth applications (enterprise apps) are a common persistence mechanism after account compromise. These commands help identify suspicious service principals and review their activity.

Before running commands against a specific service principal, select a target.

```powershell
Find-IRTServicePrincipal MyApp

findserviceprincipal "PerfectData"
```
`Find-IRTServicePrincipal` uses regex matching against DisplayName, AppDisplayName, AppId, and Id, so partial strings and app IDs both work. If a search query matches multiple service principals, none will be selected and the matches are displayed. Refine the search, or pass `-AllMatches` to select all of them.

Multiple service principals can be selected if multiple search queries are passed.
```
findsp MyApp, AnotherApp
```

On success, the objects are saved in `$Global:IRT_ServicePrincipalObjects`, which service principal commands read from automatically when no `-ServicePrincipalObject` parameter is provided.

## Tenant-Wide Checks

Start broad to find suspicious applications before drilling into a specific one.

```powershell
# check tenant service principals against threat intelligence feeds
Find-IRTRiskyServicePrincipal

# list all service principals in the tenant
Show-IRTServicePrincipal

# list OAuth2 applications a user has personally consented to
Find-IRTUser joseph.smith
Get-IRTUserServicePrincipal
```

## Sign-In Logs

```powershell
# download 30 days (default) of sign-in logs for the selected service principal
Find-IRTServicePrincipal MyApp
Get-IRTServicePrincipalSignInLog

# download 7 days of sign-in logs for all service principals in the tenant
Get-IRTServicePrincipalSignInLog -AllServicePrincipals -Days 7
```

Results are enriched with IP geolocation and Entra error descriptions, then exported to an Excel workbook.

## Service Principal Commands

| Command | Description |
|---------|-------------|
| [Find-IRTServicePrincipal](M365IncidentResponseTools/Find-IRTServicePrincipal.md) | Searches tenant service principals by name, app ID, or object ID and selects them for other commands. |
| [Show-IRTServicePrincipal](M365IncidentResponseTools/Show-IRTServicePrincipal.md) | Lists all service principals (enterprise apps) in the tenant with optional filtering and export. |
| [Get-IRTServicePrincipal](M365IncidentResponseTools/Get-IRTServicePrincipal.md) | Displays all service principals in the tenant, or filters by a search term. |
| [Find-IRTRiskyServicePrincipal](M365IncidentResponseTools/Find-IRTRiskyServicePrincipal.md) | Checks tenant service principals against threat intelligence feeds for known malicious OAuth apps. |
| [Get-IRTUserServicePrincipal](M365IncidentResponseTools/Get-IRTUserServicePrincipal.md) | Lists OAuth2 applications a user has personally consented to. |
| [Get-IRTServicePrincipalSignInLog](M365IncidentResponseTools/Get-IRTServicePrincipalSignInLog.md) | Downloads service principal sign-in logs enriched with geolocation and error descriptions. |
| [Show-IRTServicePrincipalSignIn](M365IncidentResponseTools/Show-IRTServicePrincipalSignIn.md) | Processes service principal sign-in log objects into an Excel spreadsheet. |
| [Get-IRTTenantOwner](M365IncidentResponseTools/Get-IRTTenantOwner.md) | Looks up an Entra ID tenant by domain or GUID and returns its display name, domain, tenant ID, and cloud. Useful for resolving an app's AppOwnerOrganizationId. |
| [Open-IRTTenantOwnerCSV](M365IncidentResponseTools/Open-IRTTenantOwnerCSV.md) | Opens the local tenant info cache CSV in the default application. |
| [Open-IRTTenantSheet](M365IncidentResponseTools/Open-IRTTenantSheet.md) | Opens the tenants worksheet for editing. |

**Investigating users:**
[User Investigation](investigation-user.md)

**Remediation:**
[Remediation](remediation-user.md)
