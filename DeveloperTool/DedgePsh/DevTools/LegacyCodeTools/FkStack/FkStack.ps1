param(
    [string]$inputString = "",
    [string]$deployEnv = "PRD",
    [string]$changeDescription = "",
    [string]$serviceNowId = "",
    [string]$immediateDeploy = "N")

################################################################################################################################################
# Function definitions
################################################################################################################################################
$global:servicenow_web_url = ""

function ImmediateDeployFiles ($deployEnvItem) {
    if (!(Test-Path -Path $global:stackPath)) {
        New-Item -ItemType Directory -Path $global:stackPath -ErrorAction SilentlyContinue | Out-Null
    }

    $tempDeployPath = $global:tempPath + '\DEP'

    xcopy.exe $tempDeployPath $global:stackPathEnv /E /Y /I
}

function GetDeployEnvDesc ($deployEnvItem) {

    if ($deployEnvItem -eq 'PRD') {
        return "BASISPRO - Produksjonsmiljø for Fk-Meny"
    }
    elseif ($deployEnvItem -eq 'TST') {
        return "BASISTST - Testmiljø generelt"
    }
    elseif ($deployEnvItem -eq 'MIG') {
        return "BASISMIG - Testmiljø for migrering D365"
    }
    elseif ($deployEnvItem -eq 'VFT') {
        return "BASISVFT - Testmiljø for vareforsyning test"
    }
    elseif ($deployEnvItem -eq 'VFK') {
        return "BASISVFK - Testmiljø for vareforsyning akseptansetest"
    }
    elseif ($deployEnvItem -eq 'SIT') {
        return "BASISSIT - Testmiljø for vareforsyning test"
    }
    return ""
}

function BuildDeployEnvString () {
    if ($global:immediateDeploy -eq $true) {
        $deployEnvString = "Endringen er gjennomført og overføres til følgende miljøer UMIDDELBART:"
    }
    else {
        $deployEnvString = "Endringen er gjennomført og overføres til følgende miljøer etter midnatt:"
    }

    foreach ($deployEnvItem in $global:deployEnv) {
        $deployEnvString += "`n" + '- ' + $(GetDeployEnvDesc $deployEnvItem)
    }
    return $deployEnvString
}

function MoveFilesToStackFolder () {
    if (!(Test-Path -Path $global:stackPath)) {
        New-Item -ItemType Directory -Path $global:stackPath -ErrorAction SilentlyContinue | Out-Null
    }

    $tempDeployPath = $global:tempPath + '\DEP'

    xcopy.exe $tempDeployPath $global:stackPathEnv /E /Y /I
}

function LogMessage ($message, $severity = "INFO", $skipConsole = $false) {
    $scriptName = $MyInvocation.ScriptName.Split("\")[$MyInvocation.ScriptName.Split("\").Length - 1].Replace(".ps1", "").Replace(".PS1", "")

    if ($message.StartsWith("-->") -or $message.StartsWith("==>") -or $message.StartsWith("**>")) {
        $logfileMessage = $message.Substring(3)
    }
    else {
        $logfileMessage = $message
    }

    if ($message.StartsWith("**>")) {
        $severity = "ERROR"
    }

    $dt = get-date -Format("yyyy-MM-dd HH:mm:ss,ffff").ToString()

    $logmsg = $dt + "|" + $severity.ToUpper().Trim() + '|' + $scriptName.Trim() + "|" + $logfileMessage

    if ($skipConsole -eq $false) {
        Write-Host $message
    }

    Add-Content -Path $global:scriptLogfile -Value $logmsg -ErrorAction SilentlyContinue
}

function GetServiceNowInstance() {
    $serviceNowInstance = 'fkatest'
    return $serviceNowInstance
}
function GetServiceNowCredentials() {
    $username = 'Dedge.integration'
    $password = 'XTj0+SP.1A'
    $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential ($username, $securePassword)

    return $credential
}

function Get-StateText ($uri, $credential) {
    $response = Invoke-RestMethod -Uri $uri -Method Get -Credential $credential -ContentType "application/json"
    return $response.result[0].label
}
function Get-StateTexts ($uri, $credential) {
    $response = Invoke-RestMethod -Uri $uri -Method Get -Credential $credential -ContentType "application/json"
    return $response.result

}
function GetUserSysID ($uri, $credential) {
    $response = Invoke-RestMethod -Uri $uri -Method Get -Credential $credential -ContentType "application/json"
    return $response.result[0].sys_id
}

# Function to make the API request
function GetServiceNowData ($url) {
    $credential = GetServiceNowCredentials
    $response = $null
    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -Credential $credential
    }
    catch {
        $response = $null
    }
    return $response.result
}

function GetServiceNowOpenIssuesForUser ($serviceNowId = $null) {
    # Set the ServiceNow instance and credentials
    $instance = GetServiceNowInstance
    $credential = GetServiceNowCredentials

    # Get the sys_id for the user
    $user = $Env:USERNAME
    $userUri = "https://$instance.service-now.com/api/now/table/sys_user?sysparm_query=user_name=$user&sysparm_fields=sys_id&sysparm_limit=1"
    $userSysID = GetUserSysID -uri $userUri -credential $credential

    # Get the incidents assigned to the user represented by the userSysID
    $incidentUrl = "https://$instance.service-now.com/api/now/table/incident?sysparm_query=assigned_to=" + $userSysID + '&sysparm_fields=number,short_description,priority,state,sys_id'
    $incidents = GetServiceNowData -url $incidentUrl
    # Get the incident related to the serviceNowId if any
    if ($serviceNowId.StartsWith('INC')) {
        $incidentUrl = "https://$instance.service-now.com/api/now/table/incident?sysparm_query=number=" + $serviceNowId + '&sysparm_fields=number,short_description,priority,state,sys_id'
        $incidents += GetServiceNowData -url $incidentUrl
    }
    if ($incidents -ne $null) {
        $incidents | Add-Member -MemberType NoteProperty -Name Type -Value 'Incident' -PassThru | Out-Null
    }

    # Get the service requests assigned to the user represented by the userSysID
    $srrequestUrl = "https://$instance.service-now.com/api/now/table/sc_request?sysparm_query=assigned_to=" + $userSysID + '&sysparm_fields=number,short_description,priority,state,sys_id'
    $srrequests = GetServiceNowData -url $srrequestUrl
    # Get the incident related to the serviceNowId if any
    if ($serviceNowId.StartsWith('SC')) {
        $srrequestUrl = "https://$instance.service-now.com/api/now/table/sc_request?sysparm_query=number=" + $serviceNowId + '&sysparm_fields=number,short_description,priority,state,sys_id'
        $srrequests += GetServiceNowData -url $incidentUrl
    }
    if ($srrequests -ne $null) {
        $srrequests | Add-Member -MemberType NoteProperty -Name Type -Value 'Service Request' -PassThru | Out-Null
    }

    # Get the change requests assigned to the user represented by the userSysID
    $crrequestUrl = "https://$instance.service-now.com/api/now/table/change_request?sysparm_query=state<3&assigned_to=" + $userSysID + '&sysparm_fields=number,short_description,priority,state,sys_id'
    $crrequests = GetServiceNowData -url $crrequestUrl
    if ($serviceNowId.StartsWith('CHG')) {
        $srrequestUrl = "https://$instance.service-now.com/api/now/table/change_request?sysparm_query=number=" + $serviceNowId + '&sysparm_fields=number,short_description,priority,state,sys_id'
        $srrequests += GetServiceNowData -url $incidentUrl
    }
    if ($crrequests -ne $null) {
        $crrequests | Add-Member -MemberType NoteProperty -Name Type -Value 'Change Request' -PassThru | Out-Null
    }

    # merge the arrays into one
    $requests = $incidents + $srrequests + $crrequests
    $stateCodesUri = "https://$instance.service-now.com/api/now/table/sys_choice?sysparm_query=nameINincident,change_request^element=state&language=nb&inactive=false&sysparm_fields=value,label,name,hint&sysparm_orderby=label"
    $stateCodes = Get-StateTexts -uri $stateCodesUri -credential $credential

    # Add stateText to the requests
    foreach ($request in $requests) {
        try {
            $type_formatted = $request.Type.ToLower().Replace(' ', '_')
            $stateText = $stateCodes | Where-Object { $_.value -eq $request.state -and $_.name -eq $type_formatted }
            $request | Add-Member -MemberType NoteProperty -Name "stateText" -Value $stateText.label -PassThru | Out-Null
        }
        catch {
            continue
        }
    }

    #Ssort the requests by number
    $tmpRequests = $requests | Sort-Object -Property number | Where-Object { $_.number -ne $null }
    $requests = $tmpRequests

    # Add a sequence number to the requests for menu selection
    $i = 0
    foreach ($request in $requests) {
        $i++
        $request | Add-Member -MemberType NoteProperty -Name Sequence -Value $i -PassThru | Out-Null
    }
    # rename the columns
    $requests | Format-Table -Property @{Label = "Valg"; Expression = { $_.Sequence } }, @{Label = "ServiceNowId"; Expression = { $_.number } }, @{Label = "Type"; Expression = { $_.Type } }, @{Label = "Beskrivelse"; Expression = { $_.short_description } }, @{Label = "Prioritet"; Expression = { $_.priority } }, @{Label = "Status"; Expression = { $_.state }; Alignment = "Right" }, @{Label = "Status beskrivelse"; Expression = { $_.stateText } } -AutoSize
    return $requests

}

function GetUserSysID {
    # Set the ServiceNow instance and credentials
    $instance = GetServiceNowInstance
    $credential = GetServiceNowCredentials
    $username = $env:USERNAME
    $sys_id = ""

    $userUri = "https://$instance.service-now.com/api/now/table/sys_user?sysparm_query=user_name=$username&sysparm_fields=sys_id&sysparm_limit=1"
    try {
        $response = Invoke-RestMethod -Uri $userUri -Method Get -Credential $credential -ContentType "application/json"
        $sys_id = $response.result[0].sys_id
    }
    catch {
        LogMessage -message ("Error getting user sys_id: $_") -severity "ERROR"
    }
    return $sys_id
}
function GetServiceNowInfo($serviceNowId) {
    # Set the ServiceNow instance and credentials
    $instance = GetServiceNowInstance
    $credential = GetServiceNowCredentials
    $object = $null
    $sysid = ""

    try {
        if ($object -eq $null) {
            if ($serviceNowId.StartsWith('INC')) {
                $incidentUrl = "https://$instance.service-now.com/api/now/table/incident?sysparm_query=number=" + $serviceNowId + '&sysparm_fields=number,short_description,priority,state,sys_id'
                $object = GetServiceNowData -url $incidentUrl
                $snType = 'INC'
            }
        }

        if ($object -eq $null) {
            if ($serviceNowId.StartsWith('SC')) {
                $srrequestUrl = "https://$instance.service-now.com/api/now/table/sc_request?sysparm_query=number=" + $serviceNowId + '&sysparm_fields=number,short_description,priority,state,sys_id'
                $object = GetServiceNowData -url $incidentUrl
                $snType = 'SC'
            }
        }

        if ($object -eq $null) {
            if ($serviceNowId.StartsWith('CHG')) {
                $srrequestUrl = "https://$instance.service-now.com/api/now/table/change_request?sysparm_query=number=" + $serviceNowId + '&sysparm_fields=number,short_description,priority,state,sys_id'
                $object = GetServiceNowData -url $incidentUrl
                $snType = 'CHG'
            }
        }
    }
    catch {
        LogMessage -message ("Error getting ServiceNow info: $_") -severity "ERROR"
    }

    $sysid = $object.sys_id
    return $sysid, $snType
}

function PutServiceNowData($uri, $body) {
    # Set the ServiceNow instance and credentials
    $credential = GetServiceNowCredentials
    $response = $null

    try {
        $response = Invoke-RestMethod -Uri $uri -Method Put -Body $body -Credential $credential -ContentType "application/json"
        # convert the response to JSON and display the result in the console
        # if ($ENV:USERNAME.ToUpper().Trim() -eq 'FKGEISTA') {
        #     LogMessage -message "Response: $($response | ConvertTo-Json)" -severity "DEBUG"
        # }
    }
    catch {
        LogMessage -message ("Error putting ServiceNow data: $_") -severity "ERROR"
    }
    return $response | Out-Null
}
function PostServiceNowData($uri, $body) {
    # Set the ServiceNow instance and credentials
    $credential = GetServiceNowCredentials
    $response = $null

    try {
        $response = Invoke-RestMethod -Uri $uri -Method Post -Body $body -Credential $credential -ContentType "application/json"
        # convert the response to JSON and display the result in the console
        # if ($ENV:USERNAME.ToUpper().Trim() -eq 'FKGEISTA') {
        #     LogMessage -message "Response: $($response | ConvertTo-Json)" -severity "DEBUG"
        # }
    }
    catch {
        LogMessage -message ("Error putting ServiceNow data: $_") -severity "ERROR"
    }
    return $response
}

function ShowServiceNowData ($requests) {
    $requests | Format-Table -Property @{Label = "Valg"; Expression = { $_.Sequence } }, @{Label = "ServiceNowId"; Expression = { $_.number } }, @{Label = "Type"; Expression = { $_.Type } }, @{Label = "Beskrivelse"; Expression = { $_.short_description } }, @{Label = "Prioritet"; Expression = { $_.priority } }, @{Label = "Status"; Expression = { $_.state }; Alignment = "Right" }, @{Label = "Status beskrivelse"; Expression = { $_.stateText } } -AutoSize
}

function GetServiceNowBody ($moduleList, $changeUsername, $todayStr, $tomorrow, $snType ) {

    $moduleListJoin = "`n - " + ($moduleList -join "`n - ")
    $modules = "Endring av følgende program: " + $moduleListJoin

    $backout_plan = "Hvis noe skulle gå galt etter produksjonsetting, kan utvalgte filer legges tilbake fra katalogen: N:\COBNT\_backup\$todayStr\$changeUsername\ `nEtter filene er lagt tilbake, vil det ta opptil 20 minutter før alle Citrix serverene er oppdatert. Påvirkede brukere må deretter starte FK-Meny på nytt."
    $close_notes = "Endringen er gjennomført og testet. Ingen feil ble funnet."

    $deployComment = ""

    if ($global:immediateDeploy -eq $true) {
        $deployComment = $(BuildDeployEnvString)
        $delivery_plan = ("Produksjonsdato: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
        $resolved_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }
    else {
        $deployComment = $(BuildDeployEnvString)
        $delivery_plan = ("Produksjonsdato: " + $tomorrow.ToString("yyyy-MM-dd HH:mm:ss"))
        $resolved_at = $tomorrow.ToString("yyyy-MM-dd HH:mm:ss")
    }

    if ($snType -eq 'CHG') {
        $state = "Closed"
    }
    else {
        $state = "Resolved"
    }

    $additionalInfo = @{
        comments    = $deployComment
        work_notes  = $modules
        close_notes = $delivery_plan + "`n" + "`n" + $close_notes + "`n" + "`n" + $backout_plan
        close_code  = "Solved (Permanently)"
        state       = $state
    } | ConvertTo-Json

    return $additionalInfo
}

function CreateServiceNowChangeRequest(
    $changeTitle,
    $changeDescription,
    $moduleList,
    $serviceNowId = '') {

    $serviceNowInstance = GetServiceNowInstance
    $ErrorActionPreference = 'stop'
    $changeUsername = $env:USERNAME
    $start_date_utc = (Get-Date).AddMinutes(-60).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss")
    $tomorrow_utc = ([DateTime]::UtcNow.Date.AddDays(1).AddMinutes(10)).ToUniversalTime()
    $todayStr_utc = $start_date_utc

    $todayStr = Get-Date -Format "yyyyMMdd"
    $moduleListJoin = "`n - " + ($moduleList -join "`n - ")
    $modules = "Endring av følgende program: " + $moduleListJoin
    $backout_plan = "Hvis noe går galt skal utvalgte filer legges tilbake fra katalogen: $global:prodExecPath\_backup\$todayStr\$changeUsername\ `nEtter filene er lagt tilbake, vil det ta opptil 20 minutter før alle Citrix serverene er oppdatert. Påvirkede brukere må deretter starte FK-Meny på nytt."
    $close_notes = "Endringen er gjennomført og testet. Ingen feil ble funnet."

    $implementation_plan = ""
    $outside_maintenance_schedule = "false"
    if ($global:immediateDeploy -eq $true) {
        $implementation_plan = "Endringen er gjennomført og prodsettes med UMIDDELBAR virkning!"
        $delivery_plan = ("Produksjonsdato: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
        $end_date_utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss")
        $urgency = "High"
        $outside_maintenance_schedule = "true"
    }
    else {
        $implementation_plan = "Endringen er gjennomført og prodsettes fra i morgen av."
        $delivery_plan = ("Produksjonsdato: " + $tomorrow.ToString("yyyy-MM-dd HH:mm:ss"))
        $end_date_utc = $tomorrow.ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss")
        $urgency = "Low"
        $outside_maintenance_schedule = "false"
    }

    $body = @{
        state                        = "Scheduled"
        type                         = "standard"
        short_description            = $changeTitle
        description                  = $changeDescription
        category                     = "Software"
        impact                       = "Low"
        urgency                      = $urgency
        assignment_group             = "Utvikling FK-meny"
        business_service             = "FK-Meny Prod"
        cmdb_ci                      = "FK-Meny Prod"
        unauthorized                 = "false"
        approval                     = "not requested"
        cab_required                 = "false"
        requested_by                 = $changeUsername
        assigned_to                  = $changeUsername
        backout_plan                 = $backout_plan
        test_plan                    = "Utført egentest og tester i testmiljø(er)"
        start_date                   = $start_date_utc
        review_date                  = $start_date_utc
        review_comments              = "Endringen er gjennomført og testet. Ingen feil ble funnet."
        production_system            = "true"
        outside_maintenance_schedule = $outside_maintenance_schedule
        justification                = "Endringen er nødvendig for å oppdatere FK-Meny programvare"
        implementation_plan          = $implementation_plan
        delivery_plan                = $delivery_plan
        change_plan                  = "Endringen er gjennomført og testet. Ingen feil ble funnet."
        end_date                     = $end_date_utc
        risk_impact_analysis         = "Ingen spesifikk risiko identifisert"
        risk_value                   = 3
        close_code                   = "successful"
        closed_at                    = $end_date_utc
        closed_by                    = $changeUsername
        close_notes                  = $close_notes
    } | ConvertTo-Json
    # $change
    # # new - sched - implement -review - close

    $uri = "https://$serviceNowInstance.service-now.com/api/now/v1/table/change_request"

    $response = PostServiceNowData -uri $uri -body $body

    # $serviceNowId = $response.result[0].number
    $sysId = $response.result[0].sys_id

    $servicenow_web_url = "https://$serviceNowInstance.service-now.com/nav_to.do?uri=change_request.do?sys_id=$sysId"

    # Handle put statements
    $uri = "https://$serviceNowInstance.service-now.com/api/now/v1/table/change_request/$sysId"

    # Implement
    $body = @{
        state = "Implement"
    } | ConvertTo-Json
    PutServiceNowData -uri $uri -body $body

    $body = @{
        state = "Review"
    } | ConvertTo-Json
    PutServiceNowData -uri $uri -body $body

    # Close
    $body = GetServiceNowBody -moduleList $moduleList -changeUsername $changeUsername -todayStr $todayStr_utc -tomorrow $tomorrow_utc -snType 'CHG'
    PutServiceNowData -uri $uri -body $body

    $global:servicenow_web_url = $servicenow_web_url
}

function UpdateServiceNowChangeRequest(
    $changeTitle,
    $changeDescription,
    $moduleList,
    $serviceNowId) {

    $ErrorActionPreference = 'stop'
    $changeUsername = $env:USERNAME
    $tomorrow = [DateTime]::UtcNow.Date.AddDays(1).AddMinutes(10)
    $todayStr = Get-Date -Format "yyyyMMdd"

    $servicenow_web_url = ""
    $sysid, $snType = GetServiceNowInfo -serviceNowId $serviceNowId

    $deployEnvString = BuildDeployEnvString

    if ($snType -eq 'INC') {
        $servicenow_web_url = "https://$serviceNowInstance.service-now.com/nav_to.do?uri=incident.do?sys_id=$sysId"
        $uri = "https://$serviceNowInstance.service-now.com/api/now/v1/table/incident/$sysId"
        # Construct the updated JSON payload
        $stateChange = @{
            state          = 2
            incident_state = 2
            comments       = "Endringsbeskrivelse: `n`n" + $changeTitle + "`n" + $changeDescription
        } | ConvertTo-Json
    }

    if ($snType -eq 'SC') {
        $servicenow_web_url = "https://$serviceNowInstance.service-now.com/nav_to.do?uri=sc_request.do?sys_id=$sysId"
        $uri = "https://$serviceNowInstance.service-now.com/api/now/v1/table/sc_request/$sysId"
        # Construct the updated JSON payload
        $stateChange = @{
            state    = "Implement"
            comments = "Endringsbeskrivelse: `n`n" + $changeTitle + "`n" + $changeDescription
        } | ConvertTo-Json
    }

    if ($snType -eq 'CHG') {
        $servicenow_web_url = "https://$serviceNowInstance.service-now.com/nav_to.do?uri=change_request.do?sys_id=$sysId"
        $uri = "https://$serviceNowInstance.service-now.com/api/now/v1/table/change_request/$sysId"
        # Construct the updated JSON payload
        $stateChange = @{
            state    = "Implement"
            comments = "Endringsbeskrivelse: `n`n" + $changeTitle + "`n" + $changeDescription
        } | ConvertTo-Json
    }
    PutServiceNowData -uri $uri -body $stateChange

    $body = @{
        comments = $deployEnvString
    } | ConvertTo-Json
    PutServiceNowData -uri $uri -body $body

    PutServiceNowData -uri $uri -body (@{ state = "Review" } | ConvertTo-Json)

    $body = GetServiceNowBody -moduleList $moduleList -changeUsername $changeUsername -todayStr $todayStr -tomorrow $tomorrow -snType $snType
    PutServiceNowData -uri $uri -body $body
    $global:servicenow_web_url = $servicenow_web_url
}

function ZipAndArchiveFiles ($fileObjList , $deployEnvItem, $date, $time) {

    foreach ($fileObj in $fileObjList) {
        $folder = $global:tempPath + '\ARC\' + $fileObj.MainModule.ModuleFileSuffix + 'ARC\' + $fileObj.MainModule.ModuleFilePrefix
        # Zip files in $tempPath
        $zipFileName = $fileObj.MainModule.ModuleFileName + '_' + $date + '_' + $time + '_TO_' + $deployEnvItem

        $archivePathModule = $global:archivePath + '\' + $fileObj.MainModule.ModuleFileSuffix + 'ARC\' + $fileObj.MainModule.ModuleFilePrefix

        $zipFile = $archivePathModule + '\' + $zipFileName + '.ZIP'
        if (!(Test-Path -Path $archivePathModule)) {
            New-Item -ItemType Directory -Path $archivePathModule -ErrorAction SilentlyContinue | Out-Null
        }

        if (Test-Path -Path $zipFile -PathType Leaf) {
            Remove-Item -Path $zipFile -Force -ErrorAction SilentlyContinue | Out-Null
        }

        # zip all files in the content folder
        if (Test-Path $zipFile -PathType Leaf) {
            Remove-Item -Path $zipFile -Force -ErrorAction SilentlyContinue | Out-Null
        }
        try {
            Compress-Archive -Path "$folder\*" -DestinationPath $zipFile -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-Host "Exception occurred: $_"
        }
        finally {
            Remove-Item -Path $folder -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
}

function ExportImpFileFromGsFile ($moduleInfo, $deployPath) {

    $deployPathImp = $deployPath + '\IMP'
    if (!(Test-Path -Path $deployPathImp)) {
        New-Item -ItemType Directory -Path $deployPathImp -ErrorAction SilentlyContinue | Out-Null
    }

    $exePath = '"C:\Program Files (x86)\Micro Focus\Net Express 5.1\DIALOGSYSTEM\Bin\dswin.exe"'
    $impFile = $deployPathImp + '\' + $moduleInfo.ModuleFilePrefix + '.IMP'
    $gsFile = $moduleInfo.BasePath + '.GS'
    $args = "/e  $($gsFile + " " + $impFile)"

    $process = Start-Process -FilePath "$exePath" -ArgumentList  $args -PassThru -NoNewWindow

    LogMessage -message ("--> Exporting GS file to IMP: " + $gsFile + " to " + $impFile) -skipConsole $true

    # Wait for the process to exit with a timeout
    $waitResult = $process | Wait-Process -Timeout 15 -ErrorAction SilentlyContinue

    # Check if the process DSWIN.EXE is still running
    if ($process.HasExited) {
        $waitResult = $true
    }
    else {
        $waitResult = $false
        # Clean up process resources if still needed
        $process | Stop-Process -Force
    }

    if (-not $waitResult) {
        # Process did not complete in time, terminate it and all its child processes
        LogMessage -message ("DSWIN.EXE process exceeded time limit and will be terminated.") -skipConsole $true
        Stop-Process -Id $process.Id -Force -PassThru | ForEach-Object {
            # Attempt to terminate child processes if any
            Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq $_.ProcessId } | Stop-Process -Force
        }
    }

    # Check if the file exists
    if (!(Test-Path $impFile -PathType Leaf)) {
        LogMessage -message ("**> Failed to export: " + $impFile + '.IMP') -severity "ERROR" -skipConsole $true
    }
}

function CopyModuleFilesToPath($moduleInfo, $deployPath) {
    if (!(Test-Path -Path $deployPath)) {
        New-Item -ItemType Directory -Path $deployPath -ErrorAction SilentlyContinue | Out-Null
    }

    $deployPathSrc = $deployPath + '\SRC'
    if (!(Test-Path -Path $deployPathSrc)) {
        New-Item -ItemType Directory -Path $deployPathSrc -ErrorAction SilentlyContinue | Out-Null
    }

    if ($moduleInfo.ModuleFileSuffix -eq 'CBL') {
        $deployPathCbl = $deployPathSrc + '\CBL'
        if (!(Test-Path -Path $deployPathCbl)) {
            New-Item -ItemType Directory -Path $deployPathCbl -ErrorAction SilentlyContinue | Out-Null
        }
        $source = $moduleInfo.BasePath + '.CBL'
        $dest = $deployPathCbl + '\' + $moduleInfo.ModuleFileName
        Copy-Item -Path $source -Destination $dest -Force -ErrorAction SilentlyContinue

        $deployPathCpy = $deployPathCbl + '\CPY'

        if (!(Test-Path -Path $deployPathCpy)) {
            New-Item -ItemType Directory -Path $deployPathCpy -ErrorAction SilentlyContinue | Out-Null
        }

        # Foreach element in CopyFiles
        foreach ($copyFile in $moduleInfo.CopyFiles) {
            # Copy copy files to deployPath
            $source = $copyFile
            $dest = $deployPathCpy + '\' + $copyFile.Substring($copyFile.LastIndexOf('\') + 1)
            Copy-Item -Path $source -Destination $dest -Force -ErrorAction SilentlyContinue
        }

        # Copy module INT, IDY, and BND files to deployPath
        $source = $moduleInfo.BasePath + '.INT'
        $dest = $deployPath + '\' + $moduleInfo.ModuleFilePrefix + '.INT'
        Copy-Item -Path $source -Destination $dest -Force -ErrorAction SilentlyContinue
        $source = $moduleInfo.BasePath + '.IDY'
        $dest = $deployPath + '\' + $moduleInfo.ModuleFilePrefix + '.IDY'
        Copy-Item -Path $source -Destination $dest -Force -ErrorAction SilentlyContinue
        $source = $moduleInfo.BasePath + '.BND'
        $dest = $deployPath + '\' + $moduleInfo.ModuleFilePrefix + '.BND'
        Copy-Item -Path $source -Destination $dest -Force -ErrorAction SilentlyContinue

        if ($null -ne $moduleInfo.GsTime) {
            # Copy module GS file to deployPath
            $source = $moduleInfo.BasePath + '.GS'
            $dest = $deployPath + '\' + $moduleInfo.ModuleFilePrefix + '.GS'
            Copy-Item -Path $source -Destination $dest -Force -ErrorAction SilentlyContinue

            # Copy module GS file to deployPathSrc
            $deployPathSrcGs = $deployPathCbl + '\GS'
            if (!(Test-Path -Path $deployPathSrcGs)) {
                New-Item -ItemType Directory -Path $deployPathSrcGs -ErrorAction SilentlyContinue | Out-Null
            }
            $source = $moduleInfo.BasePath + '.GS'
            $dest = $deployPathSrcGs + '\' + $moduleInfo.ModuleFilePrefix + '.GS'
            Copy-Item -Path $source -Destination $dest -Force -ErrorAction SilentlyContinue

            ExportImpFileFromGsFile -moduleInfo $moduleInfo -gsFile $source -deployPath $deployPathSrcGs
        }

    }
    else {

        $deployPathCommon = $deployPathSrc + '\' + $moduleInfo.ModuleFileSuffix
        if (!(Test-Path -Path $deployPathCommon)) {
            New-Item -ItemType Directory -Path $deployPathCommon -ErrorAction SilentlyContinue | Out-Null
        }
        $source = $moduleInfo.BasePath + '.' + $moduleInfo.ModuleFileSuffix
        $dest = $deployPathCommon + '\' + $moduleInfo.ModuleFileName
        Copy-Item -Path $source -Destination $dest -Force -ErrorAction SilentlyContinue

        $deployPathCommon = $deployPathSrc + '\' + $moduleInfo.ModuleFileSuffix
        if (!(Test-Path -Path $deployPathCommon)) {
            New-Item -ItemType Directory -Path $deployPathCommon -ErrorAction SilentlyContinue | Out-Null
        }

        # Copy module source to deployPathSrc plus ModuleFileSuffix
        $source = $moduleInfo.BasePath + '.' + $moduleInfo.ModuleFileSuffix
        $dest = $deployPathCommon + '\' + $moduleInfo.ModuleFileName
        Copy-Item -Path $source -Destination $dest -Force -ErrorAction SilentlyContinue

        if ($moduleInfo.ModuleFileSuffix -ne 'SQL') {
            # Copy module source to deployPath
            $source = $moduleInfo.BasePath + '.' + $moduleInfo.ModuleFileSuffix
            $dest = $deployPath + '\' + $moduleInfo.ModuleFileName
            Copy-Item -Path $source -Destination $dest -Force -ErrorAction SilentlyContinue
        }
    }
}

function CopyModuleFiles($moduleInfo, $mainModuleFilePrefix) {
    $moduleArchivePath = $global:tempPath + '\ARC\' + $moduleInfo.ModuleFileSuffix + 'ARC\' + $mainModuleFilePrefix
    if (!(Test-Path -Path $moduleArchivePath)) {
        New-Item -ItemType Directory -Path $moduleArchivePath -ErrorAction SilentlyContinue | Out-Null
    }
    CopyModuleFilesToPath -moduleInfo $moduleInfo -deployPath $moduleArchivePath

    $releasePath = $global:tempPath + '\DEP'
    if (!(Test-Path -Path $releasePath)) {
        New-Item -ItemType Directory -Path $releasePath -ErrorAction SilentlyContinue | Out-Null
    }
    CopyModuleFilesToPath -moduleInfo $moduleInfo -deployPath $releasePath
}
function CopyFilesToTempPath($fileObjList) {
    foreach ($fileObj in $fileObjList) {
        CopyModuleFiles -moduleInfo $fileObj.MainModule -mainModuleFilePrefix $fileObj.MainModule.ModuleFilePrefix

        if ($null -ne $fileObj.ValidationModule) {
            CopyModuleFiles -moduleInfo $fileObj.ValidationModule -mainModuleFilePrefix $fileObj.MainModule.ModuleFilePrefix
        }
    }
}
function BackupProdModule ($moduleInfo, $backupFolder) {
    if ($moduleInfo.ModuleFileSuffix -eq 'CBL') {
        $intFile = $global:prodExecPath + '\' + $moduleInfo.ModuleFilePrefix + '.INT'
        $intBackupFile = $backupFolder + '\' + $moduleInfo.ModuleFilePrefix + '.INT'
        if ((Test-Path -Path $intFile -PathType Leaf)) {
            Copy-Item -Path $intFile -Destination $intBackupFile -Force -ErrorAction SilentlyContinue
        }

        $idyFile = $global:prodExecPath + '\' + $moduleInfo.ModuleFilePrefix + '.IDY'
        $idyBackupFile = $backupFolder + '\' + $moduleInfo.ModuleFilePrefix + '.IDY'
        if ((Test-Path -Path $idyFile -PathType Leaf)) {
            Copy-Item -Path $idyFile -Destination $idyBackupFile -Force -ErrorAction SilentlyContinue
        }

        $gsFile = $global:prodExecPath + '\' + $moduleInfo.ModuleFilePrefix + '.GS'
        $gsBackupFile = $backupFolder + '\' + $moduleInfo.ModuleFilePrefix + '.GS'
        if ((Test-Path -Path $gsFile -PathType Leaf)) {
            Copy-Item -Path $gsFile -Destination $gsBackupFile -Force -ErrorAction SilentlyContinue
        }

        $bndFile = $global:prodExecPath + '\BND\' + $moduleInfo.ModuleFilePrefix + '.BND'
        $bndBackupFile = $backupFolder + '\BND\' + $moduleInfo.ModuleFilePrefix + '.BND'
        if (Test-Path -Path $bndFile -PathType Leaf) {
            Copy-Item -Path $bndFile -Destination $bndBackupFile -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        $srcFile = $moduleInfo.BasePath + $moduleInfo.ModuleFileSuffix
        $srcBackupFile = $backupFolder + '\' + $moduleInfo.ModuleFileName
        if (Test-Path -Path $srcFile -PathType Leaf) {
            Copy-Item -Path $srcFile -Destination $srcBackupFile -Force -ErrorAction SilentlyContinue
        }
    }
}

function HandleProductionFileBackup ($fileObjList) {

    # Create backup of int, idy, and bnd files in case of revert
    $backupDir = $global:prodExecPath + "\_backup"
    if (!(Test-Path -Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -ErrorAction SilentlyContinue | Out-Null
    }

    # Get current date in YYYYMMDD format
    $currentDate = Get-Date -Format "yyyyMMdd"

    # Append USER to backupDir to create subfolder path
    $subfolder = Join-Path -Path $backupDir -ChildPath $currentDate

    # Check if subfolder exists, and if not, create it
    if (!(Test-Path -Path $subfolder)) {
        New-Item -ItemType Directory -Path $subfolder -ErrorAction SilentlyContinue | Out-Null
    }

    # Append USER to backupDir to create subfolder path
    $subfolder = Join-Path -Path $subfolder -ChildPath $env:USERNAME.ToUpper()

    # Check if subfolder exists, and if not, create it
    if (!(Test-Path -Path $subfolder)) {
        New-Item -ItemType Directory -Path $subfolder -ErrorAction SilentlyContinue | Out-Null
    }

    foreach ($fileObj in $fileObjList) {
        $module = $fileObj.ModuleFileName
        $mainModule = $null
        $validationModule = $null
        if ($fileObj.MainModule.ModuleFileSuffix -eq 'CBL') {
            # Append bnd to subfolder to create subfolder path
            $subfolderbnd = Join-Path -Path $subfolder -ChildPath "BND"

            # Check if subfolderbnd exists, and if not, create it
            if (!(Test-Path -Path $subfolderbnd)) {
                New-Item -ItemType Directory -Path $subfolderbnd -ErrorAction SilentlyContinue | Out-Null
            }

            $mainModule = $fileObj.MainModule
            $validationModule = $fileObj.ValidationModule
        }
        else {
            $mainModule = $fileObj.MainModule
        }

        BackupProdModule -moduleInfo $mainModule -backupFolder $subfolder
        if ($null -ne $validationModule) {
            BackupProdModule -moduleInfo $validationModule -backupFolder $subfolder
        }
    }
    Write-Host "Backup av relaterte produksjonsfiler er lagt i katalog: $subfolder"
}

function GetFileLastWrittenTime ($filePath) {
    $fileTime = $null
    if ((Test-Path -Path $filePath)) {
        $fileTime = (Get-Item -Path $filePath).LastWriteTime
    }
    return $fileTime
}

function GetModuleInfo ($moduleFileName) {
    # Get file suffix from $module
    $pos = $moduleFileName.LastIndexOf('.')
    $moduleFileSuffix = $module.Substring($pos + 1)
    $moduleFilePrefix = $module.Substring(0, $pos)
    $basePath = $global:srcPath + '\' + $moduleFilePrefix
    $srcTime = $null
    $intTime = $null
    $idyTime = $null
    $bndTime = $null
    $gsTime = $null
    $useSql = $false
    $copyFiles = @()
    $useSql = $false
    $temp = $null
    if ($moduleFileSuffix -eq 'CBL') {
        $srcTime = GetFileLastWrittenTime -filePath ($basePath + '.CBL')
        $intTime = GetFileLastWrittenTime -filePath ($basePath + '.INT')
        $idyTime = GetFileLastWrittenTime -filePath ($basePath + '.IDY')
        $bndTime = GetFileLastWrittenTime -filePath ($basePath + '.BND')
        $gsTime = GetFileLastWrittenTime -filePath ($basePath + '.GS')
        $useSql = CblUseSql -module ($basePath + '.CBL')
        $copyFiles = ScanCobolProgram -source ($basePath + '.CBL')
        if ($null -eq $intTime) {
            $global:errorMessages += $module + ' er ikke kompilert, da INT-filen ikke finnes!'
        }

        if ($null -ne $intTime -and $null -ne $srcTime -and $intTime -lt $srcTime) {
            $global:errorMessages += $module + ' er av nyere dato enn .INT-filen!'
        }

        if ($useSql -eq $true -and $null -eq $bndTime) {
            $global:errorMessages += $module + ' benytter DB2 men BND-file mangler!'
        }
        $temp = [PSCustomObject]@{
            ModuleFileName   = $moduleFileName
            ModuleFilePrefix = $moduleFilePrefix
            ModuleFileSuffix = $moduleFileSuffix
            Type             = $module.Substring(2, 1)
            BasePath         = $basePath
            UseSql           = $useSql
            Src              = $basePath + '.' + $moduleFileSuffix
            GsTime           = $gsTime
            SrcTime          = $srcTime
            IntTime          = $intTime
            IdyTime          = $idyTime
            BndTime          = $bndTime
            CopyFiles        = $copyFiles
        }
    }
    else {
        $srcTime = GetFileLastWrittenTime -filePath ($basePath + '.' + $moduleFileSuffix)
        $temp = [PSCustomObject]@{
            ModuleFileName   = $moduleFileName
            ModuleFilePrefix = $moduleFilePrefix
            ModuleFileSuffix = $moduleFileSuffix
            BasePath         = $basePath
            Src              = $basePath + '.' + $moduleFileSuffix
            SrcTime          = $srcTime
        }
    }

    return $temp
}

function ScanCobolProgram ($source) {
    $ikkecpy = @('DS-CNTRL', 'DSSYSINF', 'DSRUNNER', 'DS-CALL', 'SQLENV', 'GMAUTILS', 'DEFCPY', 'REQFELL', 'DSUSRVAL')
    # Find line number for procedure division
    $procedureDivisionLineNumber = Select-String -Path $source -Pattern 'PROCEDURE DIVISION' | Select-Object -ExpandProperty LineNumber
    # Find all COPY statements in cobol module that are not commented out, and where  line number is less than procedure division line number
    # $copyStatements = Select-String -Path $module -Pattern '^\s*.COPY' | Where-Object { $_.LineNumber -lt $procedureDivisionLineNumber -and $_.Line -notmatch '^\s*\*.*COPY' } | Select-Object -ExpandProperty Line
    $copyStatements = Select-String -Path $source -Pattern '^\s*COPY' | Where-Object { $_.LineNumber -lt $procedureDivisionLineNumber -and $_.Line -notmatch '^\s*\*.*COPY' } | Select-Object -ExpandProperty Line

    # Remove elements from $copyStatements that are in $ikkecpy
    $copyFiles = @()
    foreach ($element in $copyStatements) {
        $copyStatement = $element.Trim().ToUpper().TrimStart('COPY').Trim()
        $copyStatement = $copyStatement.Trim() -replace '"', ''
        $copyStatement = $copyStatement.Trim() -replace "'", ''
        # $copyStatement = $copyStatement.Trim().Replace(".CPY.", ".CPY")
        # $copyStatement = $copyStatement.Trim().Replace(".CPB.", ".CPB")
        # $copyStatement = $copyStatement.Trim().Replace(".CPX.", ".CPX")
        # $copyStatement = $copyStatement.Trim().Replace(".DCL.", ".DCL")
        # Find the pos of the list of suffixes: .CPY, .CPB, .CPX, .DCL
        # $pos = $copyStatement.IndexOfAny(@('.CPY', '.CPB', '.CPX', '.DCL'))
        # Remove all text after the found suffix
        foreach ($suffix in @('.CPY', '.CPB', '.CPX', '.DCL')) {
            $pos = $copyStatement.IndexOf($suffix)
            if ($pos -gt 0) {
                $copyStatement = $copyStatement.Substring(0, $pos + 4)
                break
            }
        }
        # $copyStatement = $copyStatement.TrimEnd('.')
        $copyStatement = $copyStatement.Trim()
        try {
            $copyFilePrefix = $copyStatement.Split('.')[0].ToUpper()
            if ($copyFilePrefix -in $ikkecpy) {
                continue
            }
        }
        catch {
            continue
        }

        # check if copy file exists in source or copy directory
        $copyFile = $global:srcPath + '\' + $copyStatement
        if (!(Test-Path -Path $copyFile)) {
            $copyFile = $global:cblCpyPath + '\' + $copyStatement
            if (!(Test-Path -Path $copyFile -PathType Leaf)) {
                $global:errorMessages += 'Kan ikke finne copyelement "' + $copyStatement + '" i verken ' + $global:srcPath + ' eller ' + $global:cblCpyPath + '.'
            }
        }

        $copyFiles += $copyFile.Trim().ToUpper()
    }
    $copyFiles = $copyFiles | Where-Object { $_ -ne '' } | Sort-Object -Unique | ForEach-Object { $_.ToString() }
    return $copyFiles
}

function CblUseSql ($module) {
    $sqlString = Select-String -Path $module -Pattern '^\s*\$SET' | Select-Object -ExpandProperty Line

    $result = $false
    $defaultDatabaseInCblSetCorrect = $false
    $currentDatabase = ""

    foreach ($element in $sqlString) {
        $sqlStatement = $element.Trim().ToUpper()
        if ($sqlStatement -match '^\s*\$SET\s+DB2') {
            $result = $true
        }
        $upperElement = $element.Trim().ToUpper()
        if ($upperElement.Contains($global:defaultDatabaseInCblSet)) {
            $defaultDatabaseInCblSetCorrect = $true
        }

        if ($upperElement -match 'DB=\s*(\S+)') {
            $currentDatabase = $matches[1]
        }
    }

    if ( -not $defaultDatabaseInCblSetCorrect) {
        $global:errorMessages += $module + ' SET DATABASE i CBL er satt til: ' + $currentDatabase + ' Må stå til ' + $global:defaultDatabaseInCblSet + ' for å kunne deployes.'
    }

    return $result
}

################################################################################################################################################
# Init part
################################################################################################################################################
$dtLog = get-date -Format("yyyyMMdd").ToString()
$global:scriptLogfile = "\\DEDGE.fk.no\erpprog\cobnt\" + $dtLog + "_FkStack.log"
$global:defaultDatabaseInCblSet = 'FKAVDNT'
Write-Host "Logfile: $global:scriptLogfile"
$global:errorMessages = @()
$global:srcPath = 'C:\FKAVD\NT'
$global:cblCpyPath = 'C:\FKAVD\SYS\CPY'
$global:stackPath = 'C:\FKM_SRC_TO'
$global:prodExecPath = 'C:\COBNT'
$global:archivePath = 'C:\FKM_SRC_ARC'
$global:logPath = $global:srcPath + '\TILTP'
$global:logFile = $global:logPath + '\FKSTACK.LOG'
$global:tempPath = $global:archivePath + '\TMP\' + $env:USERNAME

if (!(Test-Path -Path $global:archivePath)) {
    New-Item -ItemType Directory -Path $global:archivePath -ErrorAction SilentlyContinue | Out-Null
}
if (!(Test-Path -Path $global:logPath)) {
    New-Item -ItemType Directory -Path $global:logPath -ErrorAction SilentlyContinue | Out-Null
}

################################################################################################################################################
# User input part
################################################################################################################################################

# param(
#     [string]$input = "",
#     [string]$changeDescription = "",
#     [string]$serviceNowId = "",
#     [bool]$immediateDeploy = $false)
Write-Host '--------------------------------------------------------------------------------'
Write-Host '********************** Overføring av kode til produksjon ***********************'
Write-Host '================================================================================'

$supportedFileSuffixes = @('CBL', 'REX', 'BAT', 'CMD')
# Future support for SQL, PS1, PSM1, EXE
if ($false) {
    $supportedFileSuffixes.Add('SQL')
    $supportedFileSuffixes.Add('PS1')
    $supportedFileSuffixes.Add('PSM1')
    $supportedFileSuffixes.Add('EXE')
}
$moduleList = @()
$deployEnv = @()
$inputString = $inputString.Trim().ToUpper().Replace(' ', '')
$deployModule = $null

if ($inputString.Contains('?')) {
    Write-Host 'Parametre:'
    Write-Host '1. inputString    : Flerbruks tekststreng'
    Write-Host '    - Alternativ 1: Komma separert liste av filnavn med filtype (CBL, REX, BAT, CMD).'
    Write-Host '    - Alternativ 2: Tekststreng som inneholder filnavn til tekstfil (.TXT) med filnavn og deploy info'
    Write-Host '2. deployEnv      : Miljø for deploy. Kan være en eller flere av verdier komma separert uten mellomrom:'
    Write-Host "                    PRD - BASISPRO - Produksjonsmiljø for Fk-Meny"
    Write-Host "                    TST - BASISTST - Testmiljø generelt"
    Write-Host "                    VFT - BASISVFT - Testmiljø for vareforsyning test"
    Write-Host "                    VFK - BASISVFK - Testmiljø for vareforsyning akseptansetest"
    Write-Host "                    MIG - BASISMIG - Testmiljø for migrering D365"
    Write-Host "                    SIT - BASISSIT - Testmiljø for vareforsyning test"
    Write-Host '3. comment        : Kommentar til overføringen'
    Write-Host '4. serviceNowId   : ServiceNow ID'
    Write-Host '5. immediateDeploy: Umiddelbar overføring (J/N)'
    # Read char if more help is needed
    $readChar = Read-Host 'Trykk ? for mer hjelp om inputString Alternativ 2 og formattering av filen.'
    if (readChar -eq '?') {
        Write-Host 'Alternativ 2: Tekststreng som inneholder filnavn til tekstfil med filnavn deploy info'
        Write-Host '--------------------------------------------------------------------------------'
        Write-Host 'Filnavn til tekstfil med filnavn deploy info må være på formatet:'
        Write-Host '--------------------------------------------------------------------------------'
        Write-Host 'DEPLOYENV: Miljø for deploy'
        Write-Host 'COMMENT:Kommentar til overføringen'
        Write-Host 'PROGRAM:Programnavn1'
        Write-Host 'PROGRAM:Programnavn2'
        Write-Host 'PROGRAM:Programnavn3'
        Write-Host '...'
        Write-Host 'PROGRAM:ProgramnavnN'
        Write-Host 'SERVICE_NOW_ID:ServiceNow ID'
        Write-Host 'IMMEDIATE_DEP:J/N'
        Write-Host '--------------------------------------------------------------------------------'
        Write-Host 'Eksempel:'
        Write-Host '--------------------------------------------------------------------------------'
        Write-Host 'COMMENT:Deploy av endringer i programmet som følge av innmeldt problem'
        Write-Host 'DEPLOYENV:PRD,MIG,VFT'
        Write-Host 'PROGRAM:WKSTYR.REX'
        Write-Host 'PROGRAM:GMAPAYD2.CBL'
        Write-Host 'PROGRAM:HIST.BAT'
        Write-Host 'SERVICE_NOW_ID:INC1234567'
        Write-Host 'IMMEDIATE_DEP:J'
    }

    Write-Host '**> Avslutter.'
    exit
}
elseif ($inputString.EndsWith('.TXT')) {
    $inputStringContent = Get-Content -Path $inputString
    foreach ($line in $inputStringContent) {
        $line = $line.Trim().ToUpper()
        if ($line.StartsWith('DEPLOYENV:')) {
            $deployEnv = $line.Substring(10).Trim()
            $deployEnv = $deployEnv.ToUpper().Replace(' ', '')
            $deployEnv = $deployEnv.Split(',')
        }
        if ($line.StartsWith('COMMENT:')) {
            $changeDescription = $line.Substring(8).Trim()
        }
        elseif ($line.StartsWith('PROGRAM:')) {
            $deployModule = $line.Substring(8).Trim()
            $deployModule = $deployModule.ToUpper().Replace(' ', '')
            $moduleList += $deployModule.Split(',')
        }
        elseif ($line.StartsWith('SERVICE_NOW_ID:')) {
            $serviceNowId = $line.Substring(15).Trim()
        }
        elseif ($line.StartsWith('IMMEDIATE_DEP:')) {
            $immediateDeploy = $line.Substring(17).Trim()
        }
    }
}
elseif ($inputString -ne '') {
    # Check if inputString is a file with supported file suffix
    $periodPos = $inputString.LastIndexOf('.')
    $moduleFileSuffix = $inputString.Substring($periodPos + 1)

    if ($moduleFileSuffix -in $supportedFileSuffixes) {
        $deployModule = $inputString
        $moduleList += $deployModule
    }
    else {
        Write-Host '**> Ugyldig source filtype.'
        Write-Host '**> Støttede source filtyper er:' $supportedFileSuffixes
        Write-Host '**> Avslutter.'
        exit
    }
}

if ($immediateDeploy.Trim().ToUpper() -in @('J', 'Y', '1', 'JA', 'YES')) {
    $global:immediateDeploy = $true
}
else {
    $global:immediateDeploy = $false
}
$serviceNowId = $serviceNowId.Trim().ToUpper()
$changeDescription = $changeDescription.Trim()

if ($global:immediateDeploy -eq $true) {
    $msg = ' UMIDDELBAR overføring av programmer til ' + $global:srcPath + ' til ' + $global:prodExecPath + ' av bruker:' + $env:USERNAME + ' '
    $msg = " UMIDDELBAR overføring av endringer til $global:stackPath av bruker $env:USERNAME"
    $padding = (80 - $msg.Length) / 2
    $centeredMsg = ('*' * $padding) + $msg + ('*' * $padding)
    Write-Host $centeredMsg
}
else {
    $msg = " Overføring av endringer  $global:stackPath av bruker $env:USERNAME"
    $padding = (80 - $msg.Length) / 2
    $centeredMsg = ('*' * $padding) + $msg + ('*' * $padding)
    Write-Host $centeredMsg
}
Write-Host ''

$moduleList += 'BKFINFA.CBL'
$moduleList += 'WKSTYR.REX'
$moduleList += 'BSHBUOR.CBL'
$deployEnv += 'PRD'
$changeDescription = 'Deploy av endringer i programmet som følge av innmeldt problem'
$global:immediateDeploy = $true

if ($deployEnv.Count -eq 0) {
    $deployEnv = @()

    Write-Host "Velg miljø for deploy av endring"
    Write-Host "1. PRD -" $(GetDeployEnvDesc "PRD")
    Write-Host "2. TST -" $(GetDeployEnvDesc "TST")
    Write-Host "3. VFT -" $(GetDeployEnvDesc "VFT")
    Write-Host "4. VFK -" $(GetDeployEnvDesc "VFK")
    Write-Host "5. MIG -" $(GetDeployEnvDesc "MIG")
    Write-Host "6. SIT -" $(GetDeployEnvDesc "SIT")
    Write-Host "9. Alle miljøer"

    $envOption = Read-Host "Velg miljø for deploy av endring eller skrien komma separert liste av miljøer (PRD,TST,VFT,VFK,MIG,SIT)"

    $deployEnvStr = $envOption.Trim()
    $deployEnvStr = $deployEnvStr.ToUpper().Replace(' ', '')
    $deployEnvLstTmp = $deployEnvStr.Split(',')

    foreach ($envOption in $deployEnvLstTmp) {
        if ($envOption -eq '1' -or $envOption -eq 'PRD' -or $envOption -eq '9') {
            $deployEnv += 'PRD'
        }
        elseif ($envOption -eq '2' -or $envOption -eq 'TST' -or $envOption -eq '9') {
            $deployEnv += 'TST'
        }
        elseif ($envOption -eq '3' -or $envOption -eq 'VFT' -or $envOption -eq '9') {
            $deployEnv += 'VFT'
        }
        elseif ($envOption -eq '4' -or $envOption -eq 'VFK' -or $envOption -eq '9') {
            $deployEnv += 'VFK'
        }
        elseif ($envOption -eq '5' -or $envOption -eq 'MIG' -or $envOption -eq '9') {
            $deployEnv += 'MIG'
        }
        elseif ($envOption -eq '6' -or $envOption -eq 'SIT' -or $envOption -eq '9') {
            $deployEnv += 'SIT'
        }
    }
}

$global:deployEnv = $deployEnv

if ($changeDescription.Length -eq 0) {
    $changeDescription = ''
    $addkommentar = ''
    Write-Host
    Write-Host '--> Skriv en fornuftig kommentar til overføringen du skal gjøre.'
    Write-Host '--> Kommentaren vil gjelde alle moduler du overfører til du avslutter.'
    Write-Host '--> Avslutt hver linje med Enter - blank linje avslutter kommentar.'
    Write-Host '--> Kommentarer og detaljer om overføringen skrives til' $global:logFile
    Write-Host
    do {
        if ($addkommentar.Length -eq 0 -and $changeDescription.Length -eq 0) {
            Write-Host '**> Du må skrive en kommentar for å fortsette.'
        }
        $addkommentar = ''
        $addkommentar = Read-Host
        if ($addkommentar.Length -eq 0 -and $changeDescription.Length -gt 0) {
            break
        }
        $changeDescription += $addkommentar.ToString().Trim()
    } until ($false)
}

$pos = $changeDescription.IndexOf('.')
if ($pos -gt 0) {
    $changeTitle = $changeDescription.Substring(0, $pos + 1)
    $changeDescription = $changeDescription.Substring($pos + 1).Trim()
}
else {
    $changeTitle = $changeDescription
    $changeDescription = ''
}

# Check if $moduleList is empty
if ($moduleList.Count -eq 0) {
    do {
        $programName = Read-Host '--> Tast programnavn (med filetype). Blank + ENTER avslutter'
        if ($programName -eq '') {
            break
        }
        $programName = $programName.ToString().Trim().ToUpper()
        $pos = $programName.LastIndexOf('.')
        $moduleFileSuffix = $programName.Substring($pos + 1)

        if ($periodPos -gt 0) {
            Write-Host ''
            Write-Host '**> Du har tastet inn et filnavn uten filtype.'
            Write-Host '**> Dette programmet må ha en filtype for å finne ut hvordan det skal deployes til produksjon.'
            Write-Host '**> Prøv igjen.'
            Write-Host ''
            continue
        }
        if ($programName -in $moduleList) {
            Write-Host ''
            Write-Host '**> Du har allerede tastet inn dette programmet.'
            Write-Host '**> Prøv igjen.'
            Write-Host ''
            continue
        }
        if ($programName.Length -gt 0) {
            $source = $global:srcPath + '\' + $programName
            # check if source file exists
            if (!(Test-Path -Path $source -PathType Leaf)) {
                Write-Host ''
                Write-Host '**> Kan ikke finne filen: ' $source
                Write-Host '**> Prøv igjen.'
                Write-Host ''
                LogMessage -message $('Kan ikke finne filen: ' + $source) -severity 'WARNING'
                continue
            }

            $moduleList += $programName
        }
    } until ($false)

    if ($moduleList.Count -eq 0) {
        Write-Host '**> Ingen programmer valgt.'
        Write-Host '**> Avslutter.'
        LogMessage -message 'Ingen programmer valgt. Avslutter.'
        exit
    }
}

# $immediateDeploy
if ($global:immediateDeploy -ne $true) {
    $global:immediateDeploy = $false
    $immediateDeploy = Read-Host '--> Ønsker du umiddelbar overføring til produksjon? (J/N)'
    if ($immediateDeploy.Trim().ToUpper() -in @('J', 'Y', '1', 'JA', 'YES')) {
        # Verify immediate deploy by acceping username and comparing to $env:USERNAME
        $username = Read-Host '--> Tast inn ditt brukernavn for å bekrefte umiddelbar overføring'
        if ($username.ToUpper().Trim() -ne $env:USERNAME.ToUpper().Trim()) {
            Write-Host '**> Brukernavn stemmer ikke overens med ditt eget.'
            Write-Host '**> Avslutter.'
            LogMessage -message 'Brukernavn stemmer ikke overens med ditt eget. Avslutter.' -severity 'ERROR'
            exit
        }
        else {
            $global:immediateDeploy = $true
        }
    }
}

# $serviceNowId
if ($deployEnv -contains 'PRD') {
    if ($serviceNowId -eq '') {
        do {
            $snRequests = @()
            $snRequests = GetServiceNowOpenIssuesForUser -serviceNowId $serviceNowId.ToUpper().Trim()
            ShowServiceNowData -requests $snRequests
            Write-Host '--> Velg fra listen eller skriv inn ServiceNow ID som du vil legge til i listen.'
            Write-Host '--> Hvis du ikke legger til en ServiceNow ID, vil det lages en ny Change Request automatisk.'
            $serviceNowId = Read-Host '--> Tast ditt valg fra listen eller skriv inn ServiceNow ID'
            $serviceNowId = $serviceNowId.Trim().ToUpper()
            # Check if $serviceNowId is a number
            if ($serviceNowId -match '^\d+$') {
                $serviceNowId = $snRequests | Where-Object { $_.Sequence -eq $serviceNowId } | Select-Object -ExpandProperty Number
                $serviceNowId = $serviceNowId.ToString().Trim().ToUpper()
                break
            }
            elseif ($serviceNowId -eq '') {
                break
            }
        } until ($false)
    }

    if ($serviceNowId.Trim().Length -eq 0) {
        # create new ServiceNow Change Request
        CreateServiceNowChangeRequest -changeTitle $changeTitle -changeDescription $changeDescription -moduleList $moduleList
    }
    else {
        # Check if $serviceNowId is a number
        UpdateServiceNowChangeRequest -changeTitle $changeTitle -changeDescription $changeDescription -moduleList $moduleList -serviceNowId $serviceNowId
    }

    # Fix servicenow web url
    try {
        if ($global:servicenow_web_url.Count -gt 1) {
            $global:servicenow_web_url = $global:servicenow_web_url[1]
        }
    }
    catch {
        $global:servicenow_web_url = ""
    }
}

# $moduleList += 'GMAPAYD.CBL'
# $moduleList += 'GMAPAYD2.CBL'
# $moduleList += 'BSHBUOR.CBL'
# $moduleList += 'BKHOPPG.CBL'

################################################################################################################################################
# Handle files
################################################################################################################################################
$ARKIVTXTTMP = $global:tempPath + '_TILTP.TXT'
$ARKIVTXT = $global:tempPath + '\TILTP.TXT'
if (!(Test-Path -Path $global:tempPath)) {
    New-Item -ItemType Directory -Path $global:tempPath | Out-Null
}
else {
    Remove-Item -Path $global:tempPath\* -Force -Recurse -ErrorAction SilentlyContinue | Out-Null
}

if (!(Test-Path -Path $global:tempPath)) {
    New-Item -ItemType Directory -Path $global:tempPath -ErrorAction SilentlyContinue | Out-Null
}

Remove-Item -Path $ARKIVTXTTMP -Force -ErrorAction SilentlyContinue | Out-Null

$fileObjList = @()
foreach ($module in $moduleList) {
    # Create custom object to hold name, sourcename, filedate
    $objInfo = GetModuleInfo -module $module
    $objValInfo = $null

    if ($objInfo.ModuleFileSuffix -eq 'CBL') {
        # get third character in program name
        $thirdChar = $module.Substring(2, 1)
        # check if third character is H or F

        $validationSource = ''
        if ($thirdChar -eq 'H' -or $thirdChar -eq 'F') {
            $validationName = $module.Trim().Substring(0, 2) + 'V' + $module.Trim().Substring(3)
            $validationSource = $global:srcPath + '\' + $validationName
            # check if validation source file exists
            if ((Test-Path -Path $validationSource)) {
                $objValInfo = GetModuleInfo -module $validationName
            }
        }

        $temp = [PSCustomObject]@{
            Name             = $module
            MainModule       = $objInfo
            ValidationModule = $objValInfo
        }
    }
    else {
        $temp = [PSCustomObject]@{
            Name       = $module
            MainModule = $objInfo
        }
    }

    $fileObjList += $temp
}

if ($global:errorMessages.Count -gt 0) {
    Write-Host 'Feil oppstod under scanning av filer:'
    foreach ($message in $global:errorMessages) {
        Write-Host '**> ' $message
    }
    Write-Host
    Write-Host '**> Avslutter.'
    exit
}

if ($global:deployEnv -contains 'PRD') {
    HandleProductionFileBackup -fileObjList $fileObjList
}

CopyFilesToTempPath -fileObjList $fileObjList -tempPath $global:tempPath -deployPath $global:stackPath

$date = Get-Date -Format "yyyyMMdd"
$time = Get-Date -Format "HHmmss"

foreach ($deployEnvItem in $global:deployEnv) {
    $deployEnvItem = $deployEnvItem.ToString()
    $global:deployEnvDesc = $(GetDeployEnvDesc $deployEnvItem)
    if ($global:deployEnvDesc.Length -eq 0) {
        Write-Host "Ugyldig miljø valgt: $deployEnvItem. Avslutter."
        exit
    }

    $global:stackPathEnv = $global:stackPath + '\' + $deployEnvItem
    $global:stackPathEnvDll = $global:stackPathEnv + '\DLL'
    $global:stackPathEnvBnd = $global:stackPathEnv + '\BND'

    if (!(Test-Path -Path $global:stackPathEnv)) {
        New-Item -ItemType Directory -Path $global:stackPathEnv -ErrorAction SilentlyContinue | Out-Null
    }
    if (!(Test-Path -Path $global:stackPathEnvDll)) {
        New-Item -ItemType Directory -Path $global:stackPathEnvDll -ErrorAction SilentlyContinue | Out-Null
    }
    if (!(Test-Path -Path $global:stackPathEnvBnd)) {
        New-Item -ItemType Directory -Path $global:stackPathEnvBnd -ErrorAction SilentlyContinue | Out-Null
    }

    ZipAndArchiveFiles -fileObjList $fileObjList -deployEnvItem $deployEnvItem

    MoveFilesToStackFolder -deployEnvItem $deployEnvItem

    if ($global:immediateDeploy -eq $true) {
        # DeployFiles -fileObjList $fileObjList
    }
}

if ($global:servicenow_web_url.Length -gt 0) {
    Write-Host '--> ServiceNow Change Request URL:' $global:servicenow_web_url
    Start-Process $global:servicenow_web_url
}

Start-Process $global:stackPath

