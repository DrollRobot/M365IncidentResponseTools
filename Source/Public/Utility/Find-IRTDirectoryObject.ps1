function Find-IRTDirectoryObject {
    [Alias('FindObject', 'FindObjects')]
    param(
        [Parameter( Position = 0 )]
        [string] $Content
    )

    begin {
        $ImportParams = @{
            Name = @(
                'Microsoft.Graph.Applications'
                'Microsoft.Graph.DirectoryObjects'
                'Microsoft.Graph.Groups'
                'Microsoft.Graph.Users'
            )
        }
        Import-IRTModule @ImportParams
        $GuidPattern = "\b[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\b"

        # get content from clipboard
        if (-not $Content) {
            Write-IRT "No content provided. Pulling from clipboard."
            $Content = Get-Clipboard
            if ( @( $Content ).Count -eq 0 ) {
                throw "No content provided, or found in clipboard. Exiting."
            }
            $DisplayLines = $Content -split "`r`n" | Select-Object -First 3
            $TruncatedLines = $DisplayLines | ForEach-Object {
                if ( $_.Length -gt 80 ) {
                    $_.Substring(0, 77) + "..."
                }
                else {
                    $_
                }
            }
            Write-IRT $TruncatedLines
        }
    }

    process {

        $Guids = $Content |
            Select-String -Pattern $GuidPattern -AllMatches |
            ForEach-Object { $_.Matches.Value }

        # remove duplicates
        $Guids = $Guids | Sort-Object -Unique

        Write-IRT "Found GUIDS:"
        $Guids

        foreach ( $Guid in $Guids ) {

            # variables
            $DirectoryObject = $null
            $ObjectType = $null

            Write-IRT "Running Get-MgDirectoryObject for ${Guid}"

            try {

                $DirectoryObject = Get-MgDirectoryObject -DirectoryObjectId $Guid -ErrorAction Stop

                $ObjectType = $DirectoryObject.AdditionalProperties.'@odata.type' -replace '#', ''

                Write-IRT "ObjectType: ${ObjectType}"
            }
            catch {
                $Pattern = 'does not exist or one of its queried' +
                ' reference-property objects are not present'
                if ( $_ -match $Pattern ) {
                    Write-IRT "Unable to find object."
                }
                else {
                    $_
                }
            }

            switch ( $ObjectType ) {
                'microsoft.graph.user' {
                    $Object = if ( $Global:IRT_UsersById -and
                        $Global:IRT_UsersById.ContainsKey($Guid)
                    ) {
                        $Global:IRT_UsersById[$Guid]
                    } else {
                        Get-MgUser -UserId $Guid
                    }
                    $Object | Format-Table
                }
                'microsoft.graph.group' {
                    $Object = if ( $Global:IRT_GroupsById -and
                        $Global:IRT_GroupsById.ContainsKey($Guid)
                    ) {
                        $Global:IRT_GroupsById[$Guid]
                    } else {
                        Get-MgGroup -GroupId $Guid
                    }
                    $Object | Format-Table
                }
                'microsoft.graph.servicePrincipal' {
                    $Object = if ( $Global:IRT_ServicePrincipalsById -and
                        $Global:IRT_ServicePrincipalsById.ContainsKey($Guid)
                    ) {
                        $Global:IRT_ServicePrincipalsById[$Guid]
                    } else {
                        Get-MgServicePrincipal -ServicePrincipalId $Guid
                    }
                    $Object | Format-Table
                }
            }
        }
    }
}
