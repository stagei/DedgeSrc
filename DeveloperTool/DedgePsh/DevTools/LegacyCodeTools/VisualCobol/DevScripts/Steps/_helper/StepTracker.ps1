<#
.SYNOPSIS
    Step tracker functions for the Visual COBOL pipeline.
.DESCRIPTION
    Provides Read-StepState, Write-StepState, and Get-StepsConfig for
    persisting pipeline progress to current-step.json and reading the
    step definitions from steps-config.json.

    Dot-source this file from the orchestrator script.
#>

$script:StepsDir = Split-Path $PSScriptRoot -Parent
$script:StateFile = Join-Path $script:StepsDir 'current-step.json'
$script:ConfigFile = Join-Path $script:StepsDir 'steps-config.json'

function Get-StepsConfig {
    [CmdletBinding()] param()
    if (-not (Test-Path $script:ConfigFile)) {
        Write-LogMessage "steps-config.json not found at: $($script:ConfigFile)" -Level ERROR
        return $null
    }
    $raw = Get-Content $script:ConfigFile -Raw -Encoding utf8 | ConvertFrom-Json
    return @($raw)
}

function Read-StepState {
    [CmdletBinding()] param()
    if (-not (Test-Path $script:StateFile)) {
        return $null
    }
    return Get-Content $script:StateFile -Raw -Encoding utf8 | ConvertFrom-Json
}

function Write-StepState {
    [CmdletBinding()]
    param(
        [int]$CurrentStep,
        [ValidateSet('Running', 'PausedForReview', 'Completed', 'Failed')]
        [string]$Status,
        [int]$LastCompleted = 0,
        [string]$StartedAt,
        [string]$PausedAt,
        [string]$PausedReason
    )

    $state = [ordered]@{
        CurrentStep  = $CurrentStep
        Status       = $Status
        LastCompleted = $LastCompleted
        StartedAt    = if ($StartedAt) { $StartedAt } else { Get-Date -Format 'yyyy-MM-dd HH:mm:ss' }
        PausedAt     = $PausedAt
        PausedReason = $PausedReason
    }
    $state | ConvertTo-Json -Depth 2 | Out-File -FilePath $script:StateFile -Encoding utf8 -Force
    return $state
}

function Remove-StepState {
    [CmdletBinding()] param()
    if (Test-Path $script:StateFile) {
        Remove-Item $script:StateFile -Force
        Write-LogMessage 'Removed current-step.json (clean start)' -Level INFO
    }
}

function Get-NextStep {
    [CmdletBinding()]
    param(
        [int]$CurrentStep,
        [array]$StepsConfig
    )
    $currentIndex = -1
    for ($i = 0; $i -lt $StepsConfig.Count; $i++) {
        if ([int]$StepsConfig[$i].Step -eq $CurrentStep) {
            $currentIndex = $i
            break
        }
    }
    if ($currentIndex -lt 0 -or ($currentIndex + 1) -ge $StepsConfig.Count) {
        return $null
    }
    return $StepsConfig[$currentIndex + 1]
}
