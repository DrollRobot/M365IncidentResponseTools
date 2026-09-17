# Testing

In-domain: All code in Source/, except functions in Lib/ folders and Build.psd1.
Non-domain: Scripts/, Tests/, **/Lib/, Build/, Output/, `Docs/<ModuleName>/`, and any
built artifacts in module root.

## Test Tags
| Tag | Axis | Description |
|------|------|-------------|
| `unit` | Scope | Single function/class in isolation; all dependencies mocked or stubbed. |
| `integration` | Scope | Multiple real components wired together across a boundary. |
| `e2e` | Scope | Whole application end to end, driven like a real user. |
| `lint` | Scope | Validates user's preferred code formatting. Run via `.\Tests.ps1 Lint`, excluded from NotLive. |
| `smoke` | Purpose | Fast "is it fundamentally broken" check. |
| `regression` | Purpose | Guards against reintroduction of a previously fixed bug. |
| `acceptance` | Purpose | Verifies behavior against a requirement or user-facing spec. |
| `functional` | Purpose | Tests behavior/output of a feature without regard to internal structure. |
| `live` | Dependency | Requires a real external resource — network, live tenant, secrets, third-party API. |
| `destructive` | Dependency | Mutates state outside the test itself. Skipped by default. |
| `local` | Destructive scope | Paired with `destructive`: mutates the host running Pester. Gated on `DISPOSABLE_ENVIRONMENT=1`. |
| `remote` | Destructive scope | Paired with `destructive`: mutates an external target. Gated on `Tests\Confirm-RemoteDisposable.ps1` confirming it (not throwing). |
| `slow` | Performance | Long-running. |

## Writing tests
- All new code should have unit and integration tests, and further tests
    wherever possible/appropriate.
- Every test MUST carry at least one Scope tag: `unit`, `integration`, `e2e`, or `lint`.
- Tests that mutate an environment, either the local device or a remote system MUST
    carry the `destructive` tag, and either `local` or `remote`.

## Running tests
**First: Pester tests**
```powershell
# run NotLive tests first, for rapid feedback
.\Tests.ps1 NotLive # runs all non-live, non-destructive tests
# then slower Live tests
.\Tests.ps1 Live # run all live, non-destructive tests
```

**Second: Autoformatting and Linting**
```powershell
# run PSSAAutoFormat first to apply automatic fixes
.\Tests.ps1 PSSAAutoFormat

# verify the precommit tests pass
pre-commit run --all-files

# run lint tests
.\Tests.ps1 Lint

# if lint tests fail during pre-commit, run individually to see results
.\Tests.ps1 LineLength
.\Tests.ps1 BacktickContinuation
.\Tests.ps1 FormatOperator
.\Tests.ps1 JoinPath
.\Tests.ps1 NonASCIICharacters
.\Tests.ps1 WriteVerboseDebug

# the remaining standalone checks
.\Tests.ps1 ModuleSyntax
.\Tests.ps1 ExplicitModuleImport
.\Tests.ps1 UnwantedStrings
.\Tests.ps1 PSSA
```

**Always use `Tests.ps1`**
- Run all tests through the `.\Tests.ps1 <Category>` orchestrator. Do not run Pester tests directly

**Checking a single file or folder**
- `.\Tests.ps1 <Category>` scans all in-scope files. To check just one file or folder,
    add `-Path` (or just list the paths -- `-Path` takes the remaining arguments).
    .\Tests.ps1 LineLength -Path .\Scripts\Invoke-RandomEmailTraffic.ps1
    .\Tests.ps1 PSSA -Path .\Source\Public
    .\Tests.ps1 Lint .\Build.ps1 .\Tests.ps1

**Quick pass/fail**
Add `-Quiet` to any formatting check for single line output.
