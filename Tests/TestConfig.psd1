# Tests\TestConfig.psd1

@{
    lint = @{
        # Paths excluded from tests. Relative to repo root.
        ExcludePath = @(
            '.local'
            'Output'
            '.staging'
        )

        # LineLength: longest allowed line, in characters.
        MaxLength   = 100

        # FixmeComments: whether tests fail if FIXME comments found
        FailOnFixme     = $false

        # NonASCIICharacters: exceptions
        ExemptCharacter = @()

        # UnwantedStrings: patterns this project must not ship, and the lines
        # exempt from them. Both default to empty (the check then generates no
        # tests). Set Features.UnwantedStringsLocal in Scripts\setup.psd1 to
        # keep them out of source control instead.
        # UnwantedPattern = @(
        #     @{ Tag = 'TODO'; Pattern = '#.*\bTODO\b' }
        # )
        # UnwantedException = @(
        #     '\bSuppressMessageAttribute\b'
        # )
    }

    remote = @{
        # A tenant with this address in its organization's
        # marketingNotificationEmails is marked disposable, so destructive
        # 'remote' tests may change it. Read by Tests\Confirm-RemoteDisposable.ps1,
        # written by Scripts\Set-RemoteDisposable.ps1. Other repos (azure-auth)
        # read the same address, so never change it.
        DisposableMarker = 'disposable-environment@example.invalid'
    }
}
