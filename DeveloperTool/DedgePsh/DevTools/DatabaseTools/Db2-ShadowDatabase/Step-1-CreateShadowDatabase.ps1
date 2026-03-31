<#
.SYNOPSIS
    Restores source DB from PRD, then creates shadow instance and database via the full pipeline.

.DESCRIPTION
    Step 1 of the shadow database workflow:

    Phase -2: Pre-migration backup of source database (optional, with timeout dialog)
    Phase -1: Restore source database from PRD backup (via Db2-CreateInitialDatabasesStdAll.ps1)
    Phase  1: Create shadow instance + database via Db2-CreateInitialDatabasesShadowUseNewConfig.ps1
              This calls Db2-CreateInitialDatabases.ps1 -> New-DatabaseAndConfigurations, which
              handles instance drop/create (Set-InstanceNameConfiguration), database creation
              (Add-Db2Database), service account setup, and all 1000+ standard configurations
              (Set-StandardConfigurations).

    Defaults are loaded from config.json. Parameters override config values.

.PARAMETER InstanceName
    The DB2 instance to create. Default from config.json TargetInstance.

.PARAMETER DatabaseName
    The shadow database name. Default from config.json TargetDatabase.

.PARAMETER DataDisk
    Drive letter for database storage (e.g. "F:"). Default from config.json.
    Falls back to auto-detect via Get-PrimaryDb2DataDisk if not set anywhere.

.PARAMETER SkipPrdRestore
    Skip Phase -1 (PRD restore). Use when source DB already has fresh data.

.PARAMETER UsePrdCacheSeed
    Set by Run-FullShadowPipeline when backup files were copied from F:\Db2ShPrdBackupCache
    into Db2Restore. Skips deleting *.001 before restore so Db2-Handler reuses staged images.

.PARAMETER SkipBackup
    Skip Phase -2 (pre-migration backup). If not specified, a 30-second timeout
    dialog is shown — defaults to Y (skip) when unattended.

.EXAMPLE
    .\Step-1-CreateShadowDatabase.ps1
    .\Step-1-CreateShadowDatabase.ps1 -SkipBackup:$false
    .\Step-1-CreateShadowDatabase.ps1 -DataDisk "F:" -SkipPrdRestore
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$InstanceName,

    [Parameter(Mandatory = $false)]
    [string]$DatabaseName,

    [Parameter(Mandatory = $false)]
    [string]$DataDisk,

    [Parameter(Mandatory = $false)]
    [switch]$SkipPrdRestore,

    [Parameter(Mandatory = $false)]
    [bool]$UsePrdCacheSeed = $true,

    [Parameter(Mandatory = $false)]
    [bool]$SkipBackup = $true
)

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

. (Join-Path $PSScriptRoot "_helpers\_Shared.ps1")
$cfgPath = if ($env:Db2ShadowConfigPath -and (Test-Path $env:Db2ShadowConfigPath)) { $env:Db2ShadowConfigPath } else { Get-ShadowDatabaseConfigPath -ScriptRoot $PSScriptRoot }
if (-not (Test-Path $cfgPath)) { throw "Config not found. Ensure config.*.json exists for this computer." }
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
if ([string]::IsNullOrEmpty($InstanceName))  { $InstanceName = $cfg.TargetInstance }
if ([string]::IsNullOrEmpty($DatabaseName))   { $DatabaseName = $cfg.TargetDatabase }
if ([string]::IsNullOrEmpty($DataDisk))       { $DataDisk = $cfg.DataDisk }
if ([string]::IsNullOrEmpty($InstanceName)) { throw "InstanceName not set. Configure TargetInstance in config.json or pass -InstanceName." }
if ([string]::IsNullOrEmpty($DatabaseName)) { throw "DatabaseName not set. Configure TargetDatabase in config.json or pass -DatabaseName." }

try {
    Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
    Write-LogMessage "Step 1: Full teardown and rebuild of $($InstanceName)/$($DatabaseName)" -Level INFO

    Test-Db2ServerAndAdmin

    $appDataPath = Get-ApplicationDataPath
    Set-OverrideAppDataFolder -Path $appDataPath
    Write-LogMessage "Work folder: $($appDataPath)" -Level INFO

    ##########################################################
    # Phase 0: Restore FederatedDb access point in DatabasesV2.json
    #
    # Step-4 Phase 0 converts the X<SourceDatabase> access point
    # from FederatedDb (shadow instance) to Alias (primary instance)
    # as its final action. If the pipeline is re-run from the start,
    # that entry is still Alias — which means Step-4 will silently
    # skip its conversion next time ("already converted or not federated").
    #
    # This phase detects that condition and restores the access point
    # back to FederatedDb on the shadow instance, so that:
    #   1. The federation config correctly represents the shadow DB
    #   2. Step-4 can perform its Alias conversion cleanly on rerun
    ##########################################################
    $fedCatalogName = "X$($cfg.SourceDatabase)"
    Write-LogMessage "Phase 0: Checking DatabasesV2.json for $($fedCatalogName) access point on $($cfg.SourceDatabase)" -Level INFO

    $databasesV2Path = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\DatabasesV2.json"
    if (-not (Test-Path $databasesV2Path)) {
        $allAppServers = @("dedge-server", "t-no1inldev-app", "t-no1fkmdev-app", "t-no1fkmtst-app", "p-no1fkmprd-app", "p-no1inlprd-app")
        foreach ($appSrv in $allAppServers) {
            $candidate = "\\$($appSrv)\DedgeCommon\Configfiles\DatabasesV2.json"
            if (Test-Path $candidate) { $databasesV2Path = $candidate; break }
        }
    }

    if (-not (Test-Path $databasesV2Path)) {
        Write-LogMessage "Phase 0: WARNING — DatabasesV2.json not found, skipping federation restore check" -Level WARN
    }
    else {
        $localDbV2Copy = Join-Path $env:TEMP "DatabasesV2_Phase0_Step1.json"
        Copy-Item -Path $databasesV2Path -Destination $localDbV2Copy -Force

        $dbV2Json  = Get-Content $localDbV2Copy -Raw | ConvertFrom-Json
        $serverShort = $cfg.ServerFqdn.Split('.')[0]
        $dbEntry   = $dbV2Json | Where-Object { $_.Database -eq $cfg.SourceDatabase -and $_.ServerName -eq $serverShort }

        if ($null -eq $dbEntry) {
            Write-LogMessage "Phase 0: $($cfg.SourceDatabase) not found in DatabasesV2.json — skipping" -Level INFO
        }
        else {
            # Find the X<SourceDatabase> access point that was converted to Alias by Step-4
            $xAp  = $dbEntry.AccessPoints | Where-Object { $_.CatalogName -eq $fedCatalogName -and $_.AccessPointType -eq "Alias" }

            if ($null -eq $xAp) {
                $existingFed = $dbEntry.AccessPoints | Where-Object { $_.CatalogName -eq $fedCatalogName }
                if ($null -ne $existingFed -and $existingFed.AccessPointType -eq "FederatedDb") {
                    Write-LogMessage "Phase 0: $($fedCatalogName) is already FederatedDb — no restore needed" -Level INFO
                }
                else {
                    Write-LogMessage "Phase 0: $($fedCatalogName) access point not found in DatabasesV2.json — skipping" -Level INFO
                }
            }
            else {
                # Restore: Alias → FederatedDb on shadow instance
                Write-LogMessage "Phase 0: $($fedCatalogName) is currently Alias/$($xAp.InstanceName) — restoring to FederatedDb/$($cfg.TargetInstance)" -Level INFO

                $backupPath = "$($databasesV2Path).bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
                Copy-Item -Path $databasesV2Path -Destination $backupPath -Force
                Write-LogMessage "Phase 0: Backup saved to $($backupPath)" -Level INFO

                $xAp.AccessPointType     = "FederatedDb"
                $xAp.InstanceName        = $cfg.TargetInstance
                $xAp.NodeName            = $fedCatalogName
                $xAp.AuthenticationType  = "KerberosServerEncrypt"

                $dbV2Json | ConvertTo-Json -Depth 10 | Out-File $localDbV2Copy -Encoding utf8 -Force
                Copy-Item -Path $localDbV2Copy -Destination $databasesV2Path -Force

                # Verify the write
                $verifyJson  = Get-Content $databasesV2Path -Raw | ConvertFrom-Json
                $verifyEntry = $verifyJson | Where-Object { $_.Database -eq $cfg.SourceDatabase -and $_.ServerName -eq $serverShort }
                $verifyAp    = $verifyEntry.AccessPoints | Where-Object { $_.CatalogName -eq $fedCatalogName }
                if ($verifyAp.AccessPointType -eq "FederatedDb" -and $verifyAp.InstanceName -eq $cfg.TargetInstance) {
                    Write-LogMessage "Phase 0: Verified — $($fedCatalogName) restored to FederatedDb/$($cfg.TargetInstance) in DatabasesV2.json" -Level INFO
                }
                else {
                    throw "Phase 0: Verification FAILED — $($fedCatalogName) was not correctly restored"
                }
            }
        }
    }

    if ([string]::IsNullOrEmpty($DataDisk)) {
        $DataDisk = Get-PrimaryDb2DataDisk
        if ([string]::IsNullOrEmpty($DataDisk)) {
            throw "Not a database server - cannot determine data disk"
        }
        Write-LogMessage "Data disk (auto-detected): $($DataDisk)" -Level INFO
    }
    else {
        $DataDisk = $DataDisk.TrimEnd('\')
        Write-LogMessage "Data disk (parameter): $($DataDisk)" -Level INFO
    }

    ##########################################################
    # Phase -2: Pre-migration backup of source database
    # Creates an online backup before anything is modified.
    # The backup image is copied to <instance>PreMigration
    # on the same disk as the <instance>Backup folder.
    #
    # When not explicitly set via -SkipBackup, a 30-second
    # timeout dialog is shown. Default is Y (skip). Interactive
    # users can press N to run the backup; unattended runs
    # (orchestrator) will auto-skip after timeout.
    ##########################################################
    if (-not $PSBoundParameters.ContainsKey('SkipBackup') -and -not $SkipBackup) {
        $response = Get-UserConfirmationWithTimeout `
            -PromptMessage "Skip pre-migration backup of $($cfg.SourceDatabase)?" `
            -TimeoutSeconds 30 -DefaultResponse "N" `
            -ProgressMessage "Pre-migration backup"
        $SkipBackup = $response.ToUpper() -eq "Y"
    }

    if ($SkipBackup) {
        Write-LogMessage "Phase -2: SKIPPED (pre-migration backup of $($cfg.SourceDatabase))" -Level INFO
    }
    else {
        Write-LogMessage "Phase -2: Starting pre-migration backup of $($cfg.SourceDatabase) on $($cfg.SourceInstance)" -Level INFO

        $backupFolderPath = Find-ExistingFolder -Name "$($cfg.SourceInstance)Backup" -SkipRecreateFolders
        $oldBackups = @(Get-ChildItem -Path $backupFolderPath -Filter "*.001" -File -ErrorAction SilentlyContinue)
        if ($oldBackups.Count -gt 0) {
            $oldTotalMB = [math]::Round(($oldBackups | Measure-Object -Property Length -Sum).Sum / 1MB, 0)
            Write-LogMessage "Phase -2: Removing $($oldBackups.Count) old backup file(s) from $($backupFolderPath) ($($oldTotalMB) MB) to free disk space" -Level INFO
            $oldBackups | Remove-Item -Force -ErrorAction SilentlyContinue
        }

        Reset-OverrideAppDataFolder
        Start-Db2Backup -InstanceName $cfg.SourceInstance -BackupType "Online" -DatabaseType "PrimaryDb" -OverrideWorkFolder $appDataPath
        Set-OverrideAppDataFolder -Path $appDataPath

        Write-LogMessage "Phase -2: Backup completed. Copying image to PreMigration folder" -Level INFO
        $newestBackup = Get-ChildItem -Path $backupFolderPath -Filter "*.001" -File -ErrorAction SilentlyContinue |
            Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1

        if ($null -eq $newestBackup) {
            Write-LogMessage "Phase -2: WARNING — No .001 backup image found in $($backupFolderPath). Skipping copy to PreMigration." -Level WARN
        }
        else {
            $backupDrive = $backupFolderPath.Substring(0, 2)
            $preMigFolder = Join-Path $backupDrive "$($cfg.SourceInstance)PreMigration"
            if (-not (Test-Path $preMigFolder)) {
                New-Item -Path $preMigFolder -ItemType Directory -Force | Out-Null
                Write-LogMessage "Phase -2: Created PreMigration folder: $($preMigFolder)" -Level INFO
            }

            $oldPreMig = @(Get-ChildItem -Path $preMigFolder -Filter "*.001" -File -ErrorAction SilentlyContinue)
            if ($oldPreMig.Count -gt 0) {
                Write-LogMessage "Phase -2: Removing $($oldPreMig.Count) old PreMigration file(s) to free disk space" -Level INFO
                $oldPreMig | Remove-Item -Force -ErrorAction SilentlyContinue
            }

            $destPath = Join-Path $preMigFolder $newestBackup.Name
            Copy-Item -Path $newestBackup.FullName -Destination $destPath -Force
            $sizeMB = [math]::Round($newestBackup.Length / 1MB, 1)
            Write-LogMessage "Phase -2: Copied $($newestBackup.Name) ($($sizeMB) MB) to $($preMigFolder)" -Level INFO
        }

        Write-LogMessage "Phase -2: Pre-migration backup of $($cfg.SourceDatabase) completed" -Level INFO
    }

    ##########################################################
    # Phase -1: Restore source database from PRD backup
    # Ensures source DB has fresh production data before creating
    # the shadow copy. Uses Db2-CreateInitialDatabasesStdAll.ps1
    #
    # Safety: PRD restore will destroy the DB2 instance and
    # recreate it. If a federated instance (DB2FED) still
    # references this database in DatabasesV2.json, the restore
    # must NOT run — it would break federation for all consumers.
    ##########################################################
    $skipPhaseNeg1 = $false

    if ($SkipPrdRestore) {
        Write-LogMessage "Phase -1: SKIPPED (-SkipPrdRestore). Using existing $($cfg.SourceDatabase) on $($cfg.SourceInstance)" -Level INFO
        $skipPhaseNeg1 = $true
    }

    if (-not $skipPhaseNeg1) {
        $dbV2Path = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\DatabasesV2.json"
        $dbV2Local = Join-Path $env:TEMP "DatabasesV2_preflight.json"
        try {
            Copy-Item -Path $dbV2Path -Destination $dbV2Local -Force -ErrorAction Stop
            $allDbs = Get-Content $dbV2Local -Raw -ErrorAction Stop | ConvertFrom-Json

            $serverShort = $cfg.ServerFqdn.Split('.')[0]
            $sourceDbEntry = $allDbs | Where-Object {
                $_.Database -eq $cfg.SourceDatabase -and $_.ServerName -eq $serverShort
            }

            if ($sourceDbEntry) {
                $fedAPs = @($sourceDbEntry.AccessPoints | Where-Object { $_.AccessPointType -eq 'FederatedDb' })
                if ($fedAPs.Count -gt 0) {
                    $fedNames = ($fedAPs | ForEach-Object { "$($_.InstanceName)/$($_.CatalogName)" }) -join ', '

                    $restoreFolderPath = Find-ExistingFolder -Name "$($cfg.SourceInstance)Restore" -SkipRecreateFolders
                    $localImages = @(Get-ChildItem -Path $restoreFolderPath -Filter "$($cfg.SourceDatabase)*.001" -File -ErrorAction SilentlyContinue)

                    if ($localImages.Count -gt 0) {
                        if (-not $UsePrdCacheSeed) {
                            Write-LogMessage "Phase -1: FederatedDb entries exist ($($fedNames)) but local restore image found in $($restoreFolderPath) — skipping PRD restore" -Level INFO
                            $skipPhaseNeg1 = $true
                        }
                        else {
                            Write-LogMessage "Phase -1: FederatedDb entries exist ($($fedNames)); -UsePrdCacheSeed — restoring from staged backup in $($restoreFolderPath)" -Level WARN
                        }
                    }
                    else {
                        Write-LogMessage "Phase -1: FederatedDb entries exist ($($fedNames)) and NO local restore image in $($restoreFolderPath) — proceeding with PRD restore (shadow will be recreated)" -Level WARN
                    }
                }
                else {
                    Write-LogMessage "Phase -1: No federated access points for $($cfg.SourceDatabase) on $($serverShort) — safe to restore" -Level INFO
                }
            }
            else {
                Write-LogMessage "Phase -1: $($cfg.SourceDatabase) on $($serverShort) not found in DatabasesV2.json — safe to restore" -Level INFO
            }
        }
        catch {
            Write-LogMessage "Phase -1: WARNING — Could not read $($dbV2Path) for federation check: $($_.Exception.Message). Proceeding with restore." -Level WARN
        }
        finally {
            if (Test-Path $dbV2Local) { Remove-Item $dbV2Local -Force -ErrorAction SilentlyContinue }
        }
    }

    if (-not $skipPhaseNeg1) {
        if ($UsePrdCacheSeed) {
            Write-LogMessage "Phase -1: Restoring $($cfg.SourceDatabase) on $($cfg.SourceInstance) using staged backup (PRD cache seed — *.001 preserved, Db2-Handler reuses local files)" -Level INFO
        }
        else {
            Write-LogMessage "Phase -1: Restoring source database $($cfg.SourceDatabase) on $($cfg.SourceInstance) from PRD backup" -Level INFO
        }

        $restoreFolderCleanup = Find-ExistingFolder -Name "$($cfg.SourceInstance)Restore" -SkipRecreateFolders
        if (-not $UsePrdCacheSeed) {
            $oldRestoreFiles = @(Get-ChildItem -Path $restoreFolderCleanup -Filter "*.001" -File -ErrorAction SilentlyContinue)
            if ($oldRestoreFiles.Count -gt 0) {
                Write-LogMessage "Phase -1: Cleaning $($oldRestoreFiles.Count) old .001 file(s) from $($restoreFolderCleanup) to force fresh PRD copy" -Level INFO
                foreach ($oldFile in $oldRestoreFiles) {
                    try {
                        Remove-Item -Path $oldFile.FullName -Force -ErrorAction Stop
                        Write-LogMessage "Phase -1: Deleted $($oldFile.Name)" -Level INFO
                    }
                    catch {
                        try {
                            Rename-Item -Path $oldFile.FullName -NewName ($oldFile.Name + ".STALE") -Force -ErrorAction Stop
                            Write-LogMessage "Phase -1: Renamed $($oldFile.Name) -> .STALE (locked file)" -Level WARN
                        }
                        catch {
                            Write-LogMessage "Phase -1: WARNING — Cannot delete or rename $($oldFile.Name): $($_.Exception.Message). PRD restore may reuse a corrupt file." -Level WARN
                        }
                    }
                }
            }
        }
        else {
            Write-LogMessage "Phase -1: -UsePrdCacheSeed — not deleting *.001 in $($restoreFolderCleanup); Db2-Handler will prefer existing staged backup" -Level INFO
        }

        $stdAllScript = Join-Path $($env:OptPath) "DedgePshApps\Db2-CreateInitialDatabases\Db2-CreateInitialDatabasesStdAllUseNewConfig.ps1"
        if (-not (Test-Path $stdAllScript -PathType Leaf)) {
            throw "Phase -1: Db2-CreateInitialDatabasesStdAllUseNewConfig.ps1 not found at $($stdAllScript)"
        }

        Write-LogMessage "Phase -1: Calling $($stdAllScript) -InstanceName $($cfg.SourceInstance) -GetBackupFromEnvironment PRD" -Level INFO
        Reset-OverrideAppDataFolder

        # GetBackupFromEnvironment="PRD": reuses *.001 in restore folder or copies latest from PRD share directly.
        $phase1Args = @("-NoProfile", "-File", $stdAllScript, "-InstanceName", $cfg.SourceInstance, "-GetBackupFromEnvironment", "PRD")
        if (-not [string]::IsNullOrEmpty($appDataPath)) {
            $phase1Args += "-OverrideWorkFolder"
            $phase1Args += $appDataPath
        }
        & pwsh.exe @phase1Args
        $restoreExitCode = [int]$LASTEXITCODE

        Set-OverrideAppDataFolder -Path $appDataPath

        if ($restoreExitCode -ne 0) {
            throw "Phase -1: PRD restore failed with exit code $($restoreExitCode)"
        }

        Write-LogMessage "Phase -1: PRD restore of $($cfg.SourceDatabase) completed (exit code 0). Validating data presence..." -Level INFO

        $validateCommands = @(
            "set DB2INSTANCE=$($cfg.SourceInstance)"
            "db2 connect to $($cfg.SourceDatabase)"
            "db2 `"SELECT COUNT(*) FROM SYSCAT.TABLES WHERE TABSCHEMA NOT IN ('SYSIBM','SYSCAT','SYSFUN','SYSSTAT','NULLID','SYSIBMADM','SYSIBMINTERNAL','SYSIBMTS','SYSPUBLIC','SYSTOOLS')`""
            "db2 connect reset"
            "db2 terminate"
        )
        $valOutput = Invoke-Db2ContentAsScript -Content $validateCommands -ExecutionType BAT `
            -FileName (Join-Path $appDataPath "PostRestoreValidate_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors

        $tableCount = 0
        $pastDashes = $false
        foreach ($valLine in ($valOutput -split "`n")) {
            $trimVal = $valLine.Trim()
            if ($trimVal -match '^-{4,}$') { $pastDashes = $true; continue }
            if ($pastDashes -and $trimVal -match '^\d+$') {
                $tableCount = [int]$trimVal
                break
            }
        }

        if ($tableCount -eq 0) {
            throw "Phase -1: PRD restore returned exit code 0 but $($cfg.SourceDatabase) has 0 user tables. The restore likely failed silently (check for SQL2062N or SQL2059W in the log above)."
        }
        Write-LogMessage "Phase -1: PRD restore of $($cfg.SourceDatabase) validated — $($tableCount) user table(s) found" -Level INFO
    }

    ##########################################################
    # Phase 1: Create shadow instance + database via pipeline
    # Uses Db2-CreateInitialDatabasesShadowUseNewConfig which calls
    # Db2-CreateInitialDatabases.ps1 -> New-DatabaseAndConfigurations.
    # The pipeline handles: instance drop/create (Set-InstanceNameConfiguration),
    # database creation (Add-Db2Database), service account setup
    # (Set-InstanceServiceUserNameAndPassword), and all 1000+ standard
    # configurations (Set-StandardConfigurations).
    ##########################################################
    Write-LogMessage "Phase 1: Creating shadow instance and database via Db2-CreateInitialDatabases pipeline" -Level INFO

    Reset-OverrideAppDataFolder

    $createDbScript = Join-Path $($env:OptPath) "DedgePshApps\Db2-CreateInitialDatabases\Db2-CreateInitialDatabasesShadowUseNewConfig.ps1"
    if (-not (Test-Path $createDbScript -PathType Leaf)) {
        throw "Db2-CreateInitialDatabasesShadowUseNewConfig.ps1 not found at $($createDbScript)"
    }

        $pipelineArgs = @("-NoProfile", "-File", $createDbScript, "-InstanceName", $cfg.TargetInstance)
        if (-not [string]::IsNullOrEmpty($appDataPath)) {
            $pipelineArgs += "-OverrideWorkFolder"
            $pipelineArgs += $appDataPath
        }

        Write-LogMessage "Calling: $($createDbScript) -InstanceName $($cfg.TargetInstance)" -Level INFO
        & pwsh.exe @pipelineArgs

    $createExitCode = $LASTEXITCODE
    Set-OverrideAppDataFolder -Path $appDataPath
    if ($null -ne $createExitCode -and $createExitCode -ne 0) {
        throw "Shadow database pipeline failed with exit code $($createExitCode)"
    }

    $verifyInstanceCmds = @("set DB2INSTANCE=$($InstanceName)", "db2 list database directory")
    $verifyOutput = Invoke-Db2ContentAsScript -Content $verifyInstanceCmds -ExecutionType BAT `
        -FileName (Join-Path $appDataPath "Phase1_VerifyDb_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors
    if ($verifyOutput -notmatch $DatabaseName) {
        throw "Pipeline completed but database $($DatabaseName) not found in DB2 catalog on instance $($InstanceName)"
    }
    Write-LogMessage "Verified: $($DatabaseName) exists in catalog on $($InstanceName)" -Level INFO

    ##########################################################
    # Phase 1.5: Grant DB2NT full DBA privileges on shadow DB
    #
    # After creating the shadow database, only $env:USERNAME
    # (the service account / instance owner) has access.
    # DB2NT is the standard admin user used across all DB2
    # operations. Grant DBADM + DATAACCESS + ACCESSCTRL +
    # SECADM so DB2NT has all SYSCAT.DBAUTH privileges.
    # Uses OS auth (no -u/-p) since the service account is SYSADM.
    ##########################################################
    Write-LogMessage "Phase 1.5: Granting DB2NT full DBA privileges on $($DatabaseName)" -Level INFO

    $grantCmds = @()
    $grantCmds += "set DB2INSTANCE=$($InstanceName)"
    $grantCmds += "db2 connect to $($DatabaseName)"
    $grantCmds += "db2 `"GRANT DBADM ON DATABASE TO USER DB2NT`""
    $grantCmds += "db2 `"GRANT DATAACCESS ON DATABASE TO USER DB2NT`""
    $grantCmds += "db2 `"GRANT ACCESSCTRL ON DATABASE TO USER DB2NT`""
    $grantCmds += "db2 `"GRANT SECADM ON DATABASE TO USER DB2NT`""
    $grantCmds += "db2 commit work"
    $grantCmds += "db2 connect reset"
    $grantCmds += "db2 terminate"

    $grantOutput = Invoke-Db2ContentAsScript -Content $grantCmds -ExecutionType BAT `
        -FileName (Join-Path $appDataPath "Phase1_5_GrantDb2nt_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors
    Write-LogMessage "Phase 1.5: DB2NT grant output: $($grantOutput)" -Level INFO

    # Also grant DB2NT on the source database (may have been restored from PRD without DB2NT)
    Write-LogMessage "Phase 1.5: Ensuring DB2NT has DBA privileges on source database $($cfg.SourceDatabase)" -Level INFO

    $grantSourceCmds = @()
    $grantSourceCmds += "set DB2INSTANCE=$($cfg.SourceInstance)"
    $grantSourceCmds += "db2 connect to $($cfg.SourceDatabase)"
    $grantSourceCmds += "db2 `"GRANT DBADM ON DATABASE TO USER DB2NT`""
    $grantSourceCmds += "db2 `"GRANT DATAACCESS ON DATABASE TO USER DB2NT`""
    $grantSourceCmds += "db2 `"GRANT ACCESSCTRL ON DATABASE TO USER DB2NT`""
    $grantSourceCmds += "db2 `"GRANT SECADM ON DATABASE TO USER DB2NT`""
    $grantSourceCmds += "db2 commit work"
    $grantSourceCmds += "db2 connect reset"
    $grantSourceCmds += "db2 terminate"

    $grantSourceOutput = Invoke-Db2ContentAsScript -Content $grantSourceCmds -ExecutionType BAT `
        -FileName (Join-Path $appDataPath "Phase1_5_GrantDb2nt_Source_$(Get-Date -Format 'yyyyMMddHHmmssfff').bat") -IgnoreErrors
    Write-LogMessage "Phase 1.5: Source DB grant output: $($grantSourceOutput)" -Level INFO

    Write-LogMessage "Step 1 COMPLETED: Shadow instance $($InstanceName) and database $($DatabaseName) created via full pipeline with all configurations" -Level INFO
    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    exit 1
}
finally {
    Reset-OverrideAppDataFolder
}
