# Changelog

All notable changes to this project will be documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- `Get-IRTAccessToken`: new public command that returns a fresh access token for Graph,
  Exchange, or IPPS, minted on demand from the MSAL cache (silent when possible, browser
  sign-in otherwise). Useful for manual REST calls and custom scripts.
- `Connect-IRTRunspaceExchange`: new public command that establishes a runspace-local
  Exchange connection with a silently-minted token. Used by playbook steps.
- The MSAL cache extension assembly is now bundled with the module instead of being
  downloaded from nuget.org during the first Connect, so the persistent token cache
  works offline and can no longer silently degrade.

### Changed

- Sign-in prompts are now deterministic. Cached accounts are matched to the target
  tenant (with per-tenant account memory), and every candidate account is tried before
  falling back to an interactive prompt. With `EnableTokenCache` enabled, connecting to
  a previously-used tenant requires no prompts, including in new PowerShell sessions.
- Exchange and IPPS now always share one MSAL app, so IPPS sign-in is always silent
  after an Exchange sign-in.
- Token refresh now re-binds only the service whose token is stale, and reconnects are
  scoped by ConnectionId, instead of force-reconnecting every service at once.
- Playbook runspace workers now mint their own Exchange tokens from the shared cache
  per step, so playbooks running longer than an hour no longer fail with expired
  tokens. The parent keeps the shared Graph context fresh while the playbook runs.
- Persistent token cache registration failures are now loud errors with remediation
  guidance instead of easily-missed warnings.
- `Get-IRTLicenseReport`: output is now a plain table. This removes the dependency on
  the external Write-PSObject script, which produced corrupted output and errors when
  run inside playbook runspaces. `-Runspace` is retained as a no-op for compatibility.

### Fixed

- Spurious interactive sign-in prompts when the token cache held accounts from multiple
  customer tenants.
- Reconnecting or refreshing Exchange/IPPS no longer tears down the other service's
  connection.
- `Connect-IRT -Refresh` no longer drops Graph scopes that were added with
  `-AdditionalScope`.
- After granting tenant-wide admin consent, the session now re-acquires and re-binds
  the Graph token instead of keeping the pre-consent token (which lacked the newly
  granted scopes) for the rest of its lifetime. Fixes Graph calls failing for up to an
  hour after first contact with a new tenant (e.g. the missing domain in the terminal
  title).
- `Get-IRTUnifiedAuditLog`: long multi-page and multi-chunk searches now refresh the
  token mid-search instead of failing after about an hour.
- Playbook steps no longer intermittently fail with "Collection was modified;
  enumeration operation may not execute": concurrent module imports across worker
  runspaces raced on PowerShell's process-wide module-analysis caches. Imports are
  now serialized with a mutex.
- `Start-IRTPlaybook`: worker runspaces no longer reset the parent terminal's title to
  plain `[IRT]`, dropping the tenant domain Connect-IRT had set.
- `Start-IRTPlaybook`: worker runspaces now import the same module version the parent
  session is running, instead of whatever version is installed system-wide. Previously
  a version mismatch could make most playbook steps fail silently.
- Module import now runs the dependency scan once per session: a successful check
  records the module root in `$Global:ModuleDependenciesChecked` (a module-agnostic
  table, since the dependency scripts are portable), and re-imports plus all playbook
  runspace workers skip the scan. Speeds up module re-import and playbook startup.


## [v2.9.2] - 2026-06-10

### Fixed

- `Show-IRTEntraAuditLog`: Fixed bug that prevented importing from xml.
- `Show-IRTEntraAuditLog`, `Show-IRTEntraSignInLog`, `Show-IRTServicePrincipalSignIn`,
  `Show-IRTUnifiedAuditLog`, `Show-IRTMessageTrace`: supplying neither a log-object list
  nor `-XmlPath` now raises a clear `InvalidArgument` error instead of crashing with a
  null-index error or halting with a mandatory-parameter prompt.
- `Show-IRTServicePrincipal`: Fixed crash when there were no results.


## [v2.9.1] - 2026-06-07

### Added

- `New-IRTEmailSearch`: new function that builds and launches a compliance content search
  for email activity using an interactive criteria builder. (partially complete)
- `Get-TenantOidc`: now a public command; accepts a domain name or tenant GUID and
  returns the tenant display name, tenant ID, and cloud environment.
- `Start-IRTPlaybook`: new `-NewTab` parameter opens the investigation folder in a new
  Windows Terminal tab so you can keep working while the playbook runs.
- `Get-IRTUnifiedAuditLog`: new `-ResultLimit` parameter stops the query once the
  specified number of records is reached. Queries spanning more than 6 months are now
  automatically split into chunks to work around API limits.
- Module dependencies are now detected and loaded dynamically instead of using
  `RequiredModules`, reducing module startup time.
- Added Confirm-Dependencies/Install-Dependencies rather than using RequiredModules
  to speed up module load time and make it easier to install dependencies.
- IP address conditional formatting rules are now read from a spreadsheet at a configurable
  path, allowing users to create their own conditional formatting rules.
- Added automatic cloud detection using OIDC data. You no longer have to specify `-GCCHigh`
  with Connect-IRT. (though, you can still specify a cloud with `-Cloud UsGov/Commercial` 
  to bypass OIDC lookup)

### Fixed

- `Get-IRTTenantOwner`: failed cross-cloud queries are now correctly identified and
  reported instead of being silently treated as successful.
- `Install-IRTDependencies`: a failure installing one module no longer causes all
  subsequent install attempts to fail in the same session.
- `Install-IRTDependencies`: added `-SkipPublisherCheck` and `-AllowClobber` to prevent
  errors when a module conflicts with an existing publisher or version.


## [v2.9.0] - 2026-05-30

### Added

- `-AllMatches` option on `Find-` functions to return all matching objects instead of
  failing when there are multiple matches.
- Added option for MSAL on-disk token cache so re-authentication is not required in every session.
- `Import-IRT` (alias: irt) to pre-load the module in the background while working in the terminal,
  reducing the wait on first use.

### Changed

- Many commands renamed to follow the `Verb-IRTNoun` naming convention.
- Updated the prompt function to be more brief.

### Removed

- Device-code auth is no longer available as a sign-in option.

### Fixed

- Commands no longer fail after token expiration; tokens are refreshed automatically.

### Security

- On-disk MSAL token cache is a security risk. Option is disabled by default.


## [v2.8.3] - 2026-05-27

### Fixed

- ip_info information was not being applied to some Unified Audit Log Excel sheets.


## [v2.8.2] - 2026-05-27

### Added

- `Find-AdDevice` and `Show-AdDevice` for on-premises Active Directory device investigation.
- Tree-view output added to `Show-AdUser` and `Show-AdDevice`.

### Fixed

- ip_info presence not being detected correctly at module startup.


## [v2.8.1] - 2026-05-26

### Added

- `Connect-IRT`: OIDC-based automatic cloud detection so the module selects the correct national cloud
  without having to use -Cloud parameter. -Cloud is optional and will skip OIDC detection.


## [v2.8.0] - 2026-05-25

### Added

- `Get-IRTServicePrincipalSignInLog` and `Show-IRTServicePrincipalSignInLog` for
  investigating service principal sign-in activity.
- `Set-IRTDeviceEnabled` for enabling or disabling Entra / Intune device records.
- `Remove-IRTDevice` for deleting a device record from Entra / Intune.
- Entra error code descriptions displayed alongside sign-in log results.
- `-ClearForceChangePasswordNextSignIn` option on `Reset-UserPassword`.
- Conditional formatting for datacenter IP addresses in Excel output.

### Changed

- `Find-Device` renamed to `Find-IRTDevice`.

### Fixed

- Bug in `Reset-ADUserPassword`.
- `Copy-IRTFunction` aliases not working correctly.


## [v2.7.0] - 2026-05-19

Initial tagged release. Core feature set:

- **Connections** -- `Connect-IRT` session manager for Graph, Exchange Online, and IPPS
  with tenant-aware prompting.
- **Sign-in logs** -- `Get-SignInLog`, `Get-NonInteractiveLog`, `Get-EntraAuditLog` with
  Excel export and IP enrichment.
- **Service principals** -- `Find-IRTServicePrincipal`, `Show-IRTServicePrincipal`.
- **Mailbox** -- inbox rule investigation, permission reporting, `Open-MailboxInOWA`.
- **Message trace** -- `Get-IRTMessageTrace`, `Request-IRTMessageTrace`.
- **Unified Audit Log** -- search and Excel reporting.
- **Users** -- `Get-IRTUser`, `Show-IRTUser`, `Reset-UserPassword` and related helpers.
- **Devices** -- `Find-IRTDevice`, `Show-DeviceInfo`.
- **Module config** -- `Import-IRTConfig` / `Set-IRTConfig` persistent configuration system.
- `Copy-IRTFunction` for exporting individual functions to ad-hoc scripts.
