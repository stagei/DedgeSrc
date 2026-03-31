<#
.SYNOPSIS
    Backs up the GenericLogHandler PostgreSQL database using connection settings from GenericLogHandler-DatabaseConfig.ps1.

.DESCRIPTION
    Calls Backup-PostgreSqlDatabase from PostgreSql-Handler. Output is written to
    the Backups folder under this script directory (or -OutputPath). Override
    config with parameters.

.PARAMETER OutputPath
    Full path for the backup file. If not set, uses .\Backups\<DatabaseName>_<yyyyMMdd-HHmmss>.backup

.PARAMETER Format
    Custom (binary, for pg_restore) or Plain (SQL text). Default: Custom

.EXAMPLE
    .\GenericLogHandler-Backup-Database.ps1
    Creates a timestamped backup in .\Backups\

.EXAMPLE
    .\GenericLogHandler-Backup-Database.ps1 -OutputPath C:\temp\GenericLogHandler.backup -Format Plain
#>

[CmdletBinding()]
[System.Diagnostics.CodeAnalysis.SuppressMessage('Security', 'PSAvoidUsingPlainTextForPassword', Justification = 'Delegates to PostgreSql-Handler.')]
param(
    [string]$OutputPath = $null,
    [ValidateSet('Custom', 'Plain')]
    [string]$Format = 'Custom',
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

if (-not $OutputPath) {
    $backupDir = Join-Path $PSScriptRoot "Backups"
    $ext = if ($Format -eq 'Plain') { '.sql' } else { '.backup' }
    $fileName = "$($config.DatabaseName)_$(Get-Date -Format 'yyyyMMdd-HHmmss')$($ext)"
    $OutputPath = Join-Path $backupDir $fileName
}

$psqlPath = Get-PostgreSqlPsqlPath
if (-not $psqlPath) {
    Write-LogMessage "PostgreSQL not found." -Level ERROR
    exit 1
}
$psqlExe = Join-Path $psqlPath "psql.exe"

Write-Host ""
Write-Host "Backup database: $($config.DatabaseName) @ $($config.PostgresHost):$($config.PostgresPort)" -ForegroundColor Cyan
Write-Host "Output: $OutputPath" -ForegroundColor Gray
Write-Host ""

try {
    $result = Backup-PostgreSqlDatabase -Host $config.PostgresHost -Port $config.PostgresPort `
        -User $config.PostgresUser -Password $config.PostgresPassword -Database $config.DatabaseName `
        -OutputPath $OutputPath -Format $Format -PsqlExe $psqlExe
    Write-Host "Backup completed: $result" -ForegroundColor Green
}
catch {
    Write-LogMessage "Backup failed: $($_.Exception.Message)" -Level ERROR
    exit 1
}
