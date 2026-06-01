# Data/

Static data files bundled with the module. ModuleBuilder copies this folder
verbatim to the output directory (configured via `CopyPaths` in `Build.psd1`).
Files here are NOT merged into the `.psm1`.

## Use cases

- Lookup tables (CSV, JSON) referenced at runtime by module functions.
- Template files (XLSX, etc.) distributed with the module.
- Configuration templates users copy to customize the module.

## Conventions

- Reference these files at runtime via `$PSScriptRoot` from within a function,
  or via a module-level path variable set during initialization.
- Do not store user-specific data or secrets here -- only static reference data.


