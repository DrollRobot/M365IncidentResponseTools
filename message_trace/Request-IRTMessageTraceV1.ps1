function Request-IRTMessageTraceV1 {
    param(
        [string[]] $SenderAddress,
        [string[]] $RecipientAddress,

        [Parameter( Mandatory )]
        [datetime] $StartDate,

        [Parameter( Mandatory )]
        [datetime] $EndDate,

        [int] $ResultLimit = 50000,

        [switch] $Quiet
    )

    begin {

        #region BEGIN

        # constants
        # $Function = $MyInvocation.MyCommand.Name
        # $ParameterSet = $PSCmdlet.ParameterSetName
        $Blue = @{ForegroundColor = 'Blue' }

        $PageSize = 5000 # 5000 is max page size for message trace
        $Page = 1
        $MoreToGet = $true

        $Params = @{
            StartDate = $StartDate
            EndDate   = $EndDate
            PageSize  = $PageSize
        }
        if ( $SenderAddress ) {
            $Params['SenderAddress'] = $SenderAddress
        }
        if ( $RecipientAddress ) {
            $Params['RecipientAddress'] = $RecipientAddress
        }
    }

    process {

        # get all records
        $AllMessages = [System.Collections.Generic.List[psobject]]::new()
        while ($MoreToGet -and $AllMessages.Count -le $ResultLimit ) {

            $Params['Page'] = $Page

            # retrieve one page
            if (-not $Quiet) {Write-Host @Blue "Requesting message trace page ${Page}"}
            $PageResults = [psobject[]]@(Get-MessageTrace @Params -WarningAction SilentlyContinue -WarningVariable mtWarnings)
            $mtWarnings | Where-Object { $_ -notlike '*Get-MessageTrace will start deprecating*' } |
                ForEach-Object { Write-Warning $_ }
            foreach ($i in $PageResults) {[void]$AllMessages.Add($i)}

            # stop if the page had less than max page size
            if (($PageResults | Measure-Object).Count -lt $PageSize) {
                $MoreToGet = $false
            }
            else {
                $Page++
            }
        }

        return $AllMessages
    }
}