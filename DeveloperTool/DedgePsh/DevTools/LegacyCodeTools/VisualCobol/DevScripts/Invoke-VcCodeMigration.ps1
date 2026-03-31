#Requires -Version 7.0
<#
.SYNOPSIS
    End-to-end COBOL code migration orchestrator for Visual COBOL.
.DESCRIPTION
    Runs the recompilation pipeline defined in Steps\steps-config.json.
    Tracks progress via Steps\current-step.json so the pipeline can be
    resumed after failures or manual-review pauses.

    Steps with Mode=Automatic run sequentially. Steps with Mode=ManualRestart
    pause the pipeline — the user reviews reports, then reruns this script
    to continue from the paused step.

    Cleanup: before each step runs, all output from that step and later
    steps is removed so the pipeline can complete cleanly.

    Utility scripts live in OneTime/ and can be run independently.
.PARAMETER StartFromStep
    Force restart from a specific step number (e.g. 30). Cleans output
    from that step onward. Overrides current-step.json.
.PARAMETER Fresh
    Delete current-step.json and start from Step 10 (full clean run).
.EXAMPLE
    .\Invoke-VcCodeMigration.ps1
    .\Invoke-VcCodeMigration.ps1 -StartFromStep 40
    .\Invoke-VcCodeMigration.ps1 -Fresh
    .\Invoke-VcCodeMigration.ps1 -SkipCompile -SkipBind
#>
[CmdletBinding()]
param(
    [string]$VcPath = $(if ($env:VCPATH) { $env:VCPATH } else { 'C:\fkavd\Dedge2' }),
    [string]$WorkFolder = $(if ($env:PSWorkPath) { "$($env:PSWorkPath)\VisualCobolCodeMigration" } else { 'C:\opt\work\VisualCobolCodeMigration' }),
    [string]$Repository = 'https://Dedge.visualstudio.com/DefaultCollection/Dedge/_git/Dedge',
    [string]$DbAlias = 'BASISVCT',
    [ValidateSet('32', '64')]
    [string]$CobMode = '32',
    [string]$BindCollection = 'DBM',
    [int]$StartFromStep = 0,
    [switch]$Fresh,
    [switch]$SkipClone,
    [switch]$SkipCompile,
    [switch]$SkipBind,
    [switch]$SendNotification
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

$allowedDatabases = @('BASISVCT', 'FKMVCT')
if ($DbAlias -notin $allowedDatabases) {
    Write-LogMessage "SAFETY: Only BASISVCT/FKMVCT allowed. Requested: $($DbAlias)" -Level ERROR
    exit 1
}

$helperDir = Join-Path $PSScriptRoot 'Steps\_helper'
. (Join-Path $helperDir 'VcEnvironmentSwitch.ps1')
. (Join-Path $helperDir 'StepTracker.ps1')
. (Join-Path $helperDir 'Clear-VcStepOutput.ps1')
. (Join-Path $helperDir 'CollectReports.ps1')

$vcSwitched = Switch-ToVisualCobol
if (-not $vcSwitched) {
    Write-LogMessage 'Failed to switch to Visual COBOL environment' -Level ERROR
    exit 1
}

$smsNumber = switch ($env:USERNAME) {
    'FKGEISTA' { '+4797188358' }
    'FKSVEERI' { '+4795762742' }
    'FKMISTA'  { '+4799348397' }
    'FKCELERI' { '+4745269945' }
    default    { '+4797188358' }
}

$stepsDir = Join-Path $PSScriptRoot 'Steps'
$startTime = Get-Date

try {
    $stepsConfig = Get-StepsConfig
    if (-not $stepsConfig) {
        Write-LogMessage 'Cannot load steps-config.json — aborting' -Level ERROR
        exit 1
    }

    if ($Fresh) {
        Remove-StepState
        $StartFromStep = [int]$stepsConfig[0].Step
    }

    $state = Read-StepState
    if ($StartFromStep -gt 0) {
        $validStep = $stepsConfig | Where-Object { [int]$_.Step -eq $StartFromStep }
        if (-not $validStep) {
            Write-LogMessage "Step $($StartFromStep) not found in steps-config.json" -Level ERROR
            exit 1
        }
        $currentStep = $StartFromStep
        Write-LogMessage "Forced restart from step $($currentStep)" -Level INFO
    } elseif ($state) {
        if ($state.Status -eq 'Completed') {
            Write-LogMessage 'Pipeline already completed. Use -Fresh to start over or -StartFromStep to rerun a specific step.' -Level INFO
            exit 0
        }
        $currentStep = [int]$state.CurrentStep
        Write-LogMessage "Resuming from step $($currentStep) (status: $($state.Status))" -Level INFO
    } else {
        $currentStep = [int]$stepsConfig[0].Step
    }

    if ($SendNotification) {
        Send-Sms -Receiver $smsNumber -Message "Migration pipeline starting at step $($currentStep)"
    }

    Write-LogMessage '=== Visual COBOL Recompilation Pipeline ===' -Level INFO
    Write-LogMessage "VcPath: $($VcPath) | CobMode: $($CobMode) | DbAlias: $($DbAlias)" -Level INFO
    Write-LogMessage "Starting at step: $($currentStep)" -Level INFO

    $startIndex = -1
    for ($i = 0; $i -lt $stepsConfig.Count; $i++) {
        if ([int]$stepsConfig[$i].Step -eq $currentStep) {
            $startIndex = $i
            break
        }
    }
    if ($startIndex -lt 0) {
        Write-LogMessage "Step $($currentStep) not found in config" -Level ERROR
        exit 1
    }

    for ($i = $startIndex; $i -lt $stepsConfig.Count; $i++) {
        $stepDef = $stepsConfig[$i]
        $stepNum = [int]$stepDef.Step
        $stepScript = Join-Path $stepsDir $stepDef.Script
        $stepMode = $stepDef.Mode

        if ($stepMode -eq 'ManualRestart') {
            $prevState = Read-StepState
            if ($prevState -and $prevState.Status -eq 'PausedForReview' -and [int]$prevState.CurrentStep -eq $stepNum) {
                Write-LogMessage "Step $($stepNum) ($($stepDef.Description)) was paused — resuming now" -Level INFO
            } elseif ($StartFromStep -ne $stepNum -and $i -ne $startIndex) {
                Write-StepState -CurrentStep $stepNum -Status 'PausedForReview' `
                    -LastCompleted ([int]$stepsConfig[$i - 1].Step) `
                    -StartedAt $startTime.ToString('yyyy-MM-dd HH:mm:ss') `
                    -PausedAt (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') `
                    -PausedReason "Manual review required before $($stepDef.Description)"
                Write-LogMessage "=== PAUSED before step $($stepNum): $($stepDef.Description) ===" -Level INFO
                Write-LogMessage 'Review reports, then rerun this script to continue.' -Level INFO

                Copy-VcReportsToArchive -ScriptName 'Invoke-VcCodeMigration' -VcPath $VcPath

                if ($SendNotification) {
                    $elapsed = (Get-Date) - $startTime
                    Send-Sms -Receiver $smsNumber -Message "Pipeline paused at step $($stepNum) ($($stepDef.Description)). Review reports. Duration so far: $($elapsed.TotalMinutes.ToString('F0'))min"
                }
                exit 0
            }
        }

        if ($SkipCompile -and $stepNum -eq 40) {
            Write-LogMessage "Step $($stepNum): $($stepDef.Description) (SKIPPED — -SkipCompile)" -Level INFO
            continue
        }
        if ($SkipBind -and $stepNum -eq 50) {
            Write-LogMessage "Step $($stepNum): $($stepDef.Description) (SKIPPED — -SkipBind)" -Level INFO
            continue
        }

        Write-LogMessage "--- Step $($stepNum): $($stepDef.Description) ---" -Level INFO

        Clear-VcStepOutput -FromStep $stepNum -VcPath $VcPath

        Write-StepState -CurrentStep $stepNum -Status 'Running' `
            -LastCompleted $(if ($i -gt 0) { [int]$stepsConfig[$i - 1].Step } else { 0 }) `
            -StartedAt $startTime.ToString('yyyy-MM-dd HH:mm:ss')

        if (-not (Test-Path $stepScript)) {
            Write-LogMessage "Script not found: $($stepScript)" -Level ERROR
            Write-StepState -CurrentStep $stepNum -Status 'Failed' `
                -StartedAt $startTime.ToString('yyyy-MM-dd HH:mm:ss')
            exit 1
        }

        $stepArgs = @{}
        switch ($stepNum) {
            15 { $stepArgs = @{ VcPath = $VcPath } }
            25 { $stepArgs = @{ VcPath = $VcPath } }
            30 { $stepArgs = @{ VcPath = $VcPath; DbAlias = $DbAlias } }
            40 { $stepArgs = @{ VcPath = $VcPath; CobMode = $CobMode } }
            50 { $stepArgs = @{ DatabaseAlias = $DbAlias; Collection = $BindCollection } }
            60 { $stepArgs = @{ VcPath = $VcPath } }
            70 { $stepArgs = @{ VcPath = $VcPath } }
        }

        & $stepScript @stepArgs
        $stepExit = $LASTEXITCODE

        if ($stepExit -ne 0) {
            Write-LogMessage "Step $($stepNum) FAILED with exit code $($stepExit)" -Level ERROR
            Write-StepState -CurrentStep $stepNum -Status 'Failed' `
                -StartedAt $startTime.ToString('yyyy-MM-dd HH:mm:ss')

            if ($SendNotification) {
                $elapsed = (Get-Date) - $startTime
                Send-Sms -Receiver $smsNumber -Message "Pipeline FAILED at step $($stepNum) ($($stepDef.Description)). Exit: $($stepExit). Duration: $($elapsed.TotalMinutes.ToString('F0'))min"
            }
            exit $stepExit
        }

        Write-LogMessage "Step $($stepNum) completed successfully" -Level INFO
    }

    Write-StepState -CurrentStep ([int]$stepsConfig[-1].Step) -Status 'Completed' `
        -LastCompleted ([int]$stepsConfig[-1].Step) `
        -StartedAt $startTime.ToString('yyyy-MM-dd HH:mm:ss')

    $elapsed = (Get-Date) - $startTime
    Write-LogMessage "=== Pipeline completed in $($elapsed.TotalMinutes.ToString('F1')) minutes ===" -Level INFO

    Copy-VcReportsToArchive -ScriptName 'Invoke-VcCodeMigration' -VcPath $VcPath

    if ($SendNotification) {
        Send-Sms -Receiver $smsNumber -Message "Migration pipeline completed. Duration: $($elapsed.TotalMinutes.ToString('F0'))min"
    }
} catch {
    $elapsed = (Get-Date) - $startTime
    Write-LogMessage "Pipeline FAILED after $($elapsed.TotalMinutes.ToString('F1')) minutes: $($_.Exception.Message)" -Level ERROR

    $currentState = Read-StepState
    if ($currentState) {
        Write-StepState -CurrentStep ([int]$currentState.CurrentStep) -Status 'Failed' `
            -StartedAt $startTime.ToString('yyyy-MM-dd HH:mm:ss')
    }

    if ($SendNotification) {
        Send-Sms -Receiver $smsNumber -Message "Migration FAILED: $($_.Exception.Message)"
    }
    throw
} finally {
    Switch-ToMicroFocus
}
