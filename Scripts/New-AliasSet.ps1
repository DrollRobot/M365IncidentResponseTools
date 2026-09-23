<#
.SYNOPSIS
    Generates every alias variation for one row of Aliases.txt.

.DESCRIPTION
    Given a canonical function name, alternate verbs, and optional abbreviations,
    produces all alias combinations covering:
      - Dash vs. no-dash
      - IRT vs. no-IRT
      - Singular vs. plural
      - All supplied verbs (canonical + alternates)
      - All supplied abbreviated nouns (no-IRT, includes bare verb-less form)

    The canonical form (Verb[0]-IRTNoun) is always excluded from the output.
    Output is a single-line @('alias1', 'alias2', ...) string, ready to paste.

.EXAMPLE
    . .\New-AliasSet.ps1

    # Simple -- one verb, no abbreviations
    New-AliasSet -Function 'Disable-IRTUser'

    # With alternate verbs
    New-AliasSet -Function 'Remove-IRTDevice' -AltVerbs @('Delete')

    # With abbreviations (bare noun-only forms are auto-included)
    New-AliasSet -Function 'Get-IRTEntraAuditLog' -AltNouns @('EALog')

    # Suppress plural forms for nouns that don't pluralize naturally
    New-AliasSet -Function 'Connect-IRTTenant' -NoPlural -BareIRT

    # Pipe to clipboard
    New-AliasSet -Function 'Disable-IRTUser' | Set-Clipboard

.OUTPUTS
    System.String. A single-line array literal of aliases.
#>

function New-AliasSet {
    [CmdletBinding()]
    [OutputType([string])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Generates text output only; does not change persistent state.')]
    param(
        # The canonical function name, e.g. 'Get-IRTEntraAuditLog'.
        # The verb and noun are parsed from this automatically.
        [Parameter(Mandatory)]
        [string]$Function,

        # Additional verbs to generate aliases for (e.g. @('Delete') for Remove-*).
        [string[]]$AltVerbs = @(),

        # Abbreviated or alternate noun forms. These get no-IRT treatment only,
        # and bare (verb-less) aliases are included unless -NoBareAlt is set.
        [string[]]$AltNouns = @(),

        # Skip plural (+'s') variants entirely.
        [switch]$NoPlural,

        # Include a bare 'IRTNoun' alias (no verb). Useful for things like
        # Connect-IRTTenant which has 'IRTTenant' as an alias.
        [switch]$BareIRT,

        # Suppress the automatic bare (verb-less) aliases for AltNouns.
        [switch]$NoBareAlt
    )

    # Parse verb and noun from the canonical function name.
    if ($Function -notmatch '^(?<Verb>[A-Z][a-zA-Z]+)-IRT(?<Noun>.+)$') {
        Write-Error "Cannot parse '$Function'. Expected format: Verb-IRTNoun"
        return
    }
    $canonVerb = $Matches.Verb
    $noun = $Matches.Noun
    $canonical = "$canonVerb-IRT$noun"
    $allVerbs = @($canonVerb) + $AltVerbs

    $out = [System.Collections.Generic.List[string]]::new()

    # --- Primary noun: with IRT and without IRT ---
    foreach ($v in $allVerbs) {
        # With IRT
        $out.Add("${v}IRT${noun}")               # VerbIRTNoun      (no dash)
        if (-not $NoPlural) {
            $out.Add("${v}-IRT${noun}s")         # Verb-IRTNouns
            $out.Add("${v}IRT${noun}s")          # VerbIRTNouns
        }
        # Without IRT
        $out.Add("${v}-${noun}")                 # Verb-Noun
        $out.Add("${v}${noun}")                  # VerbNoun
        if (-not $NoPlural) {
            $out.Add("${v}-${noun}s")            # Verb-Nouns
            $out.Add("${v}${noun}s")             # VerbNouns
        }
    }

    # Bare IRT noun form (e.g. 'IRTTenant')
    if ($BareIRT) {
        $out.Add("IRT${noun}")
        if (-not $NoPlural) { $out.Add("IRT${noun}s") }
    }

    # --- Abbreviated / alternate nouns: no IRT, bare form included ---
    foreach ($alt in $AltNouns) {
        foreach ($v in $allVerbs) {
            $out.Add("${v}-${alt}")              # Verb-Alt
            $out.Add("${v}${alt}")               # VerbAlt
            if (-not $NoPlural) {
                $out.Add("${v}-${alt}s")         # Verb-Alts
                $out.Add("${v}${alt}s")          # VerbAlts
            }
        }
        # Bare (no-verb) forms
        if (-not $NoBareAlt) {
            $out.Add($alt)                       # Alt
            if (-not $NoPlural) { $out.Add("${alt}s") }  # Alts
        }
    }

    # Remove canonical, deduplicate, preserve insertion order
    $unique = $out | Where-Object { $_ -ne $canonical } | Select-Object -Unique

    # Format as a single-line array literal
    $quoted = $unique | ForEach-Object { "'$_'" }
    "@($($quoted -join ', '))"
}
