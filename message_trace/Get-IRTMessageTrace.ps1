function Get-IRTMessageTrace {
    <#
    .SYNOPSIS
    Downloads incoming and outgoing message trace for specified user, or all users.

    .DESCRIPTION
    Retrieves Exchange Online message trace records for one or more users over a configurable
    date range and exports results to Excel. Accepts user objects, email addresses, or an
    -AllUsers switch for tenant-wide queries.

    Supports both the modern V2 API (large result sets via background jobs) and the legacy
    V1 endpoint. Date range defaults to the last 10 days when no -Days, -Start, or -End
    is specified.

    .PARAMETER UserObject
    One or more user objects to trace. Mutually exclusive with -UserEmail and -AllUsers.
    Falls back to global session objects if omitted.

    .PARAMETER UserEmail
    One or more email addresses to trace. Mutually exclusive with -UserObject and -AllUsers.

    .PARAMETER AllUsers
    Query message trace for all users in the tenant. Mutually exclusive with -UserObject
    and -UserEmail.

    .PARAMETER Days
    Number of days back to search. Cannot be used with -Start / -End.

    .PARAMETER Start
    Start of date range (parseable date string). Used with -End for an absolute range.

    .PARAMETER End
    End of date range (parseable date string). Used with -Start for an absolute range.

    .PARAMETER ResultLimit
    Maximum number of records to return. Default: 50000.

    .PARAMETER Variable
    Save results to a session variable for downstream use. Default: $true.

    .PARAMETER Excel
    Export results to an Excel workbook. Default: $true.

    .PARAMETER Quiet
    Suppress progress output.

    .PARAMETER Xml
    Export raw XML alongside the Excel file. Defaults to IRT_Config.ExportXml.

    .PARAMETER TableStyle
    Excel table style. Defaults to IRT_Config.ExcelTableStyle.

    .PARAMETER Font
    Excel font name. Defaults to IRT_Config.ExcelFont.

    .EXAMPLE
    Get-IRTMessageTrace
    Downloads message trace for the user in the global session (last 10 days).

    .EXAMPLE
    Get-IRTMessageTrace -UserObject $User -Days 30
    Downloads 30 days of message trace for a specific user.

    .EXAMPLE
    Get-IRTMessageTrace -AllUsers -Start '2026-04-01' -End '2026-04-30'
    Downloads all tenant message trace for April 2026.

    .OUTPUTS
    None. Results are exported to Excel and stored in a session variable.

    .NOTES
    Version: 1.5.0
    1.5.0 - Integrated V1 and V2 into same function.
    1.4.0 - Switched to separate get/show functions. Updated to passing objects, not files.
        Added global variables.
    #>
    [Alias('MessageTrace')]
    [CmdletBinding( DefaultParameterSetName = 'UserObject' )]
    param (
        [Parameter(ParameterSetName = 'UserObject', Position = 0)]
        [Alias('UserObjects')]
        [psobject[]] $UserObject,

        [Parameter(ParameterSetName = 'UserEmail')]
        [Alias('UserEmails')]
        [string[]] $UserEmail,

        [Parameter(ParameterSetName = 'AllUsers')]
        [switch] $AllUsers,

        [int] $Days, # default set at DEFAULTDAYS
        [string] $Start,
        [string] $End,

        [int] $ResultLimit = 50000,

        [boolean] $Variable = $true,
        [boolean] $Excel = $true,
        [switch] $Quiet,
        [boolean] $Xml = $Global:IRT_Config.ExportXml,
        [string] $TableStyle = $Global:IRT_Config.ExcelTableStyle,
        [string] $Font = $Global:IRT_Config.ExcelFont
    )

    begin {
        $FunctionName = $MyInvocation.MyCommand.Name
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $ParameterSet = $PSCmdlet.ParameterSetName
        $RawDateProperty = 'Received'
        $FileNamePrefix = 'MessageTrace'

        # create user objects depending on parameters used
        switch ( $ParameterSet ) {
            'UserObject' {
                # if users passed via script argument:
                if (($UserObject | Measure-Object).Count -gt 0) {
                    $ScriptUserObjects = $UserObject
                }
                # if not, look for global objects
                else {

                    # get from global variables
                    $ScriptUserObjects = Get-IRTUserObject

                    # if none found, exit
                    if (($ScriptUserObjects | Measure-Object).Count -eq 0) {
                        $ErrorParams = @{
                            Category    = 'InvalidArgument'
                            Message     = 'No -UserObject argument used, ' +
                                'no $Global:IRT_UserObjects present.'
                            ErrorAction = 'Stop'
                        }
                        Write-Error @ErrorParams
                    }
                }
            }
            'UserEmail' {
                # variables
                $ScriptUserObjects = [System.Collections.Generic.list[psobject]]::new()

                foreach ( $Email in $UserEmail ) {

                    # create object with userprincipalname property
                    $ScriptUserObjects.Add(
                        [pscustomobject]@{
                            UserPrincipalName = $Email
                        }
                    )
                }
            }
            'AllUsers' {
                # build user object with null principal name
                $ScriptUserObjects = @(
                    [pscustomobject]@{
                        UserPrincipalName = $null
                    }
                )
                $AllUsers = $true
            }
        }


        # parse date ranges
        $DateRangeParams = @{
            Days        = $Days
            Start       = $Start
            End         = $End
            DefaultDays = 10 #DEFAULTDAYS
        }
        $DateRange = Resolve-IRTDateRange @DateRangeParams
        $DateRangeType = $DateRange.RangeType
        $Days          = $DateRange.Days
        $StartDateUtc  = $DateRange.StartUtc
        $EndDateUtc    = $DateRange.EndUtc

        #region VERIFY COMMAND
        # verify Get-MessageTraceV2 is available
        try {
            [void](Get-Command Get-MessageTraceV2 -ErrorAction 'Stop')
        }
        catch {
            # if there was an error, revert to V1
            $WarningParams = @{
                Message = 'Get-MessageTraceV2 command not available in this tenant or' +
                    ' ExchangeOnlineManagement version. Running Get-MessageTrace instead.'
            }
            Write-Warning @WarningParams

            $V1 = $true

            # change date ranges to 10 days max
            if ($DateRangeType -eq 'Absolute') {
                $NowUtc = (Get-Date).ToUniversalTime()
                if ($StartDateUtc -lt $NowUtc.AddDays(-10)) {
                    $WarningParams = @{
                        Message = "-StartDate is more than 10 days ago. Changing to 10 days ago."
                    }
                    Write-Warning @WarningParams
                    $StartDateUtc = $NowUtc.AddDays(-10)
                }
                if ($EndDateUtc -le $StartDateUtc) {
                    $ErrorParams = @{
                        Category    = 'LimitsExceeded'
                        Message     = "-EndDate must be greater than -StartDate."
                        ErrorAction = 'Stop'
                    }
                    Write-Error @ErrorParams
                }
                # recalculate $Days to match the adjusted date range
                $Days = [Int]([Math]::Ceiling(($EndDateUtc - $StartDateUtc).TotalDays))
            }
            else {
                if ($Days -gt 10) {
                    $WarningParams = @{
                        Message = 'Get-MessageTrace can only search back 10 days.' +
                            ' Changing -Days to 10.'
                    }
                    Write-Warning @WarningParams
                    $Days = 10
                    $StartDateUtc = (Get-Date).AddDays(-10).ToUniversalTime()
                }
            }
        }

        # get client domain name for file output
        Write-Verbose "${FunctionName}: Get-AcceptedDomain $($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))"
        $DefaultDomain = Get-AcceptedDomain | Where-Object { $_.Default -eq $true }
        $DomainName = $DefaultDomain.DomainName -split '\.' | Select-Object -First 1
    }

    process {

        #region USER LOOP

        foreach ( $ScriptUserObject in $ScriptUserObjects ) {

            $AllMessages = [System.Collections.Generic.List[psobject]]::new()

            if ( $AllUsers ) {
                $UserName = 'AllUsers'
            }
            else {

                # verify user has mailbox. if not, exit.
                $Mailbox = $null
                try {
                    $Params = @{
                        UserPrincipalName = $ScriptUserObject.UserPrincipalName
                        ErrorAction       = 'Stop'
                    }
                    $Mailbox = Get-EXOMailbox @Params
                }
                catch {}
                if (-not $Mailbox) {
                    Write-IRT "No mailbox for $($ScriptUserObject.UserPrincipalName)" -Level Warn
                    if ($Global:IRT_WaitFlags) {
                        $Global:IRT_WaitFlags.MessageTraceUserDone = $true
                    }
                    continue
                }

                $UserName = $ScriptUserObject.UserPrincipalName -split '@' | Select-Object -First 1

                $LoopUserEmails = [System.Collections.Generic.HashSet[string]]::new()
                [void]$LoopUserEmails.Add($ScriptUserObject.UserPrincipalName)

                # get all user email addresses
                if (-not $ScriptUserObject.ProxyAddresses) {
                    $ScriptUserObject = $ScriptUserObject | Get-FullUserObject
                }

                $EmailPattern = "\b[a-zA-Z0-9\._%+-]+@([a-zA-Z0-9.-]+\.)[a-zA-Z]{2,6}\b"
                foreach ($p in $ScriptUserObject.ProxyAddresses) {
                    $e = $p | Select-String -Pattern $EmailPattern -AllMatches |
                    ForEach-Object { $_.Matches.Value }
                    if ($e) {
                        [void]$LoopUserEmails.Add($e)
                    }
                }
            }

            # build file name
            $FileNameDateFormat = "yy-MM-dd_HH-mm"
            $FileNameDateString = Get-Date -Format $FileNameDateFormat
            $XmlOutputPath = "${FileNamePrefix}_${Days}Days_${UserName}_${FileNameDateString}.xml"

            ### request message trace records
            if ( $AllUsers ) {

                Write-IRT "Getting message trace records for all users."
                [System.Collections.Generic.List[psobject]]$AllMessages = if ($V1) {
                    $Params = @{
                        StartDate   = $StartDateUtc
                        EndDate     = $EndDateUtc
                        ResultLimit = $ResultLimit
                        Quiet       = $Quiet
                    }
                    Request-IRTMessageTraceV1 @Params
                }
                else {
                    $Params = @{
                        Days        = $Days #FIXME update to use start/end dates instead of days
                        ResultLimit = $ResultLimit
                        Quiet       = $Quiet
                    }
                    Request-IRTMessageTrace @Params
                }
            }
            else {

                $InnerType   = 'System.Collections.Generic.List[psobject]'
                $ListOfLists  = New-Object "System.Collections.Generic.List[$InnerType]"

                foreach ($UserEmail in $LoopUserEmails) {
                    # get sender records
                    if (-not $Quiet) {
                        Write-IRT "Requesting message trace records with sender: ${UserEmail}"
                    }
                    $Messages = if ($V1) {
                        $Params = @{
                            SenderAddress = $UserEmail
                            StartDate     = $StartDateUtc
                            EndDate       = $EndDateUtc
                            ResultLimit   = $ResultLimit
                            Quiet         = $Quiet
                        }
                        Request-IRTMessageTraceV1 @Params
                    }
                    else {
                        $Params = @{
                            SenderAddress = $UserEmail
                            # FIXME: update to use start/end dates instead of days
                            Days          = $Days
                            ResultLimit   = $ResultLimit
                            Quiet         = $Quiet
                        }
                        Request-IRTMessageTrace @Params
                    }
                    if (($Messages | Measure-Object).Count -gt 0) {
                        $ListOfLists.Add([System.Collections.Generic.List[psobject]]@($Messages))
                    }
                    # get recipient records
                    if (-not $Quiet) {
                        Write-IRT "Requesting message trace records with recipient: ${UserEmail}"
                    }
                    $Messages = if ($V1) {
                        $Params = @{
                            RecipientAddress = $UserEmail
                            StartDate        = $StartDateUtc
                            EndDate          = $EndDateUtc
                            ResultLimit      = $ResultLimit
                            Quiet            = $Quiet
                        }
                        Request-IRTMessageTraceV1 @Params
                    }
                    else {
                        $Params = @{
                            RecipientAddress = $UserEmail
                            # FIXME: update to use start/end dates instead of days
                            Days             = $Days
                            ResultLimit      = $ResultLimit
                            Quiet            = $Quiet
                        }
                        Request-IRTMessageTrace @Params
                    }
                    if (($Messages | Measure-Object).Count -gt 0) {
                        $ListOfLists.Add([System.Collections.Generic.List[psobject]]@($Messages))
                    }
                }

                if ($ListOfLists.Count -eq 0) {
                    # exit if no messages returned
                    Write-IRT "0 total messages retrieved. Exiting." -Level Warn
                    if ($Global:IRT_WaitFlags) {
                        $Global:IRT_WaitFlags.MessageTraceUserDone = $true
                    }
                    continue
                }
                elseif ($ListOfLists.Count -eq 1) {
                    $AllMessages = $ListOfLists[0]
                }
                else {
                    # merge lists together
                    $MergeParams = @{
                        PropertyName = $RawDateProperty
                        Lists        = $ListOfLists
                        Descending   = $true
                    }
                    $AllMessages = [System.Collections.Generic.List[psobject]](
                        Merge-ListOnDate @MergeParams
                    )
                }
            }

            # exit if no messages found
            if (($AllMessages | Measure-Object).Count -eq 0) {
                Write-IRT "No messages found. Exiting." -Level Warn
                if ($Global:IRT_WaitFlags) {
                    if ($AllUsers) { $Global:IRT_WaitFlags.MessageTraceAllUsersDone = $true }
                    else           { $Global:IRT_WaitFlags.MessageTraceUserDone = $true }
                }
                continue
            }

            #region METADATA

            # add metadata to results
            $StartDate = (Get-Date).AddDays($Days * -1)
            $EndDate = Get-Date
            $AllMessages.Insert(0,
                [pscustomobject]@{
                    Metadata       = $true
                    UserObject     = $ScriptUserObject
                    UserEmails     = $LoopUserEmails
                    UserName       = $UserName
                    StartDate      = $StartDate
                    EndDate        = $EndDate
                    Days           = $Days
                    DomainName     = $DomainName
                    FileNamePrefix = $FileNamePrefix
                }
            )

            #region OUTPUT

            # export to variables
            if ($Variable) {
                # build table by normalized InternetMessageId
                $Table = @{}
                foreach ($Message in $AllMessages) {
                    if (-not $Message.Metadata) {
                        $NormalizedId = ($Message.MessageId -replace '[<>]','').Trim()
                        if ($NormalizedId) {
                            $Table[$NormalizedId] = $Message
                        }
                    }
                }

                # merge into global synchronized hashtable
                foreach ($Key in $Table.Keys) {
                    $Global:IRT_MessageTraceTable[$Key] = $Table[$Key]
                }
                if ($Global:IRT_WaitFlags) {
                    if ($AllUsers) { $Global:IRT_WaitFlags.MessageTraceAllUsersDone = $true }
                    else           { $Global:IRT_WaitFlags.MessageTraceUserDone = $true }
                }
                Write-Verbose "${FunctionName}: Table key count: $($Table.Count)"
            }

            # export raw data
            if ($Xml) {
                Write-Verbose "${FunctionName}: Export-CliXml $($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))"
                Write-IRT "Exporting raw data to: ${XmlOutputPath}"
                $AllMessages | Export-CliXml -Depth 10 -Path $XmlOutputPath
            }

            if ($Script) {
                Write-Output $AllMessages
                return
            }

            # create excel sheet
            if ($Excel) {
                Write-Verbose "${FunctionName}: Show-IRTMessageTrace $($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))"
                $Params = @{
                    Messages   = $AllMessages
                    TableStyle = $TableStyle
                    Font       = $Font
                }
                Show-IRTMessageTrace @Params
            }
        }
    }
}
