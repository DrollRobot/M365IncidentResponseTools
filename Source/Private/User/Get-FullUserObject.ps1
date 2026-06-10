function Get-FullUserObject {
    <#
    .SYNOPSIS
    retrieves a user with a broad set of properties and augments with optional ones.

    .NOTES
    version: 1.0.5
    - add pipeline support (by object or by id/upn)
    - keep signInActivity in initial selection
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByObject')]
    param(
        # pipe full user objects
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'ByObject')]
        [ValidateNotNull()]
        [Microsoft.Graph.PowerShell.Models.MicrosoftGraphUser] $UserObject,

        [Parameter(Mandatory, ValueFromPipeline,
            ValueFromPipelineByPropertyName, ParameterSetName = 'ById')]
        [Alias('Id')]
        [ValidateNotNullOrEmpty()]
        [string] $UserId,

        [Parameter(ParameterSetName = 'ByObject')]
        [Parameter(ParameterSetName = 'ById')]
        [switch] $NoRefresh
    )

    begin {
        Update-IRTToken -Service 'Graph'
        Import-IRTModule -Name 'Microsoft.Graph.Users', 'PSFramework'
        $ScriptUserObject = $UserObject

        # properties you can safely query on all users
        $SelectProps = @(
            'id', 'userPrincipalName', 'displayName', 'accountEnabled',
            'ageGroup', 'businessPhones', 'city', 'companyName', 'consentProvidedForMinor',
            'country', 'createdDateTime', 'creationType', 'department',
            'employeeHireDate', 'employeeId', 'employeeLeaveDateTime', 'employeeOrgData',
            'employeeType', 'externalUserState', 'externalUserStateChangeDateTime',
            'faxNumber', 'givenName', 'identities', 'imAddresses', 'isResourceAccount',
            'jobTitle', 'lastPasswordChangeDateTime', 'legalAgeGroupClassification',
            'licenseAssignmentStates', 'mail', 'mailNickname', 'mobilePhone', 'officeLocation',
            'onPremisesDistinguishedName', 'onPremisesDomainName', 'onPremisesExtensionAttributes',
            'onPremisesImmutableId', 'onPremisesLastSyncDateTime', 'onPremisesProvisioningErrors',
            'onPremisesSamAccountName', 'onPremisesSecurityIdentifier', 'onPremisesSyncEnabled',
            'onPremisesUserPrincipalName', 'otherMails', 'passwordPolicies', 'passwordProfile',
            'postalCode', 'preferredDataLocation', 'preferredLanguage', 'provisionedPlans',
            'proxyAddresses', 'securityIdentifier', 'showInAddressList',
            'signInSessionsValidFromDateTime', 'state', 'streetAddress', 'surname',
            'usageLocation', 'userType', 'signInActivity'
        )

        # properties that may error depending on licensing/mailbox/etc.
        $OptionalProps = @(
            'aboutMe', 'birthday', 'deviceEnrollmentLimit', 'hireDate', 'interests',
            'mailboxSettings', 'mailFolders', 'mySite', 'pastProjects', 'preferredName',
            'print', 'responsibilities', 'schools', 'skills'
        )
    }

    process {

        # if object is already full object, and -NoRefresh, don't query.
        if ($NoRefresh -and $PSCmdlet.ParameterSetName -eq 'ByObject' -and
            $ScriptUserObject.PSObject.Properties['AllProperties'] -and
            $ScriptUserObject.AllProperties) {
            Write-Output $ScriptUserObject
            return
        }

        # resolve the identifier for this pipeline item
        switch ($PSCmdlet.ParameterSetName) {
            'ById' { $ResolvedId = $UserId }
            'ByObject' { $ResolvedId = $ScriptUserObject.Id }
            default { $ResolvedId = $null }
        }

        if (-not $ResolvedId) {
            Write-PSFMessage -Level 8 -Message (
                "Get-FullUserObject: Skipping item - could not resolve an Id " +
                "(ParameterSetName: $($PSCmdlet.ParameterSetName)).")
            return
        }

        Write-PSFMessage -Level 8 -Message (
            "Get-FullUserObject: Fetching full object for '$ResolvedId'.")

        # get base user with wide $select
        $GetParams = @{
            UserId      = $ResolvedId
            Property    = $SelectProps
            ErrorAction = 'Stop'
        }

        try {
            $ScriptUserObject = Get-MgUser @GetParams
        }
        catch {
            Write-Error "Get-MgUser failed for '$ResolvedId': $($_.Exception.Message)"
            if ($PSCmdlet.ParameterSetName -eq 'ByObject' -and $ScriptUserObject) {
                Write-Output $ScriptUserObject
            }
            return
        }

        # augment with optional properties (best-effort)
        foreach ($Property in $OptionalProps) {
            Write-PSFMessage -Level 9 -Message (
                "Get-FullUserObject: Fetching optional property '$Property' for '$ResolvedId'.")
            try {
                $OptionalParams = @{
                    UserId      = $ResolvedId
                    Property    = $Property
                    ErrorAction = 'Stop'
                }
                $TempUserObject = Get-MgUser @OptionalParams
                $ScriptUserObject.$Property = $TempUserObject.$Property
            }
            catch {
                $ErrMsg = "Unable to retrieve property '$Property' for '$ResolvedId': " +
                $_.Exception.Message
                Write-PSFMessage -Level 8 -Message "Get-FullUserObject: $ErrMsg"
            }
        }

        # add property indicating object has all properties.
        $AmParams = @{
            NotePropertyName  = 'AllProperties'
            NotePropertyValue = $true
            Force             = $true
        }
        $ScriptUserObject | Add-Member @AmParams

        Write-Output $ScriptUserObject
    }
}
