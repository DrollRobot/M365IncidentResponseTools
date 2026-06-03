# Releasing M365IncidentResponseTools

## Steps

**Build**
```powershell
.\Build.ps1
```

**Tests**
Run tests again on the built module:
```powershell
.\Tests.ps1 Offline,Online -Built
```

**Update docs**
```powershell
.\Docs.ps1 -DeleteOrphaned
```

## Update CHANGELOG.md

`CHANGELOG.md` in the repo root is the authoritative changelog.
Before proceeding, fetch and review <https://keepachangelog.com> to get the
current format rules. Do not rely on training data -- request a fresh copy every time.

**How to update the changelog before tagging a new release**

1. **Find the previous tag** and collect every commit since then:

   ```powershell
   $prevTag = git describe --tags --abbrev=0   # most recent tag
   git log "$prevTag..HEAD" --oneline
   ```

2. **Break each commit message into individual details**, then evaluate each detail
   against the three changelog categories:
   - **Features** -- new or changed functionality a user can invoke (maps to Added,
     Changed, Deprecated, Removed).
   - **User-facing bugs** -- something that was broken and is now fixed (maps to Fixed).
   - **Security** -- vulnerabilities or security-relevant changes (maps to Security).

   If a detail does not clearly fit one of those three categories, discard it.
   Implementation details, refactors, test changes, linting fixes, and documentation
   updates are never included, even if they appear in the same commit as something that is.

   Collect all surviving details, grouped by category, then use them to build the
   changelog section.

3. **Prepend** the new release section to `CHANGELOG.md` immediately after the
   `# Changelog` heading. Use today's date and the version about to be tagged.
   Do not rewrite or delete any existing sections.

4. If `CHANGELOG.md` does not exist yet, create it with this skeleton first:

   ```markdown
   # Changelog

   All notable changes to this project will be documented in this file.
   Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

   <!-- newest release goes here -->
   ```
