#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Daily incremental backup of the AiDoc folder, triggered only when RAG indexes change.

.DESCRIPTION
    Checks all ChromaDB index directories (AiDoc.Library/*/.index) for file modifications
    since the last successful backup. If any index file is newer than the last backup
    marker, creates a date-stamped zip at $env:OptPath\data\AiDocBackup\yyyyMMdd.zip.

    Each backup zip includes a _FileInventory.txt with the complete file listing
    (full path, size, last-modified date) for every file in the backup.

    Excludes from backup:
      - .venv          (reproducible from requirements.txt)
      - .onnx_models   (re-downloaded on first use)
      - __pycache__    (Python cache)
      - offline_wheels  (pip wheel cache)
      - logs           (service runtime logs)
      - .git           (not present on server)

    Keeps backups according to -RetainDays (default: 30).

.PARAMETER AiDocRoot
    Root of the AiDoc folder. Default: $env:OptPath\FkPythonApps\AiDoc.

.PARAMETER BackupDir
    Where to store zip backups. Default: $env:OptPath\data\AiDocBackup.

.PARAMETER RetainDays
    Delete backups older than this many days. Default: 30.

.PARAMETER Force
    Create a backup even if no index files have changed.

.EXAMPLE
    pwsh.exe -File .\src\AiDoc.Pwsh.Server\Backup-AiDocDaily.ps1

.EXAMPLE
    pwsh.exe -File .\src\AiDoc.Pwsh.Server\Backup-AiDocDaily.ps1 -Force

.EXAMPLE
    pwsh.exe -File .\src\AiDoc.Pwsh.Server\Backup-AiDocDaily.ps1 -RetainDays 14
#>

param(
    [string]$AiDocRoot,
    [string]$BackupDir,
    [int]$RetainDays = 30,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

Import-Module GlobalFunctions -Force

if (-not $AiDocRoot) {
    if (-not $env:OptPath) {
        throw "Environment variable OptPath is not set. Set it (e.g. E:\opt) or pass -AiDocRoot explicitly."
    }
    $AiDocRoot = Join-Path $env:OptPath "FkPythonApps\AiDoc"
}

if (-not $BackupDir) {
    $BackupDir = Join-Path $env:OptPath "data\AiDocBackup"
}

$markerFile = Join-Path $BackupDir ".last_backup_marker"
$libraryDir = Join-Path $env:OptPath 'data\AiDoc.Library'
if (-not (Test-Path -LiteralPath $libraryDir)) {
    $libraryDir = Join-Path $AiDocRoot 'AiDoc.Library'
}

Write-LogMessage "Backup-AiDocDaily starting" -Level INFO
Write-LogMessage "AiDocRoot : $($AiDocRoot)" -Level INFO
Write-LogMessage "BackupDir : $($BackupDir)" -Level INFO

if (-not (Test-Path -LiteralPath $AiDocRoot)) {
    Write-LogMessage "AiDoc root not found: $($AiDocRoot)" -Level ERROR
    exit 1
}

if (-not (Test-Path -LiteralPath $BackupDir)) {
    New-Item -Path $BackupDir -ItemType Directory -Force | Out-Null
    Write-LogMessage "Created backup directory: $($BackupDir)" -Level INFO
}

# --- Detect changes in .index directories ---
$lastBackupTime = [datetime]::MinValue
if (Test-Path -LiteralPath $markerFile) {
    $lastBackupTime = (Get-Item -LiteralPath $markerFile).LastWriteTimeUtc
    Write-LogMessage "Last backup marker: $($lastBackupTime.ToString('yyyy-MM-dd HH:mm:ss')) UTC" -Level INFO
} else {
    Write-LogMessage "No previous backup marker found - first run" -Level INFO
}

$indexDirs = Get-ChildItem -Path $libraryDir -Directory -Recurse -Filter '.index' -ErrorAction SilentlyContinue
if (-not $indexDirs -or $indexDirs.Count -eq 0) {
    Write-LogMessage "No .index directories found under $($libraryDir). Nothing to back up." -Level WARN
    exit 0
}

$changedFiles = @()
foreach ($idxDir in $indexDirs) {
    $files = Get-ChildItem -Path $idxDir.FullName -Recurse -File -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        if ($f.LastWriteTimeUtc -gt $lastBackupTime) {
            $changedFiles += $f
        }
    }
}

if ($changedFiles.Count -eq 0 -and -not $Force) {
    Write-LogMessage "No index files changed since last backup. Skipping." -Level INFO
    exit 0
}

if ($Force -and $changedFiles.Count -eq 0) {
    Write-LogMessage "No changes detected but -Force specified. Creating backup anyway." -Level INFO
} else {
    Write-LogMessage "$($changedFiles.Count) index file(s) changed since last backup" -Level INFO
    foreach ($cf in $changedFiles | Select-Object -First 5) {
        Write-LogMessage "  Changed: $($cf.FullName) ($($cf.LastWriteTimeUtc.ToString('yyyy-MM-dd HH:mm:ss')) UTC)" -Level DEBUG
    }
    if ($changedFiles.Count -gt 5) {
        Write-LogMessage "  ... and $($changedFiles.Count - 5) more" -Level DEBUG
    }
}

# --- Create backup zip ---
$datestamp = Get-Date -Format 'yyyyMMdd'
$zipName  = "$($datestamp).zip"
$zipPath  = Join-Path $BackupDir $zipName

$excludeDirs = @('.venv', '.onnx_models', '__pycache__', 'offline_wheels', 'logs', '.git')

if (Test-Path -LiteralPath $zipPath) {
    Write-LogMessage "Backup for today already exists: $($zipPath). Overwriting." -Level WARN
}

Write-LogMessage "Creating backup: $($zipPath)" -Level INFO
$sw = [System.Diagnostics.Stopwatch]::StartNew()

$tempStaging = Join-Path $env:TEMP "AiDoc-Backup-Stage-$($datestamp)"
if (Test-Path -LiteralPath $tempStaging) { Remove-Item -LiteralPath $tempStaging -Recurse -Force }

$roboArgs = @(
    $AiDocRoot,
    $tempStaging,
    '/MIR', '/NP', '/NDL', '/NFL', '/NJH', '/NJS',
    '/XD'
)
$roboArgs += $excludeDirs

$null = & robocopy.exe @roboArgs
$roboExit = $LASTEXITCODE
if ($roboExit -ge 8) {
    Write-LogMessage "Robocopy staging failed (exit $($roboExit))" -Level ERROR
    if (Test-Path -LiteralPath $tempStaging) { Remove-Item -LiteralPath $tempStaging -Recurse -Force }
    exit 1
}

# --- Generate file inventory ---
$inventoryFile = Join-Path $tempStaging '_FileInventory.txt'
$allFiles = Get-ChildItem -Path $tempStaging -Recurse -File | Sort-Object DirectoryName, Name

$inventoryLines = [System.Collections.Generic.List[string]]::new()
$inventoryLines.Add("AiDoc Backup File Inventory")
$inventoryLines.Add("===========================")
$inventoryLines.Add("Backup Date : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$inventoryLines.Add("Source      : $($AiDocRoot)")
$inventoryLines.Add("Computer    : $($env:COMPUTERNAME)")
$inventoryLines.Add("Total Files : $($allFiles.Count)")

$totalSize = ($allFiles | Measure-Object -Property Length -Sum).Sum
$inventoryLines.Add("Total Size  : $([math]::Round($totalSize / 1MB, 2)) MB")
$inventoryLines.Add("Excluded    : $($excludeDirs -join ', ')")
$inventoryLines.Add("")
$inventoryLines.Add(("{0,-20} {1,12} {2}" -f 'LastWriteTime', 'Size', 'FullPath'))
$inventoryLines.Add(("{0,-20} {1,12} {2}" -f ('-' * 19), ('-' * 12), ('-' * 60)))

$currentDir = ''
foreach ($f in $allFiles) {
    $relPath = $f.FullName.Substring($tempStaging.Length + 1)
    $dir = Split-Path $relPath -Parent
    if ($dir -ne $currentDir) {
        $currentDir = $dir
        $inventoryLines.Add("")
        $inventoryLines.Add("[$($dir)]")
    }
    $sizeStr = if ($f.Length -ge 1MB) {
        "$([math]::Round($f.Length / 1MB, 1)) MB"
    } elseif ($f.Length -ge 1KB) {
        "$([math]::Round($f.Length / 1KB, 1)) KB"
    } else {
        "$($f.Length) B"
    }
    $inventoryLines.Add(("{0,-20} {1,12} {2}" -f $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm'), $sizeStr, $relPath))
}

$inventoryLines | Set-Content -Path $inventoryFile -Encoding UTF8
Write-LogMessage "File inventory written: $($allFiles.Count) files cataloged" -Level INFO

# --- Compress ---
try {
    Compress-Archive -Path "$($tempStaging)\*" -DestinationPath $zipPath -CompressionLevel Optimal -Force
} catch {
    Write-LogMessage "Compress-Archive failed: $($_.Exception.Message)" -Level ERROR
    if (Test-Path -LiteralPath $tempStaging) { Remove-Item -LiteralPath $tempStaging -Recurse -Force }
    exit 1
}

if (Test-Path -LiteralPath $tempStaging) { Remove-Item -LiteralPath $tempStaging -Recurse -Force }

$sw.Stop()
$zipSize = (Get-Item -LiteralPath $zipPath).Length
$sizeMB  = [math]::Round($zipSize / 1MB, 1)

Write-LogMessage "Backup created: $($zipName) ($($sizeMB) MB) in $($sw.Elapsed.TotalSeconds.ToString('F1'))s" -Level INFO

# --- Update marker ---
if (Test-Path -LiteralPath $markerFile) {
    (Get-Item -LiteralPath $markerFile).LastWriteTimeUtc = [datetime]::UtcNow
} else {
    New-Item -Path $markerFile -ItemType File -Force | Out-Null
}
Write-LogMessage "Backup marker updated" -Level INFO

# --- Retention: delete old backups ---
$cutoff = (Get-Date).AddDays(-$RetainDays)
$oldBackups = Get-ChildItem -Path $BackupDir -Filter '*.zip' -File |
    Where-Object { $_.CreationTime -lt $cutoff }

if ($oldBackups.Count -gt 0) {
    foreach ($old in $oldBackups) {
        Remove-Item -LiteralPath $old.FullName -Force
        Write-LogMessage "Deleted old backup: $($old.Name)" -Level INFO
    }
    Write-LogMessage "Cleaned up $($oldBackups.Count) backup(s) older than $($RetainDays) days" -Level INFO
} else {
    Write-LogMessage "No backups older than $($RetainDays) days to clean up" -Level INFO
}

# --- Summary ---
$remaining = (Get-ChildItem -Path $BackupDir -Filter '*.zip' -File).Count
Write-LogMessage "Backup-AiDocDaily finished. $($remaining) backup(s) in $($BackupDir)" -Level INFO
