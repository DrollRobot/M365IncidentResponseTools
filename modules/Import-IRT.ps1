function Import-IRT {
    <#
    .SYNOPSIS
        Preloads the M365IncidentResponseTools module into the current session.

    .DESCRIPTION
        A lightweight stub whose sole purpose is to trigger PowerShell's automatic
        module loading. Calling this function forces the full module to be imported --
        dot-sourcing all domain scripts and initializing shared state -- so that
        subsequent commands respond instantly instead of incurring the first-call
        import penalty.

    .EXAMPLE
        Import-IRT

        Loads M365IncidentResponseTools into the current session. Run this once at
        the start of a session to warm up the module before using any IRT commands.

    .OUTPUTS
        None

    .NOTES
        The function body is intentionally empty. The import side-effect is produced
        entirely by PowerShell's automatic module loading when any exported function
        from the module is invoked.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()
}
