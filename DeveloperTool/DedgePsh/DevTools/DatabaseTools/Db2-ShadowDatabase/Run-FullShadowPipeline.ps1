<#
.SYNOPSIS
    Runs the full shadow database pipeline end-to-end: PRD restore, shadow create,
    copy data, verify, move back to original instance, and final validation.

.DESCRIPTION
    Orchestrates Steps 1-5 (plus Step 4) of the shadow database workflow in a single
    unattended run. Designed to be started manually on the database server and run
    autonomously until completion or failure.

    Safeguards:
    - Preflight Phase 0: Restores federation entry (XFKMVFT) if left as Alias by previous Step-4
    - Preflight: F:\Db2ShPrdBackupCache (or DataDisk fallback) holds last PRD backup; seeds
      Db2Restore on repeat runs. After first successful PRD restore, images are copied there.
    - Step-2 duration guard: Aborts if data copy completes in less than MinStep2Minutes (default 2h)
    - SMS on failure and completion (fault-tolerant, per-user auto-detect)

    Pipeline:
      Step 1: Restore source DB from PRD, create shadow instance + database
      Step 2: Copy DDL and data from source to shadow (OS auth, no explicit credentials)
      Step 3: Verify schema objects match
      Step 5: Verify row counts match
      Step 4: Move shadow back to original instance (includes Phase 0 JSON conversion)
      Grant export/import: Optional role-based grant conversion on SourceDatabase
      Optional: Post-move Db2-Backup on SourceInstance (after grants, before Step 6b)
      Step 6b: Comprehensive verification (PostMove)
      Step 7: HTML report

    Each step is called as a child process so failures are isolated.

    Defaults come from config.json. All steps use the same config.

.PARAMETER SkipPrdRestore
    Skip Step 1 Phase -1 (PRD restore). Use when source DB already has fresh data.

.PARAMETER SkipShadowCreate
    Skip Step 1 Phase 1 (shadow instance/DB creation). Use when shadow already exists.

.PARAMETER SkipCopy
    Skip Step 2 (data copy). Use when shadow already has data.

.PARAMETER SkipVerify
    Skip Step 3 and Step 5 (verification). Use to save time in dev/test.

.PARAMETER StopAfterVerify
    Stop after Step 3/5 verification. Do NOT move shadow back to original instance.

.PARAMETER SkipBackup
    Skip pre-migration backup of source database (Step-1 Phase -2).

.PARAMETER MinStep2Minutes
    Minimum acceptable duration for Step-2 in minutes. If Step-2 completes faster
    than this, the pipeline aborts (data transfer likely failed). Default: 120.

.PARAMETER UseRoleBasedGrants
    When $true (default), calls Db2-GrantsImport.ps1 with -UseNewConfigurations $true
    after Step 4 to convert direct grants to DB2 role-based grants via Import-Db2GrantsAsRoles.
    When $false, calls Db2-GrantsImport.ps1 without -UseNewConfigurations to re-apply
    production grants as classic direct grants via Import-Db2Grants.

.PARAMETER RunPostMoveBackup
    When set (or when config RunPostMoveBackup is true), runs DedgePshApps\Db2-Backup\Db2-Backup.ps1
    against SourceInstance after Step 4 and after grant export/import, before Step 6b. Use to take
    an online (or offline) backup of the migrated database on the original DB2 instance.

.PARAMETER PostMoveBackupOffline
    Passes -Offline to Db2-Backup.ps1 (offline backup). Default is online backup.

.PARAMETER PostMoveBackupDatabaseType
    Passed to Db2-Backup.ps1 -DatabaseType: PrimaryDb (default), FederatedDb, or BothDatabases.

.PARAMETER SmsNumbers
    Phone numbers for SMS notifications. Auto-detected per user if not specified.

.EXAMPLE
    .\Run-FullShadowPipeline.ps1
    # Full pipeline: PRD restore -> shadow -> copy -> verify -> move back -> final verify

.EXAMPLE
    .\Run-FullShadowPipeline.ps1 -SkipPrdRestore -SkipShadowCreate -SkipCopy
    # Only move the existing shadow DB back and verify

.EXAMPLE
    .\Run-FullShadowPipeline.ps1 -SkipPrdRestore -SkipShadowCreate
    # Skip restore/create, but still copy data, verify, and move back

.EXAMPLE
    .\Run-FullShadowPipeline.ps1 -RunPostMoveBackup
    # Full pipeline; after Step 4 and grant import (role conversion), run Db2-Backup on SourceInstance before Step 6b.

.EXAMPLE
    .\Run-FullShadowPipeline.ps1 -RunPostMoveBackup -PostMoveBackupOffline -PostMoveBackupDatabaseType BothDatabases
    # Post-move offline backup including primary and federated DBs on SourceInstance (use with care; longer outage).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$SkipPrdRestore,

    [Parameter(Mandatory = $false)]
    [switch]$SkipShadowCreate,

    [Parameter(Mandatory = $false)]
    [switch]$SkipCopy,

    [Parameter(Mandatory = $false)]
    [switch]$SkipVerify,

    [Parameter(Mandatory = $false)]
    [switch]$StopAfterVerify,

    [Parameter(Mandatory = $false)]
    [bool]$SkipBackup = $true,

    [Parameter(Mandatory = $false)]
    [int]$MinStep2Minutes = 120,

    [Parameter(Mandatory = $false)]
    [bool]$UseRoleBasedGrants = $true,

    [Parameter(Mandatory = $false)]
    [switch]$RunPostMoveBackup,

    [Parameter(Mandatory = $false)]
    [switch]$PostMoveBackupOffline,

    [Parameter(Mandatory = $false)]
    [ValidateSet("PrimaryDb", "FederatedDb", "BothDatabases")]
    [string]$PostMoveBackupDatabaseType = "PrimaryDb",

    [Parameter(Mandatory = $false)]
    [string[]]$SmsNumbers
)

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

. (Join-Path $PSScriptRoot "_helpers\_Shared.ps1")
$cfgPath = Get-ShadowDatabaseConfigPath -ScriptRoot $PSScriptRoot
$env:Db2ShadowConfigPath = $cfgPath
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json

# Optional post-move backup: -RunPostMoveBackup or config RunPostMoveBackup
$effectiveRunPostMoveBackup = $false
if ($PSBoundParameters.ContainsKey('RunPostMoveBackup')) {
    $effectiveRunPostMoveBackup = $RunPostMoveBackup.IsPresent
}
elseif ($null -ne $cfg.RunPostMoveBackup) {
    $effectiveRunPostMoveBackup = [bool]$cfg.RunPostMoveBackup
}

$effectivePostMoveBackupDatabaseType = $PostMoveBackupDatabaseType
if (-not $PSBoundParameters.ContainsKey('PostMoveBackupDatabaseType') -and $cfg.PostMoveBackupDatabaseType) {
    $effectivePostMoveBackupDatabaseType = [string]$cfg.PostMoveBackupDatabaseType
}

$effectivePostMoveBackupOffline = $PostMoveBackupOffline.IsPresent
if (-not $PSBoundParameters.ContainsKey('PostMoveBackupOffline') -and $null -ne $cfg.PostMoveBackupOffline) {
    $effectivePostMoveBackupOffline = [bool]$cfg.PostMoveBackupOffline
}

if (-not $PSBoundParameters.ContainsKey('SmsNumbers')) {
    $resolvedSmsNumber = switch ($env:USERNAME) {
        "FKGEISTA" { "+4797188358" }
        "FKSVEERI" { "+4795762742" }
        "FKMISTA"  { "+4799348397" }
        "FKCELERI" { "+4745269945" }
        default    { "+4797188358" }
    }
    $SmsNumbers = @($resolvedSmsNumber)
}

$pipelineStart = Get-Date
$stepResults = [ordered]@{}

function Send-PipelineSms {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    foreach ($smsNumber in $SmsNumbers) {
        try {
            Send-Sms -Receiver $smsNumber -Message $Message
        }
        catch {
            Write-LogMessage "Failed to send SMS to $($smsNumber): $($_.Exception.Message)" -Level WARN
        }
    }
}

function Invoke-Phase0FederationRestore {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$ConfigObject
    )

    $fedCatalogName = "X$($ConfigObject.SourceDatabase)"
    Write-LogMessage "Preflight Phase 0: Checking DatabasesV2.json for $($fedCatalogName) access point" -Level INFO

    $databasesV2Path = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\DatabasesV2.json"
    if (-not (Test-Path $databasesV2Path)) {
        $allAppServers = @("dedge-server", "t-no1inldev-app", "t-no1fkmdev-app", "t-no1fkmtst-app", "p-no1fkmprd-app", "p-no1inlprd-app")
        foreach ($appSrv in $allAppServers) {
            $candidate = "\\$($appSrv)\DedgeCommon\Configfiles\DatabasesV2.json"
            if (Test-Path $candidate) {
                $databasesV2Path = $candidate
                break
            }
        }
    }

    if (-not (Test-Path $databasesV2Path)) {
        Write-LogMessage "Preflight Phase 0: DatabasesV2.json not found, continuing" -Level WARN
        return
    }

    $localDbV2Copy = Join-Path $env:TEMP "DatabasesV2_Preflight_FullPipeline.json"
    Copy-Item -Path $databasesV2Path -Destination $localDbV2Copy -Force

    $dbV2Json = Get-Content $localDbV2Copy -Raw | ConvertFrom-Json
    $serverShort = $ConfigObject.ServerFqdn.Split('.')[0]
    $dbEntry = $dbV2Json | Where-Object { $_.Database -eq $ConfigObject.SourceDatabase -and $_.ServerName -eq $serverShort }

    if ($null -eq $dbEntry) {
        Write-LogMessage "Preflight Phase 0: $($ConfigObject.SourceDatabase) not found in DatabasesV2.json" -Level INFO
        return
    }

    $xAp = $dbEntry.AccessPoints | Where-Object { $_.CatalogName -eq $fedCatalogName -and $_.AccessPointType -eq "Alias" }
    if ($null -eq $xAp) {
        $existing = $dbEntry.AccessPoints | Where-Object { $_.CatalogName -eq $fedCatalogName }
        if ($null -ne $existing -and $existing.AccessPointType -eq "FederatedDb") {
            Write-LogMessage "Preflight Phase 0: $($fedCatalogName) already FederatedDb - no restore needed" -Level INFO
        }
        else {
            Write-LogMessage "Preflight Phase 0: $($fedCatalogName) not found or already handled - no restore needed" -Level INFO
        }
        return
    }

    $backupPath = "$($databasesV2Path).bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
    Copy-Item -Path $databasesV2Path -Destination $backupPath -Force

    $xAp.AccessPointType = "FederatedDb"
    $xAp.InstanceName = $ConfigObject.TargetInstance
    $xAp.NodeName = $fedCatalogName
    $xAp.AuthenticationType = "KerberosServerEncrypt"

    $dbV2Json | ConvertTo-Json -Depth 10 | Out-File $localDbV2Copy -Encoding utf8 -Force
    Copy-Item -Path $localDbV2Copy -Destination $databasesV2Path -Force

    Write-LogMessage "Preflight Phase 0: Restored $($fedCatalogName) to FederatedDb/$($ConfigObject.TargetInstance)" -Level INFO
}

function Find-Db2Folder {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstanceName,
        [Parameter(Mandatory = $false)]
        [string]$FolderName = "Restore"
    )

    $workObject = Get-DefaultWorkObjects -DatabaseType PrimaryDb -InstanceName $InstanceName -QuickMode -SkipDb2StateInfo -SkipRecreateDb2Folders
    if ($workObject -is [array]) { $workObject = $workObject[-1] }

    $resolvedFolderName = if ($FolderName -eq "Restore") { "RestoreFolder" } else { $FolderName }
    $workObject = Get-Db2Folders -WorkObject $workObject -FolderName $resolvedFolderName -SkipRecreateDb2Folders -Quiet
    if ($workObject -is [array]) { $workObject = $workObject[-1] }

    return $workObject.RestoreFolder
}

function Get-Db2ShPrdBackupCacheRoot {
    param(
        [Parameter(Mandatory = $false)]
        [string]$DataDiskFallback = "E:"
    )
    $rootDrive = if (Test-Path -Path 'F:\' -PathType Container) { 'F:' } else { $DataDiskFallback.TrimEnd('\') }
    return Join-Path $rootDrive 'Db2ShPrdBackupCache'
}

function Copy-PrdBackupImagesToDb2ShCache {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceDatabase,
        [Parameter(Mandatory = $true)]
        [string]$RestoreFolder,
        [Parameter(Mandatory = $false)]
        [string]$DataDiskFallback = "E:"
    )
    $cacheRoot = Get-Db2ShPrdBackupCacheRoot -DataDiskFallback $DataDiskFallback
    if (-not (Test-Path -Path $cacheRoot -PathType Container)) {
        New-Item -Path $cacheRoot -ItemType Directory -Force | Out-Null
        Write-LogMessage "PIPELINE: Created PRD backup cache folder: $($cacheRoot)" -Level INFO
    }
    $backupFiles = @(Get-ChildItem -Path $RestoreFolder -Filter "$($SourceDatabase)*" -File -ErrorAction SilentlyContinue)
    if ($backupFiles.Count -eq 0) {
        Write-LogMessage "PIPELINE: No $($SourceDatabase)* backup files in $($RestoreFolder) to copy to cache" -Level WARN
        return
    }
    Get-ChildItem -Path $cacheRoot -Filter "$($SourceDatabase)*" -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    foreach ($bf in $backupFiles) {
        $dest = Join-Path $cacheRoot $bf.Name
        Copy-Item -Path $bf.FullName -Destination $dest -Force
        Write-LogMessage "PIPELINE: Cached PRD backup file $($bf.Name) -> $($cacheRoot)" -Level INFO
    }
}

function Invoke-Step {
    param(
        [string]$StepName,
        [string]$ScriptPath,
        [string[]]$Arguments = @()
    )

    Write-LogMessage "===============================================================" -Level INFO
    Write-LogMessage "PIPELINE: Starting $($StepName)" -Level INFO
    Write-LogMessage "===============================================================" -Level INFO

    $stepStart = Get-Date

    if (-not (Test-Path $ScriptPath -PathType Leaf)) {
        throw "$($StepName): Script not found at $($ScriptPath)"
    }

    $pwshArgs = @("-NoProfile", "-File", $ScriptPath) + $Arguments
    & pwsh.exe @pwshArgs
    $exitCode = $LASTEXITCODE

    $stepDuration = [math]::Round(((Get-Date) - $stepStart).TotalMinutes, 1)

    if ($null -ne $exitCode -and $exitCode -ne 0) {
        $stepResults[$StepName] = "FAILED (exit $($exitCode), $($stepDuration) min)"
        throw "$($StepName) failed with exit code $($exitCode) after $($stepDuration) minutes"
    }

    $stepResults[$StepName] = "OK ($($stepDuration) min)"
    Write-LogMessage "PIPELINE: $($StepName) completed in $($stepDuration) minutes" -Level INFO
    return [pscustomobject]@{
        ExitCode = $exitCode
        Duration = $stepDuration
    }
}


#########################################################
# Main pipeline execution
#########################################################
try {
    Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
    Write-LogMessage "Full Shadow Pipeline starting on $($env:COMPUTERNAME)" -Level INFO
    Write-LogMessage "Config: $($cfg.SourceDatabase) ($($cfg.SourceInstance)) -> $($cfg.TargetDatabase) ($($cfg.TargetInstance))" -Level INFO

    Test-Db2ServerAndAdmin

    Send-PipelineSms -Message "Shadow pipeline STARTED on $($env:COMPUTERNAME): $($cfg.SourceDatabase) -> $($cfg.TargetDatabase)"

    #########################################################
    # Preflight Phase 0: Restore federation entry if needed
    #########################################################
    Invoke-Phase0FederationRestore -ConfigObject $cfg

    #########################################################
    # Preflight: PRD backup cache (F:\Db2ShPrdBackupCache) + Db2Restore
    #########################################################
    $cacheRoot = Get-Db2ShPrdBackupCacheRoot -DataDiskFallback $cfg.DataDisk
    if (-not (Test-Path -Path $cacheRoot -PathType Container)) {
        New-Item -Path $cacheRoot -ItemType Directory -Force | Out-Null
        Write-LogMessage "Preflight: Created PRD backup cache folder: $($cacheRoot)" -Level INFO
    }
    else {
        Write-LogMessage "Preflight: PRD backup cache folder: $($cacheRoot)" -Level INFO
    }

    $restoreFolder = Find-Db2Folder -InstanceName $cfg.SourceInstance -FolderName Restore
    $localBackupPattern = "$($cfg.SourceDatabase)*.001"
    $usePrdCacheSeed = $false
    if (-not $SkipPrdRestore) {
        $cacheBackup001 = @(Get-ChildItem -Path $cacheRoot -Filter $localBackupPattern -File -ErrorAction SilentlyContinue)
        if ($cacheBackup001.Count -gt 0) {
            $cacheFilesAll = @(Get-ChildItem -Path $cacheRoot -Filter "$($cfg.SourceDatabase)*" -File -ErrorAction SilentlyContinue)
            Write-LogMessage "Preflight: Found $($cacheBackup001.Count) cached PRD image(s) in $($cacheRoot) — copying $($cacheFilesAll.Count) file(s) to $($restoreFolder)" -Level INFO
            foreach ($cf in $cacheFilesAll) {
                Copy-Item -Path $cf.FullName -Destination (Join-Path $restoreFolder $cf.Name) -Force
                Write-LogMessage "Preflight: Copied $($cf.Name) -> Db2Restore" -Level INFO
            }
            $usePrdCacheSeed = $true
        }
    }

    $localBackupFiles = @(Get-ChildItem -Path $restoreFolder -Filter $localBackupPattern -File -ErrorAction SilentlyContinue)
    if ($usePrdCacheSeed) {
        Write-LogMessage "Preflight: Db2Restore seeded from $($cacheRoot); Step-1 Phase -1 will skip PRD download (UsePrdCacheSeed)." -Level INFO
    }
    elseif ($localBackupFiles.Count -gt 0) {
        Write-LogMessage "Preflight: Found $($localBackupFiles.Count) local restore image(s) in $($restoreFolder) matching $($localBackupPattern). Step-1 will reuse local backup." -Level INFO
    }
    else {
        Write-LogMessage "Preflight: No local restore images in $($restoreFolder) matching $($localBackupPattern). Step-1 will use GetBackupFromEnvironment=PRD." -Level WARN
    }

    $scriptDir = $PSScriptRoot

    #########################################################
    # Step 1: Restore from PRD + Create shadow instance/DB
    #########################################################
    if (-not $SkipPrdRestore -or -not $SkipShadowCreate) {
        if ($SkipPrdRestore) {
            Write-LogMessage "PIPELINE: Skipping PRD restore (shadow create only)" -Level INFO
        }
        $step1Args = @("-InstanceName", $cfg.TargetInstance, "-DatabaseName", $cfg.TargetDatabase, "-DataDisk", $cfg.DataDisk)
        if ($SkipPrdRestore) { $step1Args += "-SkipPrdRestore" }
        if ($usePrdCacheSeed) { $step1Args += "-UsePrdCacheSeed:`$true" } else { $step1Args += "-UsePrdCacheSeed:`$false" }
        if ($SkipBackup) { $step1Args += "-SkipBackup:`$true" } else { $step1Args += "-SkipBackup:`$false" }
        Invoke-Step -StepName "Step 1 (PRD Restore + Shadow Create)" `
            -ScriptPath (Join-Path $scriptDir "Step-1-CreateShadowDatabase.ps1") `
            -Arguments $step1Args
        $stepResults["Step 1"] = $stepResults["Step 1 (PRD Restore + Shadow Create)"]
        if (-not $SkipPrdRestore) {
            Copy-PrdBackupImagesToDb2ShCache -SourceDatabase $cfg.SourceDatabase -RestoreFolder $restoreFolder -DataDiskFallback $cfg.DataDisk
        }
    }
    else {
        Write-LogMessage "PIPELINE: Skipping Step 1 entirely" -Level INFO
        $stepResults["Step 1"] = "SKIPPED"
    }

    #########################################################
    # Row count export paths (background jobs write here)
    #########################################################
    $execLogsDir = Join-Path $scriptDir "ExecLogs"
    if (-not (Test-Path $execLogsDir -PathType Container)) {
        New-Item -Path $execLogsDir -ItemType Directory -Force | Out-Null
    }
    $sourceRowCountFile = Join-Path $execLogsDir "$($env:COMPUTERNAME)_RowCounts_Source_$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $targetRowCountFile = Join-Path $execLogsDir "$($env:COMPUTERNAME)_RowCounts_Target_$(Get-Date -Format 'yyyyMMdd-HHmmss').json"

    #########################################################
    # Start source DB row count export (background)
    # Runs in parallel with Step 2 (data copy)
    #########################################################
    $sourceRowCountProcess = $null
    if (-not $SkipVerify -and -not $SkipCopy) {
        Write-LogMessage "PIPELINE: Starting source DB row count export in background ($($cfg.SourceInstance)/$($cfg.SourceDatabase))" -Level INFO
        $rowCountScript = Join-Path $scriptDir "Step-6-RowCountExport.ps1"
        $sourceRowCountProcess = Start-Process -FilePath "pwsh.exe" -ArgumentList @(
            "-NoProfile", "-File", $rowCountScript,
            "-InstanceName", $cfg.SourceInstance,
            "-DatabaseName", $cfg.SourceDatabase,
            "-OutputPath", $sourceRowCountFile
        ) -PassThru -WindowStyle Hidden
        Write-LogMessage "PIPELINE: Source row count export started (PID: $($sourceRowCountProcess.Id))" -Level INFO
    }

    #########################################################
    # Step 2: Copy data from source to shadow
    #########################################################
    if (-not $SkipCopy) {
        $step2Args = @(
            "-SourceInstance", $cfg.SourceInstance,
            "-SourceDatabase", $cfg.SourceDatabase,
            "-TargetInstance", $cfg.TargetInstance,
            "-TargetDatabase", $cfg.TargetDatabase,
            "-DataDisk", $cfg.DataDisk
        )
        $step2Result = Invoke-Step -StepName "Step 2 (Copy Data)" `
            -ScriptPath (Join-Path $scriptDir "Step-2-CopyDatabaseContent.ps1") `
            -Arguments $step2Args

        if ($step2Result.Duration -lt $MinStep2Minutes) {
            $tooFastMsg = "Shadow pipeline ABORTED on $($env:COMPUTERNAME): Step-2 completed in $($step2Result.Duration) min (< $($MinStep2Minutes) min threshold). Likely data transfer failure."
            Write-LogMessage $tooFastMsg -Level ERROR
            Send-PipelineSms -Message $tooFastMsg
            throw "Step-2 duration guard triggered: $($step2Result.Duration) minutes is below minimum $($MinStep2Minutes) minutes"
        }
    }
    else {
        Write-LogMessage "PIPELINE: Skipping Step 2 (data copy)" -Level INFO
        $stepResults["Step 2"] = "SKIPPED"
    }

    #########################################################
    # Wait for source row count export to finish (if started)
    #########################################################
    if ($null -ne $sourceRowCountProcess -and -not $sourceRowCountProcess.HasExited) {
        Write-LogMessage "PIPELINE: Waiting for source row count export to complete (PID: $($sourceRowCountProcess.Id))..." -Level INFO
        $sourceRowCountProcess.WaitForExit()
        Write-LogMessage "PIPELINE: Source row count export finished (exit code: $($sourceRowCountProcess.ExitCode))" -Level INFO
    }
    if ($null -ne $sourceRowCountProcess) {
        if ($sourceRowCountProcess.ExitCode -ne 0) {
            Write-LogMessage "PIPELINE: Source row count export failed (exit $($sourceRowCountProcess.ExitCode)), row counts will be unavailable for PreMove" -Level WARN
            $sourceRowCountFile = $null
        } elseif (-not (Test-Path $sourceRowCountFile)) {
            Write-LogMessage "PIPELINE: Source row count file not found at $($sourceRowCountFile), row counts will be unavailable for PreMove" -Level WARN
            $sourceRowCountFile = $null
        } else {
            Write-LogMessage "PIPELINE: Source row count file ready: $($sourceRowCountFile)" -Level INFO
            $stepResults["Source RowCount Export"] = "OK (background)"
        }
    }

    #########################################################
    # Target DB2SH row count export (background)
    # Starts here so it runs while we wait; we wait for it
    # to finish before calling Step 6a.
    #########################################################
    $targetRowCountProcess = $null
    if (-not $SkipVerify) {
        Write-LogMessage "PIPELINE: Starting target DB2SH row count export ($($cfg.TargetInstance)/$($cfg.TargetDatabase))" -Level INFO
        $rowCountScript = Join-Path $scriptDir "Step-6-RowCountExport.ps1"
        $targetRowCountProcess = Start-Process -FilePath "pwsh.exe" -ArgumentList @(
            "-NoProfile", "-File", $rowCountScript,
            "-InstanceName", $cfg.TargetInstance,
            "-DatabaseName", $cfg.TargetDatabase,
            "-OutputPath", $targetRowCountFile
        ) -PassThru -WindowStyle Hidden
        Write-LogMessage "PIPELINE: Target row count export started (PID: $($targetRowCountProcess.Id))" -Level INFO
    }

    #########################################################
    # Wait for target DB2SH row count export to finish
    #########################################################
    if ($null -ne $targetRowCountProcess) {
        if (-not $targetRowCountProcess.HasExited) {
            Write-LogMessage "PIPELINE: Waiting for target row count export to complete (PID: $($targetRowCountProcess.Id))..." -Level INFO
            $targetRowCountProcess.WaitForExit(600000)
            if (-not $targetRowCountProcess.HasExited) {
                Write-LogMessage "PIPELINE: Target row count export timed out after 10 min, killing process" -Level WARN
                $targetRowCountProcess.Kill()
            }
        }
        Write-LogMessage "PIPELINE: Target row count export finished (exit code: $($targetRowCountProcess.ExitCode))" -Level INFO
        if ($targetRowCountProcess.ExitCode -ne 0) {
            Write-LogMessage "PIPELINE: Target row count export failed (exit $($targetRowCountProcess.ExitCode))" -Level WARN
            $targetRowCountFile = $null
        } elseif (-not (Test-Path $targetRowCountFile)) {
            Write-LogMessage "PIPELINE: Target row count file not found at $($targetRowCountFile)" -Level WARN
            $targetRowCountFile = $null
        } else {
            Write-LogMessage "PIPELINE: Target row count file ready: $($targetRowCountFile)" -Level INFO
            $stepResults["Target RowCount Export"] = "OK (background)"
        }
    }

    #########################################################
    # Step 6a: Object inventory + row count comparison (PreMove)
    # Both row count files are guaranteed ready at this point.
    #########################################################
    $preMoveJsonPath = $null
    if (-not $SkipVerify) {
        $verifyArgs = @(
            "-SourceInstance", $cfg.SourceInstance,
            "-SourceDatabase", $cfg.SourceDatabase,
            "-TargetInstance", $cfg.TargetInstance,
            "-TargetDatabase", $cfg.TargetDatabase,
            "-Phase", "PreMove"
        )
        if (-not [string]::IsNullOrEmpty($sourceRowCountFile) -and (Test-Path $sourceRowCountFile)) {
            $verifyArgs += @("-SourceRowCountFile", $sourceRowCountFile)
        }
        if (-not [string]::IsNullOrEmpty($targetRowCountFile) -and (Test-Path $targetRowCountFile)) {
            $verifyArgs += @("-TargetRowCountFile", $targetRowCountFile)
        }
        Invoke-Step -StepName "Step 6a (Comprehensive Verify - PreMove)" `
            -ScriptPath (Join-Path $scriptDir "Step-6-ComprehensiveVerification.ps1") `
            -Arguments $verifyArgs

        $preMoveJsonFiles = @(Get-ChildItem -Path $execLogsDir -Filter "*_PreMove_*.json" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending)
        if ($preMoveJsonFiles.Count -gt 0) {
            $preMoveJsonPath = $preMoveJsonFiles[0].FullName
        }
    }
    else {
        Write-LogMessage "PIPELINE: Skipping pre-move verification" -Level INFO
        $stepResults["Step 6a (PreMove)"] = "SKIPPED"
    }

    if ($StopAfterVerify) {
        Write-LogMessage "PIPELINE: StopAfterVerify set — not moving shadow back to original" -Level INFO
        $stepResults["Step 4"] = "SKIPPED (StopAfterVerify)"
    }
    else {
        #########################################################
        # Step 4: Move shadow back to original instance
        #########################################################
        Invoke-Step -StepName "Step 4 (Move to Original Instance)" `
            -ScriptPath (Join-Path $scriptDir "Step-4-MoveToOriginalInstance.ps1") `
            -Arguments @("-DropExistingTarget", "-CleanupSourceAfter")

        #########################################################
        # Grant Export → Import (role-based or classic)
        # Step 4 restores FKMVFT with baseline direct grants from
        # Set-DatabasePermissions + Add-SpecificGrants. We must
        # export those grants to JSON first, then the import step
        # reads the JSON and converts direct grants to DB2 roles.
        #########################################################
        $grantExportScript = Join-Path $env:OptPath "DedgePshApps\Db2-GrantsExport\Db2-GrantsExport.ps1"
        $grantImportScript = Join-Path $env:OptPath "DedgePshApps\Db2-GrantsImport\Db2-GrantsImport.ps1"

        if ((Test-Path $grantExportScript) -and (Test-Path $grantImportScript)) {
            Write-LogMessage "PIPELINE: Exporting current grants for $($cfg.SourceDatabase) before role conversion" -Level INFO
            $exportArgs = @("-NoProfile", "-File", $grantExportScript)
            & pwsh.exe @exportArgs
            $exportExitCode = $LASTEXITCODE
            if ($null -eq $exportExitCode -or $exportExitCode -ne 0) {
                $exitDesc = if ($null -eq $exportExitCode) { "null" } else { "$($exportExitCode)" }
                Write-LogMessage "PIPELINE: Grant export failed (exit $($exitDesc)) — skipping import" -Level WARN
                $stepResults["Grant Export"] = "FAILED (exit $($exitDesc))"
                $stepResults["Grant Import"] = "SKIPPED (export failed)"
            } else {
                Write-LogMessage "PIPELINE: Grant export completed — proceeding to import" -Level INFO
                $stepResults["Grant Export"] = "OK"

                $grantMode = if ($UseRoleBasedGrants) { 'role-based' } else { 'classic' }
                Write-LogMessage "PIPELINE: Importing grants ($($grantMode)) for $($cfg.SourceDatabase)" -Level INFO
                $grantArgs = @(
                    "-NoProfile", "-File", $grantImportScript,
                    "-DatabaseName", $cfg.SourceDatabase
                )
                if ($UseRoleBasedGrants) {
                    $grantArgs += "-UseNewConfigurations:`$true"
                }
                & pwsh.exe @grantArgs
                $grantExitCode = $LASTEXITCODE
                if ($null -eq $grantExitCode -or $grantExitCode -ne 0) {
                    $exitDesc = if ($null -eq $grantExitCode) { "null" } else { "$($grantExitCode)" }
                    Write-LogMessage "PIPELINE: Grant import failed (exit $($exitDesc))" -Level WARN
                    $stepResults["Grant Import"] = "FAILED (exit $($exitDesc))"
                } else {
                    Write-LogMessage "PIPELINE: Grant import completed successfully ($($grantMode))" -Level INFO
                    $stepResults["Grant Import"] = "OK ($($grantMode))"
                }
            }
        } else {
            if (-not (Test-Path $grantExportScript)) {
                Write-LogMessage "PIPELINE: Grant export script not found at $($grantExportScript)" -Level WARN
                $stepResults["Grant Export"] = "SKIPPED (script missing)"
            }
            if (-not (Test-Path $grantImportScript)) {
                Write-LogMessage "PIPELINE: Grant import script not found at $($grantImportScript)" -Level WARN
            }
            $stepResults["Grant Import"] = "SKIPPED (script missing)"
        }

        #########################################################
        # Optional: Post-move Db2-Backup on original instance (after Step 4 + grants)
        #########################################################
        if ($effectiveRunPostMoveBackup) {
            $postBackupScript = Join-Path $env:OptPath "DedgePshApps\Db2-Backup\Db2-Backup.ps1"
            Write-LogMessage "PIPELINE: Post-move backup enabled - $($cfg.SourceInstance), DatabaseType=$($effectivePostMoveBackupDatabaseType), Offline=$($effectivePostMoveBackupOffline)" -Level INFO
            $backupStepArgs = @(
                "-InstanceName", $cfg.SourceInstance,
                "-DatabaseType", $effectivePostMoveBackupDatabaseType
            )
            if ($effectivePostMoveBackupOffline) {
                $backupStepArgs += "-Offline"
            }
            Invoke-Step -StepName "Post-move Db2-Backup ($($cfg.SourceInstance))" `
                -ScriptPath $postBackupScript `
                -Arguments $backupStepArgs
        }

        #########################################################
        # Step 6b: Comprehensive Verification (PostMove)
        # Target row count file (DB2SH counts before move)
        # was already exported and validated before Step 6a.
        #########################################################
        $postMoveJsonPath = $null
        if (-not $SkipVerify) {
            $postVerifyArgs = @(
                "-SourceInstance", $cfg.SourceInstance,
                "-SourceDatabase", $cfg.SourceDatabase,
                "-TargetInstance", $cfg.TargetInstance,
                "-TargetDatabase", $cfg.TargetDatabase,
                "-Phase", "PostMove"
            )
            if (-not [string]::IsNullOrEmpty($targetRowCountFile) -and (Test-Path $targetRowCountFile)) {
                $postVerifyArgs += @("-SourceRowCountFile", $targetRowCountFile)
            }
            Invoke-Step -StepName "Step 6b (Comprehensive Verify - PostMove)" `
                -ScriptPath (Join-Path $scriptDir "Step-6-ComprehensiveVerification.ps1") `
                -Arguments $postVerifyArgs

            $postMoveJsonFiles = @(Get-ChildItem -Path $execLogsDir -Filter "*_PostMove_*.json" -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending)
            if ($postMoveJsonFiles.Count -gt 0) {
                $postMoveJsonPath = $postMoveJsonFiles[0].FullName
            }
        }
    }

    #########################################################
    # Step 7: Generate HTML Report
    #########################################################
    $reportPath = $null
    if (-not $SkipVerify -and -not [string]::IsNullOrEmpty($preMoveJsonPath)) {
        $reportArgs = @("-PreMoveJsonPath", $preMoveJsonPath)
        if (-not [string]::IsNullOrEmpty($postMoveJsonPath)) {
            $reportArgs += @("-PostMoveJsonPath", $postMoveJsonPath)
        }
        Invoke-Step -StepName "Step 7 (Generate HTML Report)" `
            -ScriptPath (Join-Path $scriptDir "Step-7-GenerateReport.ps1") `
            -Arguments $reportArgs

        $reportFiles = @(Get-ChildItem -Path (Join-Path $scriptDir "ExecLogs") -Filter "*_Report_*.html" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending)
        if ($reportFiles.Count -gt 0) {
            $reportPath = $reportFiles[0].FullName
        }
    }

    #########################################################
    # Pipeline Summary
    #########################################################
    $totalDuration = [math]::Round(((Get-Date) - $pipelineStart).TotalMinutes, 1)

    Write-LogMessage "===============================================================" -Level INFO
    Write-LogMessage "PIPELINE SUMMARY — Total: $($totalDuration) minutes" -Level INFO
    Write-LogMessage "===============================================================" -Level INFO
    foreach ($key in $stepResults.Keys) {
        Write-LogMessage "  $($key): $($stepResults[$key])" -Level INFO
    }
    if (-not [string]::IsNullOrEmpty($reportPath)) {
        Write-LogMessage "  Report: $($reportPath)" -Level INFO
    }
    Write-LogMessage "===============================================================" -Level INFO

    $smsMsg = "Shadow pipeline COMPLETE on $($env:COMPUTERNAME): $($cfg.SourceDatabase) done in $($totalDuration) min. All steps OK."
    if (-not [string]::IsNullOrEmpty($reportPath)) {
        $smsMsg += " Report: $($reportPath)"
    }
    Send-PipelineSms -Message $smsMsg

    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    $totalDuration = [math]::Round(((Get-Date) - $pipelineStart).TotalMinutes, 1)
    Write-LogMessage "PIPELINE FAILED after $($totalDuration) minutes: $($_.Exception.Message)" -Level ERROR -Exception $_

    Write-LogMessage "===============================================================" -Level INFO
    Write-LogMessage "PIPELINE SUMMARY (FAILED) — Total: $($totalDuration) minutes" -Level INFO
    Write-LogMessage "===============================================================" -Level INFO
    foreach ($key in $stepResults.Keys) {
        Write-LogMessage "  $($key): $($stepResults[$key])" -Level INFO
    }
    Write-LogMessage "===============================================================" -Level INFO

    Send-PipelineSms -Message "Shadow pipeline FAILED on $($env:COMPUTERNAME) after $($totalDuration) min: $($_.Exception.Message)"

    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    exit 1
}
