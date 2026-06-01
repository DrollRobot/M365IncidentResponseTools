# build/

The default output directory for `Build-Module` when not using `-BuildToRoot`.

## Configuration

Enable by setting `OutputDirectory = '../build'` in `Source/Build.psd1`.
Set `VersionedOutputDirectory = $true` to get per-version subfolders.

Alternative: the `-BuildToRoot` switch on `Build-Module` (or your build script)
writes the compiled files directly to the repository root, bypassing this
folder. The root-level `.psd1` and `.psm1` are then the build artifacts.

## Expected structure

```
build/
  <ModuleName>/
    <version>/
      <ModuleName>.psd1
      <ModuleName>.psm1
      ScriptsToProcess/
      Data/
      en-US/
```

## Notes

- For PSGallery publishing, a versioned output folder here is the recommended
  approach so the built artifact is isolated from source files.
- If switching from `-BuildToRoot`, update any scripts that reference the
  built module path (test runner, doc generator, CI pipeline).
