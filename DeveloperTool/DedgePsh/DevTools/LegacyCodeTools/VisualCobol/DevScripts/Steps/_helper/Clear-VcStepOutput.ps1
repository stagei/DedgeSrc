<#
.SYNOPSIS
    Cleans output files from a given step and all subsequent steps.
.DESCRIPTION
    Before restarting or re-running a step, this function removes the output
    produced by that step and every later step. This ensures a clean state
    so the remaining pipeline can complete without stale data conflicts.

    Dot-source this file from the orchestrator or call Clear-VcStepOutput directly.
.PARAMETER FromStep
    The step number (x10) from which to start cleaning. All steps >= FromStep are cleaned.
.PARAMETER VcPath
    Local VCPATH root. Defaults to $env:VCPATH or C:\fkavd\Dedge2.
.PARAMETER OptPath
    Opt base path. Defaults to $env:OptPath or C:\opt.
.PARAMETER WhatIf
    Preview what would be deleted without deleting.
#>

function Clear-VcStepOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$FromStep,

        [string]$VcPath = $(if ($env:VCPATH) { $env:VCPATH } else { 'C:\fkavd\Dedge2' }),
        [string]$OptPath = $(if ($env:OptPath) { $env:OptPath } else { 'C:\opt' }),
        [switch]$WhatIf
    )

    $stepsConfig = Get-StepsConfig
    if (-not $stepsConfig) { return }

    $stepsToClean = @($stepsConfig | Where-Object { [int]$_.Step -ge $FromStep } | Sort-Object { [int]$_.Step } -Descending)

    if ($stepsToClean.Count -eq 0) {
        Write-LogMessage "No steps >= $($FromStep) found in config" -Level WARN
        return
    }

    Write-LogMessage "Cleaning output for steps >= $($FromStep) ($($stepsToClean.Count) steps)" -Level INFO

    foreach ($stepDef in $stepsToClean) {
        $stepNum = [int]$stepDef.Step
        $targets = Get-CleanupTargets -StepNumber $stepNum -VcPath $VcPath -OptPath $OptPath

        foreach ($target in $targets) {
            if (-not (Test-Path $target.Path)) { continue }

            if ($WhatIf) {
                Write-LogMessage "  [WhatIf] Would remove: $($target.Path) ($($target.Description))" -Level INFO
                continue
            }

            try {
                if ($target.IsFolder) {
                    Get-ChildItem -Path $target.Path -Recurse -File -ErrorAction SilentlyContinue |
                        Remove-Item -Force -ErrorAction SilentlyContinue
                    Write-LogMessage "  Cleaned folder: $($target.Path)" -Level INFO
                } else {
                    Remove-Item -Path $target.Path -Force -ErrorAction SilentlyContinue
                    Write-LogMessage "  Removed: $($target.Path)" -Level INFO
                }
            } catch {
                Write-LogMessage "  Failed to clean $($target.Path): $($_.Exception.Message)" -Level WARN
            }
        }
    }
}

function Get-CleanupTargets {
    [CmdletBinding()]
    param(
        [int]$StepNumber,
        [string]$VcPath,
        [string]$OptPath
    )

    $targets = @()

    switch ($StepNumber) {
        10 {
            $base = Join-Path $OptPath 'data\VisualCobol\Step1-Copy-VcSourceFiles'
            $sources = Join-Path $base 'Sources'
            foreach ($sub in @('cbl', 'cpy', 'cbl_uncertain', 'cpy_uncertain')) {
                $targets += @{ Path = (Join-Path $sources $sub); IsFolder = $true; Description = "Step10 $($sub) sources" }
            }
            $targets += @{ Path = (Join-Path $base 'FileIndex-*.json'); IsFolder = $false; Description = 'Step10 FileIndex JSON' }
            $targets += @{ Path = (Join-Path $base 'FileIndex-*.tsv');  IsFolder = $false; Description = 'Step10 FileIndex TSV' }
            $targets += @{ Path = (Join-Path $base 'CollectAll-*.json'); IsFolder = $false; Description = 'Step10 CollectAll JSON' }
        }
        15 {
            $projectRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
            $logFile = Join-Path $projectRoot 'Data\cbl-uncertain-files-moved.json'
            $targets += @{ Path = $logFile; IsFolder = $false; Description = 'Step15 cbl-uncertain-files-moved.json' }
        }
        20 {
            $base = Join-Path $OptPath 'data\Step2-Test-VcMissingCopybooks'
            $targets += @{ Path = (Join-Path $base 'MissingCopybooks-*.json'); IsFolder = $false; Description = 'Step20 MissingCopybooks JSON' }
            $targets += @{ Path = (Join-Path $base 'MissingCopybooks-*.tsv');  IsFolder = $false; Description = 'Step20 MissingCopybooks TSV' }
            $targets += @{ Path = (Join-Path $base 'MissingCopybooks-Impact-*.tsv'); IsFolder = $false; Description = 'Step20 Impact TSV' }
        }
        25 {
            $projectRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
            $logFile = Join-Path $projectRoot 'Data\cpy-uncertain-files-moved.json'
            $targets += @{ Path = $logFile; IsFolder = $false; Description = 'Step25 cpy-uncertain-files-moved.json' }
        }
        30 {
            foreach ($sub in @('int', 'lst', 'log', 'bnd', 'dir', 'cfg')) {
                $targets += @{ Path = (Join-Path $VcPath $sub); IsFolder = $true; Description = "Step30 VcPath\$($sub)" }
            }
        }
        40 {
            $targets += @{ Path = (Join-Path $VcPath 'int\*.int'); IsFolder = $false; Description = 'Step40 compiled .int files' }
            $targets += @{ Path = (Join-Path $VcPath 'lst\*.lst'); IsFolder = $false; Description = 'Step40 listing files' }
            $targets += @{ Path = (Join-Path $VcPath 'log\*.log'); IsFolder = $false; Description = 'Step40 log files' }
        }
        50 {
            $targets += @{ Path = (Join-Path $VcPath 'bnd\*.bnd'); IsFolder = $false; Description = 'Step50 bind files' }
            $targets += @{ Path = (Join-Path $VcPath 'BindReport-*.json'); IsFolder = $false; Description = 'Step50 BindReport JSON' }
        }
        60 {
            $base = Join-Path $OptPath 'data\Step6-Get-VcMigrationStatusReport'
            $targets += @{ Path = (Join-Path $base 'MigrationStatusReport-*.json'); IsFolder = $false; Description = 'Step60 MigrationStatus JSON' }
            $targets += @{ Path = (Join-Path $base 'MigrationStatusReport-*.tsv');  IsFolder = $false; Description = 'Step60 MigrationStatus TSV' }
            $targets += @{ Path = (Join-Path $base 'LocalCopies'); IsFolder = $true; Description = 'Step60 LocalCopies folder' }
        }
        70 {
            $uncBase = '\\t-no1fkmvct-app\opt\FkCblApps\FKMVCT'
            $targets += @{ Path = (Join-Path $uncBase 'Objects'); IsFolder = $true; Description = 'Step70 remote Objects' }
            $targets += @{ Path = (Join-Path $uncBase 'Source');  IsFolder = $true; Description = 'Step70 remote Source' }
        }
        80 {
            $uncBase = 'C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\VisualCobol\Sources'
            foreach ($sub in @('cbl', 'cpy', 'cbl_uncertain', 'cpy_uncertain')) {
                $targets += @{ Path = (Join-Path $uncBase $sub); IsFolder = $true; Description = "Step80 remote $($sub)" }
            }
        }
    }

    return $targets
}
