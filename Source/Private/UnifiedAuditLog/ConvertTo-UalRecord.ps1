function ConvertTo-UalRecord {
    <#
    .SYNOPSIS
    Converts a Graph audit log record into the record shape Show-IRTUnifiedAuditLog expects.

    .DESCRIPTION
    Internal helper. The Graph audit search API and Search-UnifiedAuditLog return the same
    events in different shapes. Rather than teach every sheet builder a second shape, the
    Graph record is translated here into the classic one, so Show-IRTUnifiedAuditLog and
    everything under Build-*Sheet keep working untouched.

    Property mapping:

        Identity     <- id
        CreationDate <- createdDateTime, as UTC [datetime]
        RecordType   <- auditLogRecordType (already PascalCase, matching the classic value)
        Operations   <- operation
        UserIds      <- userPrincipalName, falling back to userId
        AuditData    <- auditData, serialized to a JSON string

    Two details matter.

    AuditData is emitted as a JSON string rather than an object because
    Show-IRTUnifiedAuditLog runs ConvertFrom-Json over every row's AuditData. Handing it
    a string keeps that path identical to the Search-UnifiedAuditLog path.

    Graph decorates auditData with OData annotation keys ('@odata.type',
    'Actor@odata.type', 'RecordType@odata.type' and so on) that the classic API does not
    emit. They are stripped recursively, otherwise they would surface in the workbook's
    Raw column and add noise to every row.

    Extra Graph-only properties (UserType, Service, ClientIp, ObjectId,
    OrganizationId) are carried through. The sheet builders ignore them; they are useful
    when reading the raw objects directly.

    .PARAMETER Record
    One Graph audit log record, as returned by the records endpoint.

    .EXAMPLE
    ```powershell
    $Legacy = $GraphRecords | ForEach-Object { ConvertTo-UalRecord -Record $_ }
    ```
    Converts a page of Graph records for handoff to Show-IRTUnifiedAuditLog.

    .OUTPUTS
    [pscustomobject] in the Search-UnifiedAuditLog record shape.

    .NOTES
    Version: 1.0.0
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $Record
    )

    process {
        # CreationDate feeds .ToLocalTime() in the sheet builders and a [datetime]
        # comparison in the sort, so it has to be a real DateTime, not a string.
        $Created = $null
        if ($Record.createdDateTime) {
            try {
                $Created = ([datetime]$Record.createdDateTime).ToUniversalTime()
            }
            catch {
                $Created = $null
            }
        }

        # UserIds drives the actor column and the service principal detection in
        # Build-AllOperationSheet, which expects a UPN or a ServicePrincipal_ string.
        $UserIds = $Record.userPrincipalName
        if (-not $UserIds) { $UserIds = $Record.userId }

        $AuditData = Remove-ODataAnnotation -InputObject $Record.auditData
        $AuditDataJson = $null
        if ($null -ne $AuditData) {
            $AuditDataJson = $AuditData | ConvertTo-Json -Depth 10 -Compress
        }

        return [pscustomobject]@{
            Identity       = [string]$Record.id
            CreationDate   = $Created
            RecordType     = [string]$Record.auditLogRecordType
            Operations     = [string]$Record.operation
            UserIds        = [string]$UserIds
            AuditData      = $AuditDataJson
            UserType       = [string]$Record.userType
            Service        = [string]$Record.service
            ClientIp       = [string]$Record.clientIp
            ObjectId       = [string]$Record.objectId
            OrganizationId = [string]$Record.organizationId
        }
    }
}
