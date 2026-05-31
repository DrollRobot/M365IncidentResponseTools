function Get-TeamsSessionStartedSummary {
    <#
	.SYNOPSIS


	.NOTES
	Version: 1.0.0
	#>
    [CmdletBinding()]
    param (
        [Parameter( Mandatory )]
        [psobject] $Log,

        [Parameter( Mandatory )]
        [pscustomobject] $CustomObject,

        [Alias('Users')]
        [psobject[]] $User,

        [switch] $Cached
    )

    begin {

        # variables
        $AuditData = $Log.AuditData | ConvertFrom-Json
        $User = Request-GraphUser -Cached:$Cached
    }

    process {

        # UserType
        $UserTypeNum = $AuditData.UserType
        $UserTypeWord = $Global:IRT_UalUserTypeTable[[int]$UserTypeNum]
        $UserTypeString = "${UserTypeNum}:${UserTypeWord}"
        $AddParams = @{
            MemberType = 'NoteProperty'
            Name       = 'UserType'
            Value      = $UserTypeString
        }
        $CustomObject | Add-Member @AddParams


        # user?



        # summary?


    }
}