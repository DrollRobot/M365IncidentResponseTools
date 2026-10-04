# Releasing

- If the user asked you to read this file, treat that as them asking you to
  perform the procedure described below.

In-domain: All code in Source/, except functions in Lib/ folders and Build.psd1.
Non-domain: Scripts/, Tests/, **/Lib/, Build/, Output/, `Docs/<ModuleName>/`, and any
built artifacts in module root.


## Check the bundled MSAL DLL for vulnerabilities
The module ships one third-party binary,
`Source/Data/Microsoft.Identity.Client.Extensions.Msal.dll`, which runs the persistent
token cache. Core MSAL (`Microsoft.Identity.Client.dll`) is not bundled; it comes from
`Microsoft.Graph.Authentication`. Change either only when an advisory affects the
version in use, not just because a newer release exists.

1. **Find the versions in use.**
   - Extensions.Msal: `$MsalExtVersion` in `Build/PreBuild.ps1`.
   - Core MSAL: the copy inside the minimum `Microsoft.Graph.Authentication` listed in
     `Source/ScriptsToProcess/RequiredModules.psd1`:
     ```powershell
     $GraphVersion = '2.30.0'  # from RequiredModules.psd1
     $TempName = [guid]::NewGuid().ToString()
     $Temp = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath $TempName
     $null = New-Item -ItemType Directory -Path $Temp
     $SaveParams = @{
         Name            = 'Microsoft.Graph.Authentication'
         Version         = $GraphVersion
         Path            = $Temp
         TrustRepository = $true
     }
     Save-PSResource @SaveParams
     $MsalDll = Get-ChildItem -Path $Temp -Recurse -Filter 'Microsoft.Identity.Client.dll' |
         Select-Object -First 1
     [System.Reflection.AssemblyName]::GetAssemblyName($MsalDll.FullName).Version
     Remove-Item -Path $Temp -Recurse -Force
     ```

2. **List the advisories** from the GitHub Advisory Database, which NuGet's
   vulnerability warnings also come from:
   ```powershell
   $Packages = 'Microsoft.Identity.Client.Extensions.Msal', 'Microsoft.Identity.Client'
   foreach ($Package in $Packages) {
       $Advisories = gh api -X GET /advisories -f ecosystem=nuget -f "affects=$Package" |
           ConvertFrom-Json
       foreach ($Advisory in $Advisories) {
           $Advisory.vulnerabilities | Where-Object { $_.package.name -eq $Package } |
               ForEach-Object {
                   [pscustomobject]@{
                       Package    = $Package
                       Id         = $Advisory.ghsa_id
                       Severity   = $Advisory.severity
                       Vulnerable = $_.vulnerable_version_range
                       Patched    = $_.first_patched_version
                   }
               }
       }
   }
   ```
   If no `Vulnerable` range contains a version from step 1, nothing changes; go on to
   Commit. Otherwise stop and tell the user which advisory applies before changing
   anything.

3. **Core MSAL is affected:** raise every `Microsoft.Graph.*` minimum in
   `RequiredModules.psd1` (they all share one version) to the first Graph release whose
   bundled MSAL is at or past the patched version. Step 1's snippet shows the MSAL in
   any Graph version.

4. **Extensions.Msal is affected:** move to a patched release.
   1. Pick the first patched release whose `Microsoft.Identity.Client` dependency is
      no newer than core MSAL from step 1. If none qualifies, do step 3 first.
      ```powershell
      $Id = 'microsoft.identity.client.extensions.msal'
      $Version = '<candidate version>'
      $Uri = "https://api.nuget.org/v3-flatcontainer/$Id/$Version/$Id.nuspec"
      $Nuspec = Invoke-RestMethod -Uri $Uri
      $Nuspec.package.metadata.dependencies.group |
          Where-Object targetFramework -eq '.NETStandard2.0' |
          ForEach-Object { $_.dependency } |
          Where-Object id -eq 'Microsoft.Identity.Client'
      ```
   2. Download that release and hash the DLL the build uses (continues from the
      snippet above):
      ```powershell
      $TempName = [guid]::NewGuid().ToString()
      $Temp = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath $TempName
      $null = New-Item -ItemType Directory -Path $Temp
      $Nupkg = Join-Path -Path $Temp -ChildPath "$Id.$Version.nupkg"
      $Uri = "https://api.nuget.org/v3-flatcontainer/$Id/$Version/$Id.$Version.nupkg"
      Invoke-WebRequest -Uri $Uri -OutFile $Nupkg
      $Package = Join-Path -Path $Temp -ChildPath 'package'
      Expand-Archive -Path $Nupkg -DestinationPath $Package
      $DllName = 'Microsoft.Identity.Client.Extensions.Msal.dll'
      $DllParams = @{
          Path                = $Package
          ChildPath           = 'lib'
          AdditionalChildPath = @('netstandard2.0', $DllName)
      }
      $Dll = Join-Path @DllParams
      (Get-FileHash -Path $Dll -Algorithm SHA256).Hash
      ```
      On Windows, also check that `Get-AuthenticodeSignature -FilePath $Dll` reports
      `Valid` with a Microsoft Corporation signer. Then delete `$Temp`.
   3. In `Build/PreBuild.ps1`, set `$MsalExtVersion` and `$MsalExtSha256`.
   4. Set `$MsalFloor` in `Source/Private/Connect/Import-MsalExtensionAssembly.ps1` to
      the `Microsoft.Identity.Client` dependency from step 4.1, and update the floor
      versions in `Tests/Pester/Import-MsalAssembly.Tests.ps1` and
      `Tests/Pester/Import-MsalExtensionAssembly.Tests.ps1` to match.
   5. Delete `Source/Data/Microsoft.Identity.Client.Extensions.Msal.dll` and run
      `.\Build.ps1`. `Build/PreBuild.ps1` downloads the pinned release, checks its hash,
      and puts the DLL back in `Source/Data/`.
   6. Ask the user to confirm on Windows that the cache still works: with
      `EnableTokenCache` on, connect, then connect again from a new PowerShell session
      without a sign-in prompt.

5. Commit the change as one `fix(deps)` commit, and add a **Security** entry naming the
   advisory to the changelog.


## Commit
- Review before writing commit messages: [AGENTS.COMMITTING.md](AGENTS.COMMITTING.md).
- Commit any untracked files.

## Build
Build the module/scripts:
```powershell
.\Build.ps1
```

Run pester tests again on the built module:
```powershell
.\Tests.ps1 NotLive,Live -Built
```

## Update docs
- Rebuild Docs/<ModuleName>/
   ```powershell
   .\Docs.ps1
   ```

- Review the documents in the root of the Docs folder for accuracy or any new features
   that should be added. Don't review or modify files in `Docs/<ModuleName>/`. (built
   by PlatyPS)


## Update CHANGELOG.md
`CHANGELOG.md` in the repo root is the authoritative changelog, in
[Keep a Changelog](https://keepachangelog.com) format. Fetch that page for the
current format rules; do not rely on training data.

**Deviation from Keep a Changelog:** version headings end with a title after the
date. Use this format in place of Keep a Changelog's `## [1.2.3] - 2026-01-31`:
```markdown
## [1.2.3] - 2026-01-31 - <title>
```
- `<title>` is a few words naming the release's main changes.
- The release workflow publishes `v1.2.3 - <title>` as the GitHub release title and
  the section below the heading as the release notes.

1. **Collect commits** since the previous tag:
   ```powershell
   $prevTag = git describe --tags --abbrev=0
   git log "$prevTag..HEAD" --oneline
   ```

2. Select from commits. Keep only:
- Features -- functionality a user can invoke (Added, Changed, Deprecated, Removed).
- User-facing bug fixes (Fixed).
- Security changes (Security).
- Performance improvements.
- Documentation -- updates to user facing documentation.
Do not mention: refactors, tests, lint, building docs, build tooling.

3. Write each entry as a BRIEF overview, not an explanation.
- Fixed: Name what broke and where.
- Added/Changed: one or two sentences describing the new behavior.
- Detailed explanations belong in the commit message and the code, not the
   changelog.

4. Prepend the new section immediately after the # Changelog heading, headed
with the version about to be tagged, today's date, and a title in the format
above. Don't rewrite or delete existing sections unless directly requested.

## Hand off to user
- The user will run Push-NewTagToMain.ps1 to update version, merge, tag, push, etc..
