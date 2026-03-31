<#
.SYNOPSIS
    Automated PostgreSQL backup — discovers all databases on the local instance and backs up each one.

.DESCRIPTION
    Connects to the local PostgreSQL server, lists all user databases (excludes template0,
    template1, postgres), and runs pg_dump for each one. Backups are written to a date-stamped
    subfolder under the configured backup root.

    Designed to run unattended via scheduled task on any server with PostgreSQL installed.

.PARAMETER PostgresHost
    PostgreSQL host. Default: localhost

.PARAMETER PostgresPort
    PostgreSQL port. Default: 8432

.PARAMETER PostgresUser
    PostgreSQL user. Default: postgres

.PARAMETER PostgresPassword
    PostgreSQL password. Default: postgres

.PARAMETER BackupRoot
    Root folder for backups. A date-stamped subfolder is created per run.
    Default: $env:OptPath\data\PostGreSql-Backup

.PARAMETER Format
    Backup format: Custom (binary archive for pg_restore) or Plain (SQL text). Default: Custom

.PARAMETER RetentionDays
    Number of days to keep old backup folders. Folders older than this are removed. Default: 30.
    Set to 0 to skip cleanup.

.PARAMETER DatabaseFilter
    Optional wildcard filter to limit which databases are backed up (e.g. "DedgeAuth*").
    Default: * (all user databases).

.EXAMPLE
    .\PostGreSql-Backup.ps1
    Discovers and backs up all user databases on localhost:8432 to $env:OptPath\data\PostGreSql-Backup\

.EXAMPLE
    .\PostGreSql-Backup.ps1 -PostgresPort 5432 -RetentionDays 14 -Format Plain
    Uses port 5432, keeps backups for 14 days, outputs as .sql files.

.EXAMPLE
    .\PostGreSql-Backup.ps1 -DatabaseFilter "DedgeAuth*"
    Only backs up databases matching DedgeAuth*.
#>

[CmdletBinding()]
[System.Diagnostics.CodeAnalysis.SuppressMessage('Security', 'PSAvoidUsingPlainTextForPassword', Justification = 'pg_dump PGPASSWORD requires plain string.')]
param(
    [string]$PostgresHost     = "localhost",
    [int]$PostgresPort        = 8432,
    [string]$PostgresUser     = "postgres",
    [string]$PostgresPassword = "postgres",
    [string]$BackupRoot       = (Join-Path $env:OptPath "data\PostGreSql-Backup"),

    [ValidateSet('Custom', 'Plain')]
    [string]$Format           = 'Custom',

    [int]$RetentionDays       = 30,
    [string]$DatabaseFilter   = '*'
)

$ErrorActionPreference = "Stop"
Import-Module GlobalFunctions -Force
Import-Module PostgreSql-Handler -Force
Set-OverrideAppDataFolder -Path (Join-Path $env:OptPath "data\PostGreSql-Backup")
Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_STARTED

$psqlBinDir = Get-PostgreSqlPsqlPath
if (-not $psqlBinDir) {
    Write-LogMessage "PostgreSQL not found on this machine — nothing to back up." -Level ERROR
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

$pgFolders = Find-PgFolders -FolderName "BackupFolder" -SkipRecreateFolders
if (-not $BackupRoot -or $BackupRoot -eq (Join-Path $env:OptPath "data\PostGreSql-Backup")) {
    $BackupRoot = $pgFolders.BackupFolder
    Write-LogMessage "Using backup folder from Find-PgFolders: $($BackupRoot)" -Level INFO
}

$listQuery = "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('postgres') ORDER BY datname"
$dbListRaw = Invoke-PostgreSqlQuery -Host $PostgresHost -Port $PostgresPort -User $PostgresUser `
    -Password $PostgresPassword -Database "postgres" -Query $listQuery -PsqlExe $psqlExe

if ([string]::IsNullOrWhiteSpace($dbListRaw)) {
    Write-LogMessage "No user databases found." -Level WARN
    Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_COMPLETED
    exit 0
}

$databases = $dbListRaw -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

if ($DatabaseFilter -ne '*') {
    $databases = $databases | Where-Object { $_ -like $DatabaseFilter }
}

if ($databases.Count -eq 0) {
    Write-LogMessage "No databases matched filter '$($DatabaseFilter)'." -Level WARN
    Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_COMPLETED
    exit 0
}

Write-LogMessage "Databases to back up ($($databases.Count)): $($databases -join ', ')" -Level INFO

if (-not (Test-Path $BackupRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
}
Write-LogMessage "Backup folder: $($BackupRoot)" -Level INFO

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$succeeded = 0
$failed    = 0

foreach ($db in $databases) {
    $ext = if ($Format -eq 'Plain') { '.sql' } else { '.backup' }
    $outFile = Join-Path $BackupRoot "$($db)_$($timestamp)$($ext)"

    try {
        Backup-PostgreSqlDatabase -Host $PostgresHost -Port $PostgresPort -User $PostgresUser `
            -Password $PostgresPassword -Database $db -OutputPath $outFile `
            -Format $Format -PsqlExe $psqlExe
        $succeeded++
    }
    catch {
        Write-LogMessage "Failed to back up '$($db)': $($_.Exception.Message)" -Level ERROR
        $failed++
    }
}

Write-LogMessage "Backup run complete — succeeded: $($succeeded), failed: $($failed)" -Level INFO

if ($RetentionDays -gt 0) {
    $cutoff = (Get-Date).AddDays(-$RetentionDays)
    $oldFiles = Get-ChildItem -Path $BackupRoot -File -Include "*.backup", "*.sql" -ErrorAction SilentlyContinue |
        Where-Object { $_.CreationTime -lt $cutoff }
    if ($oldFiles) {
        foreach ($old in $oldFiles) {
            Remove-Item -Path $old.FullName -Force -ErrorAction SilentlyContinue
            Write-LogMessage "Removed old backup: $($old.Name)" -Level INFO
        }
        Write-LogMessage "Retention cleanup: removed $($oldFiles.Count) file(s) older than $($RetentionDays) days." -Level INFO
    }
}

if ($failed -gt 0) {
    Write-LogMessage "$($MyInvocation.MyCommand.Name) completed with $($failed) failure(s)." -Level JOB_FAILED
    exit 1
}

Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_COMPLETED
exit 0
