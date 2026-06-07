# Connecting to an M365 tenant

# Option 1 -- Direct connection

```powershell
# Connect to both Graph and Exchange (interactive browser)
Connect-IRT -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Exchange only
Connect-IRT -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -Exchange

# Request additional Graph scopes beyond the defaults
Connect-IRT -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -AdditionalScope "AuditLog.Read.All","Mail.Read"
```
A web browser will open. Sign in with your Global Admin account. You will be prompted to sign in twice. (once for Graph, once for Exchange) If you get a prompt for Graph permissions, make sure you check the checkbox at the bottom before accepting.

### Option 2 -- Tenant alias (recommended for multi-tenant work)

If you regularly connect to multiple tenants, you can preconfigure their information in the tenants spreadsheet.

To create/open the spreadsheet:
```powershell
Open-IRTTenantSheet
```
Fill in the full tenant name, aliases, and TenantId.
Alises use regex matching, so to allow multiple aliases, you could use this syntax 'contoso|contosocorp|contosocorporation'

Then, to connect:
```powershell
Connect-IRTTenant -Tenant contoso
IRTTenant contoso
```

### Verify connection status

```powershell
Test-IRTConnection
```

Connection status is also shown in the custom prompt.
```
[IRT] Connected:Graph,Exchange,IPPS Domain:contoso.com User:jsmith@contoso.com
PS > 
```


**Starting an investigation:**
[Investigation](investigation.md)