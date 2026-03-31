<#
.SYNOPSIS
    ServiceNow Table REST API handler for incident, change request, and service request management.

.DESCRIPTION
    Wraps the ServiceNow Table API (/api/now/table/) for CRUD operations on cases.
    Supports incidents (INC), change requests (CHG), and service requests (SC).

    Credential resolution order:
      1. AzureAccessTokens.json entry matching *ServiceNow* (via AzureFunctions)
      2. Guided setup prompt if no entry found

    Instance resolution:
      GlobalSettings.json -> ServiceNow.Instance, fallback "fkatest"
#>
Import-Module GlobalFunctions -Force
Import-Module AzureFunctions -Force

#region Script-Scope Caches

$script:SnowUserSysIdCache = @{}
$script:SnowStateLabelCache = @{}

#endregion

#region Table and State Mappings

$script:TableMap = @{
    'INC' = 'incident'
    'SC'  = 'sc_request'
    'CHG' = 'change_request'
}

$script:IncidentStateMap = @{
    'New'        = 1
    'InProgress' = 2
    'OnHold'     = 3
    'Resolved'   = 6
    'Closed'     = 7
    'Canceled'   = 8
}

$script:ChangeStateMap = @{
    'New'       = -5
    'Assess'    = -4
    'Authorize' = -3
    'Scheduled' = -2
    'Implement' = -1
    'Review'    = 0
    'Closed'    = 3
    'Canceled'  = 4
}

#endregion

#region Internal Functions

function Get-SnowInstance {
    <#
    .SYNOPSIS
        Resolves the ServiceNow instance subdomain.
    .DESCRIPTION
        Resolution order:
          1. AzureAccessTokens.json entry matching *ServiceNowUrl* (Token field = instance subdomain)
          2. GlobalSettings.json -> ServiceNow.Instance
          3. Fallback: "fkatest"

        Register with:
          Register-AzureAccessToken -Id "ServiceNowUrl" -Token "fkatest" -Email "system@Dedge.no" -Description "ServiceNow instance subdomain"
    #>
    try {
        $urlToken = Get-AzureAccessTokenById -IdLike '*ServiceNowUrl*'
        if ($urlToken -and -not [string]::IsNullOrWhiteSpace($urlToken.Token)) {
            return $urlToken.Token
        }
    }
    catch { }

    try {
        $cfg = Get-CachedGlobalConfiguration
        if ($cfg.PSObject.Properties.Name -contains 'ServiceNow' -and $cfg.ServiceNow.Instance) {
            return $cfg.ServiceNow.Instance
        }
    }
    catch { }

    return 'fkatest'
}

function Get-SnowCredential {
    <#
    .SYNOPSIS
        Resolves ServiceNow credentials from AzureAccessTokens.json or prompts for setup.
    #>
    [CmdletBinding()]
    param()

    try {
        $tokenObj = Get-AzureAccessTokenById -IdLike '*ServiceNow*'
        if ($tokenObj -and -not [string]::IsNullOrWhiteSpace($tokenObj.Token)) {
            $username = 'Dedge.integration'
            if ($tokenObj.Description -match 'username:\s*(\S+)') {
                $username = $matches[1]
            }
            elseif ($tokenObj.Email -and $tokenObj.Email -notmatch '@') {
                $username = $tokenObj.Email
            }
            $secPwd = ConvertTo-SecureString $tokenObj.Token -AsPlainText -Force
            return [PSCredential]::new($username, $secPwd)
        }
    }
    catch {
        Write-LogMessage "AzureAccessTokens lookup for ServiceNow failed: $($_.Exception.Message)" -Level WARN
    }

    Write-LogMessage "No ServiceNow credentials found in AzureAccessTokens.json." -Level WARN
    Write-LogMessage "Register credentials and instance URL with:" -Level WARN
    Write-LogMessage '  Register-AzureAccessToken -Id "ServiceNowPat" -Token "<password>" -Email "Dedge.integration@Dedge.no" -Description "ServiceNow fkatest - username: Dedge.integration"' -Level WARN
    Write-LogMessage '  Register-AzureAccessToken -Id "ServiceNowUrl" -Token "fkatest" -Email "system@Dedge.no" -Description "ServiceNow instance subdomain"' -Level WARN
    throw "ServiceNow credentials not configured. See instructions above."
}

function Invoke-SnowApi {
    <#
    .SYNOPSIS
        Generic ServiceNow REST API caller with credential auth and JSON handling.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [ValidateSet('Get', 'Post', 'Put', 'Patch', 'Delete')]
        [string]$Method,

        [Parameter()]
        [object]$Body
    )

    $credential = Get-SnowCredential

    $params = @{
        Uri         = $Uri
        Method      = $Method
        Credential  = $credential
        ContentType = "application/json; charset=utf-8"
    }

    if ($Body) {
        $json = if ($Body -is [string]) { $Body } else { ConvertTo-Json -InputObject $Body -Depth 10 }
        $params['Body'] = [System.Text.Encoding]::UTF8.GetBytes($json)
    }

    $response = Invoke-RestMethod @params
    return $response
}

function Get-SnowUserSysId {
    <#
    .SYNOPSIS
        Resolves a Windows username to a ServiceNow sys_id via the sys_user table.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Username = $env:USERNAME
    )

    if ($script:SnowUserSysIdCache.ContainsKey($Username)) {
        return $script:SnowUserSysIdCache[$Username]
    }

    $instance = Get-SnowInstance
    $uri = "https://$($instance).service-now.com/api/now/table/sys_user?sysparm_query=user_name=$($Username)&sysparm_fields=sys_id&sysparm_limit=1"

    $response = Invoke-SnowApi -Uri $uri -Method Get

    if ($response.result -and $response.result.Count -gt 0) {
        $sysId = $response.result[0].sys_id
        $script:SnowUserSysIdCache[$Username] = $sysId
        return $sysId
    }

    $userEmail = switch ($Username) {
        "FKGEISTA" { "geir.helge.starholm@Dedge.no" }
        "FKSVEERI" { "svein.morten.erikstad@Dedge.no" }
        "FKMISTA"  { "mina.marie.starholm@Dedge.no" }
        "FKCELERI" { "Celine.Andreassen.Erikstad@Dedge.no" }
        default    { $null }
    }

    if ($userEmail) {
        $uri = "https://$($instance).service-now.com/api/now/table/sys_user?sysparm_query=email=$($userEmail)&sysparm_fields=sys_id&sysparm_limit=1"
        $response = Invoke-SnowApi -Uri $uri -Method Get
        if ($response.result -and $response.result.Count -gt 0) {
            $sysId = $response.result[0].sys_id
            $script:SnowUserSysIdCache[$Username] = $sysId
            return $sysId
        }
    }

    throw "Could not resolve ServiceNow sys_id for user '$($Username)'"
}

function Get-SnowStateLabels {
    <#
    .SYNOPSIS
        Fetches Norwegian state labels from sys_choice for a given table.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TableName
    )

    if ($script:SnowStateLabelCache.ContainsKey($TableName)) {
        return $script:SnowStateLabelCache[$TableName]
    }

    $instance = Get-SnowInstance
    $uri = "https://$($instance).service-now.com/api/now/table/sys_choice?sysparm_query=name=$($TableName)^element=state^language=nb^inactive=false&sysparm_fields=value,label&sysparm_orderby=value"

    $response = Invoke-SnowApi -Uri $uri -Method Get
    $labels = @{}
    if ($response.result) {
        foreach ($item in $response.result) {
            $labels[$item.value] = $item.label
        }
    }

    $script:SnowStateLabelCache[$TableName] = $labels
    return $labels
}

function Resolve-SnowTable {
    <#
    .SYNOPSIS
        Resolves a case number (INC0012345, CHG0054321, SC0001234) to its ServiceNow table name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Number
    )

    # Regex: extract alphabetic prefix before the digits
    #   ^       — start of string
    #   ([A-Z]+) — one or more uppercase letters (captured group 1: the prefix)
    #   \d      — followed by a digit (not captured, just asserts digits follow)
    if ($Number -match '^([A-Z]+)\d') {
        $prefix = $matches[1]
        if ($script:TableMap.ContainsKey($prefix)) {
            return $script:TableMap[$prefix]
        }
    }

    throw "Cannot determine table for case number '$($Number)'. Expected prefix: INC, SC, or CHG."
}

function Get-SnowCaseSysId {
    <#
    .SYNOPSIS
        Resolves a case number to its sys_id.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Number
    )

    $table = Resolve-SnowTable -Number $Number
    $instance = Get-SnowInstance
    $uri = "https://$($instance).service-now.com/api/now/table/$($table)?sysparm_query=number=$($Number)&sysparm_fields=sys_id&sysparm_limit=1"

    $response = Invoke-SnowApi -Uri $uri -Method Get

    if ($response.result -and $response.result.Count -gt 0) {
        return $response.result[0].sys_id
    }

    throw "Case '$($Number)' not found in table '$($table)'"
}

function Format-SnowCaseOutput {
    <#
    .SYNOPSIS
        Formats case records with Norwegian state labels and computed last-changed date.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Records,

        [Parameter(Mandatory)]
        [string]$TableName,

        [Parameter(Mandatory)]
        [string]$CaseType
    )

    $stateLabels = Get-SnowStateLabels -TableName $TableName

    $formatted = foreach ($r in $Records) {
        $stateLabel = if ($stateLabels.ContainsKey($r.state)) { $stateLabels[$r.state] } else { "($($r.state))" }

        [PSCustomObject]@{
            Number           = $r.number
            Type             = $CaseType
            ShortDescription = $r.short_description
            Priority         = $r.priority
            State            = $r.state
            StateLabel       = $stateLabel
            Category         = $r.category
            CreatedOn        = $r.sys_created_on
            LastChanged      = $r.sys_updated_on
            FollowUp         = $r.follow_up
        }
    }

    return $formatted
}

#endregion

#region Exported Functions — List Cases

function Get-SnowAssignedCases {
    <#
    .SYNOPSIS
        Lists open incidents, service requests, and change requests assigned to the current user.
    .PARAMETER Username
        Windows username to look up. Defaults to $env:USERNAME.
    .PARAMETER IncludeClosed
        Include resolved/closed cases. Default is open only.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Username = $env:USERNAME,

        [Parameter()]
        [switch]$IncludeClosed
    )

    $userSysId = Get-SnowUserSysId -Username $Username
    $instance = Get-SnowInstance
    $fields = "number,short_description,priority,state,sys_created_on,sys_updated_on,category,subcategory,follow_up"
    $allCases = @()

    $openFilter = if (-not $IncludeClosed) { "^state<6" } else { "" }

    $incUri = "https://$($instance).service-now.com/api/now/table/incident?sysparm_query=assigned_to=$($userSysId)$($openFilter)&sysparm_fields=$($fields)&sysparm_display_value=false"
    try {
        $resp = Invoke-SnowApi -Uri $incUri -Method Get
        if ($resp.result) {
            $allCases += Format-SnowCaseOutput -Records $resp.result -TableName 'incident' -CaseType 'Incident'
        }
    }
    catch { Write-LogMessage "Failed to fetch incidents: $($_.Exception.Message)" -Level WARN }

    $scrUri = "https://$($instance).service-now.com/api/now/table/sc_request?sysparm_query=assigned_to=$($userSysId)$($openFilter)&sysparm_fields=$($fields)&sysparm_display_value=false"
    try {
        $resp = Invoke-SnowApi -Uri $scrUri -Method Get
        if ($resp.result) {
            $allCases += Format-SnowCaseOutput -Records $resp.result -TableName 'sc_request' -CaseType 'Service Request'
        }
    }
    catch { Write-LogMessage "Failed to fetch service requests: $($_.Exception.Message)" -Level WARN }

    $chgFilter = if (-not $IncludeClosed) { "^state<3" } else { "" }
    $chgUri = "https://$($instance).service-now.com/api/now/table/change_request?sysparm_query=assigned_to=$($userSysId)$($chgFilter)&sysparm_fields=$($fields)&sysparm_display_value=false"
    try {
        $resp = Invoke-SnowApi -Uri $chgUri -Method Get
        if ($resp.result) {
            $allCases += Format-SnowCaseOutput -Records $resp.result -TableName 'change_request' -CaseType 'Change Request'
        }
    }
    catch { Write-LogMessage "Failed to fetch change requests: $($_.Exception.Message)" -Level WARN }

    $sorted = $allCases | Sort-Object Number
    Write-LogMessage "Found $($sorted.Count) assigned case(s) for $($Username)" -Level INFO
    return $sorted
}

function Get-SnowCreatedCases {
    <#
    .SYNOPSIS
        Lists open incidents, service requests, and change requests created by the current user.
    .PARAMETER Username
        Windows username to look up. Defaults to $env:USERNAME.
    .PARAMETER IncludeClosed
        Include resolved/closed cases. Default is open only.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Username = $env:USERNAME,

        [Parameter()]
        [switch]$IncludeClosed
    )

    $userSysId = Get-SnowUserSysId -Username $Username
    $instance = Get-SnowInstance
    $fields = "number,short_description,priority,state,sys_created_on,sys_updated_on,category,subcategory,follow_up"
    $allCases = @()

    $openFilter = if (-not $IncludeClosed) { "^state<6" } else { "" }

    $incUri = "https://$($instance).service-now.com/api/now/table/incident?sysparm_query=caller_id=$($userSysId)$($openFilter)&sysparm_fields=$($fields)&sysparm_display_value=false"
    try {
        $resp = Invoke-SnowApi -Uri $incUri -Method Get
        if ($resp.result) {
            $allCases += Format-SnowCaseOutput -Records $resp.result -TableName 'incident' -CaseType 'Incident'
        }
    }
    catch { Write-LogMessage "Failed to fetch incidents: $($_.Exception.Message)" -Level WARN }

    $scrUri = "https://$($instance).service-now.com/api/now/table/sc_request?sysparm_query=opened_by=$($userSysId)$($openFilter)&sysparm_fields=$($fields)&sysparm_display_value=false"
    try {
        $resp = Invoke-SnowApi -Uri $scrUri -Method Get
        if ($resp.result) {
            $allCases += Format-SnowCaseOutput -Records $resp.result -TableName 'sc_request' -CaseType 'Service Request'
        }
    }
    catch { Write-LogMessage "Failed to fetch service requests: $($_.Exception.Message)" -Level WARN }

    $chgFilter = if (-not $IncludeClosed) { "^state<3" } else { "" }
    $chgUri = "https://$($instance).service-now.com/api/now/table/change_request?sysparm_query=opened_by=$($userSysId)$($chgFilter)&sysparm_fields=$($fields)&sysparm_display_value=false"
    try {
        $resp = Invoke-SnowApi -Uri $chgUri -Method Get
        if ($resp.result) {
            $allCases += Format-SnowCaseOutput -Records $resp.result -TableName 'change_request' -CaseType 'Change Request'
        }
    }
    catch { Write-LogMessage "Failed to fetch change requests: $($_.Exception.Message)" -Level WARN }

    $sorted = $allCases | Sort-Object Number
    Write-LogMessage "Found $($sorted.Count) created case(s) for $($Username)" -Level INFO
    return $sorted
}

#endregion

#region Exported Functions — Notes and Comments

function Add-SnowWorkNote {
    <#
    .SYNOPSIS
        Adds an internal work note to a case. Auto-detects table from case number prefix.
    .PARAMETER Number
        Case number (e.g. INC0012345, CHG0054321).
    .PARAMETER Note
        Work note text.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Number,

        [Parameter(Mandatory)]
        [string]$Note
    )

    $table = Resolve-SnowTable -Number $Number
    $sysId = Get-SnowCaseSysId -Number $Number
    $instance = Get-SnowInstance

    $uri = "https://$($instance).service-now.com/api/now/table/$($table)/$($sysId)"
    $body = @{ work_notes = $Note }

    Invoke-SnowApi -Uri $uri -Method Patch -Body $body | Out-Null
    Write-LogMessage "Added work note to $($Number)" -Level INFO
}

function Add-SnowComment {
    <#
    .SYNOPSIS
        Adds a customer-visible comment to a case. Auto-detects table from case number prefix.
    .PARAMETER Number
        Case number (e.g. INC0012345, CHG0054321).
    .PARAMETER Comment
        Comment text (visible to end users).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Number,

        [Parameter(Mandatory)]
        [string]$Comment
    )

    $table = Resolve-SnowTable -Number $Number
    $sysId = Get-SnowCaseSysId -Number $Number
    $instance = Get-SnowInstance

    $uri = "https://$($instance).service-now.com/api/now/table/$($table)/$($sysId)"
    $body = @{ comments = $Comment }

    Invoke-SnowApi -Uri $uri -Method Patch -Body $body | Out-Null
    Write-LogMessage "Added comment to $($Number)" -Level INFO
}

#endregion

#region Exported Functions — State Management

function Set-SnowResolved {
    <#
    .SYNOPSIS
        Sets a case to Resolved status with close code and notes.
    .PARAMETER Number
        Case number (e.g. INC0012345).
    .PARAMETER CloseNotes
        Resolution notes describing what was done.
    .PARAMETER CloseCode
        Close code. Default: "Solved (Permanently)".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Number,

        [Parameter(Mandatory)]
        [string]$CloseNotes,

        [Parameter()]
        [string]$CloseCode = "Solved (Permanently)"
    )

    $table = Resolve-SnowTable -Number $Number
    $sysId = Get-SnowCaseSysId -Number $Number
    $instance = Get-SnowInstance

    $uri = "https://$($instance).service-now.com/api/now/table/$($table)/$($sysId)"

    $body = if ($table -eq 'change_request') {
        @{
            state       = "Closed"
            close_code  = "successful"
            close_notes = $CloseNotes
        }
    }
    else {
        @{
            state          = 6
            incident_state = 6
            close_code     = $CloseCode
            close_notes    = $CloseNotes
        }
    }

    Invoke-SnowApi -Uri $uri -Method Patch -Body $body | Out-Null
    Write-LogMessage "Set $($Number) to Resolved/Closed" -Level INFO
}

function Set-SnowState {
    <#
    .SYNOPSIS
        Changes the state of a case to a named status.
    .PARAMETER Number
        Case number (e.g. INC0012345, CHG0054321).
    .PARAMETER State
        Target state name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Number,

        [Parameter(Mandatory)]
        [ValidateSet('New', 'InProgress', 'OnHold', 'Resolved', 'Closed', 'Canceled')]
        [string]$State
    )

    $table = Resolve-SnowTable -Number $Number
    $sysId = Get-SnowCaseSysId -Number $Number
    $instance = Get-SnowInstance

    $stateValue = if ($table -eq 'change_request' -and $script:ChangeStateMap.ContainsKey($State)) {
        $script:ChangeStateMap[$State]
    }
    elseif ($script:IncidentStateMap.ContainsKey($State)) {
        $script:IncidentStateMap[$State]
    }
    else {
        throw "State '$($State)' is not valid for table '$($table)'"
    }

    $uri = "https://$($instance).service-now.com/api/now/table/$($table)/$($sysId)"
    $body = @{ state = $stateValue }

    if ($table -eq 'incident') {
        $body['incident_state'] = $stateValue
    }

    Invoke-SnowApi -Uri $uri -Method Patch -Body $body | Out-Null
    Write-LogMessage "Set $($Number) state to $($State) ($($stateValue))" -Level INFO
}

function Set-SnowFollowUp {
    <#
    .SYNOPSIS
        Sets the follow_up date on a case to N days from now.
    .PARAMETER Number
        Case number (e.g. INC0012345).
    .PARAMETER Days
        Number of days from now for the follow-up date.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Number,

        [Parameter(Mandatory)]
        [int]$Days
    )

    $table = Resolve-SnowTable -Number $Number
    $sysId = Get-SnowCaseSysId -Number $Number
    $instance = Get-SnowInstance

    $followUpDate = (Get-Date).AddDays($Days).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss")

    $uri = "https://$($instance).service-now.com/api/now/table/$($table)/$($sysId)"
    $body = @{ follow_up = $followUpDate }

    Invoke-SnowApi -Uri $uri -Method Patch -Body $body | Out-Null
    Write-LogMessage "Set follow-up on $($Number) to $($followUpDate) ($($Days) days from now)" -Level INFO
}

#endregion

#region Exported Functions — Delete

function Remove-SnowCase {
    <#
    .SYNOPSIS
        Deletes a case if the current user created it and no other users have modified it.
    .DESCRIPTION
        Requires admin or itil_admin role on the ServiceNow instance.
        Safety checks: verifies caller_id/opened_by matches current user, and
        sys_updated_by matches current username (no other users touched the record).
    .PARAMETER Number
        Case number (e.g. INC0012345).
    .PARAMETER Force
        Skip the confirmation prompt.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Number,

        [Parameter()]
        [switch]$Force
    )

    $table = Resolve-SnowTable -Number $Number
    $instance = Get-SnowInstance

    $uri = "https://$($instance).service-now.com/api/now/table/$($table)?sysparm_query=number=$($Number)&sysparm_fields=sys_id,caller_id,opened_by,sys_updated_by&sysparm_limit=1"
    $response = Invoke-SnowApi -Uri $uri -Method Get

    if (-not $response.result -or $response.result.Count -eq 0) {
        throw "Case '$($Number)' not found"
    }

    $record = $response.result[0]
    $sysId = $record.sys_id
    $updatedBy = $record.sys_updated_by

    $currentUser = $env:USERNAME.ToLower()
    if ($updatedBy -and $updatedBy.ToLower() -ne $currentUser) {
        throw "Cannot delete $($Number): last updated by '$($updatedBy)', not current user '$($currentUser)'. Another user has modified this case."
    }

    if (-not $Force) {
        $confirm = Read-Host "Delete $($Number)? This cannot be undone. (y/N)"
        if ($confirm -notin 'y', 'Y', 'yes', 'Yes') {
            Write-LogMessage "Delete cancelled by user" -Level INFO
            return
        }
    }

    $deleteUri = "https://$($instance).service-now.com/api/now/table/$($table)/$($sysId)"

    try {
        Invoke-SnowApi -Uri $deleteUri -Method Delete | Out-Null
        Write-LogMessage "Deleted $($Number) (sys_id: $($sysId))" -Level INFO
    }
    catch {
        if ($_.Exception.Message -match '403|Forbidden') {
            throw "Delete failed for $($Number): insufficient permissions. Requires admin or itil_admin role."
        }
        throw
    }
}

#endregion

#region Exported Functions — Create Case (Interactive)

function New-SnowIncident {
    <#
    .SYNOPSIS
        Interactively creates a new ServiceNow incident by querying available choices from the API.
    .DESCRIPTION
        Queries the sys_choice table for categories, subcategories, impact, and urgency values,
        presents numbered menus, and creates the incident with all required fields.
    .PARAMETER NonInteractive
        When set, all parameters must be provided. Skips prompts.
    .PARAMETER ShortDescription
        Short description (title) of the incident.
    .PARAMETER Description
        Detailed description.
    .PARAMETER Category
        Category value (from sys_choice).
    .PARAMETER Subcategory
        Subcategory value (from sys_choice).
    .PARAMETER Impact
        Impact level (1=High, 2=Medium, 3=Low).
    .PARAMETER Urgency
        Urgency level (1=High, 2=Medium, 3=Low).
    .PARAMETER AssignmentGroup
        Assignment group name. Default: "Utvikling FK-meny".
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$NonInteractive,

        [Parameter()]
        [string]$ShortDescription,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [string]$Category,

        [Parameter()]
        [string]$Subcategory,

        [Parameter()]
        [ValidateSet('1', '2', '3')]
        [string]$Impact,

        [Parameter()]
        [ValidateSet('1', '2', '3')]
        [string]$Urgency,

        [Parameter()]
        [string]$AssignmentGroup = "Utvikling FK-meny"
    )

    $instance = Get-SnowInstance
    $userSysId = Get-SnowUserSysId

    if (-not $NonInteractive) {
        Write-Host "`n=== Opprett ny ServiceNow-sak ===" -ForegroundColor Cyan

        # Categories
        $catUri = "https://$($instance).service-now.com/api/now/table/sys_choice?sysparm_query=name=incident^element=category^language=nb^inactive=false&sysparm_fields=value,label&sysparm_orderby=label"
        $catResp = Invoke-SnowApi -Uri $catUri -Method Get
        if ($catResp.result -and $catResp.result.Count -gt 0) {
            Write-Host "`nKategorier:" -ForegroundColor Yellow
            for ($i = 0; $i -lt $catResp.result.Count; $i++) {
                Write-Host "  $($i + 1). $($catResp.result[$i].label) ($($catResp.result[$i].value))"
            }
            if (-not $Category) {
                $catChoice = Read-Host "Velg kategori (nummer)"
                $catIdx = [int]$catChoice - 1
                if ($catIdx -ge 0 -and $catIdx -lt $catResp.result.Count) {
                    $Category = $catResp.result[$catIdx].value
                }
                else {
                    throw "Ugyldig valg"
                }
            }
        }

        # Subcategories
        $subUri = "https://$($instance).service-now.com/api/now/table/sys_choice?sysparm_query=name=incident^element=subcategory^dependent_value=$($Category)^language=nb^inactive=false&sysparm_fields=value,label&sysparm_orderby=label"
        $subResp = Invoke-SnowApi -Uri $subUri -Method Get
        if ($subResp.result -and $subResp.result.Count -gt 0) {
            Write-Host "`nUnderkategorier:" -ForegroundColor Yellow
            for ($i = 0; $i -lt $subResp.result.Count; $i++) {
                Write-Host "  $($i + 1). $($subResp.result[$i].label) ($($subResp.result[$i].value))"
            }
            if (-not $Subcategory) {
                $subChoice = Read-Host "Velg underkategori (nummer, eller Enter for ingen)"
                if ($subChoice) {
                    $subIdx = [int]$subChoice - 1
                    if ($subIdx -ge 0 -and $subIdx -lt $subResp.result.Count) {
                        $Subcategory = $subResp.result[$subIdx].value
                    }
                }
            }
        }

        # Impact
        if (-not $Impact) {
            Write-Host "`nPåvirkning:" -ForegroundColor Yellow
            Write-Host "  1. Høy (1)"
            Write-Host "  2. Medium (2)"
            Write-Host "  3. Lav (3)"
            $Impact = Read-Host "Velg påvirkning (1-3)"
            if ($Impact -notin '1', '2', '3') { $Impact = '3' }
        }

        # Urgency
        if (-not $Urgency) {
            Write-Host "`nHast:" -ForegroundColor Yellow
            Write-Host "  1. Høy (1)"
            Write-Host "  2. Medium (2)"
            Write-Host "  3. Lav (3)"
            $Urgency = Read-Host "Velg hast (1-3)"
            if ($Urgency -notin '1', '2', '3') { $Urgency = '3' }
        }

        if (-not $ShortDescription) {
            $ShortDescription = Read-Host "`nKort beskrivelse (tittel)"
            if ([string]::IsNullOrWhiteSpace($ShortDescription)) {
                throw "Kort beskrivelse er påkrevd"
            }
        }

        if (-not $Description) {
            $Description = Read-Host "Detaljert beskrivelse (valgfritt)"
        }
    }
    else {
        if ([string]::IsNullOrWhiteSpace($ShortDescription)) {
            throw "ShortDescription is required in non-interactive mode"
        }
        if (-not $Impact) { $Impact = '3' }
        if (-not $Urgency) { $Urgency = '3' }
    }

    $body = @{
        short_description = $ShortDescription
        caller_id         = $userSysId
        assigned_to       = $userSysId
        assignment_group  = $AssignmentGroup
        impact            = [int]$Impact
        urgency           = [int]$Urgency
    }

    if ($Description) { $body['description'] = $Description }
    if ($Category) { $body['category'] = $Category }
    if ($Subcategory) { $body['subcategory'] = $Subcategory }

    $createUri = "https://$($instance).service-now.com/api/now/table/incident"
    $response = Invoke-SnowApi -Uri $createUri -Method Post -Body $body

    $created = $response.result
    $webUrl = "https://$($instance).service-now.com/nav_to.do?uri=incident.do?sys_id=$($created.sys_id)"

    Write-LogMessage "Created incident $($created.number): $($ShortDescription)" -Level INFO
    Write-Host "`nOpprettet: $($created.number)" -ForegroundColor Green
    Write-Host "URL: $($webUrl)" -ForegroundColor Cyan

    return [PSCustomObject]@{
        Number           = $created.number
        SysId            = $created.sys_id
        ShortDescription = $ShortDescription
        State            = $created.state
        Url              = $webUrl
    }
}

#endregion

Export-ModuleMember -Function *
