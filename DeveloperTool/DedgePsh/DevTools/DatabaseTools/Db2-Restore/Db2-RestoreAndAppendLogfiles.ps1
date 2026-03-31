# Db2-RestoreAndAppendLogfiles.ps1
#
# Restores a Db2 online backup image and then rolls forward using
# archived log files created after the backup, enabling point-in-time
# recovery from days-old backups.
#
# The key DB2 sequence:
#   1. RESTORE DATABASE ... REDIRECT GENERATE SCRIPT ... (with LOGTARGET)
#   2. Copy archived log files into the logtarget/overflow folder
#   3. ROLLFORWARD DB ... TO END OF LOGS AND STOP OVERFLOW LOG PATH (...)
#   4. ACTIVATE DB

param(
    [Parameter(Mandatory = $false)]
    [string]$InstanceName = "",
    [Parameter(Mandatory = $false)]
    [string]$DatabaseName = "",
    [Parameter(Mandatory = $false)]
    [string]$BackupImagePath = "",
    [Parameter(Mandatory = $false)]
    [string]$ArchivedLogPath = "",
    [Parameter(Mandatory = $false)]
    [string]$RollforwardTo = "",
    [Parameter(Mandatory = $false)]
    [string[]]$SmsNumbers = @(),
    [Parameter(Mandatory = $false)]
    [string]$OverrideWorkFolder = ""
)

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

###################################################################################
# Main
###################################################################################
try {
    Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
    Test-Db2ServerAndAdmin

    # --- Instance selection ---
    if ([string]::IsNullOrEmpty($InstanceName)) {
        $InstanceName = Get-UserChoiceForInstanceName -ThrowOnTimeout -DatabaseType "PrimaryDb"
    }

    # --- Database selection ---
    if ([string]::IsNullOrEmpty($DatabaseName)) {
        $DatabaseName = Get-UserChoiceForDatabaseName -ThrowOnTimeout
    }

    # --- Backup image path ---
    if ([string]::IsNullOrEmpty($BackupImagePath)) {
        $BackupImagePath = Read-Host "Enter path to backup image (.001 file)"
        if ([string]::IsNullOrEmpty($BackupImagePath)) {
            throw "Backup image path is required"
        }
    }
    if (-not (Test-Path -Path $BackupImagePath -PathType Leaf)) {
        throw "Backup image not found: $($BackupImagePath)"
    }

    # --- Archived log path ---
    if ([string]::IsNullOrEmpty($ArchivedLogPath)) {
        $ArchivedLogPath = Read-Host "Enter path to archived log files folder (containing S*.LOG)"
        if ([string]::IsNullOrEmpty($ArchivedLogPath)) {
            throw "Archived log path is required"
        }
    }
    if (-not (Test-Path -Path $ArchivedLogPath -PathType Container)) {
        throw "Archived log folder not found: $($ArchivedLogPath)"
    }

    # --- SMS numbers ---
    if ($SmsNumbers.Count -eq 0) {
        $SmsNumbers = Get-UserChoiceForSmsNumbers
    }

    # --- Rollforward target ---
    $rollforwardTarget = if ([string]::IsNullOrEmpty($RollforwardTo)) { "end of logs" } else { $RollforwardTo }

    # --- Work object setup ---
    $workObjects = Get-DefaultWorkObjects -DatabaseType "PrimaryDb" -DatabaseName $DatabaseName -InstanceName $InstanceName -SmsNumbers $SmsNumbers -OverrideWorkFolder $OverrideWorkFolder -SkipRecreateDb2Folders -SkipDb2StateInfo
    $workObject = if ($workObjects -is [array]) { $workObjects[-1] } else { $workObjects }

    $workFolder = $workObject.WorkFolder
    if (-not (Test-Path -Path $workFolder -PathType Container)) {
        New-Item -Path $workFolder -ItemType Directory -Force | Out-Null
    }

    Write-LogMessage "RestoreAndAppendLogfiles: DB=$($DatabaseName), Instance=$($InstanceName), BackupImage=$($BackupImagePath), ArchivedLogs=$($ArchivedLogPath), RollforwardTo=$($rollforwardTarget)" -Level INFO

    # --- Resolve DB2 folders ---
    $workObject = Get-Db2Folders -WorkObject $workObject -FolderName "All"
    if ($workObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $workObject = $workObject[-1] }

    $restoreFolder = $workObject.RestoreFolder
    $logtargetFolder = $workObject.LogtargetFolder

    # --- Copy backup image to restore folder if it's a UNC or different location ---
    $backupFileName = Split-Path -Path $BackupImagePath -Leaf
    $localBackupFile = Join-Path $restoreFolder $backupFileName

    if ($BackupImagePath -ne $localBackupFile) {
        Write-LogMessage "Copying backup image to restore folder: $($restoreFolder)" -Level INFO
        Copy-Item -Path $BackupImagePath -Destination $restoreFolder -Force
        Write-LogMessage "Backup image staged at: $($localBackupFile)" -Level INFO
    }

    # --- Parse backup header ---
    $headerInfo = Get-Db2BackupHeaderInfo -BackupFilePath $localBackupFile -WorkFolder $workFolder
    Add-Member -InputObject $workObject -NotePropertyName "BackupFile" -NotePropertyValue $localBackupFile -Force
    Add-Member -InputObject $workObject -NotePropertyName "Timestamp" -NotePropertyValue $headerInfo.Timestamp -Force
    Add-Member -InputObject $workObject -NotePropertyName "SourceDatabaseName" -NotePropertyValue $headerInfo.DatabaseName -Force
    Add-Member -InputObject $workObject -NotePropertyName "BackupMode" -NotePropertyValue $headerInfo.BackupMode -Force
    Add-Member -InputObject $workObject -NotePropertyName "Buffer" -NotePropertyValue "2050" -Force
    Add-Member -InputObject $workObject -NotePropertyName "Parallelism" -NotePropertyValue "10" -Force

    Write-LogMessage "Backup header: Source=$($headerInfo.DatabaseName), Timestamp=$($headerInfo.Timestamp), Mode=$($headerInfo.BackupMode), IncludesLogs=$($headerInfo.IncludesLogs)" -Level INFO

    if (-not $headerInfo.IncludesLogs) {
        Write-LogMessage "Backup does not include logs — this is an offline backup. Rollforward with archived logs may not work as expected." -Level WARN
    }

    # --- SMS: started ---
    $smsMessage = "RestoreAndAppendLogfiles STARTED`nDB: $($DatabaseName)`nFrom: $($headerInfo.DatabaseName)`nTimestamp: $($headerInfo.Timestamp)`nOn: $($env:COMPUTERNAME)"
    foreach ($smsNumber in $SmsNumbers) {
        Send-Sms -Receiver $smsNumber -Message $smsMessage
    }

    # --- Step 1: Quiesce + deactivate target DB ---
    Write-LogMessage "Step 1: Preparing target database (stop/clean/start/quiesce/deactivate)" -Level INFO
    $db2Commands = @()
    $db2Commands += "set DB2INSTANCE=$($workObject.InstanceName)"
    $db2Commands += "db2stop force"
    $db2Commands += "rd /s /q $($workObject.PrimaryLogsFolder)"
    $db2Commands += "md $($workObject.PrimaryLogsFolder)"
    $db2Commands += "rd /s /q $($workObject.MirrorLogsFolder)"
    $db2Commands += "md $($workObject.MirrorLogsFolder)"
    $db2Commands += "rd /s /q $($logtargetFolder)"
    $db2Commands += "md $($logtargetFolder)"
    $db2Commands += "db2start"
    $db2Commands += $(Get-SetInstanceNameCommand -WorkObject $workObject)
    $db2Commands += $(Get-ConnectCommand -WorkObject $workObject)
    $db2Commands += "db2 quiesce database immediate force connections"
    $db2Commands += "db2 connect reset"
    $db2Commands += "db2 deactivate database $($workObject.DatabaseName)"

    $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName $(Join-Path $workFolder "Step1_PrepareTarget.bat") -IgnoreErrors
    $workObject = Add-ScriptAndOutputToWorkObject -WorkObject $workObject -Name "Step1_PrepareTarget" -Script ($db2Commands -join "`n") -Output $output

    # Refresh folder paths after clean
    $workObject = Get-Db2Folders -WorkObject $workObject -FolderName "LogtargetFolder"
    if ($workObject -is [array]) { $workObject = $workObject[-1] }
    $workObject = Get-Db2Folders -WorkObject $workObject -FolderName "PrimaryLogsFolder"
    if ($workObject -is [array]) { $workObject = $workObject[-1] }
    $workObject = Get-Db2Folders -WorkObject $workObject -FolderName "MirrorLogsFolder"
    if ($workObject -is [array]) { $workObject = $workObject[-1] }
    $logtargetFolder = $workObject.LogtargetFolder

    # --- Step 2: RESTORE ... REDIRECT GENERATE SCRIPT ---
    Write-LogMessage "Step 2: Generating redirect restore script" -Level INFO
    $step2ScriptFile = Join-Path $workFolder "Step2_GeneratedRestoreContainerScript.sql"
    $db2Commands = @()
    $db2Commands += "set DB2INSTANCE=$($workObject.InstanceName)"
    $db2Commands += "db2 restore database $($headerInfo.DatabaseName) FROM '$($restoreFolder)' TAKEN AT $($headerInfo.Timestamp) INTO $($workObject.DatabaseName) REDIRECT GENERATE SCRIPT '$($step2ScriptFile)'"
    $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName $(Join-Path $workFolder "Step2_RestoreGenerateScript.bat")
    $workObject = Add-ScriptAndOutputToWorkObject -WorkObject $workObject -Name "Step2_RestoreGenerateScript" -Script ($db2Commands -join "`n") -Output $output

    # Handle SQL2532N: backup DB name differs from filename
    if ($output -match "SQL2532N") {
        $actualDbMatch = [regex]::Match($output, '(?:databasen|database)\s+"([^"]+)"')
        if ($actualDbMatch.Success) {
            $actualSourceDb = $actualDbMatch.Groups[1].Value
            Write-LogMessage "SQL2532N: Backup is from '$($actualSourceDb)', not '$($headerInfo.DatabaseName)'. Retrying." -Level WARN
            $headerInfo.DatabaseName = $actualSourceDb
            Add-Member -InputObject $workObject -NotePropertyName "SourceDatabaseName" -NotePropertyValue $actualSourceDb -Force
            $db2Commands = @()
            $db2Commands += "set DB2INSTANCE=$($workObject.InstanceName)"
            $db2Commands += "db2 restore database $($actualSourceDb) FROM '$($restoreFolder)' TAKEN AT $($headerInfo.Timestamp) INTO $($workObject.DatabaseName) REDIRECT GENERATE SCRIPT '$($step2ScriptFile)'"
            $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName $(Join-Path $workFolder "Step2_RestoreGenerateScript_Retry.bat")
            $workObject = Add-ScriptAndOutputToWorkObject -WorkObject $workObject -Name "Step2_RestoreGenerateScript_Retry" -Script ($db2Commands -join "`n") -Output $output
        }
    }

    # --- Step 3: Modify and execute the generated redirect restore script ---
    Write-LogMessage "Step 3: Executing modified restore container script (with LOGTARGET)" -Level INFO
    $workObject = Invoke-ModifiedRestoreContainerScript -WorkObject $workObject -Step3GeneratedRestoreContainerScriptFile $step2ScriptFile

    # --- Step 4: Copy archived log files into logtarget ---
    Write-LogMessage "Step 4: Copying archived log files to logtarget folder" -Level INFO

    $minLogSeq = -1
    if ($headerInfo.LastLog -match '^S(\d+)\.LOG$') {
        $minLogSeq = [int]$Matches[1]
        Write-LogMessage "Backup's last embedded log is $($headerInfo.LastLog) — copying archived logs from sequence $($minLogSeq) onward" -Level INFO
    }

    $copiedLogCount = Copy-Db2ArchivedLogFiles -SourceLogPath $ArchivedLogPath -TargetLogPath $logtargetFolder -MinLogSequence $minLogSeq
    Write-LogMessage "Copied $($copiedLogCount) archived log files to $($logtargetFolder)" -Level INFO

    if ($copiedLogCount -eq 0) {
        Write-LogMessage "No archived log files were copied. Rollforward will use only logs embedded in the backup image." -Level WARN
    }

    # --- Step 5: ROLLFORWARD with OVERFLOW LOG PATH ---
    Write-LogMessage "Step 5: Rolling forward database with overflow log path" -Level INFO
    $step5ScriptFile = Join-Path $workFolder "Step5_RollforwardAndActivate.bat"
    $db2Commands = @()
    $db2Commands += "set DB2INSTANCE=$($workObject.InstanceName)"
    $db2Commands += "db2 rollforward db $($workObject.DatabaseName) to $($rollforwardTarget) and stop overflow log path($($logtargetFolder))"
    $db2Commands += "db2start"
    $db2Commands += "db2 activate db $($workObject.DatabaseName)"
    $db2Commands += " "

    $errorCount = 0
    try {
        $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName $step5ScriptFile
        $workObject = Add-ScriptAndOutputToWorkObject -WorkObject $workObject -Name "Step5_RollforwardAndActivate" -Script ($db2Commands -join "`n") -Output $output
        Add-Member -InputObject $workObject -NotePropertyName "RollforwardAndActivateOutput" -NotePropertyValue $output -Force
    }
    catch {
        Write-LogMessage "Error executing rollforward. Waiting 60 seconds and retrying..." -Level ERROR -Exception $_
        $errorCount++
    }

    if ($errorCount -gt 0) {
        Start-Sleep -Seconds 60
        try {
            $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -FileName $step5ScriptFile
            $workObject = Add-ScriptAndOutputToWorkObject -WorkObject $workObject -Name "Step5_RollforwardAndActivate_Retry" -Script ($db2Commands -join "`n") -Output $output
            Add-Member -InputObject $workObject -NotePropertyName "RollforwardAndActivateOutput" -NotePropertyValue $output -Force
        }
        catch {
            throw "Error executing rollforward and activate script after retry: $($_.Exception.Message)"
        }
    }

    # Check for SQL1265N (backup file integrity issue)
    if ($workObject.RollforwardAndActivateOutput -like "*SQL1265N*") {
        Write-LogMessage "SQL1265N detected — validating backup file integrity" -Level WARN
        $integrityResult = Test-BackupFileIntegrity -BackupFile $workObject.BackupFile -WorkObject $workObject
        if (-not $integrityResult) {
            throw "Backup file integrity failed (SQL1265N). Provide a consistent backup file and retry."
        }
        else {
            throw "Backup file integrity verified, but SQL1265N persists. Check logs for details."
        }
    }

    # Extract rollforward timestamp from output
    if ($workObject.RollforwardAndActivateOutput -match "(?:Siste iverksatte transaksjon|Last committed transaction)\s*=\s*(\d{4}-\d{2}-\d{2}-\d{2}\.\d{2}\.\d{2}\.\d{6})") {
        $rollforwardTimestamp = $Matches[1]
        Add-Member -InputObject $workObject -NotePropertyName "RollforwardTimestamp" -NotePropertyValue $rollforwardTimestamp -Force
        Write-LogMessage "Rollforward completed. Last committed transaction: $($rollforwardTimestamp)" -Level INFO
    }

    # --- Step 6: Report ---
    Write-LogMessage "Step 6: Generating report" -Level INFO
    $htmlFile = Join-Path $workFolder "RestoreAndAppendLogfiles_Report.html"
    Export-WorkObjectToHtmlFile -WorkObject $workObject -FileName $htmlFile -Title "Db2-RestoreAndAppendLogfiles: $($DatabaseName)"

    $smsMessage = "RestoreAndAppendLogfiles COMPLETED`nDB: $($DatabaseName)`nFrom: $($headerInfo.DatabaseName)@$($headerInfo.Timestamp)`nLogs appended: $($copiedLogCount)`nRollforward to: $($rollforwardTarget)`nOn: $($env:COMPUTERNAME)"
    foreach ($smsNumber in $SmsNumbers) {
        Send-Sms -Receiver $smsNumber -Message $smsMessage
    }

    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    $message = "RestoreAndAppendLogfiles FAILED on $($env:COMPUTERNAME): $($_.Exception.Message)"
    foreach ($smsNumber in $SmsNumbers) {
        Send-Sms -Receiver $smsNumber -Message $message
    }
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    Exit 9
}
