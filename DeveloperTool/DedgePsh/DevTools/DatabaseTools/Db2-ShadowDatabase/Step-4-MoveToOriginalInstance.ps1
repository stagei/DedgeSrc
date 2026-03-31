<#
.SYNOPSIS
    Moves the verified shadow database back to the original DB2 instance.

.DESCRIPTION
    Step 4 (optional) of the shadow database workflow. Backs up the shadow DB from
    the shadow instance, optionally drops the original on the source instance,
    restores the backup using REDIRECT GENERATE SCRIPT for path remapping, and
    optionally cleans up the shadow instance afterwards.

    Defaults are loaded from config.json. Parameters override config values.
    Note: Source/Target are REVERSED vs the other steps (shadow -> original).

.PARAMETER DropExistingTarget
    Drop the existing target database before restoring.

.PARAMETER CleanupSourceAfter
    After successful restore, drop the shadow database and remove catalog entries.

.PARAMETER BackupFolder
    Override backup folder location. Default: auto-detected via Get-Db2Folders.

.PARAMETER SmsNumbers
    Phone numbers for SMS notifications.

.EXAMPLE
    .\Step-4-MoveToOriginalInstance.ps1 -DropExistingTarget
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$SourceInstance,

    [Parameter(Mandatory = $false)]
    [string]$SourceDatabase,

    [Parameter(Mandatory = $false)]
    [string]$TargetInstance,

    [Parameter(Mandatory = $false)]
    [string]$TargetDatabase,

    [Parameter(Mandatory = $false)]
    [switch]$DropExistingTarget,

    [Parameter(Mandatory = $false)]
    [switch]$CleanupSourceAfter,

    [Parameter(Mandatory = $false)]
    [string]$BackupFolder = "",

    [Parameter(Mandatory = $false)]
    [string[]]$SmsNumbers = @("+4797188358")
)

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

. (Join-Path $PSScriptRoot "_helpers\_Shared.ps1")
$cfgPath = if ($env:Db2ShadowConfigPath -and (Test-Path $env:Db2ShadowConfigPath)) { $env:Db2ShadowConfigPath } else { Get-ShadowDatabaseConfigPath -ScriptRoot $PSScriptRoot }
if (-not (Test-Path $cfgPath)) { throw "Config not found. Ensure config.*.json exists for this computer." }
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
# Step-4 is reversed: shadow -> original, so TargetInstance/DB from config = SourceInstance here
if ([string]::IsNullOrEmpty($SourceInstance))  { $SourceInstance = $cfg.TargetInstance }
if ([string]::IsNullOrEmpty($SourceDatabase))  { $SourceDatabase = $cfg.TargetDatabase }
if ([string]::IsNullOrEmpty($TargetInstance))   { $TargetInstance = $cfg.SourceInstance }
if ([string]::IsNullOrEmpty($TargetDatabase))   { $TargetDatabase = $cfg.SourceDatabase }
if ([string]::IsNullOrEmpty($SourceInstance))  { throw "SourceInstance (shadow) not set. Configure TargetInstance in config.json or pass -SourceInstance." }
if ([string]::IsNullOrEmpty($SourceDatabase))  { throw "SourceDatabase (shadow) not set. Configure TargetDatabase in config.json or pass -SourceDatabase." }
if ([string]::IsNullOrEmpty($TargetInstance))   { throw "TargetInstance (original) not set. Configure SourceInstance in config.json or pass -TargetInstance." }
if ([string]::IsNullOrEmpty($TargetDatabase))   { throw "TargetDatabase (original) not set. Configure SourceDatabase in config.json or pass -TargetDatabase." }

try {
    Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
    Write-LogMessage "Source: $($SourceDatabase) on $($SourceInstance) -> Target: $($TargetDatabase) on $($TargetInstance)" -Level INFO

    Test-Db2ServerAndAdmin

    #########################################################
    # Phase 0: Convert FederatedDb → Alias in DatabasesV2.json
    # Removes the old DB2FED federated access point and
    # replaces it with an Alias on the primary DB2 instance
    # using KerberosServerEncrypt authentication.
    #########################################################
    Write-LogMessage "Phase 0: Converting FederatedDb to Alias in DatabasesV2.json for $($TargetDatabase)" -Level INFO

    $databasesV2Path = "\\$($env:COMPUTERNAME.Split('-')[0..1] -join '-')-app\DedgeCommon\Configfiles\DatabasesV2.json"
    if (-not (Test-Path $databasesV2Path)) {
        $allAppServers = @("dedge-server", "t-no1inldev-app", "t-no1fkmdev-app", "t-no1fkmtst-app", "p-no1fkmprd-app", "p-no1inlprd-app")
        foreach ($appSrv in $allAppServers) {
            $candidate = "\\$($appSrv)\DedgeCommon\Configfiles\DatabasesV2.json"
            if (Test-Path $candidate) { $databasesV2Path = $candidate; break }
        }
    }

    if (-not (Test-Path $databasesV2Path)) {
        throw "DatabasesV2.json not found. Tried: $($databasesV2Path)"
    }
    Write-LogMessage "Phase 0: Using DatabasesV2.json at $($databasesV2Path)" -Level INFO

    $localDbV2Copy = Join-Path $env:TEMP "DatabasesV2_Phase0.json"
    Copy-Item -Path $databasesV2Path -Destination $localDbV2Copy -Force

    $dbV2Json = Get-Content $localDbV2Copy -Raw | ConvertFrom-Json
    $dbEntry = $dbV2Json | Where-Object { $_.Database -eq $TargetDatabase }

    if ($null -eq $dbEntry) {
        Write-LogMessage "Phase 0: Database $($TargetDatabase) not found in DatabasesV2.json — skipping conversion" -Level WARN
    }
    else {
        $fedAp = $dbEntry.AccessPoints | Where-Object { $_.AccessPointType -eq "FederatedDb" }
        $priAp = $dbEntry.AccessPoints | Where-Object { $_.AccessPointType -eq "PrimaryDb" }

        if ($null -eq $fedAp) {
            Write-LogMessage "Phase 0: No FederatedDb access point found for $($TargetDatabase) — already converted or not federated" -Level INFO
        }
        elseif ($null -eq $priAp) {
            Write-LogMessage "Phase 0: No PrimaryDb access point found for $($TargetDatabase) — cannot determine primary instance" -Level WARN
        }
        else {
            Write-LogMessage "Phase 0: Converting $($fedAp.CatalogName) from FederatedDb ($($fedAp.InstanceName)/$($fedAp.AuthenticationType)) to Alias ($($priAp.InstanceName)/KerberosServerEncrypt)" -Level INFO

            $fedAp.AccessPointType = "Alias"
            $fedAp.InstanceName = $priAp.InstanceName
            $fedAp.NodeName = $fedAp.CatalogName
            $fedAp.AuthenticationType = "KerberosServerEncrypt"

            $backupPath = "$($databasesV2Path).bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
            Copy-Item -Path $databasesV2Path -Destination $backupPath -Force
            Write-LogMessage "Phase 0: Backup saved to $($backupPath)" -Level INFO

            $dbV2Json | ConvertTo-Json -Depth 10 | Out-File $localDbV2Copy -Encoding utf8 -Force
            Copy-Item -Path $localDbV2Copy -Destination $databasesV2Path -Force

            $verifyJson = Get-Content $databasesV2Path -Raw | ConvertFrom-Json
            $verifyEntry = $verifyJson | Where-Object { $_.Database -eq $TargetDatabase }
            $verifyAp = $verifyEntry.AccessPoints | Where-Object { $_.CatalogName -eq $fedAp.CatalogName }
            if ($verifyAp.AccessPointType -eq "Alias" -and $verifyAp.AuthenticationType -eq "KerberosServerEncrypt") {
                Write-LogMessage "Phase 0: Verified — $($fedAp.CatalogName) is now Alias/KerberosServerEncrypt in DatabasesV2.json" -Level INFO
            }
            else {
                throw "Phase 0: Verification FAILED — $($fedAp.CatalogName) was not correctly converted"
            }
        }
    }

    $workFolder = Get-ApplicationDataPath
    Set-OverrideAppDataFolder -Path $workFolder
    Write-LogMessage "Work folder: $($workFolder)" -Level INFO

    foreach ($smsNumber in $SmsNumbers) {
        Send-Sms -Receiver $smsNumber -Message "Step 4 STARTED: Moving $($SourceDatabase) -> $($TargetDatabase) on $($env:COMPUTERNAME)"
    }

    $dataDisk = Get-PrimaryDb2DataDisk
    if ([string]::IsNullOrEmpty($dataDisk)) {
        throw "Could not detect primary DB2 data disk"
    }

    # Get standard Db2 folders for source (shadow) and target (original) instances
    $srcWorkObj = [PSCustomObject]@{ InstanceName = $SourceInstance; DatabaseName = $SourceDatabase }
    $srcWorkObj = Get-Db2Folders -WorkObject $srcWorkObj -FolderName "BackupFolder" -SkipRecreateDb2Folders
    if ($srcWorkObj -is [array]) { $srcWorkObj = $srcWorkObj[-1] }
    $srcBackupFolder = $srcWorkObj.BackupFolder
    Write-LogMessage "Source backup folder: $($srcBackupFolder)" -Level INFO

    $tgtWorkObj = [PSCustomObject]@{ InstanceName = $TargetInstance; DatabaseName = $TargetDatabase }
    $tgtWorkObj = Get-Db2Folders -WorkObject $tgtWorkObj -FolderName "RestoreFolder" -SkipRecreateDb2Folders
    if ($tgtWorkObj -is [array]) { $tgtWorkObj = $tgtWorkObj[-1] }
    $tgtRestoreFolder = $tgtWorkObj.RestoreFolder
    Write-LogMessage "Target restore folder: $($tgtRestoreFolder)" -Level INFO

    if ([string]::IsNullOrEmpty($BackupFolder)) {
        $BackupFolder = $srcBackupFolder
    }
    if (-not (Test-Path $BackupFolder -PathType Container)) {
        New-Item -Path $BackupFolder -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path $tgtRestoreFolder -PathType Container)) {
        New-Item -Path $tgtRestoreFolder -ItemType Directory -Force | Out-Null
    }

    #########################################################
    # Phase 1: Backup shadow database on source instance
    #
    # Clean old backup files first to prevent disk-full errors
    # (SQL2059W). Only one backup image is needed — the one
    # we are about to create.
    #########################################################
    Write-LogMessage "Phase 1: Backing up $($SourceDatabase) on $($SourceInstance) to $($BackupFolder)" -Level INFO

    $oldBackups = @(Get-ChildItem -Path $BackupFolder -Filter "*.001" -File -ErrorAction SilentlyContinue)
    if ($oldBackups.Count -gt 0) {
        $oldTotalMB = [math]::Round(($oldBackups | Measure-Object -Property Length -Sum).Sum / 1MB, 0)
        Write-LogMessage "Phase 1: Removing $($oldBackups.Count) old backup file(s) from $($BackupFolder) ($($oldTotalMB) MB) to free disk space" -Level INFO
        $oldBackups | Remove-Item -Force -ErrorAction SilentlyContinue
    }

    $backupCommands = @()
    $backupCommands += "set DB2INSTANCE=$($SourceInstance)"
    $backupCommands += "db2stop force"
    $backupCommands += "db2start"
    $backupCommands += "db2 backup database $($SourceDatabase) to `"$($BackupFolder)`" without prompting"

    $output = Invoke-Db2ContentAsScript -Content $backupCommands -ExecutionType BAT `
        -FileName (Join-Path $workFolder "Phase1_Backup_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors
    Write-LogMessage "Backup output: $($output)" -Level INFO

    # Extract backup timestamp from output
    $backupTimestamp = $null
    if ($output -match '(\d{14})') {
        $backupTimestamp = $matches[1]
        Write-LogMessage "Backup timestamp: $($backupTimestamp)" -Level INFO
    }
    else {
        throw "Could not determine backup timestamp from output"
    }

    #########################################################
    # Phase 1b: Move backup file to target restore folder
    #########################################################
    Write-LogMessage "Phase 1b: Moving backup file to target restore folder $($tgtRestoreFolder)" -Level INFO

    $backupFilePattern = "$($SourceDatabase).*.$($SourceInstance).DBPART000.$($backupTimestamp).*"
    $backupFile = Get-ChildItem -Path $BackupFolder -Filter $backupFilePattern -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if ($null -eq $backupFile) {
        $backupFile = Get-ChildItem -Path $BackupFolder -Filter "$($SourceDatabase)*$($backupTimestamp)*" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
    }

    if ($null -eq $backupFile) {
        throw "Backup file not found in $($BackupFolder) matching timestamp $($backupTimestamp)"
    }

    Write-LogMessage "Found backup file: $($backupFile.FullName) ($([math]::Round($backupFile.Length / 1MB, 1)) MB)" -Level INFO

    # Clean restore folder to avoid stale files from previous runs
    Get-ChildItem -Path $tgtRestoreFolder -Filter "*.001" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-LogMessage "Cleaned restore folder: $($tgtRestoreFolder)" -Level INFO

    # Copy the backup file AS-IS (no rename). DB2 locates backup files by
    # filename prefix, so the file must start with the source database name
    # (SINLTST) for the restore command to find it.
    $destPath = Join-Path $tgtRestoreFolder $backupFile.Name
    Copy-Item -Path $backupFile.FullName -Destination $destPath -Force
    Write-LogMessage "Copied backup to restore folder: $($destPath)" -Level INFO

    foreach ($smsNumber in $SmsNumbers) {
        Send-Sms -Receiver $smsNumber -Message "Step 4/Phase 1: Backup $($SourceDatabase) done, copied to $($tgtRestoreFolder)."
    }

    #########################################################
    # Phase 2: Drop old database on target instance (optional)
    #########################################################
    if ($DropExistingTarget) {
        Write-LogMessage "Phase 2: Dropping existing $($TargetDatabase) on $($TargetInstance)" -Level INFO

        # Get folder locations for the target instance before dropping
        $targetWorkObject = [PSCustomObject]@{
            InstanceName = $TargetInstance
            DatabaseName = $TargetDatabase
        }
        $targetWorkObject = Get-Db2Folders -WorkObject $targetWorkObject -SkipRecreateDb2Folders
        if ($targetWorkObject -is [array]) { $targetWorkObject = $targetWorkObject[-1] }

        $dropCommands = @()
        $dropCommands += "set DB2INSTANCE=$($TargetInstance)"
        $dropCommands += "db2 connect reset 2>nul"
        $dropCommands += "db2 terminate 2>nul"
        $dropCommands += "db2stop force"
        $dropCommands += "db2start"
        $dropCommands += "db2 connect to $($TargetDatabase)"
        $dropCommands += "db2 deactivate database $($TargetDatabase)"
        $dropCommands += "db2 connect reset"
        $dropCommands += "db2 drop database $($TargetDatabase) 2>nul"
        $dropCommands += "db2 uncatalog database $($TargetDatabase)"
        $dropCommands += "db2stop force"
        $dropCommands += "db2start"

        $output = Invoke-Db2ContentAsScript -Content $dropCommands -ExecutionType BAT `
            -FileName (Join-Path $workFolder "Phase2_DropTarget_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors
        Write-LogMessage "Drop target output: $($output)" -Level INFO

        # Clean up log/temp folders on the target instance
        $foldersToClean = @("PrimaryLogsFolder", "MirrorLogsFolder", "LogtargetFolder")
        foreach ($folderProp in $foldersToClean) {
            $folderPath = $targetWorkObject.$folderProp
            if (-not [string]::IsNullOrEmpty($folderPath) -and (Test-Path $folderPath -PathType Container)) {
                Write-LogMessage "Cleaning folder: $($folderPath)" -Level INFO
                Get-ChildItem -Path $folderPath -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        foreach ($smsNumber in $SmsNumbers) {
            Send-Sms -Receiver $smsNumber -Message "Step 4/Phase 2: Old $($TargetDatabase) dropped on $($TargetInstance). Folders cleaned."
        }
    }

    #########################################################
    # Phase 3: Restore via Db2-CreateInitialDatabasesStdAllUseNewConfig
    # Uses the FULL pipeline: restore + Set-StandardConfigurations,
    # grants, federation, catalog, and all 1000+ privileges/configs.
    # Restore-DuringDatabaseCreationNew ensures UseNewConfigurations
    # propagates so Restore-SingleDatabaseNew handles SQL2532N.
    #########################################################
    Write-LogMessage "Phase 3: Restoring $($TargetDatabase) on $($TargetInstance) using Db2-CreateInitialDatabasesStdAllUseNewConfig pipeline" -Level INFO

    $createDbScript = Join-Path $($env:OptPath) "DedgePshApps\Db2-CreateInitialDatabases\Db2-CreateInitialDatabasesStdAllUseNewConfig.ps1"
    if (-not (Test-Path $createDbScript -PathType Leaf)) {
        throw "Db2-CreateInitialDatabasesStdAllUseNewConfig.ps1 not found at $($createDbScript)"
    }

    # Pass TargetInstance (the original DB2 instance) and GetBackupFromEnvironment="" so the pipeline
    # uses the shadow backup already staged in <InstanceName>Restore by Phase 1b — NOT the PRD backup.
    Write-LogMessage "Calling: $($createDbScript) -InstanceName $($TargetInstance) -GetBackupFromEnvironment '' -OverrideWorkFolder `"$($workFolder)`"" -Level INFO

    $pipelineArgs = @("-NoProfile", "-File", $createDbScript, "-InstanceName", $TargetInstance, "-GetBackupFromEnvironment", "")
    if (-not [string]::IsNullOrEmpty($workFolder)) {
        $pipelineArgs += "-OverrideWorkFolder", $workFolder
    }
    & pwsh.exe @pipelineArgs
    $createExitCode = $LASTEXITCODE
    Write-LogMessage "Pipeline process exited with LASTEXITCODE=$($createExitCode)" -Level INFO
    if ($null -eq $createExitCode -or $createExitCode -ne 0) {
        $exitMsg = if ($null -eq $createExitCode) { "null (process may not have set exit code)" } else { "$($createExitCode)" }
        throw "Db2-CreateInitialDatabasesStdAllUseNewConfig.ps1 failed with exit code $($exitMsg)"
    }

    Write-LogMessage "Phase 3: Pipeline completed successfully for $($TargetDatabase) on $($TargetInstance)" -Level INFO

    foreach ($smsNumber in $SmsNumbers) {
        Send-Sms -Receiver $smsNumber -Message "Step 4/Phase 3: $($TargetDatabase) restored on $($TargetInstance) via full UseNewConfig pipeline."
    }

    #########################################################
    # Phase 3b: Control SQL verification
    #########################################################
    $ctlWorkObj = Get-DefaultWorkObjects -DatabaseType PrimaryDb -DatabaseName $TargetDatabase -QuickMode -SkipDb2StateInfo
    if ($ctlWorkObj -is [array]) { $ctlWorkObj = $ctlWorkObj[-1] }
    $ctlWorkObj = Get-ControlSqlStatement -WorkObject $ctlWorkObj -SelectCount -ForceGetControlSqlStatement
    if ($ctlWorkObj -is [array]) { $ctlWorkObj = $ctlWorkObj[-1] }
    $controlTable = $ctlWorkObj.TableToCheck

    if (-not [string]::IsNullOrEmpty($controlTable)) {
        Write-LogMessage "Phase 3b: Running control SQL on $($TargetDatabase) - SELECT COUNT(*) FROM $($controlTable)" -Level INFO

        $controlCmds = @("set DB2INSTANCE=$($TargetInstance)", "db2 connect to $($TargetDatabase)")
        $controlCmds += "db2 `"SELECT COUNT(*) FROM $($controlTable)`""
        $controlCmds += "db2 connect reset"
        $controlCmds += "db2 terminate"

        $controlOut = Invoke-Db2ContentAsScript -Content $controlCmds -ExecutionType BAT `
            -FileName (Join-Path $workFolder "ControlSql_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors
        Write-LogMessage "Control SQL output: $($controlOut)" -Level INFO

        if ($controlOut -match '(\d+)\s+post(\(er\))?\s+er\s+valgt') {
            $rowCount = [int]$matches[1]
            Write-LogMessage "Control SQL: $($rowCount) rows returned from $($controlTable)" -Level INFO
            if ($rowCount -eq 0) {
                throw "Control SQL FAILED: 0 rows from $($controlTable) on $($TargetDatabase). Data not converted correctly."
            }
        }
        else {
            Write-LogMessage "Control SQL: Could not parse row count from output - verify manually" -Level WARN
        }
    }
    else {
        Write-LogMessage "Phase 3b: No control table from Get-ControlSqlStatement, skipping control SQL" -Level WARN
    }

    #########################################################
    # Phase 3c + Phase 4: Drop shadow DB2 instance (DB2SH) and
    # remove its data folders after successful restore to the
    # primary instance. Same folder basename convention as
    # Get-Db2Folders (Db2-Handler.psm1): InstanceName with
    # DB2 -> Db2 .ToTitleCase() folded (e.g. DB2SH -> Db2Sh).
    #########################################################
    if ($CleanupSourceAfter) {
        Write-LogMessage "Phase 3c: Dropping shadow instance $($SourceInstance) (db2stop force + db2idrop)" -Level INFO

        $dropShadowInstCmds = @()
        $dropShadowInstCmds += "set DB2INSTANCE=$($SourceInstance)"
        $dropShadowInstCmds += "db2stop force"
        $dropShadowInstCmds += "db2idrop $($SourceInstance) -f"

        $idropOutput = Invoke-Db2ContentAsScript -Content $dropShadowInstCmds -ExecutionType BAT `
            -FileName (Join-Path $workFolder "Phase3c_Db2IdropShadow_$($SourceInstance)_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") `
            -IgnoreErrors -OutputToConsole
        Write-LogMessage "Phase 3c db2idrop output: $($idropOutput)" -Level INFO

        # Folder basenames match Find-ExistingFolder / Get-Db2Folders (per-drive scan; do not create missing folders)
        $workInstanceName = $SourceInstance.Replace("DB2", "Db2 ").ToTitleCase().Replace(" ", "")
        $shadowFolderSuffixes = @("MirrorLogs", "Restore", "Backup", "Load", "Logtarget", "PrimaryLogs", "Tablespaces", "")
        Write-LogMessage "Phase 4: Removing shadow instance folders for prefix $($workInstanceName) on all valid drives" -Level INFO

        foreach ($suffix in $shadowFolderSuffixes) {
            $baseName = if ([string]::IsNullOrEmpty($suffix)) { $workInstanceName } else { "$($workInstanceName)$($suffix)" }
            foreach ($drive in Find-ValidDrives) {
                $folderPath = "$($drive):\$($baseName)"
                if (Test-Path -LiteralPath $folderPath -PathType Container) {
                    Write-LogMessage "Phase 4: Removing folder $($folderPath)" -Level INFO
                    try {
                        Remove-Item -LiteralPath $folderPath -Recurse -Force -ErrorAction Stop
                    }
                    catch {
                        Write-LogMessage "Phase 4: Could not fully remove $($folderPath): $($_.Exception.Message)" -Level WARN
                    }
                }
            }
        }

        foreach ($smsNumber in $SmsNumbers) {
            Send-Sms -Receiver $smsNumber -Message "Step 4 COMPLETE: $($TargetDatabase) on $($TargetInstance) ready. Shadow instance $($SourceInstance) dropped and folders removed."
        }
    }
    else {
        foreach ($smsNumber in $SmsNumbers) {
            Send-Sms -Receiver $smsNumber -Message "Step 4 COMPLETE: $($TargetDatabase) restored on $($TargetInstance). Source $($SourceDatabase) kept on $($SourceInstance)."
        }
    }

    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
    $message = "Step 4 FAILED on $($env:COMPUTERNAME): $($_.Exception.Message)"
    foreach ($smsNumber in $SmsNumbers) {
        Send-Sms -Receiver $smsNumber -Message $message
    }
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    exit 1
}
finally {
    Reset-OverrideAppDataFolder
}
