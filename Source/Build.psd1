@{
    # -------------------------------------------------------------------------
    # ModuleBuilder configuration (build.psd1)
    #
    # Lives in source/ next to the module manifest. Build-Module reads this
    # automatically when run with the manifest as -SourcePath. Every key here
    # is just a default override for a Build-Module parameter.
    # -------------------------------------------------------------------------

    Path = 'M365IncidentResponseTools.psd1'

    SourceDirectories = @(
        'Classes'
        'Private'
        'Public'
    )

    PublicFilter = 'Public/*.ps1'

    CopyPaths = @(
        './ScriptsToProcess'
        './data'
    )

    # OutputDirectory          = '../output'
    # VersionedOutputDirectory = $true

    # Optional: text injected at the very top / bottom of the generated .psm1.
    Prefix = 'prefix.ps1'
    Suffix = 'suffix.ps1'
}