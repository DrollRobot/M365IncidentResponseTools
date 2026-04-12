New-Alias -Name 'MessageTrace' -Value 'Get-IRTMessageTrace' -Force
function Get-IRTMessageTrace {
    <#
	.SYNOPSIS
	Downloads incoming and outgoing message trace for specified user, or all users.
	
	.NOTES
	Version: 1.5.0
    1.5.0 - Integrated V1 and V2 into same function.
    1.4.0 - Switched to separate get/show functions. Updated to passing objects, not files. Added global variables.
	#>
    [CmdletBinding( DefaultParameterSetName = 'UserObjects' )]
    param (
        [Parameter(ParameterSetName = 'UserObjects', Position = 0)]
        [Alias( 'UserObject' )]
        [psobject[]] $UserObjects,

        [Parameter(ParameterSetName = 'UserEmails')]
        [Alias( 'UserEmail' )]
        [string[]] $UserEmails,

        [Parameter(ParameterSetName = 'AllUsers')]
        [switch] $AllUsers,

        # relative date range
        [int] $Days, # default value set at #DEFAULTDAYS
        # absolute date range
        # [string] $Start, #FIXME need to update request-irtmessagetrace
        # [string] $End,

        [int] $ResultLimit = 50000,
        [string] $TableStyle = 'Dark8',
        [boolean] $Variable = $true,
        [boolean] $Excel = $true,
        [switch] $Quiet,
        [switch] $Test,
        [boolean] $Xml = $true
    )

    begin {

        #region BEGIN

        # constants
        $Function = $MyInvocation.MyCommand.Name
        $ParameterSet = $PSCmdlet.ParameterSetName
        $RawDateProperty = 'Received'
        $FileNamePrefix = 'MessageTrace'

        # colors
        $Blue = @{ForegroundColor = 'Blue' }
        # $Green = @{ForegroundColor = 'Green'}
        # $Magenta = @{ForegroundColor = 'Magenta'}
        # $Red = @{ForegroundColor = 'Red'}
        # $Yellow = @{ForegroundColor = 'Yellow'}

        # create user objects depending on parameters used
        switch ( $ParameterSet ) {
            'UserObjects' {
                # if users passed via script argument:
                if (($UserObjects | Measure-Object).Count -gt 0) {
                    $ScriptUserObjects = $UserObjects
                }
                # if not, look for global objects
                else {
                    
                    # get from global variables
                    $ScriptUserObjects = Get-IRTUserObjects
                    
                    # if none found, exit
                    if (($ScriptUserObjects | Measure-Object).Count -eq 0) {
                        $ErrorParams = @{
                            Category    = 'InvalidArgument'
                            Message     = "No -UserObjects argument used, no `$Global:IRT_UserObjects present."
                            ErrorAction = 'Stop'
                        }
                        Write-Error @ErrorParams
                    }
                }
            }
            'UserEmails' {
                # variables
                $ScriptUserObjects = [System.Collections.Generic.list[psobject]]::new()

                foreach ( $Email in $UserEmails ) {

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

        # verify connected to exchange
        try {
            [void](Get-AcceptedDomain)
        }
        catch {
            $ErrorParams = @{
                Category    = 'ConnectionError'
                Message     = "Not connected to Exchange. Run Connect-ExchangeOnline."
                ErrorAction = 'Stop'
            }
            Write-Error @ErrorParams
        } 

        #region DATE RANGE
        # validate only days or (start and end)
        if ($Days -and ($Start -or $End)) {
            $ErrorParams = @{
                Category    = 'InvalidArgument'
                Message     = "Choose either relative range with -Days or absolute range with -Start and -End."
                ErrorAction = 'Stop'
            }
            Write-Error @ErrorParams  
        }

        # validate if start or end used, both were used.
        if (($Start -and -not $End) -or
            ($End -and -not $Start)
        ) {
            $ErrorParams = @{
                Category    = 'InvalidArgument'
                Message     = "Specify both -Start and -End"
                ErrorAction = 'Stop'
            }
            Write-Error @ErrorParams  
        }

        # attempt to parse user input dates into datetime objects
        if ($Start -and $End) {
            $DateRangeType = 'Absolute'
            # start - convert user string into object
            try {
                $StartDate = Get-Date -Date $Start -ErrorAction 'Stop'
                $StartDateUtc = [DateTime]::SpecifyKind($StartDate, [DateTimeKind]::Local).ToUniversalTime()
            }
            catch {
                $ErrorParams = @{
                    Category    = 'InvalidArgument'
                    Message     = "-Start invalid. Use format 'MM/dd/yy hh:mm(tt)"
                    ErrorAction = 'Stop'
                }
                Write-Error @ErrorParams
            }
            # end - convert user string into object
            try {
                $EndDate = Get-Date -Date $End -ErrorAction 'Stop'
                $EndDateUtc = [DateTime]::SpecifyKind($EndDate, [DateTimeKind]::Local).ToUniversalTime()
            }
            catch {
                $ErrorParams = @{
                    Category    = 'InvalidArgument'
                    Message     = "-End invalid. Use format 'MM/dd/yy hh:mm(tt)"
                    ErrorAction = 'Stop'
                }
                Write-Error @ErrorParams
            }
            # make sure earliest date is the start date
            if ($StartDateUtc -gt $EndDateUtc) {
                $Temp = $StartDateUtc
                $StartDateUtc = $EndDateUtc
                $EndDateUtc = $Temp
            }
            # set days to match range
            $Days = [Int]([Math]::Ceiling( ($EndDate - $StartDate).TotalDays ))
        }
        # create objects based on days
        else {
            $DateRangeType = 'Relative'
            # set default value for days ### must be done after checking for relative/absolute arguments
            if (-not $Days) {
                $Days = 10 #DEFAULTDAYS
            }

            $StartDateUtc = (Get-Date).AddDays($Days * -1).ToUniversalTime()
            $EndDateUtc = (Get-Date).ToUniversalTime()
        }

        #region VERIFY COMMAND
        # verify Get-MessageTraceV2 is available
        try {
            [void](Get-Command Get-MessageTraceV2 -ErrorAction 'Stop')
        }
        catch {
            # if there was an error, revert to V1
            $WarningParams = @{
                Message = "Get-MessageTraceV2 command not available in this tenant or ExchangeOnlineManagement version. Running Get-MessageTrace instead."
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
                        Message = "Get-MessageTrace can only search back 10 days. Changing -Days to 10."
                    }
                    Write-Warning @WarningParams
                    $Days = 10
                    $StartDateUtc = (Get-Date).AddDays(-10).ToUniversalTime()
                }
            }
        }

        # get client domain name for file output
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
                try {
                    $Params = @{
                        UserPrincipalName = $ScriptUserObject.UserPrincipalName
                        ErrorAction       = 'Stop'
                    }
                    $Mailbox = Get-EXOMailbox @Params
                }
                catch {}
                if (-not $Mailbox) {
                    Write-Host @Red "${Function}: $($ScriptUserObject.UserPrincipalName) does not have a mailbox. Exiting"
                    $VariableParams = @{
                        Name  = "IRT_MessageTraceTable_${UserName}"
                        Value = $Null
                        Scope = 'Global'
                        Force = $True
                    }
                    New-Variable @VariableParams
                    return
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

                Write-Host @Blue "Getting message trace records for all users."
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

                $ListOfLists = [System.Collections.Generic.List[System.Collections.Generic.List[psobject]]]::new()

                foreach ($UserEmail in $LoopUserEmails) {
                    # get sender records
                    if (-not $Quiet) { Write-Host @Blue "Requesting message trace records with sender: ${UserEmail}" }
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
                            Days          = $Days #FIXME update to use start/end dates instead of days
                            ResultLimit   = $ResultLimit
                            Quiet         = $Quiet
                        }
                        Request-IRTMessageTrace @Params
                    }
                    if (($Messages | Measure-Object).Count -gt 0) {
                        $ListOfLists.Add([System.Collections.Generic.List[psobject]]@($Messages))
                    }
                    # get recipient records
                    if (-not $Quiet) { Write-Host @Blue "Requesting message trace records with recipient: ${UserEmail}" }
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
                            Days             = $Days #FIXME update to use start/end dates instead of days
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
                    Write-Host @Red "0 total messages retrieved. Exiting."
                    $VariableParams = @{
                        Name  = "IRT_MessageTraceTable_${UserName}"
                        Value = $Null
                        Scope = 'Global'
                        Force = $True
                    }
                    New-Variable @VariableParams
                    return
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
                    [System.Collections.Generic.List[psobject]]$AllMessages = Merge-ListsOnDate @MergeParams
                }
            }

            # exit if no messages found
            if (($AllMessages | Measure-Object).Count -eq 0) {
                Write-Host @Red "${Function}: No messages found. Exiting."
                $VariableParams = @{
                    Name  = "IRT_MessageTraceTable_${UserName}"
                    Value = $Null
                    Scope = 'Global'
                    Force = $True
                }
                New-Variable @VariableParams
                return
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
                if ($AllUsers) {
                    # do nothing
                }
                else {
                    # export table by internetmessageid
                    $Table = @{}
                    foreach ($Message in $AllMessages) {
                        if (-not $Message.Metadata) {
                            $InternetMessageId = $Message.MessageId
                            $Table[$InternetMessageId] = $Message
                        }
                    }
                    $VariableName = "IRT_MessageTraceTable_${UserName}"
                    Write-Host @Blue "Exporting message trace to `$Global:${VariableName}"
                    $VariableParams = @{
                        Name  = $VariableName
                        Value = $Table
                        Scope = 'Global'
                        Force = $True
                    }
                    New-Variable @VariableParams
                }
            }

            # export raw data
            if ($Xml) {
                Write-Host @Blue "Exporting raw data to: ${XmlOutputPath}"
                $AllMessages | Export-CliXml -Depth 10 -Path $XmlOutputPath
            }

            if ($Script) {
                Write-Output $AllMessages
                return
            }

            # create excel sheet
            if ($Excel) {
                Show-IRTMessageTrace -Messages $AllMessages
            }
        }
    }
}