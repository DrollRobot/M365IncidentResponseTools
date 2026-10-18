function Get-FullUserObject {
    <#
    .SYNOPSIS
    retrieves a user with a broad set of properties and augments with optional ones.

    .NOTES
    version: 1.1.0
    - fetch the optional properties in one Graph batch request instead of one request
      each; drop deviceEnrollmentLimit and print, which aren't v1.0 user properties
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
        $ImportParams = @{
            Name = 'Microsoft.Graph.Authentication', 'Microsoft.Graph.Users', 'PSFramework'
        }
        Import-IRTModule @ImportParams
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

        # properties that may error depending on licensing/mailbox/etc. A $select naming
        # one the user or tenant doesn't have fails the whole request, so each is asked
        # for separately. A Graph batch request takes at most 20.
        $OptionalProps = @(
            'aboutMe', 'birthday', 'hireDate', 'interests', 'mailboxSettings',
            'mailFolders', 'mySite', 'pastProjects', 'preferredName', 'responsibilities',
            'schools', 'skills'
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

        # augment with optional properties (best-effort), one request per property sent
        # together in a single batch. Each comes back with its own status, so a property
        # the user or tenant doesn't have is just a failed entry, which is expected.
        $Requests = for ($Index = 0; $Index -lt $OptionalProps.Count; $Index++) {
            @{
                id     = [string]$Index
                method = 'GET'
                url    = "/users/$($ScriptUserObject.Id)?`$select=$($OptionalProps[$Index])"
            }
        }
        $BatchParams = @{
            Method      = 'POST'
            Uri         = 'v1.0/$batch'
            Body        = @{ requests = @($Requests) } | ConvertTo-Json -Depth 5
            ContentType = 'application/json'
            ErrorAction = 'Stop'
        }
        Write-PSFMessage -Level 8 -Message (
            "Get-FullUserObject: Fetching $($OptionalProps.Count) optional properties " +
            "for '$ResolvedId' in one batch.")
        $Responses = @()
        try {
            $Responses = @((Invoke-MgGraphRequest @BatchParams).responses)
        }
        catch {
            # FIXME: temporary workaround. A failed batch, unlike a failed property,
            # isn't a normal per-user condition, but it can't be classified yet.
            $SuppressParams = @{
                ErrorRecord = $_
                Message     = "Optional property batch failed for '$ResolvedId'"
            }
            Write-IRTSuppressedError @SuppressParams
        }

        foreach ($Response in $Responses) {
            $Property = $OptionalProps[[int]$Response.id]
            $HasValue = $Response.status -eq 200 -and $Response.body -and
            $Response.body.ContainsKey($Property)
            if (-not $HasValue) {
                Write-PSFMessage -Level 8 -Message (
                    "Get-FullUserObject: Unable to retrieve property '$Property' for " +
                    "'$ResolvedId' (HTTP $($Response.status)): " +
                    "$($Response.body.error.message)")
                continue
            }
            try {
                $ScriptUserObject.$Property = $Response.body[$Property]
            }
            catch {
                Write-PSFMessage -Level 8 -Message (
                    "Get-FullUserObject: Unable to set property '$Property' for " +
                    "'$ResolvedId': $($_.Exception.Message)")
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
