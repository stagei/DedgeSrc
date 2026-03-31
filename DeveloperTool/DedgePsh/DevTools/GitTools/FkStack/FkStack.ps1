param(
    [string]$inputString = "",
    [string]$changeDescription = "",
    [string]$serviceNowId = "",
    [string]$immediateDeploy = "N")

################################################################################################################################################
# Function definitions
################################################################################################################################################

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

function CreateServiceNowChangeRequest(  
    $changeDescription = 'Oppdatering av Dedge i produksjon',
    $moduleList,
    $serviceNowId = '') {

    $instance = GetServiceNowInstance
    $credential = GetServiceNowCredentials 
            
    $ErrorActionPreference = 'stop'
    $changeUsername = $env:USERNAME
    $tomorrow = [DateTime]::UtcNow.Date.AddDays(1).AddMinutes(10)
    $todayStr = Get-Date -Format "yyyyMMdd"
    $moduleListJoin = "`n - " + ($moduleList -join "`n - ")
    $additionalInfoStr = "Endring av følgende program: " + $moduleListJoin
    $backout_plan = "Hvis noe går galt skal utvalgte filer legges tilbake fra katalogen: N:\COBNT\_backup\$todayStr\$changeUsername\ `nEtter filene er lagt tilbake, vil det ta opptil 20 minutter før alle Citrix serverene er oppdatert. Påvirkede brukere må deretter starte FK-Meny på nytt."
    $close_notes = "Endringen er gjennomført og testet. Ingen feil ble funnet."

    # type = "informational"

    $change = @{
        state             = "Scheduled"
        type              = "standard"
        short_description = "Endringer av FK-Meny program i produksjon"
        description       = $changeDescription
        category          = "Software"
        impact            = "Low"
        urgency           = "Low"
        assignment_group  = "Utvikling FK-meny"
        business_service  = "FK-Meny Prod"
        cmdb_ci           = "FK-Meny Prod"
        unauthorized      = "false"
        approval          = "not requested"
        cab_required      = "false"
        requested_by      = $changeUsername
        assigned_to       = $changeUsername
        close_code        = "successful"
        close_notes       = $close_notes
        closed_at         = $closed_at
        closed_by         = $changeUsername
        backout_plan      = $backout_plan

    } | ConvertTo-Json
    # $change
    # # new - sched - implement -review - close

    $uri = "https://$serviceNowInstance.service-now.com/api/now/v1/table/change_request"
    try {
        $changeInfo = Invoke-RestMethod -Method Post -Uri $uri -Body $change -Credential $credential -ContentType "application/json"
    }
    catch {
        Write-Host "##[error]$_"
    }

    $changeNumber = $changeInfo.result[0].number
    # $changeNumber
    $sysId = $changeInfo.result[0].sys_id


    # $uri = "https://$serviceNowInstance.service-now.com/api/now/v1/table/change_request/$sysId"
    # Write-Host "Change Request Link XML: $uri"

    # $uri = "https://$serviceNowInstance.service-now.com/nav_to.do?uri=change_request.do?sys_id=$sysId"
    # Write-Host "Change Request Link Web: $uri"

    $servicenow_web_url = "https://$serviceNowInstance.service-now.com/nav_to.do?uri=change_request.do?number=$changeNumber"
    Write-Host "Change Request Link Web: $uri"

    # $uri = "https://$serviceNowInstance.service-now.com/nav_to.do?uri=change_request.do?sys_id=$sysId"
    # Write-Host "Requeste By XML: " + $changeInfo.result[0].requested_by.link

    # Construct the updated JSON payload
    $additionalInfo = @{
        comments = $additionalInfoStr
    } | ConvertTo-Json

    # Send the PUT request to update the change request
    $uri = "https://$serviceNowInstance.service-now.com/api/now/v1/table/change_request/$sysId"
    Invoke-RestMethod -Uri $uri -Method Put -Body $additionalInfo -Credential $credential -ContentType "application/json"


    # Construct the JSON payload to close the change request
    $closePayload = @{
        state = "Implement"
    } | ConvertTo-Json

    # Send the PUT request to close the change request
    $uri = "https://$serviceNowInstance.service-now.com/api/now/v1/table/change_request/$sysId"
    Invoke-RestMethod -Uri $uri -Method Put -Body $closePayload -Credential $credential -ContentType "application/json"

    $closePayload = @{
        state = "Review"
    } | ConvertTo-Json

    # Send the PUT request to close the change request
    $uri = "https://$serviceNowInstance.service-now.com/api/now/v1/table/change_request/$sysId"
    Invoke-RestMethod -Uri $uri -Method Put -Body $closePayload -Credential $credential -ContentType "application/json"


    $closePayload = @{
        state = "Closed"
    } | ConvertTo-Json

    # Send the PUT request to close the change request
    $uri = "https://$serviceNowInstance.service-now.com/api/now/v1/table/change_request/$sysId"
    Invoke-RestMethod -Uri $uri -Method Put -Body $closePayload -Credential $credential -ContentType "application/json"

    return $servicenow_web_url
}
function CreateServiceNowChangeRequestOld(  
    $username = 'Dedge.integration',
    $password = 'XTj0+SP.1A',
    $serviceNowInstance = 'fkatest',
    $changeDescription = 'Oppdatering i produksjon',
    $moduleList,
    $serviceNowId = '') {

        
    $ErrorActionPreference = 'stop'
    $changeUsername = $env:USERNAME
    $tomorrow = [DateTime]::UtcNow.Date.AddDays(1).AddMinutes(10)


    # Remove all file extensions from the list
    $fileList = @()
    foreach ($item in $moduleList.Split(",")) {
        if ($item.Contains(".")) {
            $temp = $item.Split(".")[0]
            $fileList += "`n        " + $temp.Trim().ToUpper()
        }
        else {
            $fileList += "`n        " + $item.Trim().ToUpper()
        }
    }
    $fileList = $fileList | Sort-Object -Unique




    $additionalInfoStr = "Endring av følgende program: $fileList"
    $backout_plan = "Hvis noe går galt skal utvalgte filer legges tilbake fra katalogen: N:\COBNT\_backup\$todayStr\$changeUsername\ `nEtter filene er lagt tilbake, vil det ta opptil 20 minutter før alle Citrix serverene er oppdatert. Påvirkede brukere må deretter starte FK-Meny på nytt."


    # type = "informational"

    $change = @{
        state             = "Scheduled"
        type              = "standard"
        short_description = "Endringer av FK-Meny program i produksjon"
        description       = $changeDescription
        category          = "Software"
        impact            = "Low"
        urgency           = "Low"
        assignment_group  = "Utvikling FK-meny"
        business_service  = "FK-Meny Prod"
        cmdb_ci           = "FK-Meny Prod"
        unauthorized      = "false"
        approval          = "not requested"
        cab_required      = "false"
        requested_by      = $changeUsername
        assigned_to       = $changeUsername
        close_code        = "successful"
        close_notes       = $close_notes
        closed_at         = $closed_at
        closed_by         = $changeUsername
        backout_plan      = $backout_plan

    } | ConvertTo-Json
    $change
    # new - sched - implement -review - close

    $uri = "https://$serviceNowInstance.service-now.com/api/now/v1/table/change_request"
    try {
        $bytes = [System.Text.Encoding]::ASCII.GetBytes(('{0}:{1}' -f ($username, $password)))
        $headers = @{
            Authorization  = 'Basic {0}' -f ([System.Convert]::ToBase64String($bytes))
            'Content-type' = 'application/json'
        }
        $changeInfo = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $change    
    }
    catch {
        Write-Host "##[error]$_"
    }

    $changeNumber = $changeInfo.result[0].display_value
    $changeNumber = $changeInfo.result[0].number
    $changeNumber
    $sysId = $changeInfo.result[0].sys_id


    $uri = "https://$serviceNowInstance.service-now.com/api/now/v1/table/change_request/$sysId"
    Write-Host "Change Request Link XML: $uri"

    $uri = "https://$serviceNowInstance.service-now.com/nav_to.do?uri=change_request.do?sys_id=$sysId"
    Write-Host "Change Request Link Web: $uri"

    $uri = "https://$serviceNowInstance.service-now.com/nav_to.do?uri=change_request.do?sys_id=$sysId"
    Write-Host "Requeste By XML: " + $changeInfo.result[0].requested_by.link

    # Construct the updated JSON payload
    $additionalInfo = @{
        comments = $additionalInfoStr
    } | ConvertTo-Json

    # Send the PUT request to update the change request
    $uri = "https://$serviceNowInstance.service-now.com/api/now/v1/table/change_request/$sysId"
    $headers = @{
        Authorization  = 'Basic {0}' -f ([System.Convert]::ToBase64String($bytes))
        'Content-type' = 'application/json'
    }
    Invoke-RestMethod -Uri $uri -Method Put -Headers $headers -Body $additionalInfo


    # Construct the JSON payload to close the change request
    $closePayload = @{
        state = "Implement"
    } | ConvertTo-Json

    # Send the PUT request to close the change request
    $uri = "https://$serviceNowInstance.service-now.com/api/now/v1/table/change_request/$sysId"
    $headers = @{
        Authorization  = 'Basic {0}' -f ([System.Convert]::ToBase64String($bytes))
        'Content-type' = 'application/json'
    }
    Invoke-RestMethod -Uri $uri -Method Put -Headers $headers -Body $closePayload

    $closePayload = @{
        state = "Review"
    } | ConvertTo-Json

    # Send the PUT request to close the change request
    $uri = "https://$serviceNowInstance.service-now.com/api/now/v1/table/change_request/$sysId"
    $headers = @{
        Authorization  = 'Basic {0}' -f ([System.Convert]::ToBase64String($bytes))
        'Content-type' = 'application/json'
    }
    Invoke-RestMethod -Uri $uri -Method Put -Headers $headers -Body $closePayload


    $closePayload = @{
        state = "Closed"
    } | ConvertTo-Json

    # Send the PUT request to close the change request
    $uri = "https://$serviceNowInstance.service-now.com/api/now/v1/table/change_request/$sysId"
    $headers = @{
        Authorization  = 'Basic {0}' -f ([System.Convert]::ToBase64String($bytes))
        'Content-type' = 'application/json'
    }
    Invoke-RestMethod -Uri $uri -Method Put -Headers $headers -Body $closePayload


    # new - sched - implement -review - close
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
function GetServiceNowData ($url, $credential) {
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
    $incidentUrl = "https://$instance.service-now.com/api/now/table/incident?sysparm_query=assigned_to=" + $userSysID + '&sysparm_fields=number,short_description,priority,state'
    $incidents = GetServiceNowData -url $incidentUrl -credential $credential
    # Get the incident related to the serviceNowId if any
    if ($serviceNowId.StartsWith('INC')) {
        $incidentUrl = "https://$instance.service-now.com/api/now/table/incident?sysparm_query=number=" + $serviceNowId + '&sysparm_fields=number,short_description,priority,state'
        $incidents += GetServiceNowData -url $incidentUrl -credential $credential
    }
    if ($incidents -ne $null) {
        $incidents | Add-Member -MemberType NoteProperty -Name Type -Value 'Incident' -PassThru | Out-Null
    }

    # Get the service requests assigned to the user represented by the userSysID
    $srrequestUrl = "https://$instance.service-now.com/api/now/table/sc_request?sysparm_query=assigned_to=" + $userSysID + '&sysparm_fields=number,short_description,priority,state'
    $srrequests = GetServiceNowData -url $srrequestUrl  -credential $credential
    # Get the incident related to the serviceNowId if any
    if ($serviceNowId.StartsWith('SC')) {
        $srrequestUrl = "https://$instance.service-now.com/api/now/table/sc_request?sysparm_query=number=" + $serviceNowId + '&sysparm_fields=number,short_description,priority,state'
        $srrequests += GetServiceNowData -url $incidentUrl -credential $credential
    }
    if ($srrequests -ne $null) {
        $srrequests | Add-Member -MemberType NoteProperty -Name Type -Value 'Service Request' -PassThru | Out-Null
    }

    # Get the change requests assigned to the user represented by the userSysID
    $crrequestUrl = "https://$instance.service-now.com/api/now/table/change_request?sysparm_query=state<3&assigned_to=" + $userSysID + '&sysparm_fields=number,short_description,priority,state'
    $crrequests = GetServiceNowData -url $crrequestUrl -credential $credential
    if ($serviceNowId.StartsWith('CHG')) {
        $srrequestUrl = "https://$instance.service-now.com/api/now/table/change_request?sysparm_query=number=" + $serviceNowId + '&sysparm_fields=number,short_description,priority,state'
        $srrequests += GetServiceNowData -url $incidentUrl -credential $credential
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
    $requests = $requests | Sort-Object -Property number 

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

function ShowServiceNowData ($requests) {
    $requests | Format-Table -Property @{Label = "Valg"; Expression = { $_.Sequence } }, @{Label = "ServiceNowId"; Expression = { $_.number } }, @{Label = "Type"; Expression = { $_.Type } }, @{Label = "Beskrivelse"; Expression = { $_.short_description } }, @{Label = "Prioritet"; Expression = { $_.priority } }, @{Label = "Status"; Expression = { $_.state }; Alignment = "Right" }, @{Label = "Status beskrivelse"; Expression = { $_.stateText } } -AutoSize
}

function ZipAndArchiveFiles {
    param (
        [Parameter(Mandatory = $true)]
        [System.Collections.ArrayList]$fileObjList,
        
        [Parameter(Mandatory = $true)]
        [string]$tempPath,
        
        [Parameter(Mandatory = $true)]
        [string]$archivePath
    )

    foreach ($fileObj in $fileObjList) {
        $folder = $tempPath + '\' + $fileObj.ModuleFileName
        # Zip files in $tempPath
        $date = Get-Date -Format "ddMMyy"
        $time = Get-Date -Format "HHmmss"
        $zipFileName = $fileObj.ModuleFileName + '_' + $date + '_' + $time + '_TIL_PROD'
        
        $archivePathModule = $archivePath + '\' + $fileObj.ModuleFileName

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
            $folder = $tempPath + '\' + $fileObj.ModuleFileName + '\'
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

        $deployPathCpy = $deployPathSrc + '\CPY'
        if (!(Test-Path -Path $deployPathCpy)) {
            New-Item -ItemType Directory -Path $folderCpy -ErrorAction SilentlyContinue | Out-Null
        }

        # Copy module source to deployPath
        $source = $moduleInfo.BasePath + '.' + $moduleInfo.ModuleFileSuffix
        $dest = $deployPath + '\' + $moduleInfo.ModuleFileName
        Copy-Item -Path $source -Destination $dest -Force -ErrorAction SilentlyContinue

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
        }

        foreach ($copyFile in $moduleInfo.CopyFiles) {
            # Copy copy files to deployPath
            $source = $copyFile
            $dest = $deployPathCpy + '\' + $copyFile.Substring($copyFile.LastIndexOf('\') + 1)
            Copy-Item -Path $source -Destination $dest -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        $deployPathCommon = $deployPathSrc + '\' + $moduleInfo.ModuleFileSuffix
        if (!(Test-Path -Path $deployPathCommon)) {
            New-Item -ItemType Directory -Path $deployPathCommon -ErrorAction SilentlyContinue | Out-Null
        }
        
        # Copy module source to deployPathSrc plus ModuleFileSuffix
        $source = $moduleInfo.BasePath + $moduleInfo.ModuleFileSuffix
        $dest = $deployPathCommon + '\' + $moduleInfo.ModuleFileName
        Copy-Item -Path $source -Destination $dest -Force -ErrorAction SilentlyContinue

        if ($moduleInfo.ModuleFileSuffix -ne 'SQL') {
            # Copy module source to deployPath
            $source = $moduleInfo.BasePath + $moduleInfo.ModuleFileSuffix
            $dest = $deployPath + '\' + $moduleInfo.ModuleFileName
            Copy-Item -Path $source -Destination $dest -Force -ErrorAction SilentlyContinue
        }
    }
}

function CopyModuleFiles($moduleInfo, $folderName) {
    $moduleTempPath = $global:tempPath + '\' + $folderName
    CopyModuleFilesToPath -moduleInfo $moduleInfo -deployPath $moduleTempPath

    CopyModuleFilesToPath -moduleInfo $moduleInfo -deployPath $global:stackPath

    if ($global:immediateDeploy -eq $true) {
        CopyModuleFilesToPath -moduleInfo $moduleInfo -deployPath $global:prodExecPath
    }
}
function CopyFilesToTempPath($fileObjList) {
    foreach ($fileObj in $fileObjList) {
        CopyModuleFiles $fileObj.ModuleFileName $fileObj.MainModule $fileObj.ModuleFileName
    
        if ($null -ne $fileObj.ValidationModule) {
            CopyModuleFiles $fileObj.ValidationModule.ModuleFileName $fileObj.ValidationModule $fileObj.ModuleFileName
        }
    }
}
function BackupProdModule ($moduleInfo, $backupFolder) {
    if ($moduleInfo.ModuleFileSuffix -eq 'CBL') {
        $module = $moduleInfo.ModuleFileName
        $srcFile = $moduleInfo.BasePath + '.CBL'
        $srcBackupFile = $backupFolder + '\' + $module + '.CBL'
        if ((Test-Path -Path $srcFile -PathType Leaf)) {
            Copy-Item -Path $srcFile -Destination $srcBackupFile -Force -ErrorAction SilentlyContinue
        }

        $intFile = $global:prodExecPath + '\' + $module + '.INT'
        $intBackupFile = $backupFolder + '\' + $module + '.INT'
        if ((Test-Path -Path $intFile -PathType Leaf)) {
            Copy-Item -Path $intFile -Destination $intBackupFile -Force -ErrorAction SilentlyContinue
        }

        $idyFile = $global:prodExecPath + '\' + $module + '.IDY'
        $idyBackupFile = $backupFolder + '\' + $module + '.IDY'
        if ((Test-Path -Path $idyFile -PathType Leaf)) {
            Copy-Item -Path $idyFile -Destination $idyBackupFile -Force -ErrorAction SilentlyContinue
        }

        $gsFile = $global:prodExecPath + '\' + $module + '.GS'
        $gsBackupFile = $backupFolder + '\' + $module + '.GS'
        if ((Test-Path -Path $gsFile -PathType Leaf)) {
            Copy-Item -Path $gsFile -Destination $gsBackupFile -Force -ErrorAction SilentlyContinue
        }

        $bndFile = $global:prodExecPath + '\BND\' + $module + '.BND'
        $bndBackupFile = $backupFolder + '\BND\' + $module + '.BND'
        if ((Test-Path -Path $bndFile -PathType Leaf)) {
            Copy-Item -Path $bndFile -Destination $bndBackupFile -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        $module = $moduleInfo.ModuleFileName
        $srcFile = $moduleInfo.BasePath + $moduleInfo.ModuleFileSuffix
        $srcBackupFile = $backupFolder + '\' + $module + $moduleInfo.ModuleFileSuffix
        if ((Test-Path -Path $srcFile -PathType Leaf)) {
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
    $pos = $module.LastIndexOf('.')
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
        $useSql = CblUseSql -module $basePath + '.CBL'
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
        $srcTime = GetFileLastWrittenTime -filePath ($basePath + $moduleFileSuffix)
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

    foreach ($element in $sqlString) {
        $sqlStatement = $element.Trim().ToUpper()
        if ($sqlStatement -match '^\s*\$SET\s+DB2') {
            return $true
        }
    }    
    return $false
}

################################################################################################################################################
# Init part
################################################################################################################################################
$global:errorMessages = @()
$global:srcPath = 'C:\FKAVD\NT'         
$global:cblCpyPath = 'C:\FKAVD\SYS\CPY'    
$global:prodExecPath = 'C:\COBNT'
$global:stackPath = 'C:\COBTP'             
$global:stackPathDll = 'C:\COBTP\DLL'
$global:stackPathBnd = 'C:\COBTP\BND'
$global:stackPathSrc = 'C:\COBTP\SRC'
$global:stackPathCpy = 'C:\COBTP\CPY'
$global:archivePath = 'C:\CBLARKIV'
$global:logPath = $global:srcPath + '\TILTP'
$global:logFile = $global:logPath + '\TILTP.LOG'
$global:tempPath = $global:archivePath + '\TMP\' + $env:USERNAME
$global:serviceNowInstance = 'fkatest'



if (!(Test-Path -Path $global:stackPath)) {
    New-Item -ItemType Directory -Path $global:stackPath -ErrorAction SilentlyContinue | Out-Null
}
if (!(Test-Path -Path $global:stackPathDll)) {
    New-Item -ItemType Directory -Path $global:stackPathDll -ErrorAction SilentlyContinue | Out-Null
}
if (!(Test-Path -Path $global:stackPathBnd)) {
    New-Item -ItemType Directory -Path $global:stackPathBnd -ErrorAction SilentlyContinue | Out-Null
}
if (!(Test-Path -Path $global:stackPathDll)) {
    New-Item -ItemType Directory -Path $global:stackPathDll -ErrorAction SilentlyContinue | Out-Null
}
if (!(Test-Path -Path $global:stackPathSrc)) {
    New-Item -ItemType Directory -Path $global:stackPathSrc -ErrorAction SilentlyContinue | Out-Null
}
if (!(Test-Path -Path $global:stackPathCpy)) {
    New-Item -ItemType Directory -Path $global:stackPathCpy -ErrorAction SilentlyContinue | Out-Null
}
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
$inputString = $inputString.Trim().ToUpper().Replace(' ', '')
$deployModule = $null

if ($inputString.Contains('?')) {
    Write-Host 'Parametre:'
    Write-Host '1. inputString    : Flerbruks tekststreng'
    Write-Host '    - Alternativ 1: Komma separert liste av filnavn med filtype (CBL, REX, BAT, CMD). '
    Write-Host '    - Alternativ 2: Tekststreng som inneholder filnavn til tekstfil med filnavn deploy info'
    Write-Host '2. comment        : Kommentar til overføringen'
    Write-Host '3. serviceNowId   : ServiceNow ID'
    Write-Host '4. immediateDeploy: Umiddelbar overføring (J/N)'
    # Read char if more help is needed
    $readChar = Read-Host 'Trykk ? for mer hjelp om inputString Alternativ 2 og formattering av filen.'
    if (readChar -eq '?') {
        Write-Host 'Alternativ 2: Tekststreng som inneholder filnavn til tekstfil med filnavn deploy info'

        Write-Host '--------------------------------------------------------------------------------'
        Write-Host 'Filnavn til tekstfil med filnavn deploy info må være på formatet:'
        Write-Host '--------------------------------------------------------------------------------'
        Write-Host 'COMMENT:Kommentar til overføringen'
        Write-Host 'PROGRAM:Programnavn1'
        Write-Host 'PROGRAM:Programnavn2'
        Write-Host 'PROGRAM:Programnavn3'
        Write-Host '...'
        Write-Host 'PROGRAM:ProgramnavnN'
        Write-Host 'SERVICE_NOW_ID:ServiceNow ID'
        Write-Host 'IMMEDIATE_DEPLOY:J/N'
        Write-Host '--------------------------------------------------------------------------------'
        Write-Host 'Eksempel:'
        Write-Host '--------------------------------------------------------------------------------'
        Write-Host 'COMMENT:Deploy av endringer i programmet som følge av innmeldt problem'
        Write-Host 'PROGRAM:WKSTYR.REX'
        Write-Host 'PROGRAM:GMAPAYD2.CBL'
        Write-Host 'PROGRAM:HIST.BAT'
        Write-Host 'SERVICE_NOW_ID:INC1234567'
        Write-Host 'IMMEDIATE_DEPLOY:J'
    }

    Write-Host '**> Avslutter.'
    exit
}
elseif ($inputString.EndsWith('.TXT')) {
    $inputStringContent = Get-Content -Path $inputString
    foreach ($line in $inputStringContent) {
        $line = $line.Trim().ToUpper()
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
        elseif ($line.StartsWith('IMMEDIATE_DEPLOY:')) {
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
    $msg = ' UMIDDELBAR overføring av programmer fra ' + $global:srcPath + ' til ' + $global:prodExecPath + ' av bruker:' + $env:USERNAME + ' '
    $padding = (80 - $msg.Length) / 2
    $centeredMsg = ('*' * $padding) + $msg + ('*' * $padding)
    Write-Host $centeredMsg
}
else {
    $msg = ' Overføring av programmer fra ' + $global:srcPath + ' til ' + $global:stackPath + ' av bruker ' + $env:USERNAME + ' '
    $padding = (80 - $msg.Length) / 2
    $centeredMsg = ('*' * $padding) + $msg + ('*' * $padding)
    Write-Host $centeredMsg
}
Write-Host ''




$moduleList += 'BKFINFA.CBL'
$moduleList += 'WKSTYR.REX'
$changeDescription = 'Deploy av endringer i programmet som følge av innmeldt problem'




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
                continue
            }

            $moduleList += $programName
        }
    } until ($false)

    if ($moduleList.Count -eq 0) {
        Write-Host '**> Ingen programmer valgt.'
        Write-Host '**> Avslutter.'
        exit
    }
}


# $serviceNowId
if ($serviceNowId -eq '') {
    do {
        GetServiceNowOpenIssuesForUser -serviceNowId $serviceNowId.ToUpper().Trim()
        Write-Host '--> Velg fra listen eller skriv inn ServiceNow ID som du vil legge til i listen.'
        Write-Host '--> Hvis du ikke legger til en ServiceNow ID, vil det lages en ny Change Request automatisk.'
        $serviceNowId = Read-Host '--> Tast ditt valg fra listen eller skriv inn ServiceNow ID'
        $serviceNowId = $serviceNowId.Trim().ToUpper()
        # Check if $serviceNowId is a number
        if ($serviceNowId -match '^\d+$') {
            $serviceNowId = $requests[$serviceNowId - 1].Number
            break
        }
        elseif ($serviceNowId -eq '') {
            break
        }
    } until ($false)
    
    if ($serviceNowId.Trim().Length -eq 0) {
        # create new ServiceNow Change Request
        CreateServiceNowChangeRequest -comment $changeDescription -moduleList $moduleList
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
            exit
        }
        else {
            $global:immediateDeploy = $true
        }
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
            $validationSource = $global:srcPath + '\' + $validationName + '.CBL'
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


HandleProductionFileBackup -fileObjList $fileObjList

CopyFilesToTempPath $fileObjList 

ZipAndArchiveFiles -fileObjList $fileObjList -tempPath $global:tempPath -archivePath $global:archivePath


