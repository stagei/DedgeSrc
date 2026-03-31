<#
.SYNOPSIS
    Production-grade manual runner for Db2-ShadowDatabase pipeline.

.DESCRIPTION
    Runs the full chain on the server with visible console logging:
      Step-1 -> Step-2 -> Step-3 -> Step-5 -> Step-4

    Safeguards:
    - Restores federation entry preflight (same intent as Step-1 Phase 0)
    - Detects local restore image (*.001) in Db2Restore before Step-1
    - Sends SMS on failure and completion
    - Fails fast if Step-2 completes in less than 2 hours
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$SkipBackup,

    [Parameter(Mandatory = $false)]
    [int]$MinStep2Minutes = 120,

    [Parameter(Mandatory = $false)]
    [string[]]$SmsNumbers
)

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

. (Join-Path $PSScriptRoot "_helpers\_Shared.ps1")
$configPath = Get-ShadowDatabaseConfigPath -ScriptRoot $PSScriptRoot
$env:Db2ShadowConfigPath = $configPath
$cfg = Get-Content $configPath -Raw | ConvertFrom-Json

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

    $localDbV2Copy = Join-Path $env:TEMP "DatabasesV2_Preflight_RunManually.json"
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

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StepName,
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,
        [Parameter(Mandatory = $false)]
        [string[]]$Arguments = @()
    )

    Write-LogMessage "=== Starting $($StepName) ===" -Level INFO
    $stepStart = Get-Date
    & pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments
    $exitCode = [int]$LASTEXITCODE
    $duration = (Get-Date) - $stepStart
    $durationMin = [math]::Round($duration.TotalMinutes, 1)

    if ($exitCode -ne 0) {
        throw "$($StepName) failed with exit code $($exitCode) after $($durationMin) minutes"
    }

    Write-LogMessage "=== $($StepName) completed in $($durationMin) minutes ===" -Level INFO
    return [pscustomobject]@{
        ExitCode  = $exitCode
        Duration  = $duration
        Minutes   = $durationMin
    }
}

$startTime = Get-Date
$stepResults = [ordered]@{}

try {
    Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
    Test-Db2ServerAndAdmin

    Send-PipelineSms -Message "Shadow pipeline STARTED on $($env:COMPUTERNAME): $($cfg.SourceDatabase)->$($cfg.TargetDatabase)"

    # Preflight federation restore (idempotent). Step-1 also has this logic.
    Invoke-Phase0FederationRestore -ConfigObject $cfg

    # Check if local restore image already exists.
    $restoreFolder = Find-Db2Folder -InstanceName $cfg.SourceInstance -FolderName Restore
    $localBackupPattern = "$($cfg.SourceDatabase)*.001"
    $localBackupFiles = @(Get-ChildItem -Path $restoreFolder -Filter $localBackupPattern -File -ErrorAction SilentlyContinue)
    if ($localBackupFiles.Count -gt 0) {
        Write-LogMessage "Preflight: Found $($localBackupFiles.Count) local restore image(s) in $($restoreFolder) matching $($localBackupPattern). Step-1 will reuse local backup before PRD copy." -Level INFO
    }
    else {
        Write-LogMessage "Preflight: No local restore images found in $($restoreFolder) matching $($localBackupPattern). Step-1 will use GetBackupFromEnvironment=PRD." -Level WARN
    }

    $scriptDir = $PSScriptRoot

    $step1Args = @("-InstanceName", $cfg.TargetInstance, "-DatabaseName", $cfg.TargetDatabase, "-DataDisk", $cfg.DataDisk)
    if ($SkipBackup) { $step1Args += "-SkipBackup" }
    $stepResults["Step-1"] = (Invoke-Step -StepName "Step-1-CreateShadowDatabase.ps1" -ScriptPath (Join-Path $scriptDir "Step-1-CreateShadowDatabase.ps1") -Arguments $step1Args).Minutes

    $step2Args = @(
        "-SourceInstance", $cfg.SourceInstance,
        "-SourceDatabase", $cfg.SourceDatabase,
        "-TargetInstance", $cfg.TargetInstance,
        "-TargetDatabase", $cfg.TargetDatabase,
        "-DataDisk", $cfg.DataDisk
    )
    $step2Result = Invoke-Step -StepName "Step-2-CopyDatabaseContent.ps1" -ScriptPath (Join-Path $scriptDir "Step-2-CopyDatabaseContent.ps1") -Arguments $step2Args
    $stepResults["Step-2"] = $step2Result.Minutes

    if ($step2Result.Minutes -lt $MinStep2Minutes) {
        $tooFastMessage = "Shadow pipeline ABORTED on $($env:COMPUTERNAME): Step-2 completed in $($step2Result.Minutes) min (< $($MinStep2Minutes) min)."
        Write-LogMessage $tooFastMessage -Level ERROR
        Send-PipelineSms -Message $tooFastMessage
        throw "Step-2 duration guard triggered: $($step2Result.Minutes) minutes is below minimum $($MinStep2Minutes) minutes"
    }

    $step3Args = @(
        "-SourceInstance", $cfg.SourceInstance,
        "-SourceDatabase", $cfg.SourceDatabase,
        "-TargetInstance", $cfg.TargetInstance,
        "-TargetDatabase", $cfg.TargetDatabase
    )
    $stepResults["Step-3"] = (Invoke-Step -StepName "Step-3-CleanupShadowDatabase.ps1" -ScriptPath (Join-Path $scriptDir "Step-3-CleanupShadowDatabase.ps1") -Arguments $step3Args).Minutes

    $step5Args = @(
        "-SourceInstance", $cfg.SourceInstance,
        "-SourceDatabase", $cfg.SourceDatabase,
        "-TargetInstance", $cfg.TargetInstance,
        "-TargetDatabase", $cfg.TargetDatabase
    )
    $stepResults["Step-5"] = (Invoke-Step -StepName "Step-5-VerifyRowCounts.ps1" -ScriptPath (Join-Path $scriptDir "Step-5-VerifyRowCounts.ps1") -Arguments $step5Args).Minutes

    $step4Args = @("-DropExistingTarget", "-CleanupSourceAfter")
    $stepResults["Step-4"] = (Invoke-Step -StepName "Step-4-MoveToOriginalInstance.ps1" -ScriptPath (Join-Path $scriptDir "Step-4-MoveToOriginalInstance.ps1") -Arguments $step4Args).Minutes

    $totalMinutes = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
    Write-LogMessage "Pipeline completed successfully in $($totalMinutes) minutes" -Level INFO
    foreach ($key in $stepResults.Keys) {
        Write-LogMessage "  $($key): $($stepResults[$key]) min" -Level INFO
    }

    Send-PipelineSms -Message "Shadow pipeline COMPLETE on $($env:COMPUTERNAME): all steps OK in $($totalMinutes) min."
    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    $totalMinutes = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
    $errorMessage = "Shadow pipeline FAILED on $($env:COMPUTERNAME) after $($totalMinutes) min: $($_.Exception.Message)"
    Write-LogMessage $errorMessage -Level ERROR -Exception $_
    Send-PipelineSms -Message $errorMessage
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    exit 1
}
