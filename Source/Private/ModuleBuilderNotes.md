# Private/

Internal helper functions that are NOT exported to module consumers.

ModuleBuilder merges all `.ps1` files from this folder (and subfolders) into
the generated `.psm1`. The files are included in alphabetical order by default.

## Conventions

- One function per file; file name matches the function name.
- Use subfolders to mirror the `Public/` category structure (e.g., `Connect/`,
  `Device/`, `Lib/`, `Utility/`).
- Functions here never appear in `FunctionsToExport` in the manifest.
- `Lib/` holds general-purpose helpers with no IRT-specific logic.
- `Utility/` holds IRT-specific helpers that don't fit another category.

## Standard files

None required -- only `.ps1` helper files and category subfolders.
