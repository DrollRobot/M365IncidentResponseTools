function New-InvestigationFolder {
    <#
    .SYNOPSIS
    Makes a new directory based on client and user info.

    .DESCRIPTION
    Creates a timestamped investigation output folder in the current working directory.
    The folder name is built from the tenant's default domain, an optional ticket number,
    and the display names of the users under investigation.

    If the Graph context is not available the function prompts for a client name
    interactively. Falls back to $Global:IRT_UserObjects if no -UserObject is passed.

    .PARAMETER UserObject
    One or more user objects whose names are included in the folder name. Falls back to
    global session objects if omitted.

    .PARAMETER Ticket
    Optional ticket or case number to include in the folder name.

    .EXAMPLE
    New-InvestigationFolder
    Creates a folder like: investigation_contoso_jsmith_26-05-03_14-30

    .EXAMPLE
    New-InvestigationFolder -Ticket 'INC-1234' -UserObject $User
    Creates a folder that includes the ticket number and user name.

    .OUTPUTS
    System.IO.DirectoryInfo

    .NOTES
    Version: 1.0.2
    #>
	[Alias('NewDir', 'NewFolder')]
	[CmdletBinding(SupportsShouldProcess)]
	param (
		[Parameter( Position = 0 )]
		[Alias('UserObjects')]
		[psobject[]] $UserObject,

		[string] $Ticket
	)

	begin {

		# script variables
		$CurrentPath = Get-Location
		$FileNameStrings = [System.Collections.Generic.List[string]]::new()

		# get client domain
		try {
			$DomainName = Get-IRTDefaultDomain
		}
		catch {}

		if ( -not $DomainName ) {
			$DomainName = Read-Host "Enter client name"
		}

		# get datetime string for filename
		$DateString = Get-Date -Format "yy-MM-dd_HH-mm"

		# if not passed directly, find global
		if ( -not $UserObject -or $UserObject.Count -eq 0 ) {

			# get from global variables
			$ScriptUserObjects = Get-IRTUserObject

		}
		else {
			$ScriptUserObjects = $UserObject
		}
	}

	process {

		### build string array
		# domain name
		if ( $DomainName ) {
			$FileNameStrings.Add( $DomainName )
		}

		# user name
		if ( @( $ScriptUserObjects ).Count -eq 1 ) {

			$UserEmail = $ScriptUserObjects.UserPrincipalName
			$UserName = $UserEmail -split '@' | Select-Object -First 1
			$FileNameStrings.Add( $UserName )
		}
		elseif (  @( $ScriptUserObjects ).Count -gt 1 ) {

			$FileNameStrings.Add( 'MultipleUsers' )
		}
		else {
			$UserName = Read-Host "Enter username:"
			$FileNameStrings.Add( $UserName )
		}

		# ticket number
		if (-not [string]::IsNullOrWhiteSpace($Ticket)) {
			$FileNameStrings.Add($Ticket)
		}

		# date
		$FileNameStrings.Add( $DateString )

		# investigation
		$FileNameStrings.Add( 'Investigation' )

		# build folder name
		$FolderName = $FileNameStrings -join '_'

		# create folder
		$FolderPath = Join-Path -Path $CurrentPath -ChildPath $FolderName
		if ($PSCmdlet.ShouldProcess($FolderPath, 'Create directory')) {
			$null = New-Item -ItemType Container -Path $FolderPath -Confirm:$false

			# move to folder
			Set-Location -Path $FolderPath
		}
	}
}
