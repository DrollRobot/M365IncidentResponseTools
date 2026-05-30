# Changelog

All notable changes to this project will be documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]


## [v2.9.0] - 2026-05-30

### Added

- `-AllMatches` option on `Find-` functions to return all matching objects instead of
  failing when there are multiple matches.
- MSAL on-disk token cache so re-authentication is not required every session.
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
