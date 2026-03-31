<#
.SYNOPSIS
    Restores the GenericLogHandler PostgreSQL database from a backup using connection settings from GenericLogHandler-DatabaseConfig.ps1.

.DESCRIPTION
    Calls Restore-PostgreSqlDatabase from PostgreSql-Handler. Use -InputPath to specify
    a .backup or .sql file, or -Latest to use the most recent file in .\Backups\.

.PARAMETER InputPath
    Full path to the backup file (.backup or .sql). Ignored if -Latest is set.

.PARAMETER Latest
    If set, restores from the newest backup in .\Backups\ (by write time).

.PARAMETER CreateDatabaseIfNotExists
    Create the database before restore if it does not exist.

.PARAMETER Clean
    For custom-format backups: drop existing objects before restore (pg_restore --clean --if-exists).

.EXAMPLE
    .\GenericLogHandler-Restore-Database.ps1 -Latest -CreateDatabaseIfNotExists
    Restores from latest backup in .\Backups\, creating the DB if needed.

.EXAMPLE
    .\GenericLogHandler-Restore-Database.ps1 -InputPath .\Backups\GenericLogHandler_20250101-120000.backup -Clean
#>

[CmdletBinding()]
[System.Diagnostics.CodeAnalysis.SuppressMessage('Security', 'PSAvoidUsingPlainTextForPassword', Justification = 'Delegates to PostgreSql-Handler.')]
param(
    [string]$InputPath = $null,
    [switch]$Latest,
    [switch]$CreateDatabaseIfNotExists,
    [switch]$Clean,
    [string]$PostgresHost = $null,
    [int]$PostgresPort = 0,
    [string]$PostgresUser = $null,
    [string]$PostgresPassword = $null,
    [string]$DatabaseName = $null
)

$ErrorActionPreference = "Stop"
Import-Module GlobalFunctions -Force
Import-Module PostgreSql-Handler -Force

$configPath = Join-Path $PSScriptRoot "GenericLogHandler-DatabaseConfig.ps1"
if (-not (Test-Path $configPath -PathType Leaf)) {
    Write-LogMessage "GenericLogHandler-DatabaseConfig.ps1 not found at: $($configPath)" -Level ERROR
    exit 1
}

$config = & $configPath
if ($PostgresHost) { $config.PostgresHost = $PostgresHost }
if ($PostgresPort -gt 0) { $config.PostgresPort = $PostgresPort }
if ($PostgresUser) { $config.PostgresUser = $PostgresUser }
if ($PostgresPassword) { $config.PostgresPassword = $PostgresPassword }
if ($DatabaseName) { $config.DatabaseName = $DatabaseName }

if ($Latest) {
    $backupDir = Join-Path $PSScriptRoot "Backups"
    if (-not (Test-Path $backupDir -PathType Container)) {
        Write-LogMessage "No Backups folder found at: $($backupDir)" -Level ERROR
        exit 1
    }
    $latestFile = Get-ChildItem -Path $backupDir -File -Include "*.backup", "*.sql" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latestFile) {
        Write-LogMessage "No backup files found in $($backupDir)" -Level ERROR
        exit 1
    }
    $InputPath = $latestFile.FullName
    Write-LogMessage "Using latest backup: $($InputPath)" -Level INFO
}

if ([string]::IsNullOrWhiteSpace($InputPath)) {
    Write-LogMessage "Specify -InputPath <path> or -Latest." -Level ERROR
    exit 1
}

$psqlPath = Get-PostgreSqlPsqlPath
if (-not $psqlPath) {
    Write-LogMessage "PostgreSQL not found." -Level ERROR
    exit 1
}
$psqlExe = Join-Path $psqlPath "psql.exe"

Write-Host ""
Write-Host "Restore database: $($config.DatabaseName) @ $($config.PostgresHost):$($config.PostgresPort)" -ForegroundColor Cyan
Write-Host "From: $InputPath" -ForegroundColor Gray
Write-Host ""

try {
    Restore-PostgreSqlDatabase -Host $config.PostgresHost -Port $config.PostgresPort `
        -User $config.PostgresUser -Password $config.PostgresPassword -Database $config.DatabaseName `
        -InputPath $InputPath -CreateDatabaseIfNotExists:$CreateDatabaseIfNotExists -Clean:$Clean -PsqlExe $psqlExe
    Write-Host "Restore completed." -ForegroundColor Green
}
catch {
    Write-LogMessage "Restore failed: $($_.Exception.Message)" -Level ERROR
    exit 1
}
