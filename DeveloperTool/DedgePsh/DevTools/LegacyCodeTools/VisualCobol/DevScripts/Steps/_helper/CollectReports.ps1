<#
.SYNOPSIS
    Collects key JSON reports from the data folder into a timestamped Reports subfolder.
.DESCRIPTION
    After a pipeline run, call this function to copy the most important analysis
    reports into VisualCobol\Reports\<ScriptName>-<Timestamp>\.

    Targets JSON files only — the authoritative machine-readable outputs:
      - CollectAll-*.json          (Step1: source file inventory)
      - FileIndex-*.json           (Step1: file index with hashes)
      - MissingCopybooks-*.json    (Step2: missing copybook analysis)
      - PipelineReport-*.json      (full pipeline compilation summary)
      - BindReport-*.json          (Step5: DB2 bind results)
      - MigrationStatusReport-*.json (Step6: unified migration status)
.PARAMETER ScriptName
    Name of the calling script (used in folder name). Defaults to caller's basename.
.PARAMETER Timestamp
    Timestamp string for the folder. Defaults to yyyyMMdd-HHmmss.
.PARAMETER DataFolder
    Where to look for report JSONs. Defaults to Get-ApplicationDataPath.
.PARAMETER VcPath
    VCPATH root (some reports land here). Defaults to $env:VCPATH or C:\fkavd\Dedge2.
#>

function Copy-VcReportsToArchive {
    [CmdletBinding()]
    param(
        [string]$ScriptName,
        [string]$Timestamp = (Get-Date -Format 'yyyyMMdd-HHmmss'),
        [string]$DataFolder,
        [string]$VcPath = $(if ($env:VCPATH) { $env:VCPATH } else { 'C:\fkavd\Dedge2' })
    )

    if (-not $ScriptName) {
        $ScriptName = if ($MyInvocation.PSCommandPath) {
            [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.PSCommandPath)
        } else { 'Unknown' }
    }

    if (-not $DataFolder) {
        $DataFolder = Get-ApplicationDataPath
    }

    $projectRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
    if (-not (Test-Path (Join-Path $projectRoot '_deploy.ps1'))) {
        $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    }

    $reportDir = Join-Path $projectRoot "Reports\$($ScriptName)-$($Timestamp)"
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null

    $patterns = @(
        'CollectAll-*.json'
        'FileIndex-*.json'
        'MissingCopybooks-*.json'
        'PipelineReport-*.json'
        'BindReport-*.json'
        'MigrationStatusReport-*.json'
    )

    $projectRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
    if (-not (Test-Path (Join-Path $projectRoot '_deploy.ps1'))) {
        $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    }
    $dataDir = Join-Path $projectRoot 'Data'
    $ollamaLogFiles = @(
        'cbl-uncertain-files-moved.json'
        'cpy-uncertain-files-moved.json'
    )

    $searchFolders = @($DataFolder, $VcPath) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
    $copied = 0

    foreach ($folder in $searchFolders) {
        foreach ($pattern in $patterns) {
            $latest = Get-ChildItem -Path $folder -Filter $pattern -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1

            if ($latest) {
                $destPath = Join-Path $reportDir $latest.Name
                if (-not (Test-Path $destPath)) {
                    Copy-Item -Path $latest.FullName -Destination $destPath -Force
                    Write-LogMessage "  Archived: $($latest.Name)" -Level INFO
                    $copied++
                }
            }
        }
    }

    if (Test-Path $dataDir) {
        foreach ($ollamaFile in $ollamaLogFiles) {
            $srcFile = Join-Path $dataDir $ollamaFile
            if (Test-Path $srcFile) {
                $destPath = Join-Path $reportDir $ollamaFile
                if (-not (Test-Path $destPath)) {
                    Copy-Item -Path $srcFile -Destination $destPath -Force
                    Write-LogMessage "  Archived: $($ollamaFile)" -Level INFO
                    $copied++
                }
            }
        }
    }

    if ($copied -eq 0) {
        Write-LogMessage "  No report JSONs found to archive" -Level WARN
    } else {
        Write-LogMessage "Archived $($copied) report(s) to $($reportDir)" -Level INFO
    }

    return $reportDir
}
