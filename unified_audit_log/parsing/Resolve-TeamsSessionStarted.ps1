function Resolve-TeamsSessionStarted {
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

        [psobject[]] $Users,

        [switch] $Cached
    )

    begin {

        # variables
        $ModuleRoot = $MyInvocation.MyCommand.Module.ModuleBase
        $AuditData = $Log.AuditData | ConvertFrom-Json
        $Users = Request-GraphUsers -Cached:$Cached

        # import user type csv
        $UserTypePath = Join-Path -Path $ModuleRoot -ChildPath 'data\unified_audit_log-user_type.csv'
        $UserTypeData = Import-Csv -Path $UserTypePath
    }

    process {

        # UserType
        $UserTypeNum = $AuditData.UserType
        $UserTypeWord = ( $UserTypeData | Where-Object { $_.Value = $UserTypeNum } ).'UserType member name'
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