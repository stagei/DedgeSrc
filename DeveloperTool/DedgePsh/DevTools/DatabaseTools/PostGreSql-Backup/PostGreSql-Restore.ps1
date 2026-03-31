<#
.SYNOPSIS
    PostgreSQL restore — interactive file picker from RestoreFolder or BackupFolder,
    or direct restore from a given path.

.DESCRIPTION
    Uses Find-PgFolders to locate the RestoreFolder and BackupFolder.

    When called without -InputPath (or with just a filename), the script:
    1. Scans RestoreFolder for .backup / .sql files
    2. If empty, falls back to BackupFolder (with a warning)
    3. Presents a numbered list (most recent first) showing database name, timestamp, size
    4. User picks one or more files to restore

    File naming convention (produced by PostGreSql-Backup.ps1):
        <DatabaseName>_<YYYYMMDD-HHmmss>.backup
        <DatabaseName>_<YYYYMMDD-HHmmss>.sql
        <DatabaseName>.backup
        <DatabaseName>.sql

    After a successful restore the file is moved to a "Completed" subfolder.

.PARAMETER InputPath
    Full path to a specific backup file. Skips the interactive picker.
    If only a filename is given (no directory), the file is searched in RestoreFolder then BackupFolder.

.PARAMETER PostgresHost
    PostgreSQL host. Default: localhost

.PARAMETER PostgresPort
    PostgreSQL port. Default: 8432

.PARAMETER PostgresUser
    PostgreSQL user. Default: postgres

.PARAMETER PostgresPassword
    PostgreSQL password. Default: postgres

.PARAMETER CreateDatabaseIfNotExists
    Create the target database before restore if it does not exist.

.PARAMETER Clean
    For custom-format backups: drop existing objects before restore (pg_restore --clean --if-exists).

.PARAMETER DatabaseFilter
    Optional wildcard filter to limit which files are shown (matched against derived database name).
    Default: * (all files).

.PARAMETER All
    Skip the interactive picker and restore all matching files.

.EXAMPLE
    .\PostGreSql-Restore.ps1
    Shows interactive file picker from RestoreFolder (or BackupFolder as fallback).

.EXAMPLE
    .\PostGreSql-Restore.ps1 -InputPath "E:\PostgreSqlRestore\DedgeAuth_20260312-140000.backup" -CreateDatabaseIfNotExists

.EXAMPLE
    .\PostGreSql-Restore.ps1 -DatabaseFilter "DedgeAuth" -Clean
    Shows only DedgeAuth backups in the picker.

.EXAMPLE
    .\PostGreSql-Restore.ps1 -All -CreateDatabaseIfNotExists
    Restores all files in the RestoreFolder without prompting.
#>

[CmdletBinding()]
[System.Diagnostics.CodeAnalysis.SuppressMessage('Security', 'PSAvoidUsingPlainTextForPassword', Justification = 'pg_restore PGPASSWORD requires plain string.')]
param(
    [string]$InputPath        = $null,
    [string]$PostgresHost     = "localhost",
    [int]$PostgresPort        = 8432,
    [string]$PostgresUser     = "postgres",
    [string]$PostgresPassword = "postgres",
    [switch]$CreateDatabaseIfNotExists,
    [switch]$Clean,
    [string]$DatabaseFilter   = '*',
    [switch]$All
)

$ErrorActionPreference = "Stop"
Import-Module GlobalFunctions -Force
Import-Module PostgreSql-Handler -Force
Set-OverrideAppDataFolder -Path (Join-Path $env:OptPath "data\PostGreSql-Backup")
Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_STARTED

# Regex: capture database name before an optional _YYYYMMDD or _YYYYMMDD-HHmmss timestamp suffix
# ^        — start of string
# (.+?)    — group 1: database name (non-greedy)
# (?:_...)? — optional non-capturing group: underscore + 8 digits + optional dash + 6 digits
# $        — end of string
$timestampPattern = '^(.+?)(?:_(\d{8}(?:-\d{6})?))?$'

function Get-DatabaseNameFromFile {
    param([string]$FileName)
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    if ($baseName -match $script:timestampPattern) { return $Matches[1] }
    return $baseName
}

function Get-TimestampFromFile {
    param([string]$FileName)
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    if ($baseName -match $script:timestampPattern -and $Matches[2]) { return $Matches[2] }
    return $null
}

function Get-BackupFileList {
    param([string]$FolderPath)
    if (-not $FolderPath -or -not (Test-Path $FolderPath -PathType Container)) { return @() }
    $files = Get-ChildItem -Path $FolderPath -File -Include "*.backup", "*.sql" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending
    if (-not $files) { return @() }
    return @($files)
}

# --- Connection check ---

$psqlBinDir = Get-PostgreSqlPsqlPath
if (-not $psqlBinDir) {
    Write-LogMessage "PostgreSQL not found on this machine." -Level ERROR
    exit 1
}
$psqlExe = Join-Path $psqlBinDir "psql.exe"

$ok = Test-PostgreSqlConnection -Host $PostgresHost -Port $PostgresPort -User $PostgresUser `
    -Password $PostgresPassword -PsqlExe $psqlExe
if (-not $ok) {
    Write-LogMessage "Cannot connect to PostgreSQL at $($PostgresHost):$($PostgresPort). Aborting." -Level ERROR
    exit 1
}
Write-LogMessage "Connected to PostgreSQL at $($PostgresHost):$($PostgresPort)." -Level INFO

# --- Locate folders ---

$pgFolders = Find-PgFolders -SkipRecreateFolders
$restoreFolder = $pgFolders.RestoreFolder
$backupFolder  = $pgFolders.BackupFolder

# --- Resolve input files ---

$filesToRestore = @()
$sourceWarning  = $null

if ($InputPath) {
    if (-not [System.IO.Path]::IsPathRooted($InputPath)) {
        $candidates = @(
            (Join-Path $restoreFolder $InputPath),
            (Join-Path $backupFolder $InputPath)
        )
        $found = $candidates | Where-Object { Test-Path $_ -PathType Leaf } | Select-Object -First 1
        if ($found) {
            $InputPath = $found
        } else {
            Write-LogMessage "File '$($InputPath)' not found in RestoreFolder or BackupFolder." -Level ERROR
            exit 1
        }
    }
    if (-not (Test-Path $InputPath -PathType Leaf)) {
        Write-LogMessage "File not found: $($InputPath)" -Level ERROR
        exit 1
    }
    $filesToRestore = @(Get-Item $InputPath)
} else {
    $restoreFiles = Get-BackupFileList -FolderPath $restoreFolder
    if ($restoreFiles.Count -gt 0) {
        $candidateFiles = $restoreFiles
        Write-LogMessage "Found $($restoreFiles.Count) file(s) in RestoreFolder: $($restoreFolder)" -Level INFO
    } else {
        $backupFiles = Get-BackupFileList -FolderPath $backupFolder
        if ($backupFiles.Count -eq 0) {
            Write-LogMessage "No backup files found in RestoreFolder or BackupFolder." -Level WARN
            Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_COMPLETED
            exit 0
        }
        $candidateFiles = $backupFiles
        $sourceWarning = "RestoreFolder is empty. Listing files from BackupFolder: $($backupFolder)"
        Write-LogMessage $sourceWarning -Level WARN
    }

    if ($DatabaseFilter -ne '*') {
        $candidateFiles = @($candidateFiles | Where-Object {
            (Get-DatabaseNameFromFile -FileName $_.Name) -like $DatabaseFilter
        })
        if ($candidateFiles.Count -eq 0) {
            Write-LogMessage "No files matched database filter '$($DatabaseFilter)'." -Level WARN
            Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_COMPLETED
            exit 0
        }
    }

    if ($All) {
        $filesToRestore = $candidateFiles
    } else {
        Write-Host ""
        if ($sourceWarning) {
            Write-Host "  WARNING: $($sourceWarning)" -ForegroundColor Yellow
            Write-Host ""
        }
        Write-Host "  Available backup files (most recent first):" -ForegroundColor Cyan
        Write-Host "  $('─' * 90)" -ForegroundColor DarkGray

        $idx = 1
        $fileMap = @{}
        foreach ($f in $candidateFiles) {
            $dbName    = Get-DatabaseNameFromFile -FileName $f.Name
            $ts        = Get-TimestampFromFile -FileName $f.Name
            $tsDisplay = if ($ts) { $ts } else { "no timestamp" }
            $sizeKB    = [math]::Round($f.Length / 1KB, 1)
            $sizeMB    = [math]::Round($f.Length / 1MB, 1)
            $sizeStr   = if ($sizeMB -ge 1) { "$($sizeMB) MB" } else { "$($sizeKB) KB" }
            $ext       = $f.Extension.TrimStart('.')

            Write-Host ("  [{0,3}]  {1,-25} {2,-20} {3,10}  ({4})" -f $idx, $dbName, $tsDisplay, $sizeStr, $ext)
            $fileMap[$idx] = $f
            $idx++
        }

        Write-Host "  $('─' * 90)" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Enter number(s) to restore (comma-separated), 'A' for all, or 'Q' to quit:" -ForegroundColor Cyan
        $choice = Read-Host "  Selection"

        if ($choice -eq 'Q' -or $choice -eq 'q') {
            Write-LogMessage "User cancelled." -Level INFO
            Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_COMPLETED
            exit 0
        }

        if ($choice -eq 'A' -or $choice -eq 'a') {
            $filesToRestore = $candidateFiles
        } else {
            $selections = $choice -split ',' | ForEach-Object { $_.Trim() }
            foreach ($sel in $selections) {
                $num = 0
                if ([int]::TryParse($sel, [ref]$num) -and $fileMap.ContainsKey($num)) {
                    $filesToRestore += $fileMap[$num]
                } else {
                    Write-Host "  Invalid selection: $($sel)" -ForegroundColor Red
                }
            }
        }
    }
}

if ($filesToRestore.Count -eq 0) {
    Write-LogMessage "No files selected for restore." -Level WARN
    Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_COMPLETED
    exit 0
}

# --- Restore ---

$succeeded = 0
$failed    = 0

foreach ($file in $filesToRestore) {
    $dbName = Get-DatabaseNameFromFile -FileName $file.Name
    Write-LogMessage "Restoring '$($file.Name)' into database '$($dbName)'..." -Level INFO

    try {
        Restore-PostgreSqlDatabase -Host $PostgresHost -Port $PostgresPort -User $PostgresUser `
            -Password $PostgresPassword -Database $dbName -InputPath $file.FullName `
            -CreateDatabaseIfNotExists:$CreateDatabaseIfNotExists -Clean:$Clean -PsqlExe $psqlExe

        $completedDir = Join-Path (Split-Path $file.FullName -Parent) "Completed"
        if (-not (Test-Path $completedDir -PathType Container)) {
            New-Item -ItemType Directory -Path $completedDir -Force | Out-Null
        }
        Move-Item -Path $file.FullName -Destination (Join-Path $completedDir $file.Name) -Force
        Write-LogMessage "Restored '$($dbName)' successfully — file moved to Completed." -Level INFO
        $succeeded++
    }
    catch {
        Write-LogMessage "Failed to restore '$($dbName)' from '$($file.Name)': $($_.Exception.Message)" -Level ERROR
        $failed++
    }
}

Write-LogMessage "Restore run complete — succeeded: $($succeeded), failed: $($failed)" -Level INFO

if ($failed -gt 0) {
    Write-LogMessage "$($MyInvocation.MyCommand.Name) completed with $($failed) failure(s)." -Level JOB_FAILED
    exit 1
}

Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_COMPLETED
exit 0
